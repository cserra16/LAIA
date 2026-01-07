//
//  HorizontalPagerView.swift
//  LAIA - Local AI Assistant
//
//  Horizontal pager that allows swiping between History, Main, and Settings.
//  Creates a seamless navigation experience with the main content sliding.
//

import SwiftUI

/// Pages available in the horizontal pager
public enum PagerPage: Int, CaseIterable {
    case history = 0
    case main = 1
    case settings = 2
}

/// Horizontal pager container for navigation between History, Main, and Settings
/// PERFORMANCE OPTIMIZED: Uses lazy view builders to avoid rendering off-screen pages
struct HorizontalPagerView<MainContent: View, HistoryContent: View, SettingsContent: View>: View {
    
    @Binding var currentPage: PagerPage
    
    // Use closures instead of materialized views for lazy rendering
    let mainContentBuilder: () -> MainContent
    let historyContentBuilder: () -> HistoryContent
    let settingsContentBuilder: () -> SettingsContent
    
    @State private var dragOffset: CGFloat = 0
    @GestureState private var isDragging: Bool = false
    
    private let swipeThreshold: CGFloat = 60
    private let velocityThreshold: CGFloat = 300
    
    init(
        currentPage: Binding<PagerPage>,
        @ViewBuilder mainContent: @escaping () -> MainContent,
        @ViewBuilder historyContent: @escaping () -> HistoryContent,
        @ViewBuilder settingsContent: @escaping () -> SettingsContent
    ) {
        self._currentPage = currentPage
        self.mainContentBuilder = mainContent
        self.historyContentBuilder = historyContent
        self.settingsContentBuilder = settingsContent
    }
    
    /// Determines which pages should be rendered (current + adjacent for smooth transitions)
    private func shouldRenderPage(_ page: PagerPage) -> Bool {
        // Always render current page
        if page == currentPage { return true }
        // Render adjacent pages only when dragging for smooth transitions
        if isDragging {
            switch currentPage {
            case .history: return page == .main
            case .main: return true // Render both adjacent
            case .settings: return page == .main
            }
        }
        return false
    }
    
    var body: some View {
        GeometryReader { geometry in
            let screenWidth = geometry.size.width
            let baseOffset = -CGFloat(currentPage.rawValue) * screenWidth
            
            HStack(spacing: 0) {
                // History (Left) - LAZY: Only render when visible or adjacent
                Group {
                    if shouldRenderPage(.history) {
                        historyContentBuilder()
                    } else {
                        Color.clear
                    }
                }
                .frame(width: screenWidth, height: geometry.size.height)
                
                // Main (Center) - LAZY: Only render when visible or adjacent
                Group {
                    if shouldRenderPage(.main) {
                        mainContentBuilder()
                    } else {
                        Color.clear
                    }
                }
                .frame(width: screenWidth, height: geometry.size.height)
                
                // Settings (Right) - LAZY: Only render when visible or adjacent
                Group {
                    if shouldRenderPage(.settings) {
                        settingsContentBuilder()
                    } else {
                        Color.clear
                    }
                }
                .frame(width: screenWidth, height: geometry.size.height)
            }
            .offset(x: baseOffset + dragOffset)
            .animation(isDragging ? nil : .spring(response: 0.35, dampingFraction: 0.86), value: currentPage)
            .animation(isDragging ? nil : .spring(response: 0.35, dampingFraction: 0.86), value: dragOffset)
            .gesture(
                DragGesture()
                    .updating($isDragging) { _, state, _ in
                        state = true
                    }
                    .onChanged { value in
                        // Calculate allowed drag based on current page
                        let translation = value.translation.width
                        
                        // Add resistance at edges
                        switch currentPage {
                        case .history:
                            // Can only drag left (to go right/main)
                            if translation < 0 {
                                dragOffset = translation
                            } else {
                                // Resistance when trying to go past edge
                                dragOffset = translation * 0.2
                            }
                        case .main:
                            // Can drag both directions
                            dragOffset = translation
                        case .settings:
                            // Can only drag right (to go left/main)
                            if translation > 0 {
                                dragOffset = translation
                            } else {
                                // Resistance when trying to go past edge
                                dragOffset = translation * 0.2
                            }
                        }
                    }
                    .onEnded { value in
                        let translation = value.translation.width
                        let velocity = value.predictedEndTranslation.width - translation
                        
                        // Determine if we should change page
                        let shouldChangePage = abs(translation) > swipeThreshold || abs(velocity) > velocityThreshold
                        
                        if shouldChangePage {
                            if translation > 0 || velocity > velocityThreshold {
                                // Swiped right - go to previous page
                                navigateToPreviousPage()
                            } else if translation < 0 || velocity < -velocityThreshold {
                                // Swiped left - go to next page
                                navigateToNextPage()
                            }
                        }
                        
                        // Reset drag offset
                        dragOffset = 0
                    }
            )
        }
        .ignoresSafeArea()
    }
    
    private func navigateToPreviousPage() {
        switch currentPage {
        case .history:
            break // Already at leftmost
        case .main:
            LAIAHaptics.shared.selection()
            currentPage = .history
        case .settings:
            LAIAHaptics.shared.selection()
            currentPage = .main
        }
    }
    
    private func navigateToNextPage() {
        switch currentPage {
        case .history:
            LAIAHaptics.shared.selection()
            currentPage = .main
        case .main:
            LAIAHaptics.shared.selection()
            currentPage = .settings
        case .settings:
            break // Already at rightmost
        }
    }
}

// MARK: - Programmatic Navigation Extension

extension HorizontalPagerView {
    /// Navigate to a specific page programmatically
    func navigateTo(_ page: PagerPage) {
        if currentPage != page {
            LAIAHaptics.shared.selection()
            currentPage = page
        }
    }
}

// MARK: - Preview

#Preview("Horizontal Pager") {
    struct PreviewWrapper: View {
        @State private var currentPage: PagerPage = .main
        
        var body: some View {
            HorizontalPagerView(
                currentPage: $currentPage,
                mainContent: {
                    ZStack {
                        Color.black
                        VStack {
                            Text("Main Content")
                                .foregroundStyle(.white)
                            Text("Page: \(currentPage.rawValue)")
                                .foregroundStyle(.gray)
                        }
                    }
                },
                historyContent: {
                    ZStack {
                        Color.blue.opacity(0.3)
                        Text("History")
                            .foregroundStyle(.white)
                    }
                },
                settingsContent: {
                    ZStack {
                        Color.purple.opacity(0.3)
                        Text("Settings")
                            .foregroundStyle(.white)
                    }
                }
            )
        }
    }
    
    return PreviewWrapper()
}
