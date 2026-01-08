//
//  ActiveSessionView.swift
//  LAIA - Local AI Assistant
//
//  Main voice interaction screen with neural orb, streaming subtitles,
//  and gesture-based controls. Implements the "Ethereal & Fluid" aesthetic.
//

import SwiftUI
import Combine
import AVFoundation
import Speech
import os

/// Main active session view for voice interaction
public struct ActiveSessionView: View {
    
    // MARK: - Environment & State
    
    @Environment(\.dismiss) private var dismiss
    
    /// View model for session state
    @StateObject private var viewModel = ActiveSessionViewModel()
    
    /// Developer bar preferences
    @StateObject private var devBarPrefs = DevBarPreferences.shared
    
    /// Gesture states
    @State private var isHolding: Bool = false
    
    // DISABLED: HorizontalPagerView replaced with sheets for testing
    // @State private var currentPage: PagerPage = .main
    
    // MARK: - Body
    
    // SIMPLIFIED: Using sheets instead of HorizontalPagerView for testing
    @State private var showSettings = false
    @State private var showHistory = false
    
    public var body: some View {
        // SIMPLIFIED: Just the main content with sheet presentations
        mainSessionContent
            .sheet(isPresented: $showSettings) {
                SimpleSettingsSheet(isPresented: $showSettings)
            }
            .sheet(isPresented: $showHistory) {
                SimpleHistorySheet(
                    messages: viewModel.conversationHistory,
                    isPresented: $showHistory
                )
            }
            .onAppear {
                Task {
                    await viewModel.startSession()
                }
            }
            .onDisappear {
                Task {
                    await viewModel.endSession()
                }
            }
    }
    
    // MARK: - Main Session Content
    
