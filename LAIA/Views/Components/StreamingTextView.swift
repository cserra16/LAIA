//
//  StreamingTextView.swift
//  LAIA - Local AI Assistant
//
//  Dynamic subtitle display for streaming AI responses.
//  Shows text with smooth animations and proper styling.
//

import SwiftUI

/// Streaming text display with smooth animations and proper styling
public struct StreamingTextView: View {
    
    // MARK: - Properties
    
    /// The text being streamed
    let text: String
    
    /// Whether text is still being generated
    let isStreaming: Bool
    
    /// Cursor blink state
    @State private var showCursor: Bool = true
    
    /// Scroll position tracking
    @State private var scrollOffset: CGFloat = 0
    
    // MARK: - Body
    
    public var body: some View {
        GeometryReader { geometry in
            let maxHeight = geometry.size.height * 0.90  // Use most of available container height
            let textHeight = calculateTextHeight(for: text, width: geometry.size.width - 48)
            let needsScroll = textHeight > maxHeight
            
            VStack(spacing: 0) {
                if needsScroll {
                    // Scrollable container for long text
                    ScrollViewReader { proxy in
                        ScrollView(.vertical, showsIndicators: false) {
                            textContent
                                .id("responseText")
                        }
                        .frame(maxHeight: maxHeight)
                        .mask(
                            // Fade edges for scrollable content
                            VStack(spacing: 0) {
                                LinearGradient(
                                    colors: [.clear, .white],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                                .frame(height: 20)
                                
                                Rectangle().fill(.white)
                                
                                LinearGradient(
                                    colors: [.white, .clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                                .frame(height: 20)
                            }
                        )
                        .onChange(of: text) { _, _ in
                            // Auto-scroll to bottom as new text appears
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo("responseText", anchor: .bottom)
                            }
                        }
                    }
                } else {
                    // Non-scrollable for short text
                    textContent
                }
            }
        }
        .onAppear {
            startCursorBlink()
        }
    }
    
    // MARK: - Text Content
    
    private var textContent: some View {
        VStack(alignment: .center, spacing: 8) {
            HStack(alignment: .bottom, spacing: 4) {
                Text(text)
                    .font(.system(size: 17, weight: .regular, design: .default))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(hue: 0.75, saturation: 0.15, brightness: 0.95),  // Soft lavender white
                                Color(hue: 0.70, saturation: 0.20, brightness: 0.90)   // Slight purple tint
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(
            // Subtle background card
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.03),
                            Color.white.opacity(0.01)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    LAIAColors.aiAccent.opacity(0.2),
                                    LAIAColors.aiAccent.opacity(0.05)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        )
                )
        )
        .padding(.horizontal, LAIAMetrics.paddingMedium)
    }
    
    // MARK: - Helpers
    
    private func calculateTextHeight(for text: String, width: CGFloat) -> CGFloat {
        let font = UIFont.systemFont(ofSize: 17)
        let constraintRect = CGSize(width: width, height: .greatestFiniteMagnitude)
        let boundingBox = text.boundingRect(
            with: constraintRect,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        )
        return ceil(boundingBox.height) + 32  // Add padding
    }
    
    private func startCursorBlink() {
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.1)) {
                showCursor.toggle()
            }
        }
    }
}

// MARK: - Simple Streaming Text (Alternative)

/// Simpler streaming text without animations
public struct SimpleStreamingText: View {
    let text: String
    let isStreaming: Bool
    
    public var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            Text(text)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Color(hue: 0.75, saturation: 0.1, brightness: 0.92))
                .multilineTextAlignment(.center)
            
            if isStreaming {
                TypingIndicator()
            }
        }
        .padding(.horizontal, LAIAMetrics.paddingLarge)
    }
}

// MARK: - Typing Indicator

/// Three-dot typing indicator
struct TypingIndicator: View {
    @State private var animationPhase: Int = 0
    
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(LAIAColors.aiAccent)
                    .frame(width: 5, height: 5)
                    .opacity(animationPhase == index ? 1.0 : 0.3)
            }
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in
                withAnimation(.easeInOut(duration: 0.15)) {
                    animationPhase = (animationPhase + 1) % 3
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("Streaming Text") {
    VStack(spacing: 40) {
        StreamingTextView(
            text: "Hola, soy LAIA. ¿En qué puedo ayudarte hoy? Esta es una respuesta más larga para probar cómo se ve el texto cuando hay mucho contenido que mostrar.",
            isStreaming: true
        )
        .frame(height: 200)
        
        SimpleStreamingText(
            text: "Procesando tu solicitud",
            isStreaming: true
        )
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(LAIAColors.trueBlack)
}

