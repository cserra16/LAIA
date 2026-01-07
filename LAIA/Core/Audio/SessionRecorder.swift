//
//  SessionRecorder.swift
//  LAIA - Local AI Assistant
//
//  Records user voice and TTS output for testing/debugging.
//

import Foundation
import AVFoundation
import Combine
import os

/// Records audio session for debugging and testing
@MainActor
public class SessionRecorder: ObservableObject {
    
    // MARK: - Singleton
    
    public static let shared = SessionRecorder()
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.laia.recorder", category: "Session")
    private var audioRecorder: AVAudioRecorder?
    @Published public var isRecording = false
    @Published public var currentRecordingURL: URL?
    
    // MARK: - Initialization
    
    private init() {
        logger.info("📹 SessionRecorder initialized")
    }
    
    // MARK: - Recording Control
    
    /// Start recording audio session
    public func startRecording() throws -> URL {
        guard !isRecording else {
            logger.warning("Already recording, ignoring start request")
            throw RecorderError.alreadyRecording
        }
        
        let url = generateRecordingURL()
        logger.info("🎙️ Preparing to record to: \(url.path)")
        
        // Configure audio session for recording
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
            logger.debug("Audio session configured for recording")
        } catch {
            logger.error("Audio session error: \(error.localizedDescription)")
            throw error
        }
        
        // Recording settings - high quality for testing
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.isMeteringEnabled = true
            
            guard audioRecorder?.record() == true else {
                logger.error("AVAudioRecorder.record() returned false")
                throw RecorderError.recordingFailed
            }
            
            isRecording = true
            currentRecordingURL = url
            
            logger.info("🔴 Recording STARTED: \(url.lastPathComponent)")
            
            return url
        } catch {
            logger.error("Failed to create recorder: \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Stop recording and return the file URL
    public func stopRecording() -> URL? {
        guard isRecording, let recorder = audioRecorder else {
            logger.warning("No active recording to stop")
            return nil
        }
        
        recorder.stop()
        isRecording = false
        
        let url = currentRecordingURL
        audioRecorder = nil
        
        if let url = url {
            logger.info("⏹️ Recording STOPPED: \(url.lastPathComponent)")
            
            // Log file size
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? Int64 {
                let sizeMB = Double(size) / (1024 * 1024)
                logger.info("📁 Recording size: \(String(format: "%.2f", sizeMB)) MB at \(url.path)")
            } else {
                logger.error("Could not get file attributes for \(url.path)")
            }
        }
        
        return url
    }
    
    /// Get all saved recordings
    public func getSavedRecordings() -> [URL] {
        let recordingsDir = getRecordingsDirectory()
        
        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: recordingsDir,
                includingPropertiesForKeys: [.creationDateKey],
                options: [.skipsHiddenFiles]
            )
            
            let recordings = files.filter { $0.pathExtension == "m4a" }
            logger.info("Found \(recordings.count) recordings in \(recordingsDir.path)")
            return recordings.sorted { url1, url2 in
                let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                return date1 > date2
            }
        } catch {
            logger.error("Failed to list recordings: \(error.localizedDescription)")
            return []
        }
    }
    
    /// Delete a recording
    public func deleteRecording(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
        logger.info("🗑️ Deleted recording: \(url.lastPathComponent)")
    }
    
    /// Delete all recordings
    public func deleteAllRecordings() throws {
        for url in getSavedRecordings() {
            try FileManager.default.removeItem(at: url)
        }
        logger.info("🗑️ Deleted all recordings")
    }
    
    // MARK: - Helpers
    
    private func generateRecordingURL() -> URL {
        let dir = getRecordingsDirectory()
        
        // Create directory if needed
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            logger.debug("Recordings directory ready: \(dir.path)")
        } catch {
            logger.error("Failed to create recordings directory: \(error.localizedDescription)")
        }
        
        // Generate filename with timestamp
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        
        return dir.appendingPathComponent("LAIA_Session_\(timestamp).m4a")
    }
    
    private func getRecordingsDirectory() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("LAIA_Recordings", isDirectory: true)
    }
    
    // MARK: - Error
    
    public enum RecorderError: LocalizedError {
        case alreadyRecording
        case recordingFailed
        
        public var errorDescription: String? {
            switch self {
            case .alreadyRecording: return "Ya hay una grabación en curso"
            case .recordingFailed: return "No se pudo iniciar la grabación"
            }
        }
    }
}