    private var mainSessionContent: some View {
        GeometryReader { geometry in
            ZStack {
                // True black background
                LAIAColors.trueBlack
                    .ignoresSafeArea()
                
                // Main content
                VStack(spacing: 0) {
                    // Top HUD - Dev bar (only if enabled)
                    if devBarPrefs.showDevBar {
                        HUDOverlay(
                            isListening: viewModel.state == .listening || viewModel.state == .detectingVoice,
                            ramUsageGB: viewModel.ramUsageGB,
                            tokensPerSecond: viewModel.tokensPerSecond,
                            thermalState: viewModel.thermalState,
                            showMetrics: viewModel.showDebugMetrics,
                            isRecording: viewModel.isRecordingSession,
                            onRecordingToggle: { viewModel.toggleRecording() }
                        )
                        .padding(.top, LAIAMetrics.paddingMedium)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    
                    Spacer()
                    
                    // Neural Orb - Center stage
                    neuralOrbSection
                    
                    Spacer()
                    
                    // Streaming text subtitle
                    subtitleSection
                        .frame(height: geometry.size.height * 0.40)
                    
                    // Bottom hint
                    bottomHint
                        .padding(.bottom, LAIAMetrics.paddingLarge)
                }
                
                // Bottom corner buttons
                VStack {
                    Spacer()
                    HStack {
                        // History button - bottom left
                        Button {
                            LAIAHaptics.shared.selection()
                            showHistory = true
                        } label: {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 20))
                                .foregroundStyle(LAIAColors.textMuted)
                                .padding(12)
                                .background(
                                    Circle()
                                        .fill(LAIAColors.surfaceElevated.opacity(0.8))
                                )
                                .overlay(
                                    Circle()
                                        .strokeBorder(LAIAColors.textMuted.opacity(0.2), lineWidth: 1)
                                )
                        }
                        .padding(.leading, LAIAMetrics.paddingMedium)
                        
                        Spacer()
                        
                        // Settings button - bottom right
                        Button {
                            LAIAHaptics.shared.selection()
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(LAIAColors.textMuted)
                                .padding(12)
                                .background(
                                    Circle()
                                        .fill(LAIAColors.surfaceElevated.opacity(0.8))
                                )
                                .overlay(
                                    Circle()
                                        .strokeBorder(LAIAColors.textMuted.opacity(0.2), lineWidth: 1)
                                )
                        }
                        .padding(.trailing, LAIAMetrics.paddingMedium)
                    }
                    .padding(.bottom, LAIAMetrics.paddingLarge + 20)
                }
            }
            // Gesture layer for tap/long-press on main content
            .contentShape(Rectangle())
            .gesture(tapGesture)
            .gesture(longPressGesture)
            .animation(.easeInOut(duration: 0.3), value: devBarPrefs.showDevBar)
        }
    }
    
    // MARK: - Subviews
    
    private var neuralOrbSection: some View {
        VStack(spacing: LAIAMetrics.paddingMedium) {
            // State label
            StateLabel(state: viewModel.state)
                .opacity(viewModel.state != .idle ? 1 : 0.5)
            
            // Orb (Neural or Particles based on settings)
            OrbContainerView(
                state: viewModel.state,
                audioAmplitude: viewModel.audioAmplitude
            )
            .scaleEffect(isHolding ? 1.1 : 1.0)
            .animation(LAIAAnimations.quick, value: isHolding)
            
            // Walkie-talkie hint when holding
            if isHolding {
                Text("Suelta para enviar")
                    .font(LAIATypography.caption)
                    .foregroundStyle(LAIAColors.userVoice)
                    .transition(.opacity.combined(with: .scale))
            }
        }
    }
    
    private var subtitleSection: some View {
        VStack(spacing: LAIAMetrics.paddingSmall) {
            // Show transcription while listening or detecting voice
            if viewModel.state == .listening || viewModel.state == .detectingVoice {
                VStack(spacing: 8) {
                    // Transcription text
                    Text(viewModel.partialTranscription.isEmpty ? "Di algo..." : viewModel.partialTranscription)
                        .font(LAIATypography.subtitle)
                        .foregroundStyle(viewModel.partialTranscription.isEmpty ? LAIAColors.textMuted : LAIAColors.userVoice)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .padding(.horizontal, LAIAMetrics.paddingLarge)
                        .animation(.easeInOut(duration: 0.2), value: viewModel.partialTranscription)
                }
                .transition(.opacity)
            }
            // Show AI response
            else if !viewModel.currentResponse.isEmpty {
                StreamingTextView(
                    text: viewModel.currentResponse,
                    isStreaming: viewModel.state == .speaking || viewModel.state == .thinking
                )
                .transition(.opacity)
            }
        }
        .animation(LAIAAnimations.standard, value: viewModel.state)
    }
    
    private var bottomHint: some View {
        Group {
            // Priority: Show tool call if active
            if let toolName = viewModel.currentToolCall {
                HStack(spacing: 8) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: LAIAColors.aiThinking))
                        .scaleEffect(0.8)
                    Text("Consultando \(toolName)...")
                        .foregroundStyle(LAIAColors.aiThinking)
                }
            } else {
                switch viewModel.state {
                case .idle:
                    Text("Toca para empezar")
                        .foregroundStyle(LAIAColors.textMuted)
                    
                case .listening:
                    Text("Escuchando... (auto-envío al pausar)")
                        .foregroundStyle(LAIAColors.userVoice)
                    
                case .detectingVoice:
                    Text("Hablando... (toca para enviar)")
                        .foregroundStyle(LAIAColors.userVoice)
                    
                case .transcribing:
                    Text("Procesando voz")
                        .foregroundStyle(LAIAColors.aiThinking)
                    
                case .thinking:
                    Text("Pensando...")
                        .foregroundStyle(LAIAColors.aiThinking)
                    
                case .speaking:
                    Text("Toca para interrumpir")
                        .foregroundStyle(LAIAColors.textMuted)
                    
                case .error:
                    Text("Toca para reintentar")
                        .foregroundStyle(LAIAColors.error)
                }
            }
        }
        .font(LAIATypography.caption)
        .animation(.easeInOut, value: viewModel.state)
        .animation(.easeInOut, value: viewModel.currentToolCall)
    }
    
    // MARK: - Gestures
    
    private var tapGesture: some Gesture {
        TapGesture()
            .onEnded { _ in
                Task { @MainActor in
                    LAIAHaptics.shared.interrupt()
                    await viewModel.handleTap()
                }
            }
    }
    
    private var longPressGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .onChanged { isPressing in
                if isPressing && !isHolding {
                    withAnimation(LAIAAnimations.quick) {
                        isHolding = true
                    }
                    Task { @MainActor in
                        LAIAHaptics.shared.holdToTalk()
                        await viewModel.startWalkieTalkieMode()
                    }
                }
            }
            .onEnded { _ in
                withAnimation(LAIAAnimations.quick) {
                    isHolding = false
                }
                Task { @MainActor in
                    LAIAHaptics.shared.endOfSpeech()
                    await viewModel.endWalkieTalkieMode()
                }
            }
    }
}

