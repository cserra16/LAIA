//
//  SideMenuView.swift
//  LAIA - Local AI Assistant
//
//  Reusable side menu component with slide-in animation.
//  Supports both left and right edge presentation.
//

import SwiftUI

/// Edge from which the menu appears
public enum SideMenuEdge {
    case leading  // Left side
    case trailing // Right side
}

struct SideMenuView<Content: View>: View {
    @Binding var isPresented: Bool
    let edge: SideMenuEdge
    let fullWidth: Bool
    let content: Content
    
    private let animationDuration: Double = 0.3
    
    init(
        isPresented: Binding<Bool>,
        edge: SideMenuEdge = .trailing,
        fullWidth: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self._isPresented = isPresented
        self.edge = edge
        self.fullWidth = fullWidth
        self.content = content()
    }
    
    var body: some View {
        GeometryReader { geometry in
            let menuWidth = fullWidth ? geometry.size.width : geometry.size.width * 0.85
            
            ZStack {
                // Dimmed background
                if isPresented {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                        .onTapGesture {
                            closeMenu()
                        }
                        .transition(.opacity)
                        .zIndex(0)
                }
                
                // Menu content - positioned based on edge
                HStack(spacing: 0) {
                    if edge == .trailing {
                        Spacer(minLength: 0)
                    }
                    
                    if isPresented {
                        ZStack {
                            // Background with blur
                            Rectangle()
                                .fill(.ultraThinMaterial)
                                .background(LAIAColors.trueBlack.opacity(0.95))
                            
                            // Main content
                            content
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .frame(width: menuWidth)
                        .ignoresSafeArea()
                        .transition(.move(edge: edge == .leading ? .leading : .trailing))
                        .highPriorityGesture(dragGesture)
                        .zIndex(1)
                    }
                    
                    if edge == .leading {
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }
    
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                let threshold: CGFloat = 50
                
                switch edge {
                case .leading:
                    // Swipe left to close left menu
                    if value.translation.width < -threshold {
                        closeMenu()
                    }
                case .trailing:
                    // Swipe right to close right menu
                    if value.translation.width > threshold {
                        closeMenu()
                    }
                }
            }
    }
    
    private func closeMenu() {
        withAnimation(.spring(response: animationDuration, dampingFraction: 0.8)) {
            isPresented = false
        }
    }
}

// MARK: - Preview

#Preview("Side Menu - Right") {
    struct PreviewWrapper: View {
        @State private var isOpen = true
        
        var body: some View {
            ZStack {
                Color.gray
                    .ignoresSafeArea()
                
                SideMenuView(isPresented: $isOpen, edge: .trailing, fullWidth: true) {
                    VStack {
                        Text("Settings Menu")
                            .font(.title)
                        Spacer()
                    }
                    .padding()
                }
            }
        }
    }
    
    return PreviewWrapper()
}

#Preview("Side Menu - Left") {
    struct PreviewWrapper: View {
        @State private var isOpen = true
        
        var body: some View {
            ZStack {
                Color.gray
                    .ignoresSafeArea()
                
                SideMenuView(isPresented: $isOpen, edge: .leading) {
                    VStack {
                        Text("History Menu")
                            .font(.title)
                        Spacer()
                    }
                    .padding()
                }
            }
        }
    }
    
    return PreviewWrapper()
}
