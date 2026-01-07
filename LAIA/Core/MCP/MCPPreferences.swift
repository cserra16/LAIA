//
//  MCPPreferences.swift
//  LAIA
//
//  Preferencias de usuario para la configuración del cliente MCP.
//  Almacena la IP del servidor y otras configuraciones de conexión.
//
//  Created by LAIA Team on 07/01/26.
//

import Foundation
import Combine
import SwiftUI

/// Preferencias de conexión MCP
@MainActor
public class MCPPreferences: ObservableObject {
    
    // MARK: - Singleton
    
    public static let shared = MCPPreferences()
    
    // MARK: - UserDefaults Keys
    
    private enum Keys {
        static let serverIP = "mcp_server_ip"
        static let serverPort = "mcp_server_port"
        static let autoConnect = "mcp_auto_connect"
        static let isEnabled = "mcp_is_enabled"
    }
    
    // MARK: - Published Properties
    
    /// IP del servidor MCP (ej: "192.168.1.100")
    /// No usar "localhost" en dispositivo físico
    @Published public var serverIP: String {
        didSet {
            UserDefaults.standard.set(serverIP, forKey: Keys.serverIP)
        }
    }
    
    /// Puerto del servidor MCP (default: 8000)
    @Published public var serverPort: Int {
        didSet {
            UserDefaults.standard.set(serverPort, forKey: Keys.serverPort)
        }
    }
    
    /// Auto-conectar al iniciar la app
    @Published public var autoConnect: Bool {
        didSet {
            UserDefaults.standard.set(autoConnect, forKey: Keys.autoConnect)
        }
    }
    
    /// MCP habilitado/deshabilitado
    @Published public var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Keys.isEnabled)
        }
    }
    
    // MARK: - Computed Properties
    
    /// URL completa del servidor
    public var serverURL: String {
        "http://\(serverIP):\(serverPort)"
    }
    
    /// URL del endpoint SSE
    public var sseEndpoint: String {
        "\(serverURL)/sse"
    }
    
    // MARK: - Initialization
    
    private init() {
        // Cargar valores guardados o usar defaults
        // Usamos variables locales primero para evitar acceso a self antes de inicializar todo
        let loadedIP = UserDefaults.standard.string(forKey: Keys.serverIP) ?? "192.168.1.13"
        var loadedPort = UserDefaults.standard.integer(forKey: Keys.serverPort)
        if loadedPort == 0 {
            loadedPort = 8000
        }
        let loadedAutoConnect = UserDefaults.standard.bool(forKey: Keys.autoConnect)
        // Default to enabled for testing
        let storedEnabled = UserDefaults.standard.object(forKey: Keys.isEnabled)
        let loadedIsEnabled = storedEnabled != nil ? UserDefaults.standard.bool(forKey: Keys.isEnabled) : true
        
        // Ahora asignar a las propiedades
        self.serverIP = loadedIP
        self.serverPort = loadedPort
        self.autoConnect = loadedAutoConnect
        self.isEnabled = loadedIsEnabled
    }
    
    // MARK: - Methods
    
    /// Resetea todas las preferencias a valores por defecto
    public func reset() {
        serverIP = "192.168.1.13"
        serverPort = 8000
        autoConnect = false
        isEnabled = true
    }
    
    /// Valida que la IP tenga formato correcto
    public func isValidIP(_ ip: String) -> Bool {
        let parts = ip.split(separator: ".")
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard let num = Int(part) else { return false }
            return num >= 0 && num <= 255
        }
    }
}