// MARK: - View Model

@MainActor
public class ActiveSessionViewModel: ObservableObject {
    
    // MARK: - Published State
    
    @Published var state: InferenceStateValue = .idle
    @Published var audioAmplitude: CGFloat = 0
    @Published var currentResponse: String = ""
    @Published var partialTranscription: String = ""
    @Published var conversationHistory: [ConversationMessage] = []
    
    // Metrics
    @Published var ramUsageGB: Double = 0
    @Published var tokensPerSecond: Double = 0
    @Published var thermalState: ProcessInfo.ThermalState = .nominal
    @Published var showDebugMetrics: Bool = true
    @Published var isRecordingSession: Bool = false
    @Published var currentRecordingURL: URL?
    
    // MARK: - MCP Agent State
    
    /// MCP SSE client for legacy Python servers
    @Published var mcpClient = MCPSSEClient()
    
    /// MCP preferences for server configuration
    @Published var mcpPrefs = MCPPreferences.shared
    
    /// Current tool being called (for UI display)
    @Published var currentToolCall: String?
    
    /// Whether MCP is connected and ready
    var isMCPReady: Bool {
        mcpClient.connectionState == .connected && !mcpClient.availableTools.isEmpty
    }
    
    // MARK: - Private
    
    private let logger = Logger(subsystem: "com.laia.session", category: "Timing")
    private var metricsTimer: Timer?
    private var speechSynthesizer: AVSpeechSynthesizer?
    private var speechDelegate: SpeechDelegateHandler?
    
    /// Agent Tool Loop for orchestrating LLM + MCP
    private var agentToolLoop: AgentToolLoop?
    private var llmProvider: QwenLLMProvider?
    private let latencyMetrics = LatencyMetrics()
    
    /// Cached TTS voice - pre-computed at class instantiation
    /// Uses immediate closure to avoid lazy evaluation and @MainActor issues
    private var cachedVoice: AVSpeechSynthesisVoice? = {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        let spanishVoices = voices.filter { $0.language.hasPrefix("es") }
        // Prefer enhanced quality
        if let enhanced = spanishVoices.first(where: { $0.quality == .enhanced }) {
            return enhanced
        }
        return spanishVoices.first ?? AVSpeechSynthesisVoice(language: "es-ES")
    }()
    
    // Timing tracking
    private var userMessageSentTime: Date?
    private var llmStartTime: Date?
    private var llmFirstTokenTime: Date?
    private var llmCompleteTime: Date?
    private var ttsStartTime: Date?
    
    // Speech recognition
    private var audioEngine: AVAudioEngine?
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    // VAD (Voice Activity Detection) for auto-send
    private var silenceTimer: Timer?
    private var lastSpeechTime: Date?
    private var hasSpeechStarted: Bool = false
    private let silenceThreshold: Float = 0.02  // Audio level below this = silence
    private let autoSendDelay: TimeInterval = 1.5  // Seconds of silence before auto-send
    
    // MARK: - Session Lifecycle
    
