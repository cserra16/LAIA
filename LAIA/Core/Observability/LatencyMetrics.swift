//
//  LatencyMetrics.swift
//  LAIA - Local AI Assistant
//
//  Observability system for measuring and logging latency
//  across the inference pipeline. Uses os.Logger for structured logs.
//

import Foundation
import os

/// Latency measurement points in the pipeline
public enum LatencyMeasurementPoint: String, Sendable {
    case vadTrigger = "vad_trigger"
    case sttStart = "stt_start"
    case sttComplete = "stt_complete"
    case llmStart = "llm_start"
    case llmFirstToken = "llm_first_token"
    case llmComplete = "llm_complete"
    case ttsStart = "tts_start"
    case ttsFirstAudio = "tts_first_audio"
    case ttsComplete = "tts_complete"
    case audioPlaybackStart = "audio_playback_start"
}

/// Metrics collector for pipeline latency monitoring
public actor LatencyMetrics {
    
    // MARK: - Logger
    
    private let logger = Logger(subsystem: "com.laia.metrics", category: "Latency")
    private let signpostLog = OSLog(subsystem: "com.laia.metrics", category: .pointsOfInterest)
    
    // MARK: - Properties
    
    /// Current session ID for grouping related measurements
    private var sessionId: UUID = UUID()
    
    /// Timestamp storage for measurements
    private var timestamps: [LatencyMeasurementPoint: Date] = [:]
    
    /// Historical latency data for analysis
    private var latencyHistory: [LatencyRecord] = []
    
    /// Maximum history entries to keep
    private let maxHistorySize = 100
    
    // MARK: - Types
    
    /// Individual latency record
    public struct LatencyRecord: Sendable, Identifiable {
        public let id: UUID
        public let sessionId: UUID
        public let timestamp: Date
        
        // Key latencies in milliseconds
        public let audioToText: Double?      // VAD trigger → STT complete
        public let timeToFirstToken: Double? // STT complete → LLM first token
        public let llmGeneration: Double?    // LLM first token → LLM complete
        public let textToSpeech: Double?     // TTS start → TTS first audio
        public let audioOut: Double?         // LLM first token → Audio playback start
        public let totalE2E: Double?         // VAD trigger → Audio playback start
        
        public init(
            sessionId: UUID,
            audioToText: Double? = nil,
            timeToFirstToken: Double? = nil,
            llmGeneration: Double? = nil,
            textToSpeech: Double? = nil,
            audioOut: Double? = nil,
            totalE2E: Double? = nil
        ) {
            self.id = UUID()
            self.sessionId = sessionId
            self.timestamp = Date()
            self.audioToText = audioToText
            self.timeToFirstToken = timeToFirstToken
            self.llmGeneration = llmGeneration
            self.textToSpeech = textToSpeech
            self.audioOut = audioOut
            self.totalE2E = totalE2E
        }
    }
    
    /// Summary statistics
    public struct LatencySummary: Sendable {
        public let sampleCount: Int
        public let avgAudioToText: Double?
        public let avgTimeToFirstToken: Double?
        public let avgLLMGeneration: Double?
        public let avgTextToSpeech: Double?
        public let avgAudioOut: Double?
        public let avgTotalE2E: Double?
        
        // P95 values
        public let p95AudioToText: Double?
        public let p95TimeToFirstToken: Double?
        public let p95TotalE2E: Double?
    }
    
    // MARK: - Initialization
    
    public init() {}
    
    // MARK: - Session Management
    
    /// Start a new measurement session
    public func startSession() -> UUID {
        sessionId = UUID()
        timestamps.removeAll()
        logger.info("📊 Started latency session: \(self.sessionId.uuidString.prefix(8))")
        return sessionId
    }
    
    /// Get current session ID
    public var currentSessionId: UUID {
        sessionId
    }
    
    // MARK: - Recording
    
    /// Record a measurement point
    public func record(_ point: LatencyMeasurementPoint) {
        let now = Date()
        timestamps[point] = now
        
        // Log with signpost for Instruments
        os_signpost(.event, log: signpostLog, name: "LatencyPoint", "%{public}s", point.rawValue)
        
        logger.debug("⏱️ [\(self.sessionId.uuidString.prefix(8))] \(point.rawValue) at \(now.timeIntervalSince1970)")
    }
    
    /// Record a measurement with custom timestamp
    public func record(_ point: LatencyMeasurementPoint, at date: Date) {
        timestamps[point] = date
    }
    
    // MARK: - Calculations
    
    /// Calculate latency between two points in milliseconds
    public func latencyBetween(_ start: LatencyMeasurementPoint, _ end: LatencyMeasurementPoint) -> Double? {
        guard let startTime = timestamps[start],
              let endTime = timestamps[end] else {
            return nil
        }
        return endTime.timeIntervalSince(startTime) * 1000
    }
    
    /// Finalize session and compute all latencies
    public func finalizeSession() -> LatencyRecord {
        let record = LatencyRecord(
            sessionId: sessionId,
            audioToText: latencyBetween(.vadTrigger, .sttComplete),
            timeToFirstToken: latencyBetween(.sttComplete, .llmFirstToken),
            llmGeneration: latencyBetween(.llmFirstToken, .llmComplete),
            textToSpeech: latencyBetween(.ttsStart, .ttsFirstAudio),
            audioOut: latencyBetween(.llmFirstToken, .audioPlaybackStart),
            totalE2E: latencyBetween(.vadTrigger, .audioPlaybackStart)
        )
        
        // Store in history
        latencyHistory.append(record)
        if latencyHistory.count > maxHistorySize {
            latencyHistory.removeFirst()
        }
        
        // Log summary
        logSessionSummary(record)
        
        return record
    }
    
    // MARK: - Logging
    
    private func logSessionSummary(_ record: LatencyRecord) {
        logger.info("""
            📊 Session \(record.sessionId.uuidString.prefix(8)) Complete:
            • Audio→Text: \(String(format: "%.1f", record.audioToText ?? -1))ms
            • TTFT: \(String(format: "%.1f", record.timeToFirstToken ?? -1))ms
            • LLM Gen: \(String(format: "%.1f", record.llmGeneration ?? -1))ms
            • TTS: \(String(format: "%.1f", record.textToSpeech ?? -1))ms
            • Audio Out: \(String(format: "%.1f", record.audioOut ?? -1))ms
            • Total E2E: \(String(format: "%.1f", record.totalE2E ?? -1))ms
            """)
    }
    
    // MARK: - Statistics
    
    /// Get summary statistics from history
    public func getSummary() -> LatencySummary {
        let count = latencyHistory.count
        guard count > 0 else {
            return LatencySummary(
                sampleCount: 0,
                avgAudioToText: nil,
                avgTimeToFirstToken: nil,
                avgLLMGeneration: nil,
                avgTextToSpeech: nil,
                avgAudioOut: nil,
                avgTotalE2E: nil,
                p95AudioToText: nil,
                p95TimeToFirstToken: nil,
                p95TotalE2E: nil
            )
        }
        
        return LatencySummary(
            sampleCount: count,
            avgAudioToText: average(of: \.audioToText),
            avgTimeToFirstToken: average(of: \.timeToFirstToken),
            avgLLMGeneration: average(of: \.llmGeneration),
            avgTextToSpeech: average(of: \.textToSpeech),
            avgAudioOut: average(of: \.audioOut),
            avgTotalE2E: average(of: \.totalE2E),
            p95AudioToText: percentile95(of: \.audioToText),
            p95TimeToFirstToken: percentile95(of: \.timeToFirstToken),
            p95TotalE2E: percentile95(of: \.totalE2E)
        )
    }
    
    private func average(of keyPath: KeyPath<LatencyRecord, Double?>) -> Double? {
        let values = latencyHistory.compactMap { $0[keyPath: keyPath] }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
    
    private func percentile95(of keyPath: KeyPath<LatencyRecord, Double?>) -> Double? {
        let values = latencyHistory.compactMap { $0[keyPath: keyPath] }.sorted()
        guard !values.isEmpty else { return nil }
        let index = Int(Double(values.count) * 0.95)
        return values[min(index, values.count - 1)]
    }
    
    /// Get recent history
    public func getHistory(limit: Int = 10) -> [LatencyRecord] {
        Array(latencyHistory.suffix(limit))
    }
    
    /// Clear all history
    public func clearHistory() {
        latencyHistory.removeAll()
        logger.info("Cleared latency history")
    }
}

// MARK: - Signpost Extensions

extension LatencyMetrics {
    
    /// Begin a signpost interval for Instruments profiling
    public func beginInterval(_ name: StaticString) -> OSSignpostID {
        let id = OSSignpostID(log: signpostLog)
        os_signpost(.begin, log: signpostLog, name: name, signpostID: id)
        return id
    }
    
    /// End a signpost interval
    public func endInterval(_ name: StaticString, id: OSSignpostID) {
        os_signpost(.end, log: signpostLog, name: name, signpostID: id)
    }
}
