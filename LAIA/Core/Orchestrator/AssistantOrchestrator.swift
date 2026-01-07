//
//  AssistantOrchestrator.swift
//  LAIA - Local AI Assistant
//
//  Main coordinator actor for the voice assistant pipeline.
//  Manages state transitions, audio flow, and model coordination.
//

import Foundation
import AVFoundation
import os

/// Main orchestrator actor for coordinating the voice assistant pipeline
/// Manages audio capture, VAD, STT, LLM, and TTS flow
public actor AssistantOrchestrator: Orchestrator {
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.laia.orchestrator", category: "Orchestrator")
    
    /// Inference state manager
    private let state: InferenceState
    
    /// Latency metrics
    private let metrics: LatencyMetrics
    
    /// Memory guardian reference
    private let memoryGuardian: MemoryGuardian
    
    // MARK: - Providers
    
    private let sttProvider: any STTProvider
    private let llmProvider: any LLMProvider
    private let ttsProvider: any TTSProvider
    
    // MARK: - Audio Components
    
    private let audioBuffer: AudioBufferContainer
    private let audioEngine: AudioCaptureEngine
    private let vadProcessor: SileroVADProcessor
    private var playbackQueue: AudioPlaybackQueue?
    
    // MARK: - State
    
    private weak var delegate: OrchestratorDelegate?
    
    /// Current generation task (for cancellation)
    private var generationTask: Task<Void, Never>?
    
    /// Conversation history
    private var conversationHistory: [ConversationMessage] = []
    
    /// Configuration
    private let config: OrchestratorConfiguration
    
    // MARK: - Protocol Conformance
    
    public var currentState: InferenceStateValue {
        get async {
            await state.current
        }
    }
    
    // MARK: - Configuration
    
    public struct OrchestratorConfiguration: Sendable {
        /// Whether to use dynamic audio offloading
        public var enableDynamicOffloading: Bool = true
        
        /// Maximum conversation history to keep
        public var maxHistoryMessages: Int = 10
        
        /// Whether to auto-resume listening after speaking
        public var autoResumeListening: Bool = true
        
        public init() {}
    }
    
    // MARK: - Initialization
    
    public init(
        sttProvider: any STTProvider,
        llmProvider: any LLMProvider,
        ttsProvider: any TTSProvider,
        memoryGuardian: MemoryGuardian,
        configuration: OrchestratorConfiguration = OrchestratorConfiguration()
    ) {
        self.sttProvider = sttProvider
        self.llmProvider = llmProvider
        self.ttsProvider = ttsProvider
        self.memoryGuardian = memoryGuardian
        self.config = configuration
        
        // Initialize components
        self.state = InferenceState()
        self.metrics = LatencyMetrics()
        self.audioBuffer = AudioBufferContainer()
        self.audioEngine = AudioCaptureEngine(buffer: audioBuffer)
        self.vadProcessor = SileroVADProcessor()
        
        logger.info("AssistantOrchestrator initialized")
    }
    
    // MARK: - Setup
    
    /// Setup all components
    public func setup() async throws {
        logger.info("Setting up orchestrator")
        
        // Setup audio engine
        try audioEngine.setup()
        audioEngine.setupInterruptionHandling()
        
        // Setup VAD callbacks
        vadProcessor.onSpeechStart = { [weak self] in
            Task { [weak self] in
                await self?.handleSpeechStart()
            }
        }
        
        vadProcessor.onSpeechEnd = { [weak self] samples in
            Task { [weak self] in
                await self?.handleSpeechEnd(samples: samples)
            }
        }
        
        // Load VAD model
        try vadProcessor.loadModel()
        
        // Setup audio chunk processing
        audioEngine.audioChunkCallback = { [weak self] samples in
            self?.processAudioChunk(samples)
        }
        
        // Setup playback queue
        playbackQueue = try AudioPlaybackQueue()
        
        // Register memory cleanup
        await registerMemoryCleanup()
        
        logger.info("Orchestrator setup complete")
    }
    
    private func registerMemoryCleanup() async {
        await memoryGuardian.registerCleanupHandler(identifier: "orchestrator") { [weak self] in
            await self?.handleMemoryPressure()
        }
    }
    
    // MARK: - Lifecycle
    
    public func startListening() async throws {
        let currentState = await state.current
        
        guard currentState == .idle || currentState == .error else {
            logger.warning("Cannot start listening from state: \(currentState.rawValue)")
            throw LAIAError.invalidState(currentState.rawValue)
        }
        
        logger.info("Starting listening")
        
        // Transition state
        await state.startListening()
        notifyStateChange()
        
        // Start audio capture
        try audioEngine.start()
        
        // Start metrics session
        await metrics.startSession()
        
        logger.info("Listening started")
    }
    
    public func stopListening() async {
        logger.info("Stopping listening")
        
        audioEngine.stop()
        
        await state.reset()
        notifyStateChange()
        
        logger.info("Listening stopped")
    }
    
    public func cancel() async {
        logger.info("Cancelling current operation")
        
        // Cancel ongoing generation
        generationTask?.cancel()
        generationTask = nil
        
        // Stop playback
        playbackQueue?.stop()
        
        // Reset VAD
        vadProcessor.reset()
        
        // Clear buffer
        audioBuffer.clear()
        
        // Reset state
        await state.reset()
        notifyStateChange()
    }
    
    public func setDelegate(_ delegate: OrchestratorDelegate?) async {
        self.delegate = delegate
    }
    
    // MARK: - Audio Processing
    
    private nonisolated func processAudioChunk(_ samples: [Float]) {
        // Process VAD on audio thread
        // nonisolated to avoid actor hop for each chunk
        do {
            _ = try vadProcessor.process(samples)
        } catch {
            // Log but don't throw - VAD errors shouldn't crash audio processing
        }
    }
    
    // MARK: - Speech Detection Handlers
    
    private func handleSpeechStart() async {
        let currentState = await state.current
        
        guard currentState == .listening else {
            logger.debug("Ignoring speech start in state: \(currentState.rawValue)")
            return
        }
        
        logger.info("Speech detected - starting detection phase")
        
        await state.voiceDetected()
        await metrics.record(.vadTrigger)
        notifyStateChange()
    }
    
    private func handleSpeechEnd(samples: [Float]) async {
        let currentState = await state.current
        
        guard currentState == .listening || currentState == .detectingVoice else {
            logger.debug("Ignoring speech end in state: \(currentState.rawValue)")
            return
        }
        
        guard !samples.isEmpty else {
            logger.debug("Empty speech buffer - ignoring")
            await state.startListening()
            return
        }
        
        logger.info("Speech ended with \(samples.count) samples - starting pipeline")
        
        // Start the full pipeline
        await processSpeechPipeline(audioSamples: samples)
    }
    
    // MARK: - Pipeline Execution
    
    private func processSpeechPipeline(audioSamples: [Float]) async {
        // Dynamic offloading - pause audio capture during inference
        if config.enableDynamicOffloading {
            audioEngine.pause()
        }
        
        do {
            // 1. Transcribe
            await state.startTranscription()
            notifyStateChange()
            
            let transcription = try await sttProvider.transcribe(audioSamples)
            
            guard !transcription.isEmpty else {
                logger.debug("Empty transcription - resuming listening")
                await resumeListening()
                return
            }
            
            logger.info("Transcribed: \"\(transcription)\"")
            delegate?.orchestrator(self, didTranscribe: transcription)
            
            // Add to history
            let userMessage = ConversationMessage(role: .user, content: transcription)
            addToHistory(userMessage)
            
            // 2. Generate response
            await state.startThinking()
            notifyStateChange()
            
            try await generateAndSpeak(prompt: transcription)
            
        } catch {
            logger.error("Pipeline error: \(error.localizedDescription)")
            await state.reportError()
            delegate?.orchestrator(self, didEncounterError: error)
            
            // Resume after error
            await resumeListening()
        }
    }
    
    private func generateAndSpeak(prompt: String) async throws {
        var fullResponse = ""
        var sentenceBuffer = ""
        var isFirstToken = true
        
        delegate?.orchestratorDidStartSpeaking(self)
        
        // Start generation - await the actor-isolated method
        let tokenStream = await llmProvider.generate(prompt: prompt, context: conversationHistory)
        
        do {
            for try await token in tokenStream {
                guard !Task.isCancelled else { break }
                
                if isFirstToken {
                    await metrics.record(.llmFirstToken)
                    await state.startSpeaking()
                    notifyStateChange()
                    isFirstToken = false
                }
                
                fullResponse += token
                sentenceBuffer += token
                
                // Notify partial response
                delegate?.orchestrator(self, didGeneratePartial: fullResponse)
                
                // Check for sentence boundary
                if let sentence = extractCompleteSentence(&sentenceBuffer) {
                    await speakSentence(sentence)
                }
            }
            
            // Speak remaining buffer
            if !sentenceBuffer.isEmpty {
                await speakSentence(sentenceBuffer)
            }
            
            await metrics.record(.llmComplete)
            
            // Add assistant response to history
            if !fullResponse.isEmpty {
                let assistantMessage = ConversationMessage(role: .assistant, content: fullResponse)
                addToHistory(assistantMessage)
            }
            
            // Finalize metrics
            _ = await metrics.finalizeSession()
            
            // Purge KV cache after speaking
            await llmProvider.purgeKVCache()
            
            // Resume listening
            await finishSpeaking()
            
        } catch {
            if !(error is CancellationError) {
                logger.error("Generation error: \(error.localizedDescription)")
                delegate?.orchestrator(self, didEncounterError: error)
            }
            await resumeListening()
        }
    }
    
    // MARK: - Sentence Extraction
    
    private func extractCompleteSentence(_ buffer: inout String) -> String? {
        // Look for sentence-ending punctuation
        let sentenceEnders: [Character] = [".", "!", "?", "\n"]
        
        for (index, char) in buffer.enumerated() {
            if sentenceEnders.contains(char) {
                // Extract sentence including punctuation
                let endIndex = buffer.index(buffer.startIndex, offsetBy: index + 1)
                let sentence = String(buffer[..<endIndex]).trimmingCharacters(in: .whitespaces)
                
                // Remove from buffer
                buffer = String(buffer[endIndex...]).trimmingCharacters(in: .whitespaces)
                
                // Only return if substantial
                if sentence.count >= 2 {
                    return sentence
                }
            }
        }
        
        // Also trigger on comma for longer buffers
        if buffer.count > 50, let commaIndex = buffer.firstIndex(of: ",") {
            let endIndex = buffer.index(after: commaIndex)
            let sentence = String(buffer[..<endIndex]).trimmingCharacters(in: .whitespaces)
            buffer = String(buffer[endIndex...]).trimmingCharacters(in: .whitespaces)
            return sentence
        }
        
        return nil
    }
    
    // MARK: - TTS
    
    private func speakSentence(_ sentence: String) async {
        guard !sentence.isEmpty else { return }
        
        logger.debug("Speaking: \"\(sentence.prefix(30))...\"")
        
        await metrics.record(.ttsStart)
        
        do {
            let audioStream = await ttsProvider.synthesize(sentence)
            var isFirst = true
            
            for try await buffer in audioStream {
                guard !Task.isCancelled else { break }
                
                if isFirst {
                    await metrics.record(.ttsFirstAudio)
                    await metrics.record(.audioPlaybackStart)
                    isFirst = false
                }
                
                // Queue for playback
                playbackQueue?.scheduleBuffer(buffer)
            }
            
            await metrics.record(.ttsComplete)
            
        } catch {
            logger.error("TTS error: \(error.localizedDescription)")
        }
    }
    
    // MARK: - State Transitions
    
    private func finishSpeaking() async {
        delegate?.orchestratorDidFinishSpeaking(self)
        
        if config.autoResumeListening {
            await resumeListening()
        } else {
            await state.reset()
            notifyStateChange()
        }
    }
    
    private func resumeListening() async {
        // Resume audio capture
        if config.enableDynamicOffloading {
            try? audioEngine.resume()
        }
        
        // Reset VAD
        vadProcessor.reset()
        
        // Clear buffer
        audioBuffer.clear()
        
        // Return to listening state
        await state.startListening()
        notifyStateChange()
        
        // Start new metrics session
        await metrics.startSession()
    }
    
    private func notifyStateChange() {
        Task { [weak self] in
            guard let self = self else { return }
            let newState = await self.state.current
            let delegate = await self.delegate
            await MainActor.run {
                delegate?.orchestrator(self, didChangeState: newState)
            }
        }
    }
    
    // MARK: - History Management
    
    private func addToHistory(_ message: ConversationMessage) {
        conversationHistory.append(message)
        
        // Trim if needed
        while conversationHistory.count > config.maxHistoryMessages {
            // Keep system message if present
            if conversationHistory.first?.role == .system && conversationHistory.count > 1 {
                conversationHistory.remove(at: 1)
            } else {
                conversationHistory.removeFirst()
            }
        }
    }
    
    /// Clear conversation history
    public func clearHistory() {
        conversationHistory.removeAll()
        logger.info("Conversation history cleared")
    }
    
    // MARK: - Memory Management
    
    private func handleMemoryPressure() async {
        logger.warning("Memory pressure - cleaning up orchestrator")
        
        // Cancel ongoing operations
        await cancel()
        
        // Unload models
        await sttProvider.unloadModel()
        await llmProvider.unloadModel()
        await ttsProvider.unloadModel()
    }
    
    // MARK: - Metrics Access
    
    /// Get current latency summary
    public func getLatencySummary() async -> LatencyMetrics.LatencySummary {
        await metrics.getSummary()
    }
    
    /// Get recent latency history
    public func getLatencyHistory(limit: Int = 10) async -> [LatencyMetrics.LatencyRecord] {
        await metrics.getHistory(limit: limit)
    }
}

// MARK: - Factory

extension AssistantOrchestrator {
    
    /// Create orchestrator with default providers
    @MainActor
    public static func createDefault() async throws -> AssistantOrchestrator {
        let metrics = LatencyMetrics()
        let memoryGuardian = MemoryGuardian.shared
        
        let sttProvider = WhisperSTTProvider(metrics: metrics)
        let llmProvider = QwenLLMProvider(metrics: metrics)
        let ttsProvider = TTSProviderFactory.create(metrics: metrics)
        
        let orchestrator = AssistantOrchestrator(
            sttProvider: sttProvider,
            llmProvider: llmProvider,
            ttsProvider: ttsProvider,
            memoryGuardian: memoryGuardian
        )
        
        try await orchestrator.setup()
        
        return orchestrator
    }
}
