//
//  ModelConfiguration.swift
//  LAIA - Local AI Assistant
//
//  Centralized configuration for all ML models.
//  Optimized for iPhone 17 (A19) memory constraints.
//

import Foundation
#if canImport(CoreML)
import CoreML
#endif

/// Centralized model configuration for A19 optimization
public struct LAIAModelConfig: Sendable {
    
    // MARK: - WhisperKit Configuration
    
    public struct Whisper: Sendable {
        /// Model identifier for WhisperKit
        public static let modelName = "whisper-large-v3-v20240930"
        
        /// Size of model in bytes (approximately 626MB)
        public static let modelSizeBytes: UInt64 = 626 * 1024 * 1024
        
        /// Compute units - prioritize Neural Engine for efficiency
        #if canImport(CoreML)
        public static let computeUnits: MLComputeUnits = .cpuAndNeuralEngine
        #endif
        
        /// Sample rate expected by Whisper
        public static let sampleRate: Double = 16000
        
        /// Maximum audio duration per transcription (seconds)
        public static let maxAudioDuration: Double = 30.0
        
        /// Idle timeout before unloading model (seconds)
        public static let idleUnloadTimeout: TimeInterval = 30.0
        
        /// Language hint for faster transcription
        public static let languageHint: String = "es" // Spanish
        
        /// Whether to use VAD for chunking
        public static let useVAD: Bool = true
        
        /// Compression ratio threshold for hallucination detection
        public static let compressionRatioThreshold: Float = 2.4
        
        /// Log probability threshold
        public static let logProbThreshold: Float = -1.0
        
        /// No speech threshold
        public static let noSpeechThreshold: Float = 0.6
    }
    
    // MARK: - Qwen LLM Configuration
    
    public struct Qwen: Sendable {
        /// Model repository/identifier
        public static let modelName = "mlx-community/Qwen2.5-3B-Instruct-4bit"
        
        /// Quantization format
        public static let quantization = "Q5_K_M"
        
        /// Approximate model size in bytes (~2.1GB for 4-bit)
        public static let modelSizeBytes: UInt64 = 2100 * 1024 * 1024
        
        /// Maximum context window (tokens)
        /// Reduced from 32K to save memory on A19
        public static let maxContextTokens: Int = 2048
        
        /// Larger context for complex conversations (use sparingly)
        public static let extendedContextTokens: Int = 4096
        
        /// MLX GPU cache limit in bytes (512MB)
        public static let cacheLimit: UInt64 = 512 * 1024 * 1024
        
        /// Strict cache limit for low memory (256MB)
        public static let strictCacheLimit: UInt64 = 256 * 1024 * 1024
        
        /// Temperature for generation
        public static let temperature: Float = 0.7
        
        /// Top-p sampling
        public static let topP: Float = 0.9
        
        /// Maximum tokens to generate per response
        public static let maxGenerationTokens: Int = 512
        
        /// Repetition penalty
        public static let repetitionPenalty: Float = 1.1
        
        /// System prompt for assistant behavior - loaded from file
        public static var systemPrompt: String {
            // Try to load from bundle
            if let url = Bundle.main.url(forResource: "systemPrompt", withExtension: "md", subdirectory: nil),
               let content = try? String(contentsOf: url, encoding: .utf8) {
                return content.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            
            // Fallback if file not found
            return """
                Eres LAIA, un asistente virtual inteligente y amable. \
                Respondes de forma concisa y natural en español. \
                Mantén respuestas breves para conversación fluida por voz.
                """
        }
        
        /// Idle timeout before purging KV cache
        public static let kvCachePurgeTimeout: TimeInterval = 10.0
        
        /// Idle timeout before full unload
        public static let idleUnloadTimeout: TimeInterval = 60.0
    }
    
    // MARK: - Silero VAD Configuration
    
    public struct SileroVAD: Sendable {
        /// Model file name
        public static let modelName = "silero_vad.onnx"
        
        /// Voice activity threshold (0.0 - 1.0)
        public static let threshold: Float = 0.5
        
        /// Minimum silence duration to end speech (ms)
        public static let minSilenceDurationMs: Int = 800
        
        /// Minimum speech duration to trigger (ms)
        public static let minSpeechDurationMs: Int = 250
        
        /// Sample rate expected by Silero
        public static let sampleRate: Int = 16000
        
        /// Chunk size for processing (samples)
        public static let chunkSize: Int = 512
        
        /// Window size for smoothing
        public static let windowSize: Int = 5
    }
    
    // MARK: - Memory Limits
    
    public struct MemoryLimits: Sendable {
        /// Maximum total GPU memory usage target
        public static let maxGPUMemory: UInt64 = 3 * 1024 * 1024 * 1024 // 3GB
        
        /// Warning threshold for memory usage
        public static let warningThreshold: Double = 0.7
        
        /// Critical threshold triggering aggressive unload
        public static let criticalThreshold: Double = 0.85
        
        /// Memory headroom to keep free (bytes)
        public static let headroom: UInt64 = 512 * 1024 * 1024 // 512MB
    }
    
    // MARK: - QoS Configuration
    
    public struct QoS: Sendable {
        /// Audio capture and VAD processing
        public static let audioProcessing: DispatchQoS = .userInteractive
        
        /// Model inference
        public static let inference: DispatchQoS = .userInitiated
        
        /// Background cleanup
        public static let cleanup: DispatchQoS = .utility
        
        /// File I/O operations
        public static let fileIO: DispatchQoS = .background
    }
    
    // MARK: - Paths
    
    public struct Paths: Sendable {
        /// Base directory for model storage
        public static var modelsDirectory: URL {
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first!
            return appSupport.appendingPathComponent("LAIA/Models", isDirectory: true)
        }
        
        /// WhisperKit model path
        public static var whisperModelPath: URL {
            modelsDirectory.appendingPathComponent("whisper", isDirectory: true)
        }
        
        /// Qwen model path
        public static var qwenModelPath: URL {
            modelsDirectory.appendingPathComponent("qwen", isDirectory: true)
        }
        
        /// Silero VAD model path
        public static var vadModelPath: URL {
            modelsDirectory.appendingPathComponent("vad/silero_vad.onnx")
        }
        
        /// Ensure all directories exist
        public static func ensureDirectoriesExist() throws {
            let fm = FileManager.default
            try fm.createDirectory(at: whisperModelPath, withIntermediateDirectories: true)
            try fm.createDirectory(at: qwenModelPath, withIntermediateDirectories: true)
            try fm.createDirectory(at: vadModelPath.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
    }
}

// MARK: - Environment Detection

extension LAIAModelConfig {
    
    /// Detect if running on simulator
    public static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }
    
    /// Detect available RAM estimate
    public static var estimatedAvailableRAM: UInt64 {
        ProcessInfo.processInfo.physicalMemory
    }
    
    /// Whether device has sufficient RAM for full model loading
    public static var hasSufficientRAM: Bool {
        estimatedAvailableRAM >= 6 * 1024 * 1024 * 1024 // 6GB minimum
    }
    
    /// Recommended context size based on device
    public static var recommendedContextSize: Int {
        hasSufficientRAM ? Qwen.extendedContextTokens : Qwen.maxContextTokens
    }
    
    /// Recommended cache limit based on device
    public static var recommendedCacheLimit: UInt64 {
        hasSufficientRAM ? Qwen.cacheLimit : Qwen.strictCacheLimit
    }
}