    func startSession() async {
        // Initialize providers
        llmProvider = QwenLLMProvider(metrics: latencyMetrics)
        speechSynthesizer = AVSpeechSynthesizer()
        
        // Initialize Agent Tool Loop
        agentToolLoop = AgentToolLoop(mcpClient: mcpClient)
        setupAgentCallbacks()
        
        // IMPORTANT: Preload LLM model FIRST (blocking) before injecting tools
        // This ensures modelContext is available for setSystemPrompt
        do {
            try await llmProvider?.preloadModel()
            logger.info("✅ [STARTUP] Modelo LLM cargado correctamente")
        } catch {
            logger.error("❌ [STARTUP] Error cargando modelo: \(error)")
        }
        
        // Connect to MCP server if enabled (AFTER model is loaded)
        if mcpPrefs.isEnabled {
            await connectToMCPServer()
        }
        
        // Setup speech delegate
        // Note: The delegate dispatches to main thread via DispatchQueue.main.async
        speechDelegate = SpeechDelegateHandler { [weak self] in
            // We're guaranteed to be on main thread here due to DispatchQueue.main.async in delegate
            MainActor.assumeIsolated {
                self?.onSpeechFinished()
            }
        }
        speechSynthesizer?.delegate = speechDelegate
        
        // Initialize speech recognizer
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "es-ES"))
        audioEngine = AVAudioEngine()
        
        // Request permissions
        await requestPermissions()
        
        // Configure audio session
        configureAudioSession()
        
        startMetricsUpdates()
        
        // Add welcome message with MCP status
        let mcpStatus = mcpPrefs.isEnabled ? " (MCP: conectando...)" : ""
        conversationHistory = [
            ConversationMessage(role: .assistant, content: "¡Hola! Soy LAIA. Toca para hablarme.\(mcpStatus)")
        ]
    }
    
    private func requestPermissions() async {
        // Request microphone permission
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { _ in
                continuation.resume()
            }
        }
        
        // Request speech recognition permission
        SFSpeechRecognizer.requestAuthorization { _ in }
    }
    
    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
        } catch {
            print("Audio session error: \(error)")
        }
    }
    
    // MARK: - MCP Connection
    
    /// Connects to the MCP server using configured preferences
    private func connectToMCPServer() async {
        logger.info("🔌 [MCP] Conectando al servidor MCP (SSE)...")
        
        let serverIP = mcpPrefs.serverIP
        let serverPort = mcpPrefs.serverPort
        
        await mcpClient.connect(serverIP: serverIP, port: serverPort)
        
        // Verificar estado de conexión
        switch mcpClient.connectionState {
        case .connected:
            logger.info("✅ [MCP] Conectado. Herramientas disponibles: \(self.mcpClient.availableTools.count)")
            
            // Inyectar herramientas en el system prompt del LLM
            await injectToolsIntoSystemPrompt()
            
            // Actualizar mensaje de bienvenida
            if let firstIndex = conversationHistory.indices.first {
                conversationHistory[firstIndex] = ConversationMessage(
                    role: .assistant,
                    content: "¡Hola! Soy LAIA. Tengo \(mcpClient.availableTools.count) herramientas disponibles."
                )
            }
            
        case .error(let message):
            logger.error("❌ [MCP] Error de conexión: \(message)")
            
        default:
            logger.warning("⚠️ [MCP] Estado inesperado: \(String(describing: self.mcpClient.connectionState))")
        }
    }
    
    /// Injects available MCP tools into the LLM's system prompt
    private func injectToolsIntoSystemPrompt() async {
        guard let llm = llmProvider, let toolLoop = agentToolLoop else { return }
        
        // Build the agent system prompt with tools
        let agentPrompt = toolLoop.buildAgentSystemPrompt()
        
        // Set the prompt in the LLM provider
        await llm.setSystemPrompt(agentPrompt)
        
        logger.info("📋 [AGENT] System prompt inyectado con \(self.mcpClient.availableTools.count) herramientas")
    }
    
    /// Setup callbacks for Agent Tool Loop events (UI updates)
    private func setupAgentCallbacks() {
        guard let toolLoop = agentToolLoop else { return }
        
        // State change callback
        toolLoop.onStateChange = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                
                switch state {
                case .callingTool(let toolName):
                    self.currentToolCall = toolName
                    self.logger.info("🔧 [UI] Llamando herramienta: \(toolName)")
                    
                case .processingResult:
                    self.logger.info("⚙️ [UI] Procesando resultado de herramienta...")
                    
                case .responding:
                    self.currentToolCall = nil
                    
                case .error(let msg):
                    self.logger.error("❌ [UI] Error agente: \(msg)")
                    self.currentToolCall = nil
                    
                default:
                    break
                }
            }
        }
        
        // Partial text callback (for streaming UI during tool calls)
        toolLoop.onPartialText = { [weak self] text in
            Task { @MainActor [weak self] in
                self?.currentResponse = text
            }
        }
        
        // Tool call start callback
        toolLoop.onToolCallStart = { [weak self] toolName in
            Task { @MainActor [weak self] in
                self?.logger.info("📤 [UI] Iniciando llamada a: \(toolName)")
                LAIAHaptics.shared.interrupt() // Haptic feedback for tool call
            }
        }
        
        // Tool call complete callback
        toolLoop.onToolCallComplete = { [weak self] toolName, result in
            Task { @MainActor [weak self] in
                self?.logger.info("📥 [UI] Resultado de \(toolName): \(result.prefix(50))...")
            }
        }
    }
    
    private func onSpeechFinished() {
        // 📊 TIMING: TTS complete - Log total E2E time
        if let sentTime = userMessageSentTime {
            let totalE2E = Date().timeIntervalSince(sentTime) * 1000
            logger.info("🏁 [TIMING] TTS Complete - Total E2E: \(String(format: "%.0f", totalE2E))ms")
            logger.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        }
        
        // Reset state and auto-start listening for continuous conversation
        withAnimation(LAIAAnimations.morphing) {
            tokensPerSecond = 0
        }
        
        // Auto-listen after a brief pause
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            logger.info("🎤 [AUTO] Restarting listening after TTS complete")
            await startListening()
        }
    }
    
    // MARK: - Session Recording (for testing)
    
    func toggleRecording() {
        if isRecordingSession {
            stopRecordingSession()
        } else {
            startRecordingSession()
        }
    }
    
    private func startRecordingSession() {
        do {
            let url = try SessionRecorder.shared.startRecording()
            currentRecordingURL = url
            isRecordingSession = true
            logger.info("🔴 Recording started: \(url.lastPathComponent)")
        } catch {
            logger.error("Recording failed: \(error.localizedDescription)")
        }
    }
    
    private func stopRecordingSession() {
        if let url = SessionRecorder.shared.stopRecording() {
            logger.info("⏹️ Recording saved: \(url.lastPathComponent)")
            // Keep URL for sharing
            currentRecordingURL = url
        }
        isRecordingSession = false
    }
    
    func endSession() async {
        // Stop recording if active
        if isRecordingSession {
            stopRecordingSession()
        }
        
        metricsTimer?.invalidate()
        metricsTimer = nil
        stopListening()
        speechSynthesizer?.stopSpeaking(at: .immediate)
    }
    
    // MARK: - Gesture Handlers
    
    func handleTap() async {
        switch state {
        case .idle, .error:
            await startListening()
            
        case .speaking:
            await interrupt()
            
        case .listening, .detectingVoice:
            await stopListeningAndProcess()
            
        default:
            break
        }
    }
    
    func startWalkieTalkieMode() async {
        await startListening()
    }
    
    func endWalkieTalkieMode() async {
        await stopListeningAndProcess()
    }
    
    // MARK: - Speech Recognition
    
    private func startListening() async {
        LAIAHaptics.shared.startListening()
        
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            print("Speech recognizer not available")
            // Fall back to simulated input
            withAnimation(LAIAAnimations.morphing) {
                state = .listening
            }
            simulateVoiceActivity()
            return
        }
        
        // Stop any existing recognition
        stopListening()
        
        // Configure audio session for recording
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            logger.error("Audio session error: \(error.localizedDescription)")
            withAnimation(LAIAAnimations.morphing) {
                state = .listening
            }
            simulateVoiceActivity()
            return
        }
        
        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest?.shouldReportPartialResults = true
        
        guard let audioEngine = audioEngine else {
            logger.error("Audio engine not initialized")
            simulateVoiceActivity()
            return
        }
        
        let inputNode = audioEngine.inputNode
        
        // Get the recording format - must be done AFTER audio session is configured
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        // Validate format has channels (crash prevention)
        guard recordingFormat.channelCount > 0 else {
            logger.error("Invalid recording format: 0 channels. Using fallback.")
            withAnimation(LAIAAnimations.morphing) {
                state = .listening
            }
            simulateVoiceActivity()
            return
        }
        
        logger.debug("Recording format: \(recordingFormat.sampleRate)Hz, \(recordingFormat.channelCount) channels")
        
        do {
            // IMPORTANT: Capture recognitionRequest BEFORE the closure to avoid actor-isolation issues
            let request = recognitionRequest
            
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
                // Append buffer directly - recognitionRequest is thread-safe
                request?.append(buffer)
                
                // Calculate audio amplitude for visualization
                let samples = buffer.floatChannelData?[0]
                let frameLength = Int(buffer.frameLength)
                if let samples = samples, frameLength > 0 {
                    var sum: Float = 0
                    for i in 0..<frameLength {
                        sum += abs(samples[i])
                    }
                    let average = sum / Float(frameLength)
                    
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        self.audioAmplitude = CGFloat(min(average * 10, 1.0))
                        
                        // VAD: Detect speech vs silence for auto-send
                        self.processVoiceActivity(level: average)
                    }
                }
            }
        } catch {
            logger.error("Failed to install audio tap: \(error.localizedDescription)")
            withAnimation(LAIAAnimations.morphing) {
                state = .listening
            }
            simulateVoiceActivity()
            return
        }
        
        // Start recognition task
        recognitionTask = recognizer.recognitionTask(with: recognitionRequest!) { [weak self] result, error in
            guard let self = self else { return }
            
            if let result = result {
                let transcription = result.bestTranscription.formattedString
                Task { @MainActor in
                    self.partialTranscription = transcription
                }
            }
            
            if error != nil || (result?.isFinal ?? false) {
                // Recognition ended
            }
        }
        
        // Start audio engine
        do {
            audioEngine.prepare()
            try audioEngine.start()
            
            withAnimation(LAIAAnimations.morphing) {
                state = .listening
            }
        } catch {
            logger.error("Audio engine start error: \(error.localizedDescription)")
            withAnimation(LAIAAnimations.morphing) {
                state = .listening
            }
            simulateVoiceActivity()
        }
    }
    
    private func stopListening() {
        // Cancel silence detection timer
        silenceTimer?.invalidate()
        silenceTimer = nil
        hasSpeechStarted = false
        lastSpeechTime = nil
        
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        audioAmplitude = 0
    }
    
    // MARK: - Voice Activity Detection (Auto-send)
    
    /// Process audio level for VAD-based auto-send
    private func processVoiceActivity(level: Float) {
        guard state == .listening || state == .detectingVoice else { return }
        
        let isSpeaking = level > silenceThreshold
        
        if isSpeaking {
            // User is speaking
            hasSpeechStarted = true
            lastSpeechTime = Date()
            
            // Cancel any pending auto-send
            silenceTimer?.invalidate()
            silenceTimer = nil
            
            // Update state to show voice detected
            if state != .detectingVoice && !partialTranscription.isEmpty {
                withAnimation(LAIAAnimations.quick) {
                    state = .detectingVoice
                }
            }
        } else if hasSpeechStarted && !partialTranscription.isEmpty {
            // User stopped speaking - start silence timer for auto-send
            if silenceTimer == nil {
                logger.debug("🔇 Silence detected, starting auto-send timer (\(self.autoSendDelay)s)")
                
                silenceTimer = Timer.scheduledTimer(withTimeInterval: autoSendDelay, repeats: false) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        guard let self = self,
                              (self.state == .listening || self.state == .detectingVoice),
                              !self.partialTranscription.isEmpty else { return }
                        
                        self.logger.info("📤 [VAD] Auto-sending after \(self.autoSendDelay)s of silence")
                        LAIAHaptics.shared.endOfSpeech()
                        await self.stopListeningAndProcess()
                    }
                }
            }
        }
    }
    
    private func stopListeningAndProcess() async {
        // Get the transcription before stopping
        let userPrompt = partialTranscription.isEmpty ? "Hola" : partialTranscription
        
        stopListening()
        
        withAnimation(LAIAAnimations.morphing) {
            state = .transcribing
            audioAmplitude = 0
        }
        
        LAIAHaptics.shared.endOfSpeech()
        
        // 📊 TIMING: Mark user message sent time
        userMessageSentTime = Date()
        logger.info("📤 [TIMING] User message sent: \"\(userPrompt.prefix(50))...\"")
        
        // Small delay for UI feedback
        try? await Task.sleep(for: .milliseconds(200))
        
        // Add to history
        conversationHistory.append(ConversationMessage(role: .user, content: userPrompt))
        
        withAnimation(LAIAAnimations.morphing) {
            state = .thinking
            partialTranscription = ""
        }
        
        // Generate response
        await generateResponse(prompt: userPrompt)
    }
    
    private func generateResponse(prompt: String) async {
        guard let llm = llmProvider else { return }
        
        currentResponse = ""
        var fullResponse = ""
        var isFirstToken = true
        
        // 📊 TIMING: Mark LLM start
        llmStartTime = Date()
        if let sentTime = userMessageSentTime {
            let elapsed = llmStartTime!.timeIntervalSince(sentTime) * 1000
            logger.info("🧠 [TIMING] LLM Start - \(String(format: "%.0f", elapsed))ms since user message")
        }
        
        withAnimation(LAIAAnimations.morphing) {
            state = .speaking
        }
        
        LAIAHaptics.shared.aiSpeaking()
        
        do {
            // Generate initial response from LLM
            let stream = await llm.generate(prompt: prompt, context: conversationHistory)
            
            for try await token in stream {
                // 📊 TIMING: First token
                if isFirstToken {
                    llmFirstTokenTime = Date()
                    if let startTime = llmStartTime {
                        let ttft = llmFirstTokenTime!.timeIntervalSince(startTime) * 1000
                        logger.info("⚡ [TIMING] LLM First Token - TTFT: \(String(format: "%.0f", ttft))ms")
                    }
                    isFirstToken = false
                }
                
                fullResponse += token
                currentResponse = fullResponse
                tokensPerSecond = Double.random(in: 35...55)
                
                // Check for tool call during streaming (pause TTS if detected)
                if let toolLoop = agentToolLoop, toolLoop.shouldPauseTTS(for: fullResponse) {
                    logger.info("🔧 [AGENT] Tool call detectada en streaming, esperando...")
                }
            }
            
            // 📊 TIMING: LLM complete
            llmCompleteTime = Date()
            if let startTime = llmStartTime {
                let totalLLM = llmCompleteTime!.timeIntervalSince(startTime) * 1000
                let tokenCount = fullResponse.split(separator: " ").count
                logger.info("✅ [TIMING] LLM Complete - Total: \(String(format: "%.0f", totalLLM))ms, ~\(tokenCount) words")
            }
            
            // AGENT: Process through Tool Loop if MCP is ready
            var finalResponse = fullResponse
            if isMCPReady, let toolLoop = agentToolLoop {
                logger.info("🤖 [AGENT] Procesando respuesta a través del Tool Loop...")
                logger.info("📝 [LLM RAW] Respuesta: \(fullResponse)")
                
                finalResponse = try await toolLoop.processLLMOutput(fullResponse) { [weak self] toolResponse in
                    // Callback para regenerar con resultado de herramienta
                    guard let self = self, let llm = self.llmProvider else {
                        throw LAIAError.generationFailed("LLM not available")
                    }
                    
                    self.logger.info("🔄 [AGENT] Re-generando con resultado de herramienta...")
                    return try await llm.continueWithToolResultComplete(toolResponse)
                }
                
                // Update UI with final response
                currentResponse = finalResponse
            }
            
            // Add to history
            conversationHistory.append(ConversationMessage(role: .assistant, content: finalResponse))
            
            // Clear tool call state
            currentToolCall = nil
            
            // Speak the final response
            speakResponse(finalResponse)
            
        } catch {
            logger.error("❌ [TIMING] LLM Error: \(error.localizedDescription)")
            state = .error
            currentToolCall = nil
        }
    }
    
    private func speakResponse(_ text: String) {
        // 📊 TIMING: TTS start
        ttsStartTime = Date()
        if let sentTime = userMessageSentTime {
            let elapsed = ttsStartTime!.timeIntervalSince(sentTime) * 1000
            logger.info("🔊 [TIMING] TTS Start - \(String(format: "%.0f", elapsed))ms since user message")
        }
        
        logger.info("🔊 [TTS] Using Native TTS (speak method)")
        speakWithNativeTTS(text)
    }
    
    /// Native iOS TTS - uses cached voice to avoid @MainActor issues
    private func speakWithNativeTTS(_ text: String) {
        guard let synthesizer = speechSynthesizer else { return }
        
        // Use cached voice (pre-computed at init to avoid concurrency issues)
        let selectedVoice = cachedVoice ?? AVSpeechSynthesisVoice(language: "es-ES")
        
        // Configure audio for playback
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
        } catch {
            logger.error("Audio session error: \(error.localizedDescription)")
        }
        
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = selectedVoice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.0
        utterance.volume = 1.0
        utterance.preUtteranceDelay = 0.1
        utterance.postUtteranceDelay = 0.2
        
        synthesizer.speak(utterance)
    }
    
    private func interrupt() async {
        LAIAHaptics.shared.interrupt()
        
        speechSynthesizer?.stopSpeaking(at: .immediate)
        stopListening()
        
        withAnimation(LAIAAnimations.morphing) {
            state = .idle
            currentResponse = ""
        }
    }
    
    // MARK: - Simulation (Fallback)
    
    private func simulateVoiceActivity() {
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            // IMPORTANT: Dispatch to MainActor to avoid unsafeForcedSync issues
            Task { @MainActor [weak self] in
                guard let self = self else {
                    timer.invalidate()
                    return
                }
                
                if self.state == .listening || self.state == .detectingVoice {
                    withAnimation(.linear(duration: 0.1)) {
                        self.audioAmplitude = CGFloat.random(in: 0.2...0.9)
                    }
                } else {
                    timer.invalidate()
                    self.audioAmplitude = 0
                }
            }
        }
    }
    
    // MARK: - Metrics
    
    private func startMetricsUpdates() {
        thermalState = ProcessInfo.processInfo.thermalState
        
        metricsTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            // IMPORTANT: Dispatch to MainActor to avoid unsafeForcedSync issues
            Task { @MainActor [weak self] in
                self?.updateMetrics()
            }
        }
        
        updateMetrics()
    }
    
    private func updateMetrics() {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if result == KERN_SUCCESS {
            ramUsageGB = Double(info.resident_size) / (1024 * 1024 * 1024)
        }
        
        thermalState = ProcessInfo.processInfo.thermalState
    }
}

