//
//  LAIADesignSystem.swift
//  LAIA - Local AI Assistant
//
//  Design system defining the "Ethereal & Fluid" aesthetic.
//  Optimized for OLED ProMotion displays with True Black backgrounds.
//

import SwiftUI

// MARK: - Color Palette

/// Semantic color definitions for LAIA's ethereal design language
public struct LAIAColors {
    
    // MARK: - Core Backgrounds (OLED Optimized)
    
    /// True black for maximum OLED efficiency
    public static let trueBlack = Color(red: 0, green: 0, blue: 0)
    
    /// Subtle elevation layer
    public static let surfaceElevated = Color(white: 0.06)
    
    /// Card/panel background with glassmorphism
    public static let glassSurface = Color(white: 0.08).opacity(0.7)
    
    // MARK: - AI Accent Colors (Neural Energy)
    
    /// Primary AI accent - Electric Indigo
    public static let aiAccent = Color(red: 0.35, green: 0.34, blue: 1.0)
    
    /// Secondary AI accent - Cosmic Purple
    public static let aiSecondary = Color(red: 0.58, green: 0.25, blue: 0.92)
    
    /// AI thinking state - Deep Violet
    public static let aiThinking = Color(red: 0.45, green: 0.20, blue: 0.85)
    
    /// AI speaking state - Luminous Cyan
    public static let aiSpeaking = Color(red: 0.25, green: 0.85, blue: 0.95)
    
    // MARK: - User Voice Colors
    
    /// User voice visualization - Soft White
    public static let userVoice = Color(white: 0.95)
    
    /// User voice active - Warm White
    public static let userVoiceActive = Color(red: 1.0, green: 0.98, blue: 0.94)
    
    // MARK: - System Indicators
    
    /// Privacy indicator - Secure Green
    public static let privacySecure = Color(red: 0.20, green: 0.85, blue: 0.55)
    
    /// Privacy active listening - Secure Blue
    public static let privacyListening = Color(red: 0.30, green: 0.65, blue: 0.95)
    
    /// Warning state - Amber
    public static let warning = Color(red: 1.0, green: 0.75, blue: 0.25)
    
    /// Error/Thermal state - Coral Red
    public static let error = Color(red: 1.0, green: 0.40, blue: 0.40)
    
    // MARK: - Text Colors
    
    /// Primary text
    public static let textPrimary = Color(white: 0.95)
    
    /// Secondary text
    public static let textSecondary = Color(white: 0.65)
    
    /// Muted text
    public static let textMuted = Color(white: 0.40)
    
    // MARK: - Gradient Definitions
    
    /// Neural orb gradient - Idle state
    public static let orbGradientIdle: [Color] = [
        aiAccent.opacity(0.6),
        aiSecondary.opacity(0.4),
        aiAccent.opacity(0.2)
    ]
    
    /// Neural orb gradient - Listening state
    public static let orbGradientListening: [Color] = [
        userVoice,
        userVoiceActive.opacity(0.8),
        aiAccent.opacity(0.3)
    ]
    
    /// Neural orb gradient - Thinking state
    public static let orbGradientThinking: [Color] = [
        aiThinking,
        aiSecondary,
        aiAccent.opacity(0.5)
    ]
    
    /// Neural orb gradient - Speaking state
    public static let orbGradientSpeaking: [Color] = [
        aiSpeaking,
        aiAccent,
        aiSecondary.opacity(0.6)
    ]
    
    // MARK: - State Color Mapping
    
    /// Get primary color for inference state
    public static func primaryColor(for state: InferenceStateValue) -> Color {
        switch state {
        case .idle:
            return aiAccent.opacity(0.5)
        case .listening, .detectingVoice:
            return userVoice
        case .transcribing:
            return userVoiceActive
        case .thinking:
            return aiThinking
        case .speaking:
            return aiSpeaking
        case .error:
            return error
        }
    }
    
    /// Get gradient for inference state
    public static func gradient(for state: InferenceStateValue) -> [Color] {
        switch state {
        case .idle:
            return orbGradientIdle
        case .listening, .detectingVoice:
            return orbGradientListening
        case .transcribing, .thinking:
            return orbGradientThinking
        case .speaking:
            return orbGradientSpeaking
        case .error:
            return [error, warning, error.opacity(0.5)]
        }
    }
}

// MARK: - Typography

