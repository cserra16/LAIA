//
//  HapticFeedback.swift
//  LAIA - Local AI Assistant
//
//  Core Haptics patterns for voice assistant feedback.
//  Provides tactile feedback for state transitions.
//

import CoreHaptics
import UIKit

/// Haptic feedback manager for LAIA interactions
@MainActor
public final class LAIAHaptics {
    
    // MARK: - Singleton
    
    public static let shared = LAIAHaptics()
    
    // MARK: - Properties
    
    private var engine: CHHapticEngine?
    private var isSupported: Bool = false
    
    // MARK: - Initialization
    
    private init() {
        setupEngine()
    }
    
    private func setupEngine() {
        // Check hardware support
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            isSupported = false
            return
        }
        
        isSupported = true
        
        do {
            engine = try CHHapticEngine()
            engine?.isAutoShutdownEnabled = true
            
            // Handle engine reset - callbacks run on background thread
            engine?.resetHandler = { [weak self] in
                Task { @MainActor in
                    try? self?.engine?.start()
                }
            }
            
            // Handle interruption - callbacks run on background thread
            engine?.stoppedHandler = { [weak self] reason in
                Task { @MainActor in
                    self?.engine = nil
                }
            }
            
            try engine?.start()
        } catch {
            isSupported = false
        }
    }
    
    // MARK: - Feedback Patterns
    
    /// Light tap when starting to listen
    public func startListening() {
        guard isSupported else {
            // Fallback to UIKit haptics
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            return
        }
        
        playPattern(events: [
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.5),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.6)
                ],
                relativeTime: 0
            )
        ])
    }
    
    /// Double tap when speech ends and processing begins
    public func endOfSpeech() {
        guard isSupported else {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                generator.impactOccurred()
            }
            return
        }
        
        playPattern(events: [
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.6),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.7)
                ],
                relativeTime: 0
            ),
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.7),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8)
                ],
                relativeTime: 0.08
            )
        ])
    }
    
    /// Soft pulse when AI starts speaking
    public func aiSpeaking() {
        guard isSupported else {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            return
        }
        
        playPattern(events: [
            CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.4),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3)
                ],
                relativeTime: 0,
                duration: 0.15
            )
        ])
    }
    
    /// Tap to interrupt
    public func interrupt() {
        guard isSupported else {
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            return
        }
        
        playPattern(events: [
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.9),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.9)
                ],
                relativeTime: 0
            )
        ])
    }
    
    /// Hold for walkie-talkie mode
    public func holdToTalk() {
        guard isSupported else {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            return
        }
        
        playPattern(events: [
            CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.7),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
                ],
                relativeTime: 0,
                duration: 0.2
            )
        ])
    }
    
    /// Thermal throttling warning - slow, grave vibration
    public func thermalWarning() {
        guard isSupported else {
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.warning)
            return
        }
        
        playPattern(events: [
            // First wave
            CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.6),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.2)
                ],
                relativeTime: 0,
                duration: 0.3
            ),
            // Second wave
            CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.8),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.15)
                ],
                relativeTime: 0.4,
                duration: 0.4
            )
        ])
    }
    
    /// Error feedback
    public func error() {
        guard isSupported else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }
        
        playPattern(events: [
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0)
                ],
                relativeTime: 0
            ),
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.8),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8)
                ],
                relativeTime: 0.1
            ),
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.6),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.6)
                ],
                relativeTime: 0.2
            )
        ])
    }
    
    /// Selection tick
    public func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
    
    // MARK: - Pattern Playback
    
    private func playPattern(events: [CHHapticEvent]) {
        guard let engine = engine else { return }
        
        do {
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            
            try engine.start()
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            // Silently fail - haptics are non-critical
        }
    }
    
    // MARK: - State-Based Feedback
    
    /// Provide haptic feedback for state transition
    public func feedbackForStateChange(from oldState: InferenceStateValue, to newState: InferenceStateValue) {
        switch newState {
        case .listening:
            if oldState == .idle {
                startListening()
            }
            
        case .transcribing:
            if oldState == .listening || oldState == .detectingVoice {
                endOfSpeech()
            }
            
        case .speaking:
            aiSpeaking()
            
        case .error:
            error()
            
        default:
            break
        }
    }
}
