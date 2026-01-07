//
//  SettingsView.swift
//  LAIA - Local AI Assistant
//
//  Settings menu showing model details for STT, LLM, and TTS.
//

import SwiftUI
import AVFoundation

/// Settings view displaying model information
public struct SettingsView: View {
    
    @Environment(\.dismiss) private var dismiss
    @StateObject private var voiceManager = TTSVoiceManager.shared
    @StateObject private var orbStyleManager = OrbStyleManager.shared
    @StateObject private var devBarPrefs = DevBarPreferences.shared
    @StateObject private var ttsPrefs = TTSPreferences.shared
    @State private var showingAdvanced: Bool = false
    @State private var isSystemPromptExpanded: Bool = false
    
    public var onDismiss: (() -> Void)?
    
    private var ttsModelName: String {
        guard let voice = voiceManager.selectedVoice, 
              voice != AVSpeechSynthesisVoice() else {
            return "Sistema"
        }
        let quality = voice.quality == .enhanced ? "Enhanced" : "Default"
        return "\(voice.name) (\(quality))"
    }
    
    public init(onDismiss: (() -> Void)? = nil) {
        self.onDismiss = onDismiss
    }
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: LAIAMetrics.paddingLarge) {
                    
                    // Header
                    headerSection
                    
                    // Model Cards
                    VStack(spacing: LAIAMetrics.paddingMedium) {
                        // STT Model
                        ModelInfoCard(
                            icon: "waveform",
                            iconColor: LAIAColors.userVoice,
                            title: "Transcripción (STT)",
                            modelName: LAIAModelConfig.Whisper.modelName,
                            details: [
                                ("Motor", "WhisperKit"),
                                ("Idioma", "Español (es)"),
                                ("Tamaño", formatBytes(LAIAModelConfig.Whisper.modelSizeBytes)),
                                ("Compute", "CPU + Neural Engine")
                            ]
                        )
                        
                        // LLM Model
                        ModelInfoCard(
                            icon: "brain",
                            iconColor: LAIAColors.aiThinking,
                            title: "Inferencia LLM",
                            modelName: LAIAModelConfig.Qwen.modelName,
                            details: [
                                ("Motor", "MLX Swift"),
                                ("Cuantización", LAIAModelConfig.Qwen.quantization),
                                ("Tamaño", formatBytes(LAIAModelConfig.Qwen.modelSizeBytes)),
                                ("Contexto máx.", "\(LAIAModelConfig.Qwen.maxContextTokens) tokens")
                            ]
                        )
                        
                        // TTS Model
                        ModelInfoCard(
                            icon: "speaker.wave.3",
                            iconColor: Color(red: 0.4, green: 0.9, blue: 1.0),
                            title: "Síntesis de Voz (TTS)",
                            modelName: ttsModelName,
                            details: [
                                ("Motor", ttsPrefs.currentEngineName),
                                ("Idioma", "Español (es-ES)"),
                                ("Calidad", (voiceManager.selectedVoice?.quality == .enhanced ? "Enhanced ⭐" : "Default"))
                            ]
                        )
                    }
                    
                    // Voice Selector
                    voiceSelectorSection
                    
                    // Orb Style Selector
                    orbStyleSection
                    
                    // Memory Info
                    memorySection
                    
                    // System Prompt
                    systemPromptSection
                    
                    // Dev Options section
                    devOptionsSection
                    
                    // Advanced toggle
                    if showingAdvanced {
                        advancedSection
                    }
                    
                    // App version
                    versionSection
                }
                .padding()
            }
            .background(LAIAColors.trueBlack)
            .navigationTitle("Configuración")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") {
                        if let onDismiss = onDismiss {
                            onDismiss()
                        } else {
                            dismiss()
                        }
                    }
                    .foregroundStyle(LAIAColors.aiAccent)
                }
            }
        }
    }
    
    // MARK: - Sections
    
    private var headerSection: some View {
        VStack(spacing: LAIAMetrics.paddingSmall) {
            Image(systemName: "gearshape.2.fill")
                .font(.system(size: 44))
                .foregroundStyle(
                    LinearGradient(
                        colors: [LAIAColors.aiAccent, LAIAColors.aiThinking],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Text("Modelos de IA")
                .font(LAIATypography.displayMedium)
                .foregroundStyle(LAIAColors.textPrimary)
            
            Text("Información sobre los modelos utilizados")
                .font(LAIATypography.caption)
                .foregroundStyle(LAIAColors.textMuted)
        }
        .padding(.vertical, LAIAMetrics.paddingMedium)
    }
    
    private var voiceSelectorSection: some View {
        VStack(alignment: .leading, spacing: LAIAMetrics.paddingSmall) {
            // Header
            HStack(spacing: LAIAMetrics.paddingSmall) {
                Image(systemName: "person.wave.2")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(LAIAColors.aiSpeaking)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(LAIAColors.aiSpeaking.opacity(0.15))
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Voz del Asistente")
                        .font(LAIATypography.subtitle)
                        .foregroundStyle(LAIAColors.textPrimary)
                    
                    if let voice = voiceManager.selectedVoice {
                        Text("\(voice.name) (\(voice.quality == .enhanced ? "Enhanced" : "Default"))")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color(red: 0.4, green: 0.9, blue: 1.0)) // Light blue/cyan
                    }
                }
                
                Spacer()
            }
            
            Divider()
                .background(LAIAColors.textMuted.opacity(0.2))
            
            // Voice Picker
            VStack(spacing: 12) {
                HStack {
                    Text("Voz activa")
                        .font(LAIATypography.caption)
                        .foregroundStyle(LAIAColors.textMuted)
                    
                    Spacer()
                    
                    voiceMenu
                }
                
                HStack {
                    Text("Tipo")
                        .font(LAIATypography.caption)
                        .foregroundStyle(LAIAColors.textMuted)
                    
                    Spacer()
                    
                    Text(voiceManager.isPersonalVoice(voiceManager.selectedVoice ?? AVSpeechSynthesisVoice()) ? "Voz Personal" : "Voz del Sistema")
                        .font(LAIATypography.caption)
                        .foregroundStyle(LAIAColors.textSecondary)
                }
                
                // Preview button
                Button {
                    if let voice = voiceManager.selectedVoice {
                        previewVoice(voice)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.circle.fill")
                        Text("Escuchar muestra")
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(red: 0.4, green: 0.9, blue: 1.0))
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: LAIAMetrics.cornerRadiusMedium)
                .fill(LAIAColors.surfaceElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: LAIAMetrics.cornerRadiusMedium)
                        .strokeBorder(
                            LinearGradient(
                                colors: [LAIAColors.aiSpeaking.opacity(0.3), LAIAColors.aiSpeaking.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
    }
    
    private var voiceMenu: some View {
        Menu {
            // Personal Voices
            if !voiceManager.availablePersonalVoices.isEmpty {
                Section("Personales") {
                    ForEach(voiceManager.availablePersonalVoices, id: \.identifier) { voice in
                        Button {
                            voiceManager.selectedVoiceIdentifier = voice.identifier
                        } label: {
                            HStack {
                                Text("👤 " + voice.name)
                                if voiceManager.selectedVoiceIdentifier == voice.identifier {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            }
            
            // System Voices
            Section("Sistema") {
                ForEach(voiceManager.availableSpanishVoices, id: \.identifier) { voice in
                    Button {
                        voiceManager.selectedVoiceIdentifier = voice.identifier
                    } label: {
                        HStack {
                            Text(voiceManager.displayName(for: voice))
                            if voiceManager.selectedVoiceIdentifier == voice.identifier {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                if let voice = voiceManager.selectedVoice {
                    Text(voice.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(red: 0.4, green: 0.9, blue: 1.0))
                    
                    if voice.quality == .enhanced {
                        Text("⭐")
                            .font(.system(size: 12))
                    }
                    
                    Text(voice.language.contains("ES") ? "🇪🇸" : "🌍")
                        .font(.system(size: 14))
                } else {
                    Text("Seleccionar")
                        .font(.system(size: 14))
                        .foregroundStyle(LAIAColors.textMuted)
                }
                
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(LAIAColors.aiSpeaking)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(LAIAColors.aiSpeaking.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
    
    private func previewVoice(_ voice: AVSpeechSynthesisVoice) {
        let utterance = AVSpeechUtterance(string: "Hola, soy LAIA, tu asistente personal.")
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.volume = 1.0
        
        let synthesizer = AVSpeechSynthesizer()
        synthesizer.speak(utterance)
    }
    
    private var orbStyleSection: some View {
        VStack(alignment: .leading, spacing: LAIAMetrics.paddingSmall) {
            // Header
            HStack(spacing: LAIAMetrics.paddingSmall) {
                Image(systemName: "circle.hexagongrid")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(LAIAColors.aiAccent)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(LAIAColors.aiAccent.opacity(0.15))
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Estilo del Orbe")
                        .font(LAIATypography.subtitle)
                        .foregroundStyle(LAIAColors.textPrimary)
                    
                    Text(orbStyleManager.selectedStyle.displayName)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(LAIAColors.aiAccent)
                }
                
                Spacer()
            }
            
            Divider()
                .background(LAIAColors.textMuted.opacity(0.2))
            
            // Style Selector
            HStack(spacing: 12) {
                ForEach(OrbStyle.allCases) { style in
                    OrbStyleButton(
                        style: style,
                        isSelected: orbStyleManager.selectedStyle == style
                    ) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            orbStyleManager.selectedStyle = style
                        }
                    }
                }
            }
            
            Text(orbStyleManager.selectedStyle.description)
                .font(.system(size: 11))
                .foregroundStyle(LAIAColors.textMuted)
                .padding(.top, 4)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: LAIAMetrics.cornerRadiusMedium)
                .fill(LAIAColors.surfaceElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: LAIAMetrics.cornerRadiusMedium)
                        .strokeBorder(
                            LinearGradient(
                                colors: [LAIAColors.aiAccent.opacity(0.3), LAIAColors.aiAccent.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
    }
    
    private var memorySection: some View {
        VStack(alignment: .leading, spacing: LAIAMetrics.paddingSmall) {
            // Header
            HStack(spacing: LAIAMetrics.paddingSmall) {
                Image(systemName: "memorychip")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(LAIAColors.warning)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(LAIAColors.warning.opacity(0.15))
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Uso de Memoria")
                        .font(LAIATypography.subtitle)
                        .foregroundStyle(LAIAColors.textPrimary)
                    
                    Text(LAIAModelConfig.hasSufficientRAM ? "Óptimo" : "Limitado")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(LAIAModelConfig.hasSufficientRAM ? LAIAColors.privacySecure : LAIAColors.warning)
                }
                
                Spacer()
            }
            
            Divider()
                .background(LAIAColors.textMuted.opacity(0.2))
            
            // Details
            VStack(spacing: 8) {
                MemoryRow(
                    label: "Límite GPU máximo",
                    value: formatBytes(LAIAModelConfig.MemoryLimits.maxGPUMemory)
                )
                MemoryRow(
                    label: "Headroom reservado",
                    value: formatBytes(LAIAModelConfig.MemoryLimits.headroom)
                )
                MemoryRow(
                    label: "RAM del dispositivo",
                    value: formatBytes(LAIAModelConfig.estimatedAvailableRAM)
                )
                MemoryRow(
                    label: "RAM suficiente",
                    value: LAIAModelConfig.hasSufficientRAM ? "✓ Sí" : "✗ No"
                )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: LAIAMetrics.cornerRadiusMedium)
                .fill(LAIAColors.surfaceElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: LAIAMetrics.cornerRadiusMedium)
                        .strokeBorder(
                            LinearGradient(
                                colors: [LAIAColors.warning.opacity(0.3), LAIAColors.warning.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
    }
    
    private var systemPromptSection: some View {
        VStack(alignment: .leading, spacing: LAIAMetrics.paddingSmall) {
            HStack {
                Image(systemName: "text.bubble")
                    .foregroundStyle(LAIAColors.aiAccent)
                Text("System Prompt")
                    .font(LAIATypography.subtitle)
                    .foregroundStyle(LAIAColors.textPrimary)
            }
            
                VStack(alignment: .leading, spacing: 4) {
                    Text(LAIAModelConfig.Qwen.systemPrompt)
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundStyle(LAIAColors.textSecondary)
                        .lineLimit(isSystemPromptExpanded ? nil : 3)
                        .multilineTextAlignment(.leading)
                    
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            isSystemPromptExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(isSystemPromptExpanded ? "Mostrar menos" : "Mostrar más")
                            Image(systemName: isSystemPromptExpanded ? "chevron.up" : "chevron.down")
                        }
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(LAIAColors.aiAccent)
                        .padding(.top, 4)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: LAIAMetrics.cornerRadiusSmall)
                        .fill(Color.black.opacity(0.3))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: LAIAMetrics.cornerRadiusSmall)
                        .strokeBorder(LAIAColors.aiAccent.opacity(0.2), lineWidth: 1)
                )
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: LAIAMetrics.cornerRadiusMedium)
                .fill(LAIAColors.surfaceElevated)
        )
    }
    
    private var devOptionsSection: some View {
        VStack(alignment: .leading, spacing: LAIAMetrics.paddingSmall) {
            // Header
            HStack(spacing: LAIAMetrics.paddingSmall) {
                Image(systemName: "hammer.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(LAIAColors.textMuted)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(LAIAColors.textMuted.opacity(0.15))
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Dev Options")
                        .font(LAIATypography.subtitle)
                        .foregroundStyle(LAIAColors.textPrimary)
                    
                    Text("Opciones de desarrollo")
                        .font(.system(size: 11))
                        .foregroundStyle(LAIAColors.textMuted)
                }
                
                Spacer()
            }
            
            Divider()
                .background(LAIAColors.textMuted.opacity(0.2))
            
            // Toggle for dev bar
            Toggle(isOn: $devBarPrefs.showDevBar) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mostrar barra de desarrollo")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(LAIAColors.textPrimary)
                    
                    Text("Muestra memoria, grabación y métricas")
                        .font(.system(size: 11))
                        .foregroundStyle(LAIAColors.textMuted)
                }
            }
            .tint(LAIAColors.aiAccent)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: LAIAMetrics.cornerRadiusMedium)
                .fill(LAIAColors.surfaceElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: LAIAMetrics.cornerRadiusMedium)
                        .strokeBorder(LAIAColors.textMuted.opacity(0.2), lineWidth: 0.5)
                )
        )
    }
    
    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: LAIAMetrics.paddingSmall) {
            Text("Configuración Avanzada")
                .font(LAIATypography.subtitle)
                .foregroundStyle(LAIAColors.textPrimary)
            
            VStack(spacing: 8) {
                MemoryRow(label: "Timeout idle Whisper", value: "\(Int(LAIAModelConfig.Whisper.idleUnloadTimeout))s")
                MemoryRow(label: "Timeout idle LLM", value: "\(Int(LAIAModelConfig.Qwen.idleUnloadTimeout))s")
                MemoryRow(label: "Cache KV purge", value: "\(Int(LAIAModelConfig.Qwen.kvCachePurgeTimeout))s")
                MemoryRow(label: "Temperatura LLM", value: String(format: "%.1f", LAIAModelConfig.Qwen.temperature))
                MemoryRow(label: "Top-P sampling", value: String(format: "%.1f", LAIAModelConfig.Qwen.topP))
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: LAIAMetrics.cornerRadiusMedium)
                    .fill(LAIAColors.surfaceElevated)
            )
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
    
    private var versionSection: some View {
        VStack(spacing: 4) {
            Button {
                withAnimation(LAIAAnimations.standard) {
                    showingAdvanced.toggle()
                }
            } label: {
                Text(showingAdvanced ? "Ocultar avanzado" : "Mostrar avanzado")
                    .font(LAIATypography.caption)
                    .foregroundStyle(LAIAColors.aiAccent)
            }
            
            Divider()
                .background(LAIAColors.textMuted.opacity(0.3))
                .padding(.vertical, LAIAMetrics.paddingSmall)
            
            Text("LAIA v1.0")
                .font(LAIATypography.caption)
                .foregroundStyle(LAIAColors.textMuted)
            
            Text("Local AI Assistant")
                .font(.system(size: 10))
                .foregroundStyle(LAIAColors.textMuted.opacity(0.6))
        }
        .padding(.top, LAIAMetrics.paddingMedium)
    }
    
    // MARK: - Helpers
    
    private func formatBytes(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / (1024 * 1024 * 1024)
        if gb >= 1 {
            return String(format: "%.1f GB", gb)
        } else {
            let mb = Double(bytes) / (1024 * 1024)
            return String(format: "%.0f MB", mb)
        }
    }
}

// MARK: - Model Info Card

struct ModelInfoCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let modelName: String
    let details: [(String, String)]
    
    var body: some View {
        VStack(alignment: .leading, spacing: LAIAMetrics.paddingSmall) {
            // Header
            HStack(spacing: LAIAMetrics.paddingSmall) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(iconColor.opacity(0.15))
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(LAIATypography.subtitle)
                        .foregroundStyle(LAIAColors.textPrimary)
                    
                    Text(modelName)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(iconColor)
                        .lineLimit(1)
                }
                
                Spacer()
            }
            
            Divider()
                .background(LAIAColors.textMuted.opacity(0.2))
            
            // Details
            ForEach(details, id: \.0) { detail in
                HStack {
                    Text(detail.0)
                        .font(LAIATypography.caption)
                        .foregroundStyle(LAIAColors.textMuted)
                    
                    Spacer()
                    
                    Text(detail.1)
                        .font(LAIATypography.caption)
                        .foregroundStyle(LAIAColors.textSecondary)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: LAIAMetrics.cornerRadiusMedium)
                .fill(LAIAColors.surfaceElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: LAIAMetrics.cornerRadiusMedium)
                        .strokeBorder(
                            LinearGradient(
                                colors: [iconColor.opacity(0.3), iconColor.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
    }
}

// MARK: - Memory Row

struct MemoryRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(LAIATypography.caption)
                .foregroundStyle(LAIAColors.textMuted)
            
            Spacer()
            
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(LAIAColors.textSecondary)
        }
    }
}

// MARK: - Voice Row

struct VoiceRow: View {
    let voice: AVSpeechSynthesisVoice
    let isSelected: Bool
    let displayName: String
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName)
                        .font(LAIATypography.caption)
                        .foregroundStyle(isSelected ? LAIAColors.aiAccent : LAIAColors.textPrimary)
                    
                    Text(voice.language)
                        .font(.system(size: 10))
                        .foregroundStyle(LAIAColors.textMuted)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(LAIAColors.aiAccent)
                        .font(.system(size: 18))
                }
            }
            .padding(.horizontal, LAIAMetrics.paddingMedium)
            .padding(.vertical, LAIAMetrics.paddingSmall)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isSelected ? LAIAColors.aiAccent.opacity(0.1) : Color.clear)
    }
}

// MARK: - Orb Style Button

struct OrbStyleButton: View {
    let style: OrbStyle
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 8) {
                // Icon
                ZStack {
                    Circle()
                        .fill(isSelected ? LAIAColors.aiAccent : LAIAColors.surfaceElevated)
                        .frame(width: 60, height: 60)
                    
                    Image(systemName: style.icon)
                        .font(.system(size: 24))
                        .foregroundStyle(isSelected ? .white : LAIAColors.textMuted)
                }
                .overlay(
                    Circle()
                        .strokeBorder(
                            isSelected ? LAIAColors.aiAccent : LAIAColors.textMuted.opacity(0.3),
                            lineWidth: 2
                        )
                )
                
                // Name
                Text(style.displayName)
                    .font(LAIATypography.caption)
                    .foregroundStyle(isSelected ? LAIAColors.aiAccent : LAIAColors.textSecondary)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Preview

#Preview("Settings") {
    SettingsView()
}
