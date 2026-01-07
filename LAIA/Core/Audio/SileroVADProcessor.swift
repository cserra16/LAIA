//
//  SileroVADProcessor.swift
//  LAIA - Local AI Assistant
//
//  Voice Activity Detection using Silero VAD via ONNX Runtime.
//  Implements silence detection for end-of-speech triggering.
//

import Foundation
import os

// Note: Uncomment when ONNX Runtime is added as dependency
// import OnnxRuntimeSwift

/// Silero VAD implementation for voice activity detection
/// Uses ONNX Runtime for efficient inference
public final class SileroVADProcessor: @unchecked Sendable, VADProcessor {
    
    // MARK: - Configuration
    
    /// VAD configuration
    public struct Configuration: Sendable {
        /// Voice activity threshold (0.0 - 1.0)
        public var threshold: Float
        
        /// Minimum silence duration to end speech (ms)
        public var minSilenceDurationMs: Int
        
        /// Minimum speech duration to trigger (ms)
        public var minSpeechDurationMs: Int
        
        /// Sample rate
        public var sampleRate: Int
        
        /// Chunk size for processing
        public var chunkSize: Int
        
        /// Window size for probability smoothing
        public var windowSize: Int
        
        public init(
            threshold: Float = LAIAModelConfig.SileroVAD.threshold,
            minSilenceDurationMs: Int = LAIAModelConfig.SileroVAD.minSilenceDurationMs,
            minSpeechDurationMs: Int = LAIAModelConfig.SileroVAD.minSpeechDurationMs,
            sampleRate: Int = LAIAModelConfig.SileroVAD.sampleRate,
            chunkSize: Int = LAIAModelConfig.SileroVAD.chunkSize,
            windowSize: Int = LAIAModelConfig.SileroVAD.windowSize
        ) {
            self.threshold = threshold
            self.minSilenceDurationMs = minSilenceDurationMs
            self.minSpeechDurationMs = minSpeechDurationMs
            self.sampleRate = sampleRate
            self.chunkSize = chunkSize
            self.windowSize = windowSize
        }
    }
    
    // MARK: - Callback Types
    
    /// Called when speech starts
    public typealias SpeechStartCallback = () -> Void
    
    /// Called when speech ends (with final audio)
    public typealias SpeechEndCallback = ([Float]) -> Void
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.laia.vad", category: "SileroVAD")
    
    /// Configuration
    private let config: Configuration
    
    /// ONNX Runtime session
    /// Uncomment when ONNX Runtime is available:
    // private var session: ORTSession?
    
    /// Model state (h, c tensors for LSTM)
    private var modelState: (h: [Float], c: [Float])?
    
    /// Probability history for smoothing
    private var probabilityWindow: [Float] = []
    
    /// Lock for state access
    private let stateLock = OSAllocatedUnfairLock()
    
    /// Speech detection state
    private var isSpeaking: Bool = false
    
    /// Accumulated audio during speech
    private var speechBuffer: [Float] = []
    
    /// Samples since last speech
    private var silenceSamples: Int = 0
    
    /// Samples since speech started
    private var speechSamples: Int = 0
    
    /// Callbacks
    public var onSpeechStart: SpeechStartCallback?
    public var onSpeechEnd: SpeechEndCallback?
    
    /// Whether model is loaded
    private var isLoaded: Bool = false
    
    // MARK: - Initialization
    
    public init(configuration: Configuration = Configuration()) {
        self.config = configuration
        self.probabilityWindow = []
        
        logger.info("SileroVADProcessor initialized with threshold: \(configuration.threshold)")
    }
    
    // MARK: - Model Loading
    
    /// Load the ONNX model
    public func loadModel() throws {
        guard !isLoaded else { return }
        
        logger.info("Loading Silero VAD model")
        
        let modelPath = LAIAModelConfig.Paths.vadModelPath.path
        
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw LAIAError.vadError("Model file not found at: \(modelPath)")
        }
        
        /*
         Uncomment when ONNX Runtime is available:
         
         let env = try ORTEnvironment(
             loggingLevel: .warning,
             name: "silero_vad"
         )
         
         let options = try ORTSessionOptions()
         try options.setIntraOpNumThreads(1)
         try options.setGraphOptimizationLevel(.all)
         
         session = try ORTSession(
             environment: env,
             modelPath: modelPath,
             sessionOptions: options
         )
         */
        
        // Initialize model state
        resetState()
        
