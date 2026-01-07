//
//  PlexusOrbView.swift
//  LAIA - Local AI Assistant
//
//  Neural Plexus orb visualization inspired by Three.js particle network.
//  Creates an elegant mesh of interconnected nodes with fluid animations.
//  
//  PERFORMANCE OPTIMIZED:
//  - Adaptive frame rate based on inference state
//  - Reduced node count during heavy processing
//  - GPU-accelerated rendering with drawingGroup()
//  - Simplified calculations during thinking state
//

import SwiftUI

// MARK: - Plexus Node

private struct PlexusNode {
    var current: CGPoint
    var target: CGPoint
    var velocity: CGFloat
    var phase: Double
    var size: CGFloat
    var nearestIndices: [Int]
    
    init(index: Int, totalNodes: Int, orbRadius: CGFloat, canvasCenter: CGFloat) {
        self.phase = Double.random(in: 0...(Double.pi * 2))
        self.velocity = CGFloat.random(in: 0.6...1.4)
        self.size = CGFloat.random(in: 1.5...3.5)
        self.nearestIndices = []
        
        // Initialize in toroid shape
        let R: CGFloat = orbRadius * 0.75
        let tubeMax: CGFloat = orbRadius * 0.35
        let theta = CGFloat.random(in: 0...(CGFloat.pi * 2))
        let phi = CGFloat.random(in: 0...(CGFloat.pi * 2))
        let r = CGFloat.random(in: 0...tubeMax)
        
        // Project 3D torus to 2D with perspective
        let x3D = (R + r * cos(phi)) * cos(theta)
        let y3D = (R + r * cos(phi)) * sin(theta)
        let z3D = r * sin(phi)
        
        let scale: CGFloat = 1.0 + z3D / (orbRadius * 2)
        let x = canvasCenter + x3D * scale
        let y = canvasCenter + y3D * scale
        
        self.current = CGPoint(x: x, y: y)
        self.target = self.current
    }
    
    mutating func updateTarget(for state: InferenceStateValue, orbRadius: CGFloat, canvasCenter: CGFloat, index: Int, totalNodes: Int) {
        let isSphere = state == .speaking
        
        if isSphere {
            let phi = CGFloat.random(in: 0...(CGFloat.pi * 2))
            let cosTheta = CGFloat.random(in: -1...1)
            let u = CGFloat.random(in: 0...1)
            let r = orbRadius * 0.85 * pow(u, 1.0/3.0)
            let theta = acos(cosTheta)
            
            let x = r * sin(theta) * cos(phi)
            let y = r * sin(theta) * sin(phi)
            
            self.target = CGPoint(x: canvasCenter + x, y: canvasCenter + y)
        } else {
            let R: CGFloat = orbRadius * 0.72
            let tubeMax: CGFloat = orbRadius * 0.32
            let theta = CGFloat.random(in: 0...(CGFloat.pi * 2))
            let phi = CGFloat.random(in: 0...(CGFloat.pi * 2))
            let r = CGFloat.random(in: 0...tubeMax)
            
            let x = (R + r * cos(phi)) * cos(theta)
            let y = (R + r * cos(phi)) * sin(theta)
            
            self.target = CGPoint(x: canvasCenter + x, y: canvasCenter + y)
        }
    }
}

// MARK: - Plexus Orb View

/// Neural Plexus orb visualization with interconnected nodes
/// Performance-optimized for concurrent LLM inference
public struct PlexusOrbView: View {
    
    // MARK: - Properties
    
    let state: InferenceStateValue
    let audioAmplitude: CGFloat
    
    @State private var nodes: [PlexusNode] = []
    @State private var rippleClock: Double = -10
    @State private var lastStateChange: Date = Date()
    @State private var frameSkipCounter: Int = 0
    
    // Adaptive configuration based on state
    private var nodeCount: Int {
        switch state {
        case .thinking, .transcribing:
            return 60  // Reduced during inference
        default:
            return 100 // Normal operation
        }
    }
    
