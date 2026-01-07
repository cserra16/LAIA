//
//  StreamingPipeline.swift
//  LAIA - Local AI Assistant
//
//  Coordinates LLM token streaming through sentence buffer to TTS.
//  Implements dynamic offloading and latency tracking.
//

import Foundation
import AVFoundation
import os

/// Streaming pipeline coordinator for LLM → TTS flow
/// Manages sentence-based buffering and audio output
public actor StreamingPipeline {
    
    // MARK: - Configuration
    
    public struct Configuration: Sendable {
        /// Whether to pause audio capture during LLM inference
        public var enableDynamicOffloading: Bool = true
        
        /// Prefetch next sentence while current is playing
        public var enablePrefetch: Bool = true
        
        /// Maximum concurrent TTS syntheses
        public var maxConcurrentSynthesis: Int = 2
        
        public init() {}
    }
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.laia.streaming", category: "Pipeline")
    
    private let config: Configuration
    
    /// LLM provider
    private let llmProvider: any LLMProvider
    
    /// TTS provider
    private let ttsProvider: any TTSProvider
    
    /// Audio playback queue
    private let playbackQueue: AudioPlaybackQueue
    
    /// Sentence buffer
    private let sentenceBuffer: SentenceStreamBuffer
    
    /// Latency metrics
    private let metrics: LatencyMetrics
    
    /// Audio capture engine (for dynamic offloading)
    private weak var audioCaptureEngine: AudioCaptureEngine?
    
    /// Current pipeline task
    private var pipelineTask: Task<Void, Never>?
    
    /// Is actively streaming
    private var _isStreaming: Bool = false
    
    /// Callback for generated text
    public var onTextGenerated: ((String) -> Void)?
    
    /// Callback for sentence spoken
    public var onSentenceSpoken: ((String) -> Void)?
    
    /// Callback for completion
    public var onComplete: ((String) -> Void)?
    
    /// Callback for error
    public var onError: ((Error) -> Void)?
    
    // MARK: - Computed Properties
    
    public var isStreaming: Bool {
        _isStreaming
    }
    
    // MARK: - Initialization
    
    public init(
        llmProvider: any LLMProvider,
        ttsProvider: any TTSProvider,
        playbackQueue: AudioPlaybackQueue,
        metrics: LatencyMetrics,
        configuration: Configuration = Configuration()
    ) {
        self.llmProvider = llmProvider
        self.ttsProvider = ttsProvider
        self.playbackQueue = playbackQueue
        self.metrics = metrics
        self.config = configuration
        
        self.sentenceBuffer = SentenceStreamBuffer()
        
        logger.info("StreamingPipeline initialized")
    }
    
    /// Set audio capture engine for dynamic offloading
    public func setAudioCaptureEngine(_ engine: AudioCaptureEngine?) {
        self.audioCaptureEngine = engine
    }
    
    // MARK: - Pipeline Execution
    
    /// Start streaming pipeline
    /// - Parameters:
    ///   - prompt: User prompt
    ///   - context: Conversation history
    public func start(
        prompt: String,
        context: [ConversationMessage]
    ) async throws {
        guard !_isStreaming else {
            throw LAIAError.invalidState("Pipeline already streaming")
        }
        
        logger.info("Starting streaming pipeline for prompt: \"\(prompt.prefix(30))...\"")
        
        _isStreaming = true
        
        // Dynamic offloading - pause capture
        if config.enableDynamicOffloading {
            audioCaptureEngine?.pause()
        }
        
        // Setup sentence buffer callbacks
        await sentenceBuffer.configure(
            onSentence: { [weak self] sentence in
                await self?.handleSentence(sentence)
            },
            onComplete: { [weak self] fullResponse in
                await self?.handleComplete(fullResponse)
            }
        )
        
        // Reset buffer
        await sentenceBuffer.reset()
        
        // Start generation task
        pipelineTask = Task { [weak self] in
            guard let self = self else { return }
            
            do {
                try await self.runPipeline(prompt: prompt, context: context)
            } catch {
                if !(error is CancellationError) {
                    self.logger.error("Pipeline error: \(error.localizedDescription)")
                    let errorHandler = await self.onError
                    errorHandler?(error)
                }
                await self.cleanup()
            }
        }
    }
    
    private func runPipeline(
        prompt: String,
        context: [ConversationMessage]
    ) async throws {
        await metrics.record(.llmStart)
        
        var isFirstToken = true
        
        // Get token stream from LLM
        let tokenStream = await llmProvider.generate(prompt: prompt, context: context)
        
        // Process tokens
        for try await token in tokenStream {
            guard !Task.isCancelled else {
                throw LAIAError.cancelled
            }
            
            if isFirstToken {
                await metrics.record(.llmFirstToken)
                isFirstToken = false
            }
            
            // Add to sentence buffer (may trigger TTS)
            await sentenceBuffer.addToken(token)
            
            // Notify text generated
            let accumulated = await sentenceBuffer.accumulatedResponse
            onTextGenerated?(accumulated)
        }
        
        await metrics.record(.llmComplete)
        
        // Flush remaining buffer
        await sentenceBuffer.flush()
        
        // Wait for playback to complete
        await playbackQueue.waitForCompletion()
        
        logger.info("Pipeline complete")
        
        await cleanup()
    }
    
    // MARK: - Sentence Handling
    
    private func handleSentence(_ sentence: String) async {
        logger.debug("Processing sentence: \"\(sentence.prefix(30))...\"")
        
        await metrics.record(.ttsStart)
        
        do {
            // Synthesize sentence
            let audioStream = await ttsProvider.synthesize(sentence)
            var isFirst = true
            
            for try await buffer in audioStream {
                guard !Task.isCancelled else { return }
                
                if isFirst {
                    await metrics.record(.ttsFirstAudio)
                    await metrics.record(.audioPlaybackStart)
                    isFirst = false
                }
                
                // Queue for playback
                playbackQueue.scheduleBuffer(buffer)
            }
            
            await metrics.record(.ttsComplete)
            
            onSentenceSpoken?(sentence)
            
        } catch {
            logger.error("TTS error for sentence: \(error.localizedDescription)")
        }
    }
    
    private func handleComplete(_ fullResponse: String) async {
        logger.info("Generation complete: \(fullResponse.count) chars")
        
        // Finalize metrics
        let record = await metrics.finalizeSession()
        
        logger.info("""
            Pipeline metrics:
            • TTFT: \(String(format: "%.0f", record.timeToFirstToken ?? -1))ms
            • Audio Out: \(String(format: "%.0f", record.audioOut ?? -1))ms
            • Total: \(String(format: "%.0f", record.totalE2E ?? -1))ms
            """)
        
        onComplete?(fullResponse)
    }
    
    // MARK: - Control
    
    /// Cancel the current pipeline
    public func cancel() async {
        logger.info("Cancelling pipeline")
        
        pipelineTask?.cancel()
        pipelineTask = nil
        
        playbackQueue.stop()
        await sentenceBuffer.reset()
        
        await cleanup()
    }
    
    private func cleanup() async {
        _isStreaming = false
        
        // Purge LLM cache
        await llmProvider.purgeKVCache()
        
        // Resume audio capture if offloaded
        if config.enableDynamicOffloading {
            try? audioCaptureEngine?.resume()
        }
    }
    
    // MARK: - Queries
    
    /// Get current accumulated response
    public func getCurrentResponse() async -> String {
        await sentenceBuffer.accumulatedResponse
    }
    
    /// Get sentence count
    public func getSentenceCount() async -> Int {
        await sentenceBuffer.emittedSentenceCount
    }
}