        isLoaded = true
        logger.info("Silero VAD model loaded")
    }
    
    /// Unload model to free memory
    public func unloadModel() {
        /*
         Uncomment when ONNX Runtime is available:
         session = nil
         */
        
        modelState = nil
        isLoaded = false
        
        logger.info("Silero VAD model unloaded")
    }
    
    // MARK: - Processing
    
    public func process(_ samples: [Float]) throws -> Float {
        guard isLoaded else {
            throw LAIAError.vadError("Model not loaded")
        }
        
        // Ensure correct chunk size
        var chunk = samples
        if chunk.count < config.chunkSize {
            // Pad with zeros
            chunk.append(contentsOf: [Float](repeating: 0, count: config.chunkSize - chunk.count))
        } else if chunk.count > config.chunkSize {
            // Truncate
            chunk = Array(chunk.prefix(config.chunkSize))
        }
        
        /*
         Uncomment when ONNX Runtime is available:
         
         guard let session = session else {
             throw LAIAError.vadError("Session not available")
         }
         
         // Prepare input tensor
         let inputData = Data(bytes: chunk, count: chunk.count * MemoryLayout<Float>.size)
         let inputShape: [Int64] = [1, Int64(config.chunkSize)]
         let inputTensor = try ORTValue(
             tensorData: NSMutableData(data: inputData),
             elementType: .float,
             shape: inputShape
         )
         
         // Prepare state tensors (h, c)
         let (h, c) = modelState ?? (
             [Float](repeating: 0, count: 128),
             [Float](repeating: 0, count: 128)
         )
         
         // Run inference
         let outputs = try session.run(
             withInputs: ["input": inputTensor, "h": hTensor, "c": cTensor],
             outputNames: ["output", "hn", "cn"]
         )
         
         // Extract probability
         let outputData = try outputs["output"]!.tensorData() as Data
         let probability = outputData.withUnsafeBytes { $0.load(as: Float.self) }
         
         // Update state
         modelState = (extractState(outputs["hn"]), extractState(outputs["cn"]))
         */
        
        // Placeholder: Simple energy-based VAD for testing
        let energy = sqrt(chunk.map { $0 * $0 }.reduce(0, +) / Float(chunk.count))
        let probability = min(energy * 20, 1.0) // Scale energy to 0-1
        
        // Smooth probability
        let smoothedProbability = smoothProbability(probability)
        
        // Update speech detection state
        updateSpeechState(probability: smoothedProbability, samples: samples)
        
        return smoothedProbability
    }
    
    public func reset() {
        stateLock.withLock {
            isSpeaking = false
            speechBuffer.removeAll()
            silenceSamples = 0
            speechSamples = 0
            probabilityWindow.removeAll()
        }
        
        resetState()
    }
    
    // MARK: - State Management
    
    private func resetState() {
        // Reset LSTM state
        modelState = (
            [Float](repeating: 0, count: 128),
            [Float](repeating: 0, count: 128)
        )
    }
    
    private func smoothProbability(_ probability: Float) -> Float {
        stateLock.withLock {
            probabilityWindow.append(probability)
            
            // Keep window size
            if probabilityWindow.count > config.windowSize {
                probabilityWindow.removeFirst()
            }
            
            // Return average
            return probabilityWindow.reduce(0, +) / Float(probabilityWindow.count)
        }
    }
    
    private func updateSpeechState(probability: Float, samples: [Float]) {
        let wasSpeeking = stateLock.withLock { isSpeaking }
        
        if probability >= config.threshold {
            // Voice activity detected
            stateLock.withLock {
                silenceSamples = 0
                speechSamples += samples.count
                speechBuffer.append(contentsOf: samples)
            }
            
            let reachedMinDuration = stateLock.withLock {
                speechSamples >= (config.minSpeechDurationMs * config.sampleRate / 1000)
            }
            
            if !wasSpeeking && reachedMinDuration {
                // Speech started
                stateLock.withLock {
                    isSpeaking = true
                }
                
                logger.debug("Speech started")
                onSpeechStart?()
            }
            
        } else {
            // Silence detected
            stateLock.withLock {
                silenceSamples += samples.count
                
                if isSpeaking {
                    speechBuffer.append(contentsOf: samples)
                }
            }
            
            let (speaking, silenceCount, buffer) = stateLock.withLock {
                (isSpeaking, silenceSamples, speechBuffer)
            }
            
            let minSilenceSamples = config.minSilenceDurationMs * config.sampleRate / 1000
            
            if speaking && silenceCount >= minSilenceSamples {
                // Speech ended
                stateLock.withLock {
                    isSpeaking = false
                    speechSamples = 0
                }
                
                logger.debug("Speech ended with \(buffer.count) samples")
                onSpeechEnd?(buffer)
                
                // Clear buffer
                stateLock.withLock {
                    speechBuffer.removeAll()
                }
            }
        }
    }
    
    // MARK: - Queries
    
    /// Whether currently detecting speech
    public var isCurrentlySpeaking: Bool {
        stateLock.withLock { isSpeaking }
    }
    
    /// Get accumulated speech buffer
    public var currentSpeechBuffer: [Float] {
        stateLock.withLock { speechBuffer }
    }
    
    /// Speech duration in seconds
    public var currentSpeechDuration: Double {
        stateLock.withLock {
            Double(speechSamples) / Double(config.sampleRate)
        }
    }
}

// MARK: - VAD State

extension SileroVADProcessor {
    
    /// Current VAD state for UI
    public enum VADState: Sendable {
        case idle
        case detecting
        case speaking
        case silence
    }
    
    public var currentState: VADState {
        stateLock.withLock {
            if !isLoaded {
                return .idle
            }
            
            if isSpeaking {
                return .speaking
            }
            
            if silenceSamples > 0 && speechSamples > 0 {
                return .silence
            }
            
            return .detecting
        }
    }
}