    private var frameInterval: TimeInterval {
        switch state {
        case .thinking, .transcribing:
            return 1/24  // 24fps during inference (saves CPU)
        case .speaking:
            return 1/30  // 30fps during TTS
        default:
            return 1/60  // 60fps when idle/listening
        }
    }
    
    private var shouldDrawConnections: Bool {
        // Skip connection drawing during heavy processing
        switch state {
        case .thinking, .transcribing:
            return frameSkipCounter % 2 == 0  // Draw connections every other frame
        default:
            return true
        }
    }
    
    private let orbRadius: CGFloat = 100
    private let canvasSize: CGFloat = 280
    private let minConnectionDistance: CGFloat = 50  // Increased for fewer connections
    private let maxConnections = 2  // Reduced from 3
    
    // Ripple wave configuration
    private let rippleSpeed: Double = 0.08
    private let rippleStrength: CGFloat = 12
    private let rippleFrequency: CGFloat = 0.08
    private let rippleWidth: CGFloat = 0.003
    
    private var canvasCenter: CGFloat { canvasSize / 2 }
    
    // MARK: - Computed Properties
    
    private var primaryColor: Color {
        switch state {
        case .idle:
            return .white.opacity(0.7)
        case .listening, .detectingVoice:
            return .white
        case .thinking, .transcribing:
            return .white.opacity(0.5)
        case .speaking:
            return Color(red: 1.0, green: 0.42, blue: 0.0)
        case .error:
            return .red
        }
    }
    
    private var nodeBrightness: CGFloat {
        switch state {
        case .idle: return 0.8
        case .listening, .detectingVoice: return 1.0
        case .thinking, .transcribing: return 0.5
        case .speaking: return 1.4
        case .error: return 1.0
        }
    }
    
    private var shouldRotate: Bool {
        state == .thinking || state == .transcribing
    }
    
    private var scaleMultiplier: CGFloat {
        switch state {
        case .idle: return 1.0
        case .listening, .detectingVoice: return 1.0
        case .thinking, .transcribing: return 0.9
        case .speaking: return 1.15
        case .error: return 1.0
        }
    }
    
    // MARK: - Body
    
    public var body: some View {
        TimelineView(.animation(minimumInterval: frameInterval)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            
            Canvas(opaque: true, colorMode: .linear, rendersAsynchronously: true) { context, size in
                // Fill background first (opaque canvas optimization)
                context.fill(
                    Rectangle().path(in: CGRect(origin: .zero, size: size)),
                    with: .color(LAIAColors.trueBlack)
                )
                
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                drawPlexusNetwork(context: context, center: center, time: time)
            }
            .frame(width: canvasSize, height: canvasSize)
            .drawingGroup(opaque: true, colorMode: .linear) // GPU acceleration
            .onChange(of: timeline.date) { _, _ in
                frameSkipCounter += 1
                updateNodes(time: time)
            }
        }
        .onAppear {
            initializeNodes()
        }
        .onChange(of: state) { oldState, newState in
            handleStateChange(from: oldState, to: newState)
        }
    }
    
    // MARK: - Drawing
    
    private func drawPlexusNetwork(context: GraphicsContext, center: CGPoint, time: TimeInterval) {
        guard !nodes.isEmpty else { return }
        
        let color = primaryColor
        
        // Simplified rotation calculation
        let rotation = shouldRotate ? time * 3.0 : 0  // Slower rotation
        
        // Simplified breathing (less sin calculations)
        let breathe = 1.0 + sin(time) * 0.03
        let audioPulse: CGFloat = state == .speaking ? audioAmplitude * 0.1 : 0
        let currentScale = scaleMultiplier * breathe * (1.0 + audioPulse)
        
        // Apply transformations
        var ctx = context
        ctx.translateBy(x: center.x, y: center.y)
        ctx.scaleBy(x: currentScale, y: currentScale)
        ctx.rotate(by: .radians(rotation))
        ctx.translateBy(x: -canvasCenter, y: -canvasCenter)
        
        // Draw connections (conditionally)
        if shouldDrawConnections {
            drawConnections(context: ctx, color: color)
        }
        
        // Draw nodes (simplified during thinking)
        drawNodes(context: ctx, time: time, color: color)
        
        // Draw glow (simplified)
        drawGlow(context: context, center: center, scale: currentScale)
    }
    