// MARK: - Pipeline Builder

extension StreamingPipeline {
    
    /// Builder for creating configured pipeline
    public class Builder {
        private var llmProvider: (any LLMProvider)?
        private var ttsProvider: (any TTSProvider)?
        private var playbackQueue: AudioPlaybackQueue?
        private var metrics: LatencyMetrics?
        private var config = Configuration()
        
        public init() {}
        
        public func withLLMProvider(_ provider: any LLMProvider) -> Builder {
            self.llmProvider = provider
            return self
        }
        
        public func withTTSProvider(_ provider: any TTSProvider) -> Builder {
            self.ttsProvider = provider
            return self
        }
        
        public func withPlaybackQueue(_ queue: AudioPlaybackQueue) -> Builder {
            self.playbackQueue = queue
            return self
        }
        
        public func withMetrics(_ metrics: LatencyMetrics) -> Builder {
            self.metrics = metrics
            return self
        }
        
        public func withDynamicOffloading(_ enabled: Bool) -> Builder {
            self.config.enableDynamicOffloading = enabled
            return self
        }
        
        public func build() throws -> StreamingPipeline {
            guard let llm = llmProvider else {
                throw LAIAError.invalidState("LLM provider required")
            }
            guard let tts = ttsProvider else {
                throw LAIAError.invalidState("TTS provider required")
            }
            guard let queue = playbackQueue else {
                throw LAIAError.invalidState("Playback queue required")
            }
            guard let metrics = metrics else {
                throw LAIAError.invalidState("Metrics required")
            }
            
            return StreamingPipeline(
                llmProvider: llm,
                ttsProvider: tts,
                playbackQueue: queue,
                metrics: metrics,
                configuration: config
            )
        }
    }
}
