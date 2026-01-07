//
//  TTSVoiceManager.swift
//  LAIA - Local AI Assistant
//
//  Manages TTS voice selection and persistence.
//  Supports Personal Voice (iOS 17+).
//

import Foundation
import AVFoundation
import Combine

/// Manager for TTS voice selection and persistence
/// Marked as @MainActor to prevent concurrency issues with @Published properties
@MainActor
public class TTSVoiceManager: ObservableObject {
    
    // MARK: - Singleton
    
    public static let shared = TTSVoiceManager()
    
    // MARK: - Published Properties
    
    @Published public var selectedVoiceIdentifier: String {
        didSet {
            UserDefaults.standard.set(selectedVoiceIdentifier, forKey: "laia_tts_voice_id")
        }
    }
    
    @Published public var personalVoiceAuthStatus: AVSpeechSynthesizer.PersonalVoiceAuthorizationStatus = .notDetermined
    
    // MARK: - Properties
    
    /// All available Personal Voices (iOS 17+)
    public var availablePersonalVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.voiceTraits.contains(.isPersonalVoice) }
    }
    
    /// All available Spanish voices (system voices)
    public var availableSpanishVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("es") && !$0.voiceTraits.contains(.isPersonalVoice) }
            .sorted { voice1, voice2 in
                // Sort by quality (enhanced first), then by name
                if voice1.quality != voice2.quality {
                    return voice1.quality.rawValue > voice2.quality.rawValue
                }
                return voice1.name < voice2.name
            }
    }
    
    /// All voices: Personal first, then Spanish system voices
    public var allAvailableVoices: [AVSpeechSynthesisVoice] {
        availablePersonalVoices + availableSpanishVoices
    }
    
    /// Currently selected voice
    public var selectedVoice: AVSpeechSynthesisVoice? {
        if let voice = AVSpeechSynthesisVoice(identifier: selectedVoiceIdentifier) {
            return voice
        }
        // Fallback to default Spanish voice
        return AVSpeechSynthesisVoice(language: "es-ES")
    }
    
    // MARK: - Initialization
    
    private init() {
        // Load saved voice or use default
        if let savedId = UserDefaults.standard.string(forKey: "laia_tts_voice_id"),
           AVSpeechSynthesisVoice(identifier: savedId) != nil {
            self.selectedVoiceIdentifier = savedId
        } else {
            // Find best default Spanish voice
            let defaultVoice = Self.findBestDefaultVoice()
            self.selectedVoiceIdentifier = defaultVoice?.identifier ?? ""
        }
        
        // Check current Personal Voice authorization
        personalVoiceAuthStatus = AVSpeechSynthesizer.personalVoiceAuthorizationStatus
        
        // Request authorization if not determined
        if personalVoiceAuthStatus == .notDetermined {
            requestPersonalVoiceAccess()
        }
    }
    
    // MARK: - Personal Voice Authorization
    
    /// Request access to Personal Voice
    public func requestPersonalVoiceAccess() {
        AVSpeechSynthesizer.requestPersonalVoiceAuthorization { [weak self] status in
            DispatchQueue.main.async {
                self?.personalVoiceAuthStatus = status
                // Refresh voices list after authorization
                self?.objectWillChange.send()
            }
        }
    }
    
    // MARK: - Helpers
    
    private static func findBestDefaultVoice() -> AVSpeechSynthesisVoice? {
        let spanishVoices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("es") && !$0.voiceTraits.contains(.isPersonalVoice) }
        
        // Prefer enhanced quality
        if let enhanced = spanishVoices.first(where: { $0.quality == .enhanced }) {
            return enhanced
        }
        
        // Fall back to any Spanish voice
        return spanishVoices.first ?? AVSpeechSynthesisVoice(language: "es-ES")
    }
    
    /// Get display name for a voice
    public func displayName(for voice: AVSpeechSynthesisVoice) -> String {
        let isPersonal = voice.voiceTraits.contains(.isPersonalVoice)
        
        if isPersonal {
            return "👤 \(voice.name) (Voz Personal)"
        }
        
        let qualityBadge = voice.quality == .enhanced ? " ⭐" : ""
        let regionFlag = regionFlag(for: voice.language)
        return "\(voice.name)\(qualityBadge) \(regionFlag)"
    }
    
    /// Check if a voice is personal voice
    public func isPersonalVoice(_ voice: AVSpeechSynthesisVoice) -> Bool {
        voice.voiceTraits.contains(.isPersonalVoice)
    }
    
    /// Get region flag emoji for language code
    private func regionFlag(for languageCode: String) -> String {
        switch languageCode {
        case "es-ES": return "🇪🇸"
        case "es-MX": return "🇲🇽"
        case "es-AR": return "🇦🇷"
        case "es-CO": return "🇨🇴"
        case "es-CL": return "🇨🇱"
        case "es-US": return "🇺🇸"
        default: return "🌎"
        }
    }
}

