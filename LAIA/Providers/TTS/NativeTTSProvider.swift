//
//  NativeTTSProvider.swift
//  LAIA - Local AI Assistant
//
//  Native TTS provider using iOS AVSpeechSynthesizer.
//

import Foundation
import AVFoundation
import os

/// Native iOS TTS provider using AVSpeechSynthesizer
/// Provides real-time speech synthesis with Spanish voice
public actor NativeTTSProvider: TTSProvider {
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.laia.tts", category: "NativeTTS")
    
    /// AVSpeechSynthesizer instance
    private let synthesizer = AVSpeechSynthesizer()
    
    /// Speech delegate for tracking
    private let speechDelegate: SpeechDelegate
    
    /// Whether "model" is loaded (always true for native)
    private var _isLoaded: Bool = false
    
    /// Output audio format
    public let outputFormat: AVAudioFormat
    
    /// Latency metrics
    private let metrics: LatencyMetrics
    
    /// Spanish voice
    private var spanishVoice: AVSpeechSynthesisVoice?
    
    // MARK: - Protocol Conformance
    
    public var isLoaded: Bool {
        _isLoaded
    }
    
    // MARK: - Initialization
    
    public init(metrics: LatencyMetrics) {
        self.metrics = metrics
        self.speechDelegate = SpeechDelegate()
        
        // Configure output format
        self.outputFormat = AVAudioFormat(
            standardFormatWithSampleRate: 24000,
            channels: 1
        )!
        
        // Find Spanish voice
        self.spanishVoice = Self.findBestSpanishVoice()
        
        logger.info("NativeTTSProvider initialized with voice: \(self.spanishVoice?.name ?? "default")")
    }
    
    // MARK: - Model Lifecycle
    
    public func preloadModel() async throws {
        guard !_isLoaded else { return }
        
        logger.info("Initializing native TTS")
        
        // Configure audio session for playback
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
        } catch {
            logger.error("Failed to configure audio session: \(error.localizedDescription)")
        }
        
        _isLoaded = true
        logger.info("Native TTS ready")
    }
    
    public func unloadModel() async {
        guard _isLoaded else { return }
        
        synthesizer.stopSpeaking(at: .immediate)
        _isLoaded = false
        
        logger.info("Native TTS stopped")
    }
    
    // MARK: - Synthesis
    
    public func synthesize(_ text: String) -> AsyncThrowingStream<AVAudioPCMBuffer, Error> {
        logger.info("📱 NATIVE TTS: synthesize called with text: \"\(text.prefix(50))...\"")
        
        return AsyncThrowingStream { continuation in
            Task { [weak self] in
                guard let self = self else {
                    continuation.finish(throwing: LAIAError.generationFailed("Provider deallocated"))
                    return
                }
                
                do {
                    try await self.performSynthesis(text: text, continuation: continuation)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    private func performSynthesis(
        text: String,
        continuation: AsyncThrowingStream<AVAudioPCMBuffer, Error>.Continuation
    ) async throws {
        if !_isLoaded {
            try await preloadModel()
        }
        
        guard !text.isEmpty else {
            continuation.finish()
            return
        }
        
        logger.debug("Synthesizing: \"\(text.prefix(50))...\"")
        
        await metrics.record(.ttsStart)
        
        // Create utterance
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = spanishVoice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.1 // Slightly faster
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        
        // IMPORTANT: Capture metrics reference BEFORE the closure to avoid actor-isolation issues
        // The callback runs on a background thread and accessing self.metrics causes unsafeForcedSync
        let capturedMetrics = self.metrics
        var isFirst = true
        
        synthesizer.write(utterance) { buffer in
            // Note: Do NOT access 'self' here - it would cause unsafeForcedSync
            
            if let pcmBuffer = buffer as? AVAudioPCMBuffer, pcmBuffer.frameLength > 0 {
                if isFirst {
                    Task {
                        await capturedMetrics.record(.ttsFirstAudio)
                    }
                    isFirst = false
                }
                
                continuation.yield(pcmBuffer)
            } else {
                // Synthesis complete
                Task {
                    await capturedMetrics.record(.ttsComplete)
                }
                continuation.finish()
            }
        }
    }
    
    // MARK: - Voice Selection
    
    private static func findBestSpanishVoice() -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        
        // Prefer enhanced/premium voices
        let spanishVoices = voices.filter { voice in
            voice.language.hasPrefix("es")
        }
        
        // Try to find enhanced voice first
        if let enhanced = spanishVoices.first(where: { $0.quality == .enhanced }) {
            return enhanced
        }
        
        // Fall back to any Spanish voice
        if let spanish = spanishVoices.first {
            return spanish
        }
        
        // Default to system
        return AVSpeechSynthesisVoice(language: "es-ES")
    }
}

// MARK: - Speech Delegate

private final class SpeechDelegate: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    
    var onStart: (() -> Void)?
    var onFinish: (() -> Void)?
    var onCancel: (() -> Void)?
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        onStart?()
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        onFinish?()
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        onCancel?()
    }
}

// MARK: - TTS Provider Factory

public enum TTSProviderFactory {
    private static let factoryLogger = Logger(subsystem: "com.laia.tts", category: "TTSFactory")
    
    public static func create(metrics: LatencyMetrics) -> any TTSProvider {
        factoryLogger.info("🔊 TTS FACTORY: Creating NativeTTSProvider")
        return NativeTTSProvider(metrics: metrics)
    }
}

public typealias KokoroTTSProvider = NativeTTSProvider
