//
//  HistorySideMenuView.swift
//  LAIA - Local AI Assistant
//
//  Side menu view for conversation history.
//  Elegant scrollable list of past messages.
//

import SwiftUI

struct HistorySideMenuView: View {
    let messages: [ConversationMessage]
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: onDismiss) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(LAIAColors.textSecondary)
                }
                
                Spacer()
                
                Text("Historial")
                    .font(LAIATypography.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(LAIAColors.textPrimary)
                
                Spacer()
                
                // Balance the header
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.clear)
            }
            .padding(.horizontal, LAIAMetrics.paddingMedium)
            .padding(.top, 60)
            .padding(.bottom, LAIAMetrics.paddingMedium)
            
            Divider()
                .background(LAIAColors.textMuted.opacity(0.2))
            
            // Messages list
            if messages.isEmpty {
                Spacer()
                
                VStack(spacing: 12) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 40))
                        .foregroundStyle(LAIAColors.textMuted.opacity(0.5))
                    
                    Text("Sin conversaciones aún")
                        .font(LAIATypography.body)
                        .foregroundStyle(LAIAColors.textMuted)
                    
                    Text("Toca el orbe para comenzar")
                        .font(LAIATypography.caption)
                        .foregroundStyle(LAIAColors.textMuted.opacity(0.7))
                }
                
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(messages) { message in
                                HistoryMessageRow(message: message)
                                    .id(message.id)
                            }
                        }
                        .padding(.horizontal, LAIAMetrics.paddingMedium)
                        .padding(.top, LAIAMetrics.paddingMedium)
                        .padding(.bottom, LAIAMetrics.paddingLarge + 40)
                    }
                    .onAppear {
                        // Scroll to most recent message
                        if let lastMessage = messages.last {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .background(LAIAColors.trueBlack)
    }
}

// MARK: - Message Row

private struct HistoryMessageRow: View {
    let message: ConversationMessage
    
    private var isUser: Bool {
        message.role == .user
    }
    
    private var roleIcon: String {
        switch message.role {
        case .user: return "person.fill"
        case .assistant: return "brain.head.profile"
        case .system: return "gear"
        }
    }
    
    private var roleColor: Color {
        switch message.role {
        case .user: return LAIAColors.userVoice
        case .assistant: return LAIAColors.aiSpeaking
        case .system: return LAIAColors.textMuted
        }
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Role indicator
            Image(systemName: roleIcon)
                .font(.system(size: 12))
                .foregroundStyle(roleColor.opacity(0.8))
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(roleColor.opacity(0.15))
                )
            
            VStack(alignment: .leading, spacing: 4) {
                // Role label with timestamp
                HStack {
                    Text(isUser ? "Tú" : "LAIA")
                        .font(LAIATypography.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(roleColor)
                    
                    Spacer()
                    
                    Text(formatTime(message.timestamp))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(LAIAColors.textMuted.opacity(0.6))
                }
                
                // Message content
                Text(message.content)
                    .font(LAIATypography.body)
                    .foregroundStyle(LAIAColors.textPrimary.opacity(0.9))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isUser ? LAIAColors.aiAccent.opacity(0.08) : LAIAColors.surfaceElevated.opacity(0.5))
        )
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - Preview

#Preview("History Side Menu") {
    HistorySideMenuView(
        messages: [
            ConversationMessage(role: .assistant, content: "¡Hola! Soy LAIA. ¿En qué puedo ayudarte?"),
            ConversationMessage(role: .user, content: "¿Qué tiempo hace hoy?"),
            ConversationMessage(role: .assistant, content: "Lo siento, no tengo acceso a información del clima en tiempo real. Sin embargo, puedo ayudarte con otras cosas como responder preguntas, explicar conceptos o mantener una conversación."),
            ConversationMessage(role: .user, content: "Vale, cuéntame un chiste"),
            ConversationMessage(role: .assistant, content: "¡Claro! Aquí va uno: ¿Por qué los pájaros no usan Facebook? Porque ya tienen Twitter. 🐦")
        ],
        onDismiss: {}
    )
    .frame(width: 350)
    .background(Color.black)
}
