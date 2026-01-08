//
//  QwenLLMProvider.swift
//  LAIA - Local AI Assistant
//
//  LLM provider using MLX Swift LM.
//  Filters thinking tokens and handles GPU background errors.
//

import Foundation
import os

#if canImport(MLXLLM)
import MLX
import MLXLMCommon
import MLXLLM
private let mlxAvailable = true
#else
private let mlxAvailable = false
#endif

/// MLX-based LLM provider
public actor QwenLLMProvider: LLMProvider {
    
    private let logger = Logger(subsystem: "com.laia.llm", category: "QwenLLM")
    
    private var _isLoaded: Bool = false
    private var _currentContextTokens: Int = 0
    private var conversationHistory: [ConversationMessage] = []
    private let metrics: LatencyMetrics
    private var isGenerating: Bool = false
    
    #if canImport(MLXLLM)
    private var chatSession: ChatSession?
    private var modelContext: ModelContext?  // Store for recreating ChatSession
    // Using Qwen2.5 instead of Qwen3 to avoid thinking tokens
    private let modelId = "mlx-community/Qwen2.5-3B-Instruct-4bit"
    #endif
    
    public var isLoaded: Bool { _isLoaded }
    public var currentContextTokens: Int { _currentContextTokens }
    public let maxContextTokens: Int = 4096
    
    public init(metrics: LatencyMetrics) {
        self.metrics = metrics
        logger.info("QwenLLMProvider initialized (MLX: \(mlxAvailable))")
    }
    
    // MARK: - Model Lifecycle
    
    public func preloadModel() async throws {
        guard !_isLoaded else { return }
        
        #if canImport(MLXLLM)
        logger.info("Loading MLX model: \(self.modelId)")
        let startTime = Date()
        
        do {
            let model = try await loadModel(id: modelId) { progress in
                print("Download: \(Int(progress.fractionCompleted * 100))%")
            }
            
            // Store the model container for later ChatSession recreation
            modelContext = model
            
            // Create initial ChatSession with default instructions
            chatSession = ChatSession(model, instructions: defaultSystemPrompt)
            
            _isLoaded = true
            let elapsed = Date().timeIntervalSince(startTime)
            logger.info("Model loaded in \(String(format: "%.2f", elapsed))s")
        } catch {
            logger.error("Load failed: \(error.localizedDescription)")
            throw LAIAError.generationFailed("Model load: \(error.localizedDescription)")
        }
        #else
        logger.info("MLX not available - placeholder mode")
        _isLoaded = true
        #endif
        
        addSystemPrompt()
    }
    
    public func unloadModel() async {
        #if canImport(MLXLLM)
        chatSession = nil
        #endif
        _isLoaded = false
        conversationHistory.removeAll()
        logger.info("Model unloaded")
    }
    
    public func purgeKVCache() async {
        _currentContextTokens = estimateTokenCount(for: conversationHistory)
    }
    
    // MARK: - Generation
    
    public func generate(
        prompt: String,
        context: [ConversationMessage]
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task { [weak self] in
                guard let self = self else {
                    continuation.finish(throwing: LAIAError.generationFailed("Deallocated"))
                    return
                }
                do {
                    try await self.performGeneration(prompt: prompt, continuation: continuation)
                } catch {
                    // Handle GPU background error gracefully
                    if "\(error)".contains("Background") || "\(error)".contains("GPU") {
                        self.logger.warning("GPU background error - using fallback")
                        await self.generateFallback(prompt: prompt, continuation: continuation)
                    } else {
                        continuation.finish(throwing: error)
                    }
                }
            }
        }
    }
    
    private func performGeneration(
        prompt: String,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        if !_isLoaded { try await preloadModel() }
        
        guard !isGenerating else {
            throw LAIAError.invalidState("Already generating")
        }
        
        isGenerating = true
        defer { isGenerating = false }
        
        await metrics.record(.llmStart)
        conversationHistory.append(ConversationMessage(role: .user, content: prompt))
        
        logger.debug("Generating for: \"\(prompt.prefix(40))...\"")
        
        #if canImport(MLXLLM)
        guard let session = chatSession else {
            throw LAIAError.modelNotLoaded("ChatSession")
        }
        
        var isFirst = true
        
        do {
            // Get response from ChatSession
            var response = try await session.respond(to: prompt)
            
            // LOG: Raw response before any filtering
            logger.info("🔍 [LLM RAW BEFORE FILTER] '\(response.prefix(200))...'")
            
            // Filter and limit response length
            // NOTE: Don't filter tool_call tags!
            response = filterThinkingTokens(response)
            response = limitResponseLength(response, maxWords: 50)
            
            logger.info("🔍 [LLM AFTER FILTER] '\(response.prefix(200))...'")
            
            // Stream word by word for UI
            for word in response.split(separator: " ") {
                if Task.isCancelled { throw LAIAError.cancelled }
                
                if isFirst {
                    await metrics.record(.llmFirstToken)
                    isFirst = false
                }
                
                continuation.yield(String(word) + " ")
                try await Task.sleep(for: .milliseconds(25))
            }
            
            conversationHistory.append(ConversationMessage(role: .assistant, content: response))
            
        } catch {
            logger.error("Generation error: \(error.localizedDescription)")
            throw error
        }
        
        #else
        await generateFallback(prompt: prompt, continuation: continuation)
        #endif
        
        await metrics.record(.llmComplete)
        continuation.finish()
        logger.info("Generation completed")
    }
    
    /// Filter out thinking/reasoning tokens from Qwen3 responses
    private func filterThinkingTokens(_ text: String) -> String {
        var result = text
        
        // Remove <think>...</think> blocks
        while let thinkStart = result.range(of: "<think>"),
              let thinkEnd = result.range(of: "</think>") {
            if thinkStart.lowerBound < thinkEnd.upperBound {
                result.removeSubrange(thinkStart.lowerBound..<thinkEnd.upperBound)
            } else {
                break
            }
        }
        
        // Remove any remaining thinking markers
        result = result.replacingOccurrences(of: "<think>", with: "")
        result = result.replacingOccurrences(of: "</think>", with: "")
        
        // Clean up whitespace
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove multiple consecutive newlines
        while result.contains("\n\n\n") {
            result = result.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        
        return result
    }
    
    /// Limit response to a maximum number of words
    private func limitResponseLength(_ text: String, maxWords: Int) -> String {
        let words = text.split(separator: " ")
        
        if words.count <= maxWords {
            return text
        }
        
        // Take first maxWords and try to end at a sentence
        let truncated = words.prefix(maxWords).joined(separator: " ")
        
        // Try to end at a natural break point
        if let lastPeriod = truncated.lastIndex(of: ".") {
            return String(truncated[...lastPeriod])
        }
        if let lastQuestion = truncated.lastIndex(of: "?") {
            return String(truncated[...lastQuestion])
        }
        if let lastExclamation = truncated.lastIndex(of: "!") {
            return String(truncated[...lastExclamation])
        }
        
        return truncated + "."
    }
    
    private func generateFallback(
        prompt: String,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async {
        let response = generateContextualResponse(for: prompt)
        var isFirst = true
        
        for word in response.split(separator: " ") {
            if isFirst {
                await metrics.record(.llmFirstToken)
                isFirst = false
            }
            
            continuation.yield(String(word) + " ")
            try? await Task.sleep(for: .milliseconds(50))
        }
        
        conversationHistory.append(ConversationMessage(role: .assistant, content: response))
        await metrics.record(.llmComplete)
        continuation.finish()
    }
    
    // MARK: - Fallback Responses
    
    private func generateContextualResponse(for prompt: String) -> String {
        let lowercased = prompt.lowercased()
        
        if containsAny(lowercased, ["hola", "buenos", "hey"]) {
            return "¡Hola! Soy LAIA, tu asistente personal. ¿En qué puedo ayudarte?"
        }
        
        if containsAny(lowercased, ["hora"]) {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            formatter.locale = Locale(identifier: "es_ES")
            return "Son las \(formatter.string(from: Date()))."
        }
        
        if containsAny(lowercased, ["fecha", "día"]) {
            let formatter = DateFormatter()
            formatter.dateStyle = .full
            formatter.locale = Locale(identifier: "es_ES")
            return "Hoy es \(formatter.string(from: Date()))."
        }
        
        if containsAny(lowercased, ["gracias"]) {
            return "¡De nada! Estoy aquí para ayudarte."
        }
        
        return "Entiendo. ¿En qué más puedo ayudarte?"
    }
    
    private func containsAny(_ text: String, _ keywords: [String]) -> Bool {
        keywords.contains { text.contains($0) }
    }
    
    // MARK: - Context
    
    /// Current system prompt (can be customized with tools)
    private var currentSystemPrompt: String = ""
    
    /// Set a custom system prompt (e.g., with MCP tools injected)
    /// This recreates the ChatSession with the new instructions
    public func setSystemPrompt(_ prompt: String) {
        currentSystemPrompt = prompt
        
        // CRITICAL: Recreate ChatSession with new instructions
        #if canImport(MLXLLM)
        if let model = modelContext {
            logger.info("📋 [LLM] Recreando ChatSession con nuevo system prompt (\(prompt.count) chars)")
            chatSession = ChatSession(model, instructions: prompt)
        } else {
            logger.warning("⚠️ [LLM] ModelContainer no disponible para setSystemPrompt")
        }
        #endif
        
        addSystemPrompt()
    }
    
    private func addSystemPrompt() {
        let prompt = currentSystemPrompt.isEmpty ? defaultSystemPrompt : currentSystemPrompt
        
        conversationHistory = [
            ConversationMessage(
                role: .system,
                content: prompt
            )
        ]
        _currentContextTokens = estimateTokenCount(for: conversationHistory)
    }
    
    /// Default system prompt (without tools)
    private var defaultSystemPrompt: String {
        """
        Eres LAIA, asistente de voz. REGLAS ESTRICTAS:
        - Responde SOLO en español
        - Máximo 1-2 oraciones cortas
        - Sin listas ni explicaciones largas
        - Sin introducciones ni conclusiones
        - Respuesta directa al punto
        """
    }
    
    private func estimateTokenCount(for messages: [ConversationMessage]) -> Int {
        messages.reduce(0) { $0 + $1.content.count } / 4
    }
    
    public func clearHistory() {
        #if canImport(MLXLLM)
        chatSession = nil
        Task {
            try? await preloadModel()
        }
        #endif
        addSystemPrompt()
    }
    
    public func getHistory() -> [ConversationMessage] {
        conversationHistory
    }
    
    // MARK: - Tool Loop Support
    
    /// Añade un mensaje de herramienta al historial y regenera
    /// - Parameter toolResponse: Respuesta formateada de la herramienta (<tool_response>...</tool_response>)
    /// - Returns: Stream de tokens de la nueva generación
    public func continueWithToolResult(_ toolResponse: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task { [weak self] in
                guard let self = self else {
                    continuation.finish(throwing: LAIAError.generationFailed("Deallocated"))
                    return
                }
                
                do {
                    // Añadir respuesta de herramienta como mensaje del sistema
                    await self.addToolResponse(toolResponse)
                    
                    // Regenerar sin prompt adicional (el modelo continúa desde el contexto)
                    try await self.performContinuation(continuation: continuation)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    private var lastToolResponse: String = ""
    
    private func addToolResponse(_ response: String) {
        // Guardar para usar en performContinuation
        lastToolResponse = response
        // Añadir como mensaje especial (rol tool o usuario según implementación)
        conversationHistory.append(ConversationMessage(role: .user, content: response))
        _currentContextTokens = estimateTokenCount(for: conversationHistory)
    }
    
    private func performContinuation(
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        guard !isGenerating else {
            throw LAIAError.invalidState("Already generating")
        }
        
        isGenerating = true
        defer { isGenerating = false }
        
        await metrics.record(.llmStart)
        
        logger.debug("Continuing generation with tool result...")
        
        #if canImport(MLXLLM)
        guard let session = chatSession else {
            throw LAIAError.modelNotLoaded("ChatSession")
        }
        
        var isFirst = true
        
        do {
            // IMPORTANTE: Pasar los datos reales de la herramienta en el prompt
            // para que el modelo los vea y use
            let prompt = """
            Resultado de la herramienta: \(lastToolResponse)
            
            Responde al usuario de forma natural usando estos datos. Solo di la información, no repitas el comando.
            """
            
            logger.info("📝 [LLM] Prompt para continuación: \(prompt.prefix(100))...")
            
            var response = try await session.respond(to: prompt)
            
            // Filter and limit response
            response = filterThinkingTokens(response)
            response = limitResponseLength(response, maxWords: 80)
            
            // Stream word by word
            for word in response.split(separator: " ") {
                if Task.isCancelled { throw LAIAError.cancelled }
                
                if isFirst {
                    await metrics.record(.llmFirstToken)
                    isFirst = false
                }
                
                continuation.yield(String(word) + " ")
                try await Task.sleep(for: .milliseconds(25))
            }
            
            conversationHistory.append(ConversationMessage(role: .assistant, content: response))
            
        } catch {
            logger.error("Continuation error: \(error.localizedDescription)")
            throw error
        }
        
        #else
        // Fallback mode
        let response = "He procesado la información de la herramienta."
        for word in response.split(separator: " ") {
            continuation.yield(String(word) + " ")
            try? await Task.sleep(for: .milliseconds(50))
        }
        conversationHistory.append(ConversationMessage(role: .assistant, content: response))
        #endif
        
        await metrics.record(.llmComplete)
        continuation.finish()
        logger.info("Continuation completed")
    }
    
    /// Genera una respuesta completa (no streaming) - útil para tool loop
    public func generateComplete(prompt: String) async throws -> String {
        var fullResponse = ""
        let stream = generate(prompt: prompt, context: conversationHistory)
        
        for try await token in stream {
            fullResponse += token
        }
        
        return fullResponse
    }
    
    /// Continúa y retorna respuesta completa (para tool loop)
    public func continueWithToolResultComplete(_ toolResponse: String) async throws -> String {
        var fullResponse = ""
        let stream = continueWithToolResult(toolResponse)
        
        for try await token in stream {
            fullResponse += token
        }
        
        return fullResponse
    }
}
