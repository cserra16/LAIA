//
//  AudioCaptureEngine.swift
//  LAIA - Local AI Assistant
//
//  AVAudioEngine-based audio capture at 16kHz mono.
//  Feeds directly into AudioBufferContainer for VAD processing.
//

import Foundation
import AVFoundation
import os

/// Audio capture engine using AVAudioEngine
/// Configured for 16kHz mono capture optimized for speech recognition
public final class AudioCaptureEngine: @unchecked Sendable {
    
    // MARK: - Configuration
    
    /// Target sample rate
    public static let targetSampleRate: Double = 16000
    
    /// Target channel count
    public static let targetChannels: AVAudioChannelCount = 1
    
    /// Buffer size in samples (100ms at 16kHz)
    public static let bufferSize: AVAudioFrameCount = 1600
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.laia.audio", category: "AudioCapture")
    
    /// AVAudioEngine instance
    private let audioEngine: AVAudioEngine
    
    /// Audio buffer container for captured samples
    private let buffer: AudioBufferContainer
    
    /// Target format for processing
    private var targetFormat: AVAudioFormat?
    
    /// Format converter if needed
    private var formatConverter: AVAudioConverter?
    
    /// Lock for thread-safe state access
    private let stateLock = OSAllocatedUnfairLock()
    
    /// Capture state
    private var _isCapturing: Bool = false
    
    /// Pause state (for dynamic offloading)
    private var _isPaused: Bool = false
    
    /// Callback for audio level monitoring
    public var audioLevelCallback: ((Float) -> Void)?
    
    /// Callback when audio chunk is available
    public var audioChunkCallback: (([Float]) -> Void)?
    
    // MARK: - Computed Properties
    
    public var isCapturing: Bool {
        stateLock.withLock { _isCapturing }
    }
    
    public var isPaused: Bool {
        stateLock.withLock { _isPaused }
    }
    
    // MARK: - Initialization
    
    public init(buffer: AudioBufferContainer) {
        self.audioEngine = AVAudioEngine()
        self.buffer = buffer
        
        logger.info("AudioCaptureEngine initialized")
    }
    
    deinit {
        stop()
    }
    
    // MARK: - Setup
    
    /// Setup audio session and engine
    public func setup() throws {
        logger.info("Setting up audio capture engine")
        
        // Configure audio session
        let session = AVAudioSession.sharedInstance()
        
        do {
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [
                .defaultToSpeaker,
                .allowBluetooth,
                .allowBluetoothA2DP
            ])
            
            try session.setPreferredSampleRate(Self.targetSampleRate)
            try session.setPreferredIOBufferDuration(0.01) // 10ms
            
            try session.setActive(true)
            
            logger.info("Audio session configured: \(session.sampleRate)Hz")
        } catch {
            logger.error("Failed to configure audio session: \(error.localizedDescription)")
            throw LAIAError.audioEngineError("Session configuration failed: \(error.localizedDescription)")
        }
        
        // Create target format
        targetFormat = AVAudioFormat(
            standardFormatWithSampleRate: Self.targetSampleRate,
            channels: Self.targetChannels
        )
        
        guard targetFormat != nil else {
            throw LAIAError.audioEngineError("Failed to create target format")
        }
        
        // Setup format converter if input format differs
        setupFormatConverter()
        
