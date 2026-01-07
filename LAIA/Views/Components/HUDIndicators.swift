//
//  HUDIndicators.swift
//  LAIA - Local AI Assistant
//
//  Head-Up Display indicators for privacy status and performance metrics.
//  Designed for minimal visual footprint with glassmorphism.
//

import SwiftUI

// MARK: - Privacy Indicator

/// Privacy shield indicator showing local processing status
public struct PrivacyIndicator: View {
    
    /// Whether microphone is actively listening
    let isListening: Bool
    
    /// Pulse animation state
    @State private var isPulsing: Bool = false
    
    private var indicatorColor: Color {
        isListening ? LAIAColors.privacyListening : LAIAColors.privacySecure
    }
    
    public var body: some View {
        HStack(spacing: 6) {
            // Shield icon with pulse
            ZStack {
                // Pulse ring
                Circle()
                    .stroke(indicatorColor.opacity(0.3), lineWidth: 2)
                    .frame(width: 24, height: 24)
                    .scaleEffect(isPulsing ? 1.4 : 1.0)
                    .opacity(isPulsing ? 0 : 0.5)
                
                // Shield icon
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(indicatorColor)
            }
            
            Text(isListening ? "Escuchando" : "Local")
                .font(LAIATypography.caption)
                .foregroundStyle(LAIAColors.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .glassmorphism(cornerRadius: LAIAMetrics.cornerRadiusPill)
        .onAppear {
            withAnimation(LAIAAnimations.pulse) {
                isPulsing = true
            }
        }
    }
}

// MARK: - Performance Metrics Pill

/// Minimal performance metrics display for technical users
public struct MetricsPill: View {
    
    /// RAM usage in GB
    let ramUsageGB: Double
    
    /// Tokens per second
    let tokensPerSecond: Double
    
    /// Whether to show expanded view
    @State private var isExpanded: Bool = false
    
    public var body: some View {
        HStack(spacing: 8) {
            // RAM indicator
            HStack(spacing: 4) {
                Circle()
                    .fill(ramColor)
                    .frame(width: 6, height: 6)
                
                Text(String(format: "%.1fGB", ramUsageGB))
                    .font(LAIATypography.tiny)
                    .foregroundStyle(LAIAColors.textSecondary)
            }
            
            if isExpanded || tokensPerSecond > 0 {
                // Separator
                Rectangle()
                    .fill(LAIAColors.textMuted)
                    .frame(width: 1, height: 12)
                
                // TPS indicator
                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(LAIAColors.aiAccent)
                    
                    Text(String(format: "%.0f TPS", tokensPerSecond))
                        .font(LAIATypography.tiny)
                        .foregroundStyle(LAIAColors.textSecondary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .glassmorphism(cornerRadius: LAIAMetrics.cornerRadiusPill)
        .onTapGesture {
            withAnimation(LAIAAnimations.quick) {
                isExpanded.toggle()
            }
        }
    }
    
    private var ramColor: Color {
        if ramUsageGB > 4.0 {
            return LAIAColors.warning
        } else if ramUsageGB > 3.0 {
            return LAIAColors.privacyListening
        } else {
            return LAIAColors.privacySecure
        }
    }
}

// MARK: - Thermal Warning Banner

/// Warning banner for thermal throttling
public struct ThermalWarningBanner: View {
    
    let thermalState: ProcessInfo.ThermalState
    
    @State private var isVisible: Bool = false
    
    private var shouldShow: Bool {
        thermalState == .serious || thermalState == .critical
    }
    
    public var body: some View {
        if shouldShow {
            HStack(spacing: 8) {
                Image(systemName: "thermometer.high")
                    .font(.system(size: 14))
                    .foregroundStyle(thermalState == .critical ? LAIAColors.error : LAIAColors.warning)
                
                Text(thermalState == .critical ? "Dispositivo caliente - Reduciendo rendimiento" : "Temperatura alta")
                    .font(LAIATypography.caption)
                    .foregroundStyle(LAIAColors.textPrimary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: LAIAMetrics.cornerRadiusPill)
                    .fill(thermalState == .critical ? LAIAColors.error.opacity(0.2) : LAIAColors.warning.opacity(0.2))
            )
            .overlay(
                RoundedRectangle(cornerRadius: LAIAMetrics.cornerRadiusPill)
                    .stroke(thermalState == .critical ? LAIAColors.error.opacity(0.5) : LAIAColors.warning.opacity(0.5), lineWidth: 1)
            )
            .transition(.move(edge: .top).combined(with: .opacity))
            .onAppear {
                // Trigger haptic
                Task { @MainActor in
                    LAIAHaptics.shared.thermalWarning()
                }
            }
        }
    }
}

// MARK: - State Label

/// Small label showing current state
public struct StateLabel: View {
    
    let state: InferenceStateValue
    
    public var body: some View {
        Text(state.rawValue)
            .font(LAIATypography.caption)
            .foregroundStyle(LAIAColors.primaryColor(for: state))
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(LAIAColors.primaryColor(for: state).opacity(0.15))
            )
    }
}

// MARK: - Combined HUD View

/// Combined HUD overlay with all indicators - Developer bar
public struct HUDOverlay: View {
    
    let isListening: Bool
    let ramUsageGB: Double
    let tokensPerSecond: Double
    let thermalState: ProcessInfo.ThermalState
    let showMetrics: Bool
    
    /// Recording state (passed from parent)
    var isRecording: Bool = false
    var onRecordingToggle: (() -> Void)? = nil
    
    public init(
        isListening: Bool = false,
        ramUsageGB: Double = 0,
        tokensPerSecond: Double = 0,
        thermalState: ProcessInfo.ThermalState = .nominal,
        showMetrics: Bool = true,
        isRecording: Bool = false,
        onRecordingToggle: (() -> Void)? = nil
    ) {
        self.isListening = isListening
        self.ramUsageGB = ramUsageGB
        self.tokensPerSecond = tokensPerSecond
        self.thermalState = thermalState
        self.showMetrics = showMetrics
        self.isRecording = isRecording
        self.onRecordingToggle = onRecordingToggle
    }
    
    public var body: some View {
        VStack(spacing: LAIAMetrics.paddingSmall) {
            // Consolidated dev bar
            HStack(spacing: 12) {
                // Left: Privacy indicator
                PrivacyIndicator(isListening: isListening)
                
                Spacer()
                
                // Center: Recording button
                Button {
                    onRecordingToggle?()
                } label: {
                    ZStack {
                        Circle()
                            .fill(isRecording ? LAIAColors.error : LAIAColors.surfaceElevated.opacity(0.8))
                            .frame(width: 40, height: 40)
                        
                        Image(systemName: isRecording ? "stop.fill" : "record.circle")
                            .font(.system(size: isRecording ? 14 : 22))
                            .foregroundStyle(isRecording ? .white : LAIAColors.error.opacity(0.8))
                    }
                    .overlay(
                        Circle()
                            .strokeBorder(
                                isRecording ? LAIAColors.error : LAIAColors.textMuted.opacity(0.3),
                                lineWidth: 1
                            )
                    )
                }
                
                Spacer()
                
                // Right: Metrics pill
                if showMetrics {
                    MetricsPill(ramUsageGB: ramUsageGB, tokensPerSecond: tokensPerSecond)
                }
            }
            .padding(.horizontal, LAIAMetrics.paddingMedium)
            
            // Thermal warning if needed
            ThermalWarningBanner(thermalState: thermalState)
        }
    }
}

// MARK: - Preview

#Preview("HUD Indicators") {
    VStack(spacing: 30) {
        HUDOverlay(
            isListening: true,
            ramUsageGB: 3.2,
            tokensPerSecond: 45,
            thermalState: .nominal
        )
        
        HUDOverlay(
            isListening: false,
            ramUsageGB: 4.5,
            tokensPerSecond: 0,
            thermalState: .serious
        )
        
        HStack(spacing: 20) {
            StateLabel(state: .idle)
            StateLabel(state: .listening)
            StateLabel(state: .thinking)
            StateLabel(state: .speaking)
        }
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(LAIAColors.trueBlack)
}
