//
//  TTSPreferences.swift
//  LAIA - Local AI Assistant
//
//  Manages TTS engine preferences (native iOS vs Kokoro neural TTS).
//

import Foundation
import Combine

// MARK: - TTS Preferences Manager

/// Manager for TTS engine preferences
@MainActor
public class TTSPreferences: ObservableObject {
    
    // MARK: - Singleton
    
    public static let shared = TTSPreferences()
    
    // MARK: - Published Properties
    
    // Note: Kokoro-related properties removed. Native TTS is now the only option.
    
    // MARK: - Initialization
    
    private init() {
    }
    
    // MARK: - Status
    
    /// Current TTS engine name for display
    public var currentEngineName: String {
        "iOS Nativo"
    }
    
    /// Current voice display name
    public var currentVoiceDisplayName: String {
        "Sistema"
    }
}

