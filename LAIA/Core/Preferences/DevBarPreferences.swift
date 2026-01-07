//
//  DevBarPreferences.swift
//  LAIA - Local AI Assistant
//
//  Manages developer options visibility preferences.
//

import Foundation
import Combine

/// Manager for developer options preferences
@MainActor
public class DevBarPreferences: ObservableObject {
    
    // MARK: - Singleton
    
    public static let shared = DevBarPreferences()
    
    // MARK: - Published Properties
    
    /// Whether to show the developer bar (memory, status, recording)
    @Published public var showDevBar: Bool {
        didSet {
            UserDefaults.standard.set(showDevBar, forKey: "laia_show_dev_bar")
        }
    }
    
    // MARK: - Initialization
    
    private init() {
        // Default to false (hidden) for regular users
        self.showDevBar = UserDefaults.standard.bool(forKey: "laia_show_dev_bar")
    }
}