        logger.info("Audio capture engine setup complete")
    }
    
    private func setupFormatConverter() {
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        guard let target = targetFormat else { return }
        
        // Check if conversion is needed
        if inputFormat.sampleRate != target.sampleRate ||
           inputFormat.channelCount != target.channelCount {
            
            formatConverter = AVAudioConverter(from: inputFormat, to: target)
            
            logger.info("Format converter created: \(inputFormat.sampleRate)Hz → \(target.sampleRate)Hz")
        }
    }
    
    // MARK: - Capture Control
    
    /// Start audio capture
    public func start() throws {
        guard !isCapturing else {
            logger.debug("Already capturing")
            return
        }
        
        logger.info("Starting audio capture")
        
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        // Install tap on input node
        inputNode.installTap(
            onBus: 0,
            bufferSize: Self.bufferSize,
            format: inputFormat
        ) { [weak self] (pcmBuffer, time) in
            self?.processAudioBuffer(pcmBuffer, time: time)
        }
        
        // Prepare and start engine
        audioEngine.prepare()
        
        do {
            try audioEngine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            throw LAIAError.audioEngineError("Failed to start engine: \(error.localizedDescription)")
        }
        
        stateLock.withLock {
            _isCapturing = true
            _isPaused = false
        }
        
        logger.info("Audio capture started")
    }
    
    /// Stop audio capture
    public func stop() {
        guard isCapturing else { return }
        
        logger.info("Stopping audio capture")
        
        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)
        
        audioEngine.stop()
        
        stateLock.withLock {
            _isCapturing = false
            _isPaused = false
        }
        
        logger.info("Audio capture stopped")
    }
    
    /// Pause capture (for dynamic offloading during LLM inference)
    public func pause() {
        guard isCapturing, !isPaused else { return }
        
        logger.debug("Pausing audio capture")
        
        audioEngine.pause()
        
        stateLock.withLock {
            _isPaused = true
        }
    }
    
    /// Resume capture after pause
    public func resume() throws {
        guard isCapturing, isPaused else { return }
        
        logger.debug("Resuming audio capture")
        
        do {
            try audioEngine.start()
        } catch {
            throw LAIAError.audioEngineError("Failed to resume: \(error.localizedDescription)")
        }
        
        stateLock.withLock {
            _isPaused = false
        }
    }
    
    // MARK: - Audio Processing
    
    private func processAudioBuffer(_ pcmBuffer: AVAudioPCMBuffer, time: AVAudioTime) {
        // Skip if paused
        guard !isPaused else { return }
        
        // Convert to target format if needed
        let processBuffer: AVAudioPCMBuffer
        
        if let converter = formatConverter, let target = targetFormat {
            guard let converted = convertBuffer(pcmBuffer, converter: converter, targetFormat: target) else {
                return
            }
            processBuffer = converted
        } else {
            processBuffer = pcmBuffer
        }
        
        // Extract samples
        guard let channelData = processBuffer.floatChannelData?[0] else { return }
        
        let frameLength = Int(processBuffer.frameLength)
        
        // Write to ring buffer using direct pointer
        let bufferPointer = UnsafeBufferPointer(start: channelData, count: frameLength)
        buffer.write(bufferPointer)
        
        // Calculate RMS for level monitoring
        var rms: Float = 0
        for i in 0..<frameLength {
            rms += channelData[i] * channelData[i]
        }
        rms = sqrt(rms / Float(frameLength))
        
        // Call level callback on main thread
        if let callback = audioLevelCallback {
            DispatchQueue.main.async {
                callback(rms)
            }
        }
        
        // Call chunk callback for VAD processing
        if let chunkCallback = audioChunkCallback {
            var samples = [Float](repeating: 0, count: frameLength)
            for i in 0..<frameLength {
                samples[i] = channelData[i]
            }
            chunkCallback(samples)
        }
    }
    
    private func convertBuffer(
        _ input: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        targetFormat: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let ratio = targetFormat.sampleRate / input.format.sampleRate
        let outputFrameCapacity = AVAudioFrameCount(Double(input.frameLength) * ratio)
        
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: outputFrameCapacity
        ) else {
            return nil
        }
        
        var error: NSError?
        let status = converter.convert(to: outputBuffer, error: &error) { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return input
        }
        
        if status == .error {
            logger.error("Conversion error: \(error?.localizedDescription ?? "unknown")")
            return nil
        }
        
        return outputBuffer
    }
    
    // MARK: - Utilities
    
    /// Clear the audio buffer
    public func clearBuffer() {
        buffer.clear()
    }
    
    /// Get current buffer contents for processing
    public func getBufferContents() -> [Float] {
        buffer.peek()
    }
    
    /// Get buffer energy for quick VAD check
    public func getRecentEnergy() -> Float {
        buffer.recentEnergy()
    }
}

// MARK: - Audio Session Notifications

extension AudioCaptureEngine {
    
    /// Setup audio session interruption handling
    public func setupInterruptionHandling() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleInterruption(notification)
        }
        
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleRouteChange(notification)
        }
    }
    
    private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        switch type {
        case .began:
            logger.info("Audio session interruption began")
            pause()
            
        case .ended:
            logger.info("Audio session interruption ended")
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    try? resume()
                }
            }
            
        @unknown default:
            break
        }
    }
    
    private func handleRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        
        logger.info("Audio route changed: \(String(describing: reason))")
        
        // Reconfigure if needed
        if reason == .newDeviceAvailable || reason == .oldDeviceUnavailable {
            setupFormatConverter()
        }
    }
}
