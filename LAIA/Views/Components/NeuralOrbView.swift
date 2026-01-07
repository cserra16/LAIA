//
//  NeuralOrbView.swift
//  LAIA - Local AI Assistant
//
//  Minimalist orb visualization optimized for maximum fluidity.
//  Prioritizes smooth 60fps animation over visual complexity.
//  
//  Design Philosophy:
//  - Simple shapes, no complex calculations per frame
//  - Subtle breathing animation conveys "listening"
//  - Scale pulse reacts to audio for "responding"  
//  - Color shifts indicate state changes
//

import SwiftUI

/// Minimal, fluid orb visualizer
/// PERFORMANCE: Pauses animation when not visible to save GPU cycles
public struct NeuralOrbView: View {
    
    // MARK: - Properties
    
    let state: InferenceStateValue
    let audioAmplitude: CGFloat
    
    // Simple animation states
    @State private var breathPhase: CGFloat = 0
    @State private var pulsePhase: CGFloat = 0
    
    // Visibility tracking for performance
    @State private var isVisible: Bool = true
    
    // Fixed size for consistency
    private let orbSize: CGFloat = 160
    
    // MARK: - Colors (Simple, elegant)
    
    private var orbColor: Color {
        switch state {
        case .idle:
            return .white.opacity(0.6)
        case .listening, .detectingVoice:
            return .white
        case .thinking, .transcribing:
            return .white.opacity(0.4)
        case .speaking:
            return Color(red: 1.0, green: 0.45, blue: 0.1) // Warm orange
        case .error:
            return .red.opacity(0.8)
        }
    }
    
    private var glowIntensity: CGFloat {
        switch state {
        case .idle: return 0.15
        case .listening, .detectingVoice: return 0.25
        case .thinking, .transcribing: return 0.1
        case .speaking: return 0.35
        case .error: return 0.2
        }
    }
    
    private var breatheSpeed: CGFloat {
        switch state {
        case .thinking, .transcribing: return 2.5  // Faster breathing when thinking
        default: return 1.2
        }
    }
    
    // PERFORMANCE: Computed property for frame interval based on visibility
    private var animationInterval: TimeInterval {
        isVisible ? 1.0/60.0 : 1.0 // Effectively pause when not visible
    }
    
    // MARK: - Body
    
    public var body: some View {
        TimelineView(.animation(minimumInterval: animationInterval)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            
            // Simple calculations (skip expensive math if not visible)
            let breathe = isVisible ? sin(time * breatheSpeed) * 0.04 : 0
            let audioPulse = isVisible ? audioAmplitude * 0.12 : 0
            let scale = 1.0 + breathe + audioPulse
            
            ZStack {
                // Layer 1: Outer glow (single layer, not 3)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                orbColor.opacity(glowIntensity),
                                orbColor.opacity(glowIntensity * 0.3),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: orbSize * 0.3,
                            endRadius: orbSize * 0.9
                        )
                    )
                    .frame(width: orbSize * 1.8, height: orbSize * 1.8)
                
                // Layer 2: Main orb core
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                orbColor,
                                orbColor.opacity(0.7),
                                orbColor.opacity(0.3)
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: orbSize * 0.45
                        )
                    )
                    .frame(width: orbSize * 0.7, height: orbSize * 0.7)
                    .blur(radius: 2)
                
                // Layer 3: Inner bright core
                Circle()
                    .fill(orbColor.opacity(0.9))
                    .frame(width: orbSize * 0.25, height: orbSize * 0.25)
                    .blur(radius: 4)
                
                // Layer 4: Pulse ring (only when actively communicating AND visible)
                if isVisible && (state == .listening || state == .detectingVoice || state == .speaking) {
                    PulseRingView(color: orbColor, size: orbSize)
                }
            }
            .scaleEffect(scale)
        }
        .frame(width: orbSize * 2, height: orbSize * 2)
        .animation(.easeInOut(duration: 0.5), value: state)
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
    }
}

// MARK: - Pulse Ring (Separate view for isolation)

private struct PulseRingView: View {
    let color: Color
    let size: CGFloat
    
    @State private var ringScale: CGFloat = 0.5
    @State private var ringOpacity: CGFloat = 0.4
    
    var body: some View {
        Circle()
            .stroke(color.opacity(ringOpacity), lineWidth: 1.5)
            .frame(width: size * ringScale, height: size * ringScale)
            .onAppear {
                withAnimation(
                    .easeOut(duration: 1.5)
                    .repeatForever(autoreverses: false)
                ) {
                    ringScale = 1.2
                    ringOpacity = 0
                }
            }
    }
}

// MARK: - Preview

#Preview("Neural Orb - Minimal") {
    VStack(spacing: 50) {
        HStack(spacing: 40) {
            VStack {
                NeuralOrbView(state: .idle, audioAmplitude: 0)
                Text("Idle").font(.caption).foregroundStyle(.gray)
            }
            
            VStack {
                NeuralOrbView(state: .listening, audioAmplitude: 0.3)
                Text("Listening").font(.caption).foregroundStyle(.gray)
            }
        }
        
        HStack(spacing: 40) {
            VStack {
                NeuralOrbView(state: .thinking, audioAmplitude: 0)
                Text("Thinking").font(.caption).foregroundStyle(.gray)
            }
            
            VStack {
                NeuralOrbView(state: .speaking, audioAmplitude: 0.6)
                Text("Speaking").font(.caption).foregroundStyle(.gray)
            }
        }
    }
    .padding(40)
    .background(Color.black)
}
