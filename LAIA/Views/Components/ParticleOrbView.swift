//
//  ParticleOrbView.swift
//  LAIA - Local AI Assistant
//
//  Particle-based orb visualization inspired by HTML particle system.
//  Creates a living cloud of particles that compose/decompose.
//

import SwiftUI

/// Particle orb visualizer - Alternative style with particle cloud
public struct ParticleOrbView: View {
    
    // MARK: - Properties
    
    let state: InferenceStateValue
    let audioAmplitude: CGFloat
    
    @State private var particles: [Particle] = []
    @State private var isComposed: Bool = true
    @State private var thinkingPhase: Double = 0
    
    private let particleCount = 300  // Reduced from 500 for performance
    private let orbRadius: CGFloat = 70
    
    // Adaptive particle count based on state
    private var activeParticleCount: Int {
        switch state {
        case .thinking, .transcribing:
            return 150  // Half particles during inference
        default:
            return particleCount
        }
    }
    
    // Adaptive frame rate
    private var frameInterval: TimeInterval {
        switch state {
        case .thinking, .transcribing:
            return 1/24  // 24fps during inference
        case .speaking:
            return 1/30  // 30fps during TTS
        default:
            return 1/60  // 60fps normal
        }
    }
    
    // MARK: - Body
    
    public var body: some View {
        TimelineView(.animation(minimumInterval: frameInterval)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            
            Canvas(opaque: false, colorMode: .linear, rendersAsynchronously: true) { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                
                // Draw glow background (pulsing with audio)
                drawGlow(context: context, center: center, size: size, time: time)
                
                // Draw only active particles
                let count = min(particles.count, activeParticleCount)
                for i in 0..<count {
                    drawParticle(context: context, particle: particles[i], center: center, time: time)
                }
            }
            .frame(width: 300, height: 300)
            .drawingGroup() // GPU acceleration
            .onChange(of: timeline.date) { _, _ in
                updateParticles(time: time)
            }
        }
        .onAppear {
            initializeParticles()
        }
        .onChange(of: state) { oldState, newState in
            handleStateChange(from: oldState, to: newState)
        }
    }
    
    // MARK: - Drawing
    
    private func drawGlow(context: GraphicsContext, center: CGPoint, size: CGSize, time: TimeInterval) {
        // Glow pulses with audio when speaking
        let audioPulse = state == .speaking ? 1.0 + audioAmplitude * 0.5 : 1.0
        let glowRadius = orbRadius * 2.5 * audioPulse
        
        // Color shifts based on state
        let hue: Double
        switch state {
        case .idle: hue = 0.75
        case .listening, .detectingVoice: hue = 0.55
        case .thinking, .transcribing: hue = 0.08
        case .speaking: hue = 0.80 + sin(time * 3) * 0.05
        case .error: hue = 0.0
        }
        
        let gradient = Gradient(colors: [
            Color(hue: hue, saturation: 0.6, brightness: 0.8).opacity(0.2 + audioAmplitude * 0.1),
            Color.clear
        ])
        
        context.fill(
            Circle().path(in: CGRect(
                x: center.x - glowRadius,
                y: center.y - glowRadius,
                width: glowRadius * 2,
                height: glowRadius * 2
            )),
            with: .radialGradient(gradient, center: center, startRadius: 0, endRadius: glowRadius)
        )
    }
    