/// Typography system using SF Pro Rounded
public struct LAIATypography {
    
    /// Large display text (AI response main)
    public static let displayLarge = Font.system(size: 28, weight: .medium, design: .rounded)
    
    /// Medium display
    public static let displayMedium = Font.system(size: 24, weight: .medium, design: .rounded)
    
    /// Streaming subtitle text
    public static let subtitle = Font.system(size: 20, weight: .regular, design: .rounded)
    
    /// Streaming subtitle emphasized
    public static let subtitleBold = Font.system(size: 20, weight: .semibold, design: .rounded)
    
    /// Body text
    public static let body = Font.system(size: 17, weight: .regular, design: .rounded)
    
    /// Caption/metrics
    public static let caption = Font.system(size: 13, weight: .medium, design: .rounded)
    
    /// Tiny metrics/debug
    public static let tiny = Font.system(size: 11, weight: .medium, design: .monospaced)
}

// MARK: - Animation Constants

/// Animation timing and curves for fluid transitions
public struct LAIAAnimations {
    
    /// Standard spring for most interactions
    public static let standard = Animation.spring(response: 0.4, dampingFraction: 0.75)
    
    /// Quick spring for immediate feedback
    public static let quick = Animation.spring(response: 0.25, dampingFraction: 0.8)
    
    /// Slow morphing for state transitions
    public static let morphing = Animation.easeInOut(duration: 0.8)
    
    /// Breathing animation for orb
    public static let breathing = Animation.easeInOut(duration: 2.0).repeatForever(autoreverses: true)
    
    /// Text fade in
    public static let textAppear = Animation.easeOut(duration: 0.15)
    
    /// Continuous rotation for neural nodes
    public static let orbitalRotation = Animation.linear(duration: 20).repeatForever(autoreverses: false)
    
    /// Pulse for indicators
    public static let pulse = Animation.easeInOut(duration: 1.2).repeatForever(autoreverses: true)
}

// MARK: - Spacing & Sizing

public struct LAIAMetrics {
    
    /// Orb sizes
    public static let orbSizeIdle: CGFloat = 180
    public static let orbSizeListening: CGFloat = 220
    public static let orbSizeThinking: CGFloat = 160
    public static let orbSizeSpeaking: CGFloat = 200
    
    /// Standard padding
    public static let paddingSmall: CGFloat = 8
    public static let paddingMedium: CGFloat = 16
    public static let paddingLarge: CGFloat = 24
    public static let paddingXLarge: CGFloat = 40
    
    /// Corner radii
    public static let cornerRadiusSmall: CGFloat = 8
    public static let cornerRadiusMedium: CGFloat = 16
    public static let cornerRadiusLarge: CGFloat = 24
    public static let cornerRadiusPill: CGFloat = 100
    
    /// Get orb size for state
    public static func orbSize(for state: InferenceStateValue) -> CGFloat {
        switch state {
        case .idle:
            return orbSizeIdle
        case .listening, .detectingVoice:
            return orbSizeListening
        case .transcribing, .thinking:
            return orbSizeThinking
        case .speaking:
            return orbSizeSpeaking
        case .error:
            return orbSizeIdle
        }
    }
}

// MARK: - View Modifiers

/// Glassmorphism background modifier
struct GlassmorphismModifier: ViewModifier {
    var cornerRadius: CGFloat = LAIAMetrics.cornerRadiusMedium
    
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.ultraThinMaterial)
                    .background(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(LAIAColors.glassSurface)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.2), .white.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            )
    }
}

/// Neon glow modifier
struct NeonGlowModifier: ViewModifier {
    let color: Color
    let radius: CGFloat
    
    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(0.8), radius: radius * 0.5)
            .shadow(color: color.opacity(0.5), radius: radius)
            .shadow(color: color.opacity(0.3), radius: radius * 2)
    }
}

// MARK: - View Extensions

public extension View {
    
    /// Apply glassmorphism effect
    func glassmorphism(cornerRadius: CGFloat = LAIAMetrics.cornerRadiusMedium) -> some View {
        modifier(GlassmorphismModifier(cornerRadius: cornerRadius))
    }
    
    /// Apply neon glow effect
    func neonGlow(_ color: Color, radius: CGFloat = 20) -> some View {
        modifier(NeonGlowModifier(color: color, radius: radius))
    }
}

// MARK: - Color Extensions

extension Color {
    
    /// Create color from hex string
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
