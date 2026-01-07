//
//  AudioPlaybackQueue.swift
//  LAIA - Local AI Assistant
//
//  Gapless audio playback using AVAudioPlayerNode.
//  Implements buffer scheduling for continuous speech output.
//

import Foundation
import AVFoundation
import os

/// Audio playback queue for gapless TTS output
/// Uses AVAudioPlayerNode with anticipatory buffer scheduling
public final class AudioPlaybackQueue: @unchecked Sendable {
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.laia.audio", category: "PlaybackQueue")
    
    /// Audio engine for playback
    private let audioEngine: AVAudioEngine
    
    /// Player node
    private let playerNode: AVAudioPlayerNode
    
    /// Lock for state access
    private let stateLock = OSAllocatedUnfairLock()
    
    /// Pending buffers queue
    private var pendingBuffers: [AVAudioPCMBuffer] = []
    
    /// Is currently playing
    private var _isPlaying: Bool = false
    
    /// Is engine running
    private var _isEngineRunning: Bool = false
    
    /// Buffers currently scheduled
    private var scheduledBufferCount: Int = 0
    
    /// Callback when playback completes
    public var onPlaybackComplete: (() -> Void)?
    
    /// Callback for each buffer completion
    public var onBufferComplete: ((Int) -> Void)?
    
    // MARK: - Computed Properties
    
    public var isPlaying: Bool {
        stateLock.withLock { self._isPlaying }
    }
    
    public var hasPendingBuffers: Bool {
        stateLock.withLock { !self.pendingBuffers.isEmpty || self.scheduledBufferCount > 0 }
    }
    
    // MARK: - Initialization
    
    public init() throws {
        self.audioEngine = AVAudioEngine()
        self.playerNode = AVAudioPlayerNode()
        
        // Attach player to engine
        audioEngine.attach(playerNode)
        
        // Connect player to output
        let mainMixer = audioEngine.mainMixerNode
        let outputFormat = mainMixer.outputFormat(forBus: 0)
        
        audioEngine.connect(playerNode, to: mainMixer, format: outputFormat)
        
        logger.info("AudioPlaybackQueue initialized")
    }
    
    deinit {
        stop()
    }
    
    // MARK: - Engine Control
    
    /// Start the audio engine
    public func startEngine() throws {
        guard !_isEngineRunning else { return }
        
        // Configure audio session for playback
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .voicePrompt)
        try session.setActive(true)
        
        audioEngine.prepare()
        try audioEngine.start()
        
        stateLock.withLock {
            self._isEngineRunning = true
        }
        
