//
//  Protocols.swift
//  LAIA - Local AI Assistant
//
//  Core protocols for provider abstraction with Swift 6 strict concurrency.
//  Designed for iPhone 17 (A19) with aggressive memory management.
//

import Foundation
import AVFoundation

// MARK: - Message Types

/// Represents a conversation message for LLM context
public struct ConversationMessage: Sendable, Codable, Identifiable {
    public let id: UUID
    public let role: Role
    public let content: String
    public let timestamp: Date
    
    public enum Role: String, Sendable, Codable {
        case system
        case user
        case assistant
    }
    
    public init(role: Role, content: String) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
    }
}

// MARK: - Provider Protocols

/// Speech-to-Text provider protocol
/// Implementations must be actors for Swift 6 concurrency safety
public protocol STTProvider: Actor {
    /// Transcribe audio samples to text
    /// - Parameter audio: Float32 audio samples at 16kHz
    /// - Returns: Transcribed text
    func transcribe(_ audio: [Float]) async throws -> String
    
    /// Check if model is currently loaded in memory
    var isLoaded: Bool { get async }
    
    /// Preload model into memory for faster first inference
    func preloadModel() async throws
    
    /// Aggressively unload model from memory
    /// Called by MemoryGuardian under pressure
    func unloadModel() async
}

/// Large Language Model provider protocol
public protocol LLMProvider: Actor {
    /// Generate streaming response tokens
    /// - Parameters:
    ///   - prompt: Current user prompt
    ///   - context: Conversation history for context
    /// - Returns: AsyncThrowingStream of token strings
    func generate(
        prompt: String,
        context: [ConversationMessage]
    ) -> AsyncThrowingStream<String, Error>
    
    /// Check if model is currently loaded in memory
    var isLoaded: Bool { get async }
    
    /// Preload model into memory
    func preloadModel() async throws
    
    /// Purge KV cache to reclaim memory
    /// Called immediately after TTS completes speaking
    func purgeKVCache() async
    
    /// Unload model completely from memory
    func unloadModel() async
    
    /// Current token count in context
    var currentContextTokens: Int { get async }
    
    /// Maximum allowed context window
    var maxContextTokens: Int { get }
}

/// Text-to-Speech provider protocol
public protocol TTSProvider: Actor {
    /// Synthesize text to streaming audio buffers
    /// - Parameter text: Text to synthesize (sentence or phrase)
    /// - Returns: AsyncThrowingStream of audio buffers
    func synthesize(_ text: String) -> AsyncThrowingStream<AVAudioPCMBuffer, Error>
    
    /// Check if model is currently loaded
    var isLoaded: Bool { get async }
    
    /// Preload model into memory
    func preloadModel() async throws
    
    /// Unload model from memory
    func unloadModel() async
    
    /// Output audio format
    var outputFormat: AVAudioFormat { get async }
}

// MARK: - VAD Protocol

/// Voice Activity Detection protocol
public protocol VADProcessor: Sendable {
    /// Process audio chunk and detect voice activity
    /// - Parameter samples: Float32 audio samples
    /// - Returns: Probability of voice activity (0.0 - 1.0)
    func process(_ samples: [Float]) throws -> Float
    
    /// Reset internal state for new utterance
    func reset()
}

// MARK: - Audio Buffer Protocol

/// Protocol for thread-safe audio buffer access
public protocol AudioBufferProtocol: Sendable {
    /// Write samples to buffer (called from audio thread)
    func write(_ samples: UnsafeBufferPointer<Float>)
    
    /// Read samples for processing (non-blocking)
    func read(count: Int) -> [Float]?
    
    /// Get all available samples without consuming
    func peek() -> [Float]
    
    /// Clear buffer contents
    func clear()
    
    /// Current number of samples in buffer
    var count: Int { get }
    
    /// Buffer capacity in samples
    var capacity: Int { get }
}

// MARK: - Orchestrator Delegate

/// Delegate protocol for orchestrator state changes
public protocol OrchestratorDelegate: AnyObject, Sendable {
    /// Called when inference state changes
    func orchestrator(_ orchestrator: any Orchestrator, didChangeState state: InferenceStateValue)
    
    /// Called when transcription is complete
    func orchestrator(_ orchestrator: any Orchestrator, didTranscribe text: String)
    
    /// Called when LLM generates partial response
    func orchestrator(_ orchestrator: any Orchestrator, didGeneratePartial text: String)
    
    /// Called when TTS starts speaking
    func orchestratorDidStartSpeaking(_ orchestrator: any Orchestrator)
    
    /// Called when TTS finishes speaking
    func orchestratorDidFinishSpeaking(_ orchestrator: any Orchestrator)
    
    /// Called on error
    func orchestrator(_ orchestrator: any Orchestrator, didEncounterError error: Error)
}

/// Main orchestrator protocol
public protocol Orchestrator: Actor {
    /// Start listening for voice input
    func startListening() async throws
    
    /// Stop listening
    func stopListening() async
    
    /// Cancel current operation
    func cancel() async
    
    /// Current inference state
    var currentState: InferenceStateValue { get async }
    
    /// Set delegate for callbacks
    func setDelegate(_ delegate: OrchestratorDelegate?) async
}

// MARK: - Inference State

/// Enum representing possible inference states
public enum InferenceStateValue: String, Sendable, CaseIterable {
    case idle = "Idle"
    case listening = "Listening"
    case detectingVoice = "Detecting Voice"
    case transcribing = "Transcribing"
    case thinking = "Thinking"
    case speaking = "Speaking"
    case error = "Error"
    
    /// Whether this state allows interruption
    public var isInterruptible: Bool {
        switch self {
        case .idle, .listening, .detectingVoice:
            return true
        case .transcribing, .thinking, .speaking, .error:
            return false
        }
    }
    
    /// Whether audio capture should be active
    public var shouldCaptureAudio: Bool {
        switch self {
        case .idle, .listening, .detectingVoice:
            return true
        case .transcribing, .thinking, .speaking, .error:
            return false
        }
    }
}

// MARK: - Error Types

/// Errors specific to LAIA operations
public enum LAIAError: Error, Sendable {
    case modelNotLoaded(String)
    case transcriptionFailed(String)
    case generationFailed(String)
    case synthesisFailed(String)
    case audioEngineError(String)
    case memoryPressure
    case thermalThrottling
    case cancelled
    case invalidState(String)
    case vadError(String)
}

extension LAIAError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .modelNotLoaded(let model):
            return "Model not loaded: \(model)"
        case .transcriptionFailed(let reason):
            return "Transcription failed: \(reason)"
        case .generationFailed(let reason):
            return "Generation failed: \(reason)"
        case .synthesisFailed(let reason):
            return "Synthesis failed: \(reason)"
        case .audioEngineError(let reason):
            return "Audio engine error: \(reason)"
        case .memoryPressure:
            return "Operation cancelled due to memory pressure"
        case .thermalThrottling:
            return "Operation throttled due to thermal state"
        case .cancelled:
            return "Operation was cancelled"
        case .invalidState(let state):
            return "Invalid state for operation: \(state)"
        case .vadError(let reason):
            return "VAD error: \(reason)"
        }
    }
}
