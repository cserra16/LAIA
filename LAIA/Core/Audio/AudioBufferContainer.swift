//
//  AudioBufferContainer.swift
//  LAIA - Local AI Assistant
//
//  High-performance ring buffer for real-time audio processing.
//  Uses OSAllocatedUnfairLock for non-blocking access from audio thread.
//  Optimized for 16kHz mono audio capture.
//

import Foundation
import os

/// Thread-safe ring buffer for audio samples using unfair lock
/// Designed for real-time audio thread access without blocking Swift concurrency
public final class AudioBufferContainer: @unchecked Sendable, AudioBufferProtocol {
    
    // MARK: - Configuration
    
    /// Sample rate in Hz
    public static let sampleRate: Double = 16000
    
    /// Buffer duration in seconds
    public static let bufferDurationSeconds: Double = 1.0
    
    /// Buffer capacity in samples (1000ms at 16kHz = 16000 samples)
    public static let bufferCapacity: Int = Int(sampleRate * bufferDurationSeconds)
    
    // MARK: - Properties
    
    /// Internal storage for audio samples
    private let storage: UnsafeMutableBufferPointer<Float>
    
    /// Write position in ring buffer
    private var writeIndex: Int = 0
    
    /// Read position in ring buffer
    private var readIndex: Int = 0
    
    /// Current number of samples available
    private var availableCount: Int = 0
    
    /// Lock for thread-safe access (non-blocking for real-time audio)
    private let lock = OSAllocatedUnfairLock()
    
    /// Logger for diagnostics
    private let logger = Logger(subsystem: "com.laia.audio", category: "AudioBuffer")
    
    // MARK: - Computed Properties
    
    public var count: Int {
        lock.withLock { availableCount }
    }
    
    public var capacity: Int {
        Self.bufferCapacity
    }
    
    /// Whether buffer is full
    public var isFull: Bool {
        lock.withLock { availableCount >= Self.bufferCapacity }
    }
    
    /// Whether buffer is empty
    public var isEmpty: Bool {
        lock.withLock { availableCount == 0 }
    }
    
    // MARK: - Initialization
    
    public init() {
        // Allocate contiguous memory for samples
        storage = UnsafeMutableBufferPointer<Float>.allocate(capacity: Self.bufferCapacity)
        storage.initialize(repeating: 0.0)
        
        logger.debug("AudioBufferContainer initialized with capacity: \(Self.bufferCapacity) samples")
    }
    
    deinit {
        storage.deallocate()
    }
    
    // MARK: - Write Operations
    
    /// Write samples to buffer from audio callback
    /// This method is designed for real-time audio thread - minimal overhead
    public func write(_ samples: UnsafeBufferPointer<Float>) {
        lock.withLock {
            for sample in samples {
                storage[writeIndex] = sample
                writeIndex = (writeIndex + 1) % Self.bufferCapacity
                
                if availableCount < Self.bufferCapacity {
                    availableCount += 1
                } else {
                    // Buffer full - advance read index (overwrite oldest)
                    readIndex = (readIndex + 1) % Self.bufferCapacity
                }
            }
        }
    }
    
    /// Write from array (convenience method)
    public func write(_ samples: [Float]) {
        samples.withUnsafeBufferPointer { ptr in
            write(ptr)
        }
    }
    
    /// Write from AVAudioPCMBuffer
    public func write(from buffer: UnsafeMutablePointer<Float>, count: Int) {
        let bufferPtr = UnsafeBufferPointer(start: buffer, count: count)
        write(bufferPtr)
    }
    
    // MARK: - Read Operations
    
    /// Read and consume samples from buffer
    /// - Parameter count: Number of samples to read
    /// - Returns: Array of samples, or nil if insufficient samples
    public func read(count requestedCount: Int) -> [Float]? {
        lock.withLock {
            guard availableCount >= requestedCount else {
                return nil
            }
            
            var result = [Float](repeating: 0.0, count: requestedCount)
            
            for i in 0..<requestedCount {
                result[i] = storage[readIndex]
                readIndex = (readIndex + 1) % Self.bufferCapacity
            }
            
            availableCount -= requestedCount
            return result
        }
    }
    
    /// Peek at samples without consuming
    /// Returns all available samples in correct order
    public func peek() -> [Float] {
        lock.withLock {
            guard availableCount > 0 else {
                return []
            }
            
            var result = [Float](repeating: 0.0, count: availableCount)
            var currentIndex = readIndex
            
            for i in 0..<availableCount {
                result[i] = storage[currentIndex]
                currentIndex = (currentIndex + 1) % Self.bufferCapacity
            }
            
            return result
        }
    }
    
    /// Peek at last N samples (most recent audio)
    public func peekLast(_ count: Int) -> [Float] {
        lock.withLock {
            let actualCount = min(count, availableCount)
            guard actualCount > 0 else {
                return []
            }
            
            var result = [Float](repeating: 0.0, count: actualCount)
            
            // Calculate starting position for last N samples
            let startOffset = availableCount - actualCount
            var currentIndex = (readIndex + startOffset) % Self.bufferCapacity
            
            for i in 0..<actualCount {
                result[i] = storage[currentIndex]
                currentIndex = (currentIndex + 1) % Self.bufferCapacity
            }
            
            return result
        }
    }
    
    // MARK: - Buffer Management
    
    /// Clear all samples from buffer
    public func clear() {
        lock.withLock {
            writeIndex = 0
            readIndex = 0
            availableCount = 0
        }
    }
    
    /// Consume N samples without returning them
    public func discard(_ count: Int) {
        lock.withLock {
            let discardCount = min(count, availableCount)
            readIndex = (readIndex + discardCount) % Self.bufferCapacity
            availableCount -= discardCount
        }
    }
    
    // MARK: - Analysis Helpers
    
    /// Calculate RMS energy of recent samples (for VAD triggering)
    public func recentEnergy(sampleCount: Int = 1600) -> Float {
        let samples = peekLast(sampleCount)
        guard !samples.isEmpty else { return 0.0 }
        
        var sumSquares: Float = 0.0
        for sample in samples {
            sumSquares += sample * sample
        }
        
        return sqrt(sumSquares / Float(samples.count))
    }
    
    /// Get samples formatted for VAD analysis (specific chunk size)
    public func samplesForVAD(chunkSize: Int = 512) -> [Float]? {
        let samples = peek()
        guard samples.count >= chunkSize else { return nil }
        
        // Return last chunk
        return Array(samples.suffix(chunkSize))
    }
}

// MARK: - Debug Extensions

extension AudioBufferContainer: CustomDebugStringConvertible {
    public var debugDescription: String {
        lock.withLock {
            "AudioBufferContainer(count: \(availableCount)/\(Self.bufferCapacity), write: \(writeIndex), read: \(readIndex))"
        }
    }
}