    private func drawParticle(context: GraphicsContext, particle: Particle, center: CGPoint, time: TimeInterval) {
        let x = particle.x
        let y = particle.y
        
        // Audio-reactive size boost when speaking
        var sizeBoost: CGFloat = 0
        if state == .speaking {
            // Individual particles pulse at different rates based on audio
            let particlePulse = sin(time * 8 + particle.phase * 2) * 0.5 + 0.5
            sizeBoost = audioAmplitude * 2.5 * particlePulse
        }
        let size = particle.size + sizeBoost
        
        // Pulsing alpha - faster when speaking
        let pulseSpeed = state == .speaking ? 4.0 : 2.0
        let pulseAlpha = 0.5 + sin(time * pulseSpeed + particle.phase) * 0.3
        let alpha = particle.alpha * pulseAlpha
        
        let rect = CGRect(
            x: x - size / 2,
            y: y - size / 2,
            width: size,
            height: size
        )
        
        // Color based on state
        let hue: Double
        switch state {
        case .idle: hue = 0.75 + particle.colorOffset * 0.1
        case .listening, .detectingVoice: hue = 0.55 + particle.colorOffset * 0.1
        case .thinking, .transcribing: hue = 0.08 + particle.colorOffset * 0.1
        case .speaking: hue = 0.80 + particle.colorOffset * 0.15
        case .error: hue = 0.0
        }
        
        // Brightness pulses with audio when speaking
        let brightnessPulse = state == .speaking ? audioAmplitude * 0.3 : 0
        
        let color = Color(
            hue: hue,
            saturation: 0.7 + particle.colorOffset * 0.2,
            brightness: 0.6 + particle.colorOffset * 0.3 + brightnessPulse
        ).opacity(alpha)
        
        context.fill(Circle().path(in: rect), with: .color(color))
        
        // Add glow for larger particles (more glow when speaking)
        let glowThreshold: CGFloat = state == .speaking ? 2.0 : 2.5
        if size > glowThreshold {
            let glowRect = CGRect(
                x: x - size,
                y: y - size,
                width: size * 2,
                height: size * 2
            )
            let glowOpacity = 0.2 + (state == .speaking ? audioAmplitude * 0.3 : 0)
            context.fill(
                Circle().path(in: glowRect),
                with: .color(color.opacity(glowOpacity))
            )
        }
    }
    
    // MARK: - Particle System
    
    private func initializeParticles() {
        particles = (0..<particleCount).map { _ in
            Particle(orbRadius: orbRadius, canvasSize: 300)
        }
    }
    
    private func updateParticles(time: TimeInterval) {
        let canvasCenter: CGFloat = 150
        
        // Different behavior based on state
        let targetRadius: CGFloat
        let speed: CGFloat
        let vibrationIntensity: CGFloat
        
        switch state {
        case .idle:
            targetRadius = orbRadius
            speed = 0.06
            vibrationIntensity = 0.3
            
        case .listening, .detectingVoice:
            // Slightly expanded, gentle movement
            targetRadius = orbRadius * 1.1
            speed = 0.08
            vibrationIntensity = 0.5 + audioAmplitude * 2
            
        case .thinking, .transcribing:
            // Dispersed across screen
            targetRadius = orbRadius * 4  // Wide dispersion
            speed = 0.02  // Slow, dreamy movement
            vibrationIntensity = 1.5
            
        case .speaking:
            // Compact but vibrating STRONGLY with audio
            let audioPulse = audioAmplitude * 40  // Doubled pulse effect
            targetRadius = orbRadius * 0.8 + audioPulse
            speed = 0.15  // Very quick response
            vibrationIntensity = 5.0 + audioAmplitude * 25  // MUCH stronger vibration
            
        case .error:
            targetRadius = orbRadius * 1.5
            speed = 0.05
            vibrationIntensity = 3.0
        }
        
        for i in particles.indices {
            let targetX: CGFloat
            let targetY: CGFloat
            
            if state == .thinking || state == .transcribing {
                // Use scatter positions for thinking
                targetX = particles[i].scatterX
                targetY = particles[i].scatterY
            } else {
                // Calculate position on orb
                let scale = targetRadius / orbRadius
                targetX = canvasCenter + particles[i].relativeX * scale
                targetY = canvasCenter + particles[i].relativeY * scale
            }
            
            // Lerp towards target
            particles[i].x += (targetX - particles[i].x) * speed * particles[i].velocity
            particles[i].y += (targetY - particles[i].y) * speed * particles[i].velocity
            
            // Add vibration based on state
            // Speaking: synchronized vibration with audio
            if state == .speaking && audioAmplitude > 0.05 {
                let vibrationAngle = time * 20 + particles[i].phase
                let vibrationAmount = audioAmplitude * vibrationIntensity
                particles[i].x += cos(vibrationAngle) * vibrationAmount
                particles[i].y += sin(vibrationAngle * 1.3) * vibrationAmount
            } else {
                // Regular brownian motion
                particles[i].x += CGFloat.random(in: -vibrationIntensity...vibrationIntensity)
                particles[i].y += CGFloat.random(in: -vibrationIntensity...vibrationIntensity)
            }
            
            // For thinking state, add more dramatic orbital movement
            if state == .thinking || state == .transcribing {
                let orbitSpeed = 0.8 * particles[i].velocity  // Faster orbit
                let angle = time * orbitSpeed + particles[i].phase
                particles[i].x += cos(angle) * 2.0  // Larger orbit
                particles[i].y += sin(angle) * 2.0
            }
        }
    }
    
