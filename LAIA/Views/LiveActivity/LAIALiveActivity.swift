//
//  LAIALiveActivity.swift
//  LAIA - Local AI Assistant
//
//  Dynamic Island and Live Activity integration.
//  Shows compact orb visualization when app is minimized.
//

import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Live Activity Attributes

/// Attributes for LAIA Live Activity
public struct LAIAActivityAttributes: ActivityAttributes {
    
    /// Dynamic content that updates
    public struct ContentState: Codable, Hashable {
        /// Current assistant state
        var stateRawValue: String
        
        /// Whether AI is speaking
        var isSpeaking: Bool
        
        /// Current response preview (truncated)
        var responsePreview: String
        
        /// Audio waveform levels (5 values for visualization)
        var waveformLevels: [Float]
        
        public init(
            state: InferenceStateValue = .idle,
            isSpeaking: Bool = false,
            responsePreview: String = "",
            waveformLevels: [Float] = [0.3, 0.5, 0.7, 0.5, 0.3]
        ) {
            self.stateRawValue = state.rawValue
            self.isSpeaking = isSpeaking
            self.responsePreview = String(responsePreview.prefix(50))
            self.waveformLevels = waveformLevels
        }
    }
    
    /// Session start time
    public var startTime: Date
    
    public init(startTime: Date = Date()) {
        self.startTime = startTime
    }
}

// MARK: - Live Activity Manager

/// Manages Live Activity lifecycle
@MainActor
public final class LAIALiveActivityManager {
    
    public static let shared = LAIALiveActivityManager()
    
    private var currentActivity: Activity<LAIAActivityAttributes>?
    
    private init() {}
    
    /// Start a new Live Activity
    public func startActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            return
        }
        
        let attributes = LAIAActivityAttributes()
        let initialState = LAIAActivityAttributes.ContentState()
        
        do {
            currentActivity = try Activity.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: nil),
                pushType: nil
            )
        } catch {
            // Live Activities not available
        }
    }
    
    /// Update the Live Activity state
    public func update(state: InferenceStateValue, responsePreview: String = "", waveformLevels: [Float] = []) {
        let contentState = LAIAActivityAttributes.ContentState(
            state: state,
            isSpeaking: state == .speaking,
            responsePreview: responsePreview,
            waveformLevels: waveformLevels.isEmpty ? generateWaveform(for: state) : waveformLevels
        )
        
        Task {
            await currentActivity?.update(
                ActivityContent(state: contentState, staleDate: nil)
            )
        }
    }
    
    /// End the Live Activity
    public func endActivity() {
        Task {
            await currentActivity?.end(nil, dismissalPolicy: .immediate)
            currentActivity = nil
        }
    }
    
    private func generateWaveform(for state: InferenceStateValue) -> [Float] {
        switch state {
        case .speaking:
            return (0..<5).map { _ in Float.random(in: 0.4...1.0) }
        case .listening:
            return (0..<5).map { _ in Float.random(in: 0.2...0.8) }
        case .thinking:
            return [0.3, 0.5, 0.7, 0.5, 0.3]
        default:
            return [0.2, 0.2, 0.3, 0.2, 0.2]
        }
    }
}

// MARK: - Dynamic Island Views

/// Compact leading view for Dynamic Island
struct LAIACompactLeadingView: View {
    let state: LAIAActivityAttributes.ContentState
    
    var body: some View {
        // Mini orb indicator
        Circle()
            .fill(stateGradient)
            .frame(width: 20, height: 20)
            .overlay(
                Circle()
                    .stroke(.white.opacity(0.3), lineWidth: 1)
            )
    }
    
    private var stateGradient: LinearGradient {
        let colors: [Color] = state.isSpeaking
            ? [LAIAColors.aiSpeaking, LAIAColors.aiAccent]
            : [LAIAColors.aiAccent, LAIAColors.aiSecondary]
        
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// Compact trailing view for Dynamic Island
struct LAIACompactTrailingView: View {
    let state: LAIAActivityAttributes.ContentState
    
    var body: some View {
        // Mini waveform
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(LAIAColors.aiAccent)
                    .frame(width: 2, height: CGFloat(state.waveformLevels[safe: index] ?? 0.3) * 16)
            }
        }
    }
}

/// Minimal Dynamic Island view
struct LAIAMinimalView: View {
    let state: LAIAActivityAttributes.ContentState
    
    var body: some View {
        Circle()
            .fill(LAIAColors.aiAccent)
            .frame(width: 12, height: 12)
    }
}

/// Expanded Dynamic Island view
struct LAIAExpandedView: View {
    let state: LAIAActivityAttributes.ContentState
    
    var body: some View {
        HStack(spacing: 12) {
            // Left: Mini orb
            Circle()
                .fill(
                    RadialGradient(
                        colors: state.isSpeaking
                            ? [LAIAColors.aiSpeaking, LAIAColors.aiAccent.opacity(0.5)]
                            : [LAIAColors.aiAccent, LAIAColors.aiSecondary.opacity(0.5)],
                        center: .center,
                        startRadius: 0,
                        endRadius: 25
                    )
                )
                .frame(width: 50, height: 50)
                .overlay(
                    // Waveform overlay
                    WaveformView(levels: state.waveformLevels)
                        .frame(width: 30, height: 20)
                )
            
            // Right: Text preview
            VStack(alignment: .leading, spacing: 4) {
                Text(state.isSpeaking ? "LAIA está hablando" : "LAIA")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                
                if !state.responsePreview.isEmpty {
                    Text(state.responsePreview)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(2)
                }
            }
            
            Spacer()
        }
        .padding()
    }
}

/// Waveform visualization for Dynamic Island
struct WaveformView: View {
    let levels: [Float]
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<levels.count, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(.white)
                    .frame(width: 3, height: CGFloat(levels[safe: index] ?? 0.3) * 20)
            }
        }
    }
}

// MARK: - Widget Configuration

/// Widget for Lock Screen and Dynamic Island
public struct LAIALiveActivityWidget: Widget {
    
    public init() {}
    
    public var body: some WidgetConfiguration {
        ActivityConfiguration(for: LAIAActivityAttributes.self) { context in
            // Lock Screen view
            LAIAExpandedView(state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.8))
                .activitySystemActionForegroundColor(.white)
            
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded regions
                DynamicIslandExpandedRegion(.leading) {
                    LAIACompactLeadingView(state: context.state)
                }
                
                DynamicIslandExpandedRegion(.trailing) {
                    LAIACompactTrailingView(state: context.state)
                }
                
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.isSpeaking ? "Hablando..." : "LAIA")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                }
                
                DynamicIslandExpandedRegion(.bottom) {
                    if !context.state.responsePreview.isEmpty {
                        Text(context.state.responsePreview)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(1)
                    }
                }
                
            } compactLeading: {
                LAIACompactLeadingView(state: context.state)
                
            } compactTrailing: {
                LAIACompactTrailingView(state: context.state)
                
            } minimal: {
                LAIAMinimalView(state: context.state)
            }
        }
    }
}

// MARK: - Array Extension

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