        logger.info("Playback engine started")
    }
    
    /// Stop the audio engine
    public func stopEngine() {
        audioEngine.stop()
        
        stateLock.withLock {
            self._isEngineRunning = false
            self._isPlaying = false
        }
        
        logger.info("Playback engine stopped")
    }
    
    // MARK: - Playback Control
    
    /// Schedule a buffer for playback
    public func scheduleBuffer(_ buffer: AVAudioPCMBuffer) {
        // Ensure engine is running
        if !_isEngineRunning {
            do {
                try startEngine()
            } catch {
                logger.error("Failed to start engine: \(error.localizedDescription)")
                return
            }
        }
        
        // Convert format if needed
        let playbackBuffer: AVAudioPCMBuffer
        if let converted = convertToPlaybackFormat(buffer) {
            playbackBuffer = converted
        } else {
            playbackBuffer = buffer
        }
        
        // Schedule with completion handler
        let bufferIndex = stateLock.withLock { () -> Int in
            self.scheduledBufferCount += 1
            return self.scheduledBufferCount
        }
        
        playerNode.scheduleBuffer(playbackBuffer) { [weak self] in
            self?.handleBufferComplete(index: bufferIndex)
        }
        
        // Start playing if not already
        if !isPlaying {
            playerNode.play()
            
            stateLock.withLock {
                self._isPlaying = true
            }
            
            logger.debug("Playback started")
        }
        
        logger.debug("Scheduled buffer \(bufferIndex) (\(playbackBuffer.frameLength) frames)")
    }
    
    /// Schedule multiple buffers at once
    public func scheduleBuffers(_ buffers: [AVAudioPCMBuffer]) {
        for buffer in buffers {
            scheduleBuffer(buffer)
        }
    }
    
    /// Stop playback and clear queue
    public func stop() {
        playerNode.stop()
        
        stateLock.withLock {
            self._isPlaying = false
            self.pendingBuffers.removeAll()
            self.scheduledBufferCount = 0
        }
        
        logger.info("Playback stopped")
    }
    
    /// Pause playback
    public func pause() {
        playerNode.pause()
        
        stateLock.withLock {
            self._isPlaying = false
        }
        
        logger.debug("Playback paused")
    }
    
    /// Resume playback
    public func resume() {
        guard hasPendingBuffers else { return }
        
        playerNode.play()
        
        stateLock.withLock {
            self._isPlaying = true
        }
        
        logger.debug("Playback resumed")
    }
    
    // MARK: - Buffer Handling
    
    private func handleBufferComplete(index: Int) {
        stateLock.withLock {
            self.scheduledBufferCount = max(0, self.scheduledBufferCount - 1)
        }
        
        logger.debug("Buffer \(index) complete, remaining: \(self.scheduledBufferCount)")
        
        self.onBufferComplete?(index)
        
        // Check if all done
        let remaining = stateLock.withLock { self.scheduledBufferCount }
        
        if remaining == 0 {
            stateLock.withLock {
                self._isPlaying = false
            }
            
            logger.info("All buffers complete")
            
            DispatchQueue.main.async { [weak self] in
                self?.onPlaybackComplete?()
            }
        }
    }
    
    // MARK: - Format Conversion
    
    private func convertToPlaybackFormat(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let outputFormat = audioEngine.mainMixerNode.outputFormat(forBus: 0)
        
        // Check if conversion needed
        guard buffer.format.sampleRate != outputFormat.sampleRate ||
              buffer.format.channelCount != outputFormat.channelCount else {
            return nil // No conversion needed
        }
        
        // Create converter
        guard let converter = AVAudioConverter(from: buffer.format, to: outputFormat) else {
            logger.warning("Could not create format converter")
            return nil
        }
        
        // Calculate output capacity
        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let outputCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio * 1.1)
        
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: outputCapacity
        ) else {
            return nil
        }
        
        var error: NSError?
        let status = converter.convert(to: outputBuffer, error: &error) { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        
        if status == .error {
            logger.error("Conversion error: \(error?.localizedDescription ?? "unknown")")
            return nil
        }
        
        return outputBuffer
    }
    
    // MARK: - Utilities
    
    /// Get current playback time
    public var currentTime: TimeInterval {
        guard let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else {
            return 0
        }
        
        return Double(playerTime.sampleTime) / playerTime.sampleRate
    }
    
    /// Volume control (0.0 - 1.0)
    public var volume: Float {
        get { playerNode.volume }
        set { playerNode.volume = max(0, min(1, newValue)) }
    }
}

// MARK: - Async Interface

extension AudioPlaybackQueue {
    
    /// Schedule buffers from an async stream
    public func scheduleFromStream(
        _ stream: AsyncThrowingStream<AVAudioPCMBuffer, Error>
    ) async throws {
        for try await buffer in stream {
            scheduleBuffer(buffer)
        }
    }
    
    /// Wait for all playback to complete
    public func waitForCompletion() async {
        await withCheckedContinuation { continuation in
            let existingCallback = onPlaybackComplete
            
            onPlaybackComplete = { [weak self] in
                existingCallback?()
                self?.onPlaybackComplete = existingCallback
                continuation.resume()
            }
            
            // If already done, resume immediately
            if !hasPendingBuffers {
                onPlaybackComplete = existingCallback
                continuation.resume()
            }
        }
    }
}

