//
//  OrbContainerView.swift
//  LAIA - Local AI Assistant
//
//  Container that switches between different orb styles.
//

import SwiftUI

/// Container view that renders the selected orb style
/// NOTE: Currently fixed to NeuralOrbView while optimizing. Other styles commented out.
public struct OrbContainerView: View {
    
    let state: InferenceStateValue
    let audioAmplitude: CGFloat
    
    // Temporarily disabled while focusing on Neural orb
    // @StateObject private var styleManager = OrbStyleManager.shared
    
    public var body: some View {
        // RESTORED: NeuralOrbView with visibility-based optimization
        NeuralOrbView(state: state, audioAmplitude: audioAmplitude)
        
        /* Style switcher - disabled for now
        Group {
            switch styleManager.selectedStyle {
            case .neural:
                NeuralOrbView(state: state, audioAmplitude: audioAmplitude)
                
            case .particles:
                ParticleOrbView(state: state, audioAmplitude: audioAmplitude)
                
            case .plexus:
                PlexusOrbView(state: state, audioAmplitude: audioAmplitude)
            }
        }
        .animation(.easeInOut(duration: 0.5), value: styleManager.selectedStyle)
        */
    }
}

// MARK: - Preview

#Preview("Orb Container") {
    VStack {
        OrbContainerView(state: .speaking, audioAmplitude: 0.5)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.black)
}
