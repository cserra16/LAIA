//
//  OrbStyleManager.swift
//  LAIA - Local AI Assistant
//
//  Manages orb style selection and persistence.
//

import Foundation
import Combine

/// Available orb visual styles
public enum OrbStyle: String, CaseIterable, Identifiable {
    case neural = "neural"
    case particles = "particles"
    case plexus = "plexus"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .neural: return "Neural"
        case .particles: return "Partículas"
        case .plexus: return "Plexus"
        }
    }
    
    public var description: String {
        switch self {
        case .neural: return "Núcleo energético con nodos orbitales"
        case .particles: return "Nube de partículas que se compone y descompone"
        case .plexus: return "Red neural con nodos interconectados"
        }
    }
    
    public var icon: String {
        switch self {
        case .neural: return "circle.hexagongrid"
        case .particles: return "sparkles"
        case .plexus: return "point.3.connected.trianglepath.dotted"
        }
    }
}

/// Manager for orb style selection and persistence
@MainActor
public class OrbStyleManager: ObservableObject {
    
    // MARK: - Singleton
    
    public static let shared = OrbStyleManager()
    
    // MARK: - Published Properties
    
    @Published public var selectedStyle: OrbStyle {
        didSet {
            UserDefaults.standard.set(selectedStyle.rawValue, forKey: "laia_orb_style")
        }
    }
    
    // MARK: - Initialization
    
    private init() {
        if let savedStyle = UserDefaults.standard.string(forKey: "laia_orb_style"),
           let style = OrbStyle(rawValue: savedStyle) {
            self.selectedStyle = style
        } else {
            self.selectedStyle = .neural
        }
    }
}