    private func drawConnections(context: GraphicsContext, color: Color) {
        // Only draw nearest neighbor connections during heavy load
        let shouldDrawProximity = state != .thinking && state != .transcribing
        
        var drawnConnections = Set<String>()
        let activeNodeCount = min(nodes.count, nodeCount)
        
        for i in 0..<activeNodeCount {
            // Draw to nearest neighbors (always)
            for neighborIdx in nodes[i].nearestIndices {
                guard neighborIdx < activeNodeCount else { continue }
                let key = i < neighborIdx ? "\(i)-\(neighborIdx)" : "\(neighborIdx)-\(i)"
                if drawnConnections.contains(key) { continue }
                drawnConnections.insert(key)
                
                var path = Path()
                path.move(to: nodes[i].current)
                path.addLine(to: nodes[neighborIdx].current)
                
                let alpha = 0.2 * nodeBrightness
                context.stroke(path, with: .color(color.opacity(alpha)), lineWidth: 0.8)
            }
            
            // Draw proximity connections only when not thinking
            if shouldDrawProximity {
                for j in (i + 1)..<activeNodeCount {
                    let dist = hypot(nodes[i].current.x - nodes[j].current.x,
                                    nodes[i].current.y - nodes[j].current.y)
                    
                    if dist < minConnectionDistance {
                        let key = "\(i)-\(j)"
                        if drawnConnections.contains(key) { continue }
                        drawnConnections.insert(key)
                        
                        let alpha = max(0.03, (1.0 - dist / minConnectionDistance) * 0.1 * nodeBrightness)
                        
                        var path = Path()
                        path.move(to: nodes[i].current)
                        path.addLine(to: nodes[j].current)
                        
                        context.stroke(path, with: .color(color.opacity(alpha)), lineWidth: 0.5)
                    }
                }
            }
        }
    }
    
    private func drawNodes(context: GraphicsContext, time: TimeInterval, color: Color) {
        let activeNodeCount = min(nodes.count, nodeCount)
        let skipPulse = state == .thinking || state == .transcribing
        
        for i in 0..<activeNodeCount {
            let node = nodes[i]
            
            // Simplified size calculation during thinking
            let pulse: CGFloat = skipPulse ? 1.0 : (1.0 + sin(time * 3 + node.phase) * 0.2)
            let size = node.size * pulse * nodeBrightness
            
            let rect = CGRect(
                x: node.current.x - size / 2,
                y: node.current.y - size / 2,
                width: size,
                height: size
            )
            
            // Main node only (skip glow during thinking)
            context.fill(Circle().path(in: rect), with: .color(color.opacity(0.85)))
            
            // Glow only for larger nodes and not during thinking
            if !skipPulse && size > 2.5 {
                let glowRect = CGRect(
                    x: node.current.x - size,
                    y: node.current.y - size,
                    width: size * 2,
                    height: size * 2
                )
                context.fill(Circle().path(in: glowRect), with: .color(color.opacity(0.12)))
            }
        }
    }
    