    private func handleStateChange(from oldState: InferenceStateValue, to newState: InferenceStateValue) {
        switch newState {
        case .thinking, .transcribing:
            // Generate wide scatter positions for dispersion
            regenerateScatterPositions(wide: true)
            
        case .speaking:
            // Particles will compose back automatically
            break
            
        case .error:
            regenerateScatterPositions(wide: false)
            
        default:
            break
        }
    }
    
    private func regenerateScatterPositions(wide: Bool) {
        for i in particles.indices {
            if wide {
                // FULL SCREEN dispersion for thinking - particles go everywhere!
                let angle = CGFloat(i) / CGFloat(particleCount) * CGFloat.pi * 12
                let distance = CGFloat.random(in: 50...280)  // Much wider range
                
                // Some particles go in spiral, some random
                if i % 3 == 0 {
                    // Spiral pattern
                    particles[i].scatterX = 150 + cos(angle) * distance
                    particles[i].scatterY = 150 + sin(angle) * distance
                } else {
                    // Full screen random - can go to edges and beyond
                    particles[i].scatterX = CGFloat.random(in: -150...450)
                    particles[i].scatterY = CGFloat.random(in: -150...450)
                }
            } else {
                particles[i].scatterX = CGFloat.random(in: -30...330)
                particles[i].scatterY = CGFloat.random(in: -30...330)
            }
        }
    }
}

// MARK: - Particle Model

private struct Particle {
    var x: CGFloat
    var y: CGFloat
    var relativeX: CGFloat
    var relativeY: CGFloat
    var scatterX: CGFloat
    var scatterY: CGFloat
    var size: CGFloat
    var alpha: CGFloat
    var velocity: CGFloat
    var phase: Double
    var colorOffset: Double
    
    init(orbRadius: CGFloat, canvasSize: CGFloat) {
        let center = canvasSize / 2
        
        // Start at center for smooth initial animation
        self.x = center + CGFloat.random(in: -20...20)
        self.y = center + CGFloat.random(in: -20...20)
        
        // Position relative to orb center (spherical distribution)
        let angle = CGFloat.random(in: 0...(CGFloat.pi * 2))
        let r = orbRadius * sqrt(CGFloat.random(in: 0...1))
        self.relativeX = cos(angle) * r
        self.relativeY = sin(angle) * r
        
        // Scatter positions
        self.scatterX = CGFloat.random(in: -100...400)
        self.scatterY = CGFloat.random(in: -100...400)
        
        // Particle properties - more variation
        self.size = CGFloat.random(in: 0.8...4.0)
        self.alpha = CGFloat.random(in: 0.4...0.9)
        self.velocity = CGFloat.random(in: 0.4...1.2)
        self.phase = Double.random(in: 0...(Double.pi * 2))
        self.colorOffset = Double.random(in: 0...1)
    }
}

// MARK: - Preview

#Preview("Particle Orb") {
    VStack(spacing: 30) {
        ParticleOrbView(state: .thinking, audioAmplitude: 0)
        ParticleOrbView(state: .speaking, audioAmplitude: 0.7)
    }
    .background(Color.black)
}

