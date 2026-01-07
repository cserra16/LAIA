//
//  WhisperSTTProvider.swift
//  LAIA - Local AI Assistant
//
//  STT provider using WhisperKit for on-device transcription.
//  Optimized for A19 with aggressive memory management.
//

import Foundation
import AVFoundation
import os

// WhisperKit import - add via SPM: https://github.com/argmaxinc/WhisperKit
#if canImport(WhisperKit)
import WhisperKit
#endif

/// WhisperKit-based STT provider for on-device transcription
/// Implements lazy loading and aggressive memory management
public actor WhisperSTTProvider: STTProvider {
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.laia.stt", category: "WhisperSTT")
    
    #if canImport(WhisperKit)
    /// WhisperKit pipeline instance
    private var whisperKit: WhisperKit?
    #endif
    
    /// Whether model is loaded
    private var _isLoaded: Bool = false
    
    /// Last transcription time for idle tracking
    private var lastTranscriptionTime: Date?
    
    /// Idle unload timer
    private var idleUnloadTimer: Task<Void, Never>?
    
    /// Latency metrics
    private let metrics: LatencyMetrics
    
    // MARK: - Protocol Conformance
    
    public var isLoaded: Bool {
        _isLoaded
    }
    
    // MARK: - Initialization
    
    public init(metrics: LatencyMetrics) {
        self.metrics = metrics
        logger.info("WhisperSTTProvider initialized")
    }
    
    // MARK: - Model Lifecycle
    
    public func preloadModel() async throws {
        guard !_isLoaded else {
            logger.debug("Model already loaded")
            return
        }
        
        logger.info("Loading WhisperKit model: \(LAIAModelConfig.Whisper.modelName)")
        
        let startTime = Date()
        
        #if canImport(WhisperKit)
        do {
            // Initialize WhisperKit with configuration
            whisperKit = try await WhisperKit(
                model: LAIAModelConfig.Whisper.modelName,
                computeOptions: .init(
                    melCompute: .cpuAndNeuralEngine,
                    audioEncoderCompute: .cpuAndNeuralEngine,
                    textDecoderCompute: .cpuAndNeuralEngine
                ),
                verbose: false,
                logLevel: .error,
                prewarm: true,
                load: true,
                download: true
            )
            
            _isLoaded = true
            
            let elapsed = Date().timeIntervalSince(startTime)
            logger.info("WhisperKit model loaded in \(String(format: "%.2f", elapsed))s")
            
        } catch {
            logger.error("Failed to load WhisperKit: \(error.localizedDescription)")
            throw LAIAError.modelLoadFailed("WhisperKit: \(error.localizedDescription)")
        }
        #else
        // Placeholder when WhisperKit not available
        try await Task.sleep(for: .milliseconds(100))
        _isLoaded = true
        logger.warning("WhisperKit not available - using placeholder")
        #endif
        
        startIdleTimer()
    }
    
    public func unloadModel() async {
        guard _isLoaded else { return }
        
        logger.info("Unloading WhisperKit model")
        
        idleUnloadTimer?.cancel()
        idleUnloadTimer = nil
        
        #if canImport(WhisperKit)
        whisperKit = nil
        #endif
        
        _isLoaded = false
        
        // Force cleanup
        autoreleasepool { }
        
        logger.info("WhisperKit model unloaded")
    }
    
    // MARK: - Transcription
    
    public func transcribe(_ audioSamples: [Float]) async throws -> String {
        // Ensure model is loaded
        if !_isLoaded {
            try await preloadModel()
        }
        
        guard !audioSamples.isEmpty else {
            logger.debug("Empty audio samples - skipping transcription")
            return ""
        }
        
        logger.debug("Transcribing \(audioSamples.count) samples")
        
        await metrics.record(.sttStart)
        lastTranscriptionTime = Date()
        
        #if canImport(WhisperKit)
        guard let whisper = whisperKit else {
            throw LAIAError.modelNotLoaded("WhisperKit")
        }
        
        do {
            // Configure transcription options
            let options = DecodingOptions(
                language: LAIAModelConfig.Whisper.languageHint,
                task: .transcribe,
                temperatureFallbackCount: 3,
                compressionRatioThreshold: LAIAModelConfig.Whisper.compressionRatioThreshold,
                logProbThreshold: LAIAModelConfig.Whisper.logProbThreshold,
                noSpeechThreshold: LAIAModelConfig.Whisper.noSpeechThreshold,
                usePrefillPrompt: false,
                usePrefillCache: true,
                skipSpecialTokens: true,
                withoutTimestamps: true,
                clipTimestamps: []
            )
            
            // Transcribe
            let results = try await whisper.transcribe(
                audioArray: audioSamples,
                decodeOptions: options
            )
            
            await metrics.record(.sttComplete)
            
            // Extract text
            let transcription = results.compactMap { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            
            logger.info("Transcribed: \"\(transcription.prefix(50))...\"")
            
            // Restart idle timer
            startIdleTimer()
            
            return transcription
            
        } catch {
            logger.error("Transcription failed: \(error.localizedDescription)")
            throw LAIAError.transcriptionFailed(error.localizedDescription)
        }
        #else
        // Placeholder response when WhisperKit not available
        try await Task.sleep(for: .milliseconds(200))
        await metrics.record(.sttComplete)
        
        let placeholder = "Hola, ¿cómo puedo ayudarte?"
        logger.warning("WhisperKit not available - returning placeholder: \"\(placeholder)\"")
        
        startIdleTimer()
        return placeholder
        #endif
    }
    
    // MARK: - Idle Management
    
    private func startIdleTimer() {
        idleUnloadTimer?.cancel()
        
        idleUnloadTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(LAIAModelConfig.Whisper.idleUnloadTimeout))
            guard !Task.isCancelled else { return }
            await self?.checkIdleAndUnload()
        }
    }
    
    private func checkIdleAndUnload() async {
        guard let lastTime = lastTranscriptionTime else {
            await unloadModel()
            return
        }
        
        let idleTime = Date().timeIntervalSince(lastTime)
        
        if idleTime >= LAIAModelConfig.Whisper.idleUnloadTimeout {
            logger.info("Idle timeout reached - unloading WhisperKit")
            await unloadModel()
        }
    }
}