    private func drawGlow(context: GraphicsContext, center: CGPoint, scale: CGFloat) {
        let glowRadius = orbRadius * 1.5 * scale
        
        let gradient = Gradient(colors: [
            primaryColor.opacity(0.12),
            primaryColor.opacity(0.04),
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
    
    // MARK: - Node System
    
    private func initializeNodes() {
        let maxNodes = 100  // Initialize with max, use subset during thinking
        nodes = (0..<maxNodes).map { i in
            PlexusNode(index: i, totalNodes: maxNodes, orbRadius: orbRadius, canvasCenter: canvasCenter)
        }
        computeNearestNeighbors()
    }
    
    private func computeNearestNeighbors() {
        for i in nodes.indices {
            var distances: [(idx: Int, dist: CGFloat)] = []
            
            for j in nodes.indices where i != j {
                let dist = hypot(nodes[i].target.x - nodes[j].target.x,
                                nodes[i].target.y - nodes[j].target.y)
                distances.append((j, dist))
            }
            
            distances.sort { $0.dist < $1.dist }
            nodes[i].nearestIndices = Array(distances.prefix(maxConnections).map { $0.idx })
        }
    }
    
    private func updateNodes(time: TimeInterval) {
        // Simplified updates during thinking
        let isHeavyState = state == .thinking || state == .transcribing
        let lerpFactor: CGFloat = isHeavyState ? 0.02 : 0.04  // Slower lerp during thinking
        let activeNodeCount = min(nodes.count, nodeCount)
        
        // Update ripple clock
        if !isHeavyState {
            rippleClock += rippleSpeed
            if rippleClock > 50 {
                rippleClock = -10
            }
        }
        
        for i in 0..<activeNodeCount {
            // Lerp towards target
            let dx = (nodes[i].target.x - nodes[i].current.x) * lerpFactor * nodes[i].velocity
            let dy = (nodes[i].target.y - nodes[i].current.y) * lerpFactor * nodes[i].velocity
            
            nodes[i].current.x += dx
            nodes[i].current.y += dy
            
            // Skip ripple during thinking
            if !isHeavyState && rippleClock > -5 && rippleClock < 45 {
                let nodeCenter = CGPoint(x: nodes[i].current.x - canvasCenter,
                                        y: nodes[i].current.y - canvasCenter)
                let dist = hypot(nodeCenter.x, nodeCenter.y)
                
                let wavePhase: CGFloat
                let center: CGFloat
                
                if state == .speaking {
                    wavePhase = dist * rippleFrequency - CGFloat(rippleClock)
                    center = CGFloat(rippleClock) * 0.65
                } else {
                    wavePhase = dist * rippleFrequency + CGFloat(rippleClock)
                    center = 22 - CGFloat(rippleClock) * 0.65
                }
                
                let envelope = exp(-pow(dist - center, 2) * rippleWidth)
                let rippleAmount = sin(wavePhase) * envelope * rippleStrength * (1.0 + audioAmplitude)
                
                if dist > 0.01 {
                    nodes[i].current.x += nodeCenter.x / dist * rippleAmount
                    nodes[i].current.y += nodeCenter.y / dist * rippleAmount
                }
            }
            
            // Minimal noise during thinking
            if !isHeavyState {
                let noise = sin(time * 7 + Double(i)) * 0.3
                nodes[i].current.x += noise
                nodes[i].current.y += noise
            }
            
            // Audio-reactive vibration when speaking
            if state == .speaking && audioAmplitude > 0.05 {
                let vibrationAngle = time * 15 + nodes[i].phase
                let vibrationAmount = audioAmplitude * 8
                nodes[i].current.x += cos(vibrationAngle) * vibrationAmount
                nodes[i].current.y += sin(vibrationAngle * 1.3) * vibrationAmount
            }
        }
    }
    
    private func handleStateChange(from oldState: InferenceStateValue, to newState: InferenceStateValue) {
        lastStateChange = Date()
        frameSkipCounter = 0
        
        // Regenerate targets
        for i in nodes.indices {
            nodes[i].updateTarget(for: newState, orbRadius: orbRadius, canvasCenter: canvasCenter, index: i, totalNodes: nodes.count)
        }
        
        computeNearestNeighbors()
        
        if newState == .speaking {
            rippleClock = -5
        }
    }
}

// MARK: - Preview

#Preview("Plexus Orb - States") {
    VStack(spacing: 40) {
        HStack(spacing: 30) {
            VStack {
                PlexusOrbView(state: .listening, audioAmplitude: 0)
                Text("Listening")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            VStack {
                PlexusOrbView(state: .thinking, audioAmplitude: 0)
                Text("Thinking")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        
        HStack(spacing: 30) {
            VStack {
                PlexusOrbView(state: .speaking, audioAmplitude: 0.5)
                Text("Speaking")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            VStack {
                PlexusOrbView(state: .idle, audioAmplitude: 0)
                Text("Idle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
    .padding()
    .background(Color.black)
}