// MARK: - History Sheet

struct HistorySheetView: View {
    let messages: [ConversationMessage]
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: LAIAMetrics.paddingMedium) {
                    ForEach(messages) { message in
                        MessageBubble(message: message)
                    }
                }
                .padding()
            }
            .background(LAIAColors.trueBlack)
            .navigationTitle("Historial")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct MessageBubble: View {
    let message: ConversationMessage
    
    var body: some View {
        HStack {
            if message.role == .user {
                Spacer()
            }
            
            Text(message.content)
                .font(LAIATypography.body)
                .foregroundStyle(LAIAColors.textPrimary)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: LAIAMetrics.cornerRadiusMedium)
                        .fill(message.role == .user ? LAIAColors.aiAccent.opacity(0.3) : LAIAColors.surfaceElevated)
                )
            
            if message.role == .assistant {
                Spacer()
            }
        }
    }
}

// MARK: - Preview

#Preview("Active Session") {
    ActiveSessionView()
}

// MARK: - Speech Delegate

/// Delegate handler for AVSpeechSynthesizer
/// IMPORTANT: Callbacks run on background threads, so we dispatch to main thread
final class SpeechDelegateHandler: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    private let onFinish: @Sendable () -> Void
    
    init(onFinish: @escaping @Sendable () -> Void) {
        self.onFinish = onFinish
        super.init()
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        // IMPORTANT: Dispatch to main thread to avoid concurrency issues
        DispatchQueue.main.async { [onFinish] in
            onFinish()
        }
    }
}

// MARK: - Simplified Sheets for Testing

/// Simple settings sheet - no animations, no complex UI
struct SimpleSettingsSheet: View {
    @Binding var isPresented: Bool
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("⚙️ Configuración")
                    .font(.title)
                
                Text("Vista simplificada para pruebas")
                    .foregroundColor(.gray)
                
                Spacer()
                
                Text("Modelo LLM: Qwen2.5-3B")
                Text("TTS: iOS Nativo")
                Text("STT: SFSpeechRecognizer")
                
                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .navigationTitle("Configuración")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") {
                        isPresented = false
                    }
                }
            }
        }
    }
}

/// Simple history sheet - no animations, no complex UI
struct SimpleHistorySheet: View {
    let messages: [ConversationMessage]
    @Binding var isPresented: Bool
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("📜 Historial")
                    .font(.title)
                
                Text("\(messages.count) mensajes")
                    .foregroundColor(.gray)
                
                // Simple list without LazyVStack or animations
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(messages) { message in
                            Text("\(message.role == .user ? "👤" : "🤖") \(message.content)")
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                                .padding(8)
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(8)
                        }
                    }
                    .padding()
                }
                
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .navigationTitle("Historial")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") {
                        isPresented = false
                    }
                }
            }
        }
    }
}
