//
//  MCPNetworkManager.swift
//  LAIA
//
//  Manager para la conexión con servidores MCP (Model Context Protocol).
//  Utiliza el SDK oficial de MCP para Swift.
//
//  Documentación: https://github.com/modelcontextprotocol/swift-sdk
//
//  Created by LAIA Team on 07/01/26.
//

import Foundation
import Combine
import MCP
import os

// MARK: - MCP Connection State

/// Estado de la conexión MCP
public enum MCPConnectionState: Sendable, Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)
}

// MARK: - MCP Tool Wrapper

/// Wrapper para exponer herramientas MCP de forma observable
public struct MCPToolInfo: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let description: String
    
    public init(name: String, description: String) {
        self.id = name
        self.name = name
        self.description = description
    }
}

// MARK: - MCP Network Manager

/// Manager principal para la comunicación con servidores MCP
/// Utiliza el SDK oficial: https://github.com/modelcontextprotocol/swift-sdk
@MainActor
public class MCPNetworkManager: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published public private(set) var connectionState: MCPConnectionState = .disconnected
    @Published public private(set) var availableTools: [MCPToolInfo] = []
    @Published public private(set) var serverName: String = ""
    @Published public private(set) var serverVersion: String = ""
    
    // MARK: - Private Properties
    
    private let logger = Logger(subsystem: "com.laia.mcp", category: "Network")
    
    /// Cliente MCP del SDK oficial
    private var client: Client?
    
    /// Transporte HTTP para comunicación SSE
    private var transport: HTTPClientTransport?
    
    /// Capacidades del servidor (almacenadas como flag)
    private var supportsToolsCapability: Bool = false
    private var supportsResourcesCapability: Bool = false
    private var supportsPromptsCapability: Bool = false
    
    /// Nombre y versión del cliente para el handshake
    private let clientName = "LAIAHost"
    private let clientVersion = "1.0.0"
    
    // MARK: - Initialization
    
    public init() {}
    
    // MARK: - Connection Management
    
    /// Establece conexión con el servidor MCP usando SSE
    /// - Parameter serverIP: IP local del servidor (ej: "192.168.1.100")
    /// - Parameter port: Puerto del servidor (default: 8000)
    /// - Note: NO usar "localhost" en dispositivo físico, usar la IP local del Mac/PC
    public func connect(serverIP: String, port: Int = 8000) async {
        guard connectionState != .connecting else {
            logger.warning("⚠️ [MCP] Ya hay una conexión en progreso")
            return
        }
        
        connectionState = .connecting
        logger.info("🔌 [MCP] Conectando a \(serverIP):\(port)...")
        
        // Construir URL del endpoint MCP (sin SSE)
        guard let mcpURL = URL(string: "http://\(serverIP):\(port)/mcp") else {
            connectionState = .error("URL inválida")
            logger.error("❌ [MCP] URL inválida: \(serverIP):\(port)")
            return
        }
        
        do {
            // 1. Inicializar el Cliente MCP
            client = Client(name: clientName, version: clientVersion)
            
            // 2. Configurar el transporte HTTP sin streaming (para servidores sin SSE)
            transport = HTTPClientTransport(
                endpoint: mcpURL,
                streaming: false  // Disable SSE - use standard HTTP request/response
            )
            
            // 3. Conectar y negociar capacidades
            guard let client = client, let transport = transport else {
                throw MCPConnectionError.clientNotInitialized
            }
            
            let initResult = try await client.connect(transport: transport)
            
            // Guardar información del servidor
            serverName = initResult.serverInfo.name
            serverVersion = initResult.serverInfo.version
            
            // Guardar capacidades como flags
            supportsToolsCapability = initResult.capabilities.tools != nil
            supportsResourcesCapability = initResult.capabilities.resources != nil
            supportsPromptsCapability = initResult.capabilities.prompts != nil
            
            logger.info("✅ [MCP] Conectado a '\(self.serverName)' v\(self.serverVersion)")
            
            // Log de capacidades
            if supportsToolsCapability {
                logger.info("   ✓ Servidor soporta herramientas (tools)")
            }
            if supportsResourcesCapability {
                logger.info("   ✓ Servidor soporta recursos (resources)")
            }
            if supportsPromptsCapability {
                logger.info("   ✓ Servidor soporta prompts")
            }
            
            connectionState = .connected
            
            // 4. Descubrir herramientas disponibles
            await discoverTools()
            
        } catch {
            connectionState = .error(error.localizedDescription)
            logger.error("❌ [MCP] Error de conexión: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Tool Discovery
    
    /// Descubre las herramientas disponibles en el servidor
    public func discoverTools() async {
        guard let client = client else {
            logger.warning("⚠️ [MCP] Cliente no inicializado")
            return
        }
        
        do {
            // Listar herramientas registradas en el servidor
            let (tools, _) = try await client.listTools()
            
            // Convertir a nuestro tipo observable
            let toolInfos = tools.map { tool in
                MCPToolInfo(
                    name: tool.name,
                    description: tool.description ?? "Sin descripción"
                )
            }
            
            availableTools = toolInfos
            
            // Log de herramientas detectadas
            for tool in tools {
                logger.info("🔧 [MCP] Herramienta detectada: \(tool.name) - \(tool.description ?? "")")
            }
            
            if tools.isEmpty {
                logger.info("ℹ️ [MCP] El servidor no tiene herramientas registradas")
            }
            
        } catch {
            logger.error("❌ [MCP] Fallo al listar herramientas: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Tool Execution
    
    /// Ejecuta una herramienta en el servidor MCP
    /// - Parameters:
    ///   - name: Nombre de la herramienta
    ///   - arguments: Argumentos para la herramienta (diccionario JSON-compatible)
    /// - Returns: Tupla con el contenido de respuesta y si hubo error
    public func callTool(name: String, arguments: [String: Any] = [:]) async throws -> (content: String, isError: Bool) {
        guard let client = client else {
            throw MCPConnectionError.clientNotInitialized
        }
        
        guard connectionState == .connected else {
            throw MCPConnectionError.notConnected
        }
        
        logger.info("📤 [MCP] Llamando herramienta: \(name)")
        
        // Convertir argumentos a formato esperado por el SDK
        let mcpArguments = convertToMCPArguments(arguments)
        
        let (content, isErrorOptional) = try await client.callTool(
            name: name,
            arguments: mcpArguments
        )
        
        // Unwrap optional Bool (SDK returns Bool?)
        let isError = isErrorOptional ?? false
        
        // Extraer texto del contenido
        var responseText = ""
        for item in content {
            switch item {
            case .text(let text):
                responseText += text
            case .image(_, let mimeType, _):
                responseText += "[Imagen: \(mimeType)]"
            case .audio(_, let mimeType):
                responseText += "[Audio: \(mimeType)]"
            case .resource(let uri, _, let text):
                responseText += text ?? "[Recurso: \(uri)]"
            }
        }
        
        if isError {
            logger.error("❌ [MCP] Error en herramienta '\(name)': \(responseText)")
        } else {
            logger.info("✅ [MCP] Respuesta de '\(name)': \(responseText.prefix(100))...")
        }
        
        return (responseText, isError)
    }
    
    /// Convierte un diccionario Swift a argumentos MCP
    private func convertToMCPArguments(_ dict: [String: Any]) -> [String: Value] {
        var result: [String: Value] = [:]
        for (key, value) in dict {
            if let stringValue = value as? String {
                result[key] = .string(stringValue)
            } else if let intValue = value as? Int {
                result[key] = .int(intValue)
            } else if let doubleValue = value as? Double {
                result[key] = .double(doubleValue)
            } else if let boolValue = value as? Bool {
                result[key] = .bool(boolValue)
            }
            // Para tipos más complejos, se requiere serialización JSON
        }
        return result
    }
    
    // MARK: - Test Methods
    
    /// Prueba la herramienta de clima (test de integración)
    /// Esta función sirve como validación de la Fase 2
    public func testWeatherTool() async {
        do {
            let (content, isError) = try await callTool(
                name: "get_weather_lhospitalet",
                arguments: [:]  // La función no requiere parámetros
            )
            
            if !isError {
                logger.info("✅ [TEST] Respuesta del servidor: \(content)")
                print("🌤️ Respuesta del servidor MCP: \(content)")
            } else {
                logger.error("❌ [TEST] Error en respuesta: \(content)")
            }
            
        } catch {
            logger.error("❌ [TEST] Error en la llamada de prueba: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Disconnection
    
    /// Desconecta del servidor MCP
    public func disconnect() async {
        // El SDK maneja la desconexión limpiamente
        if let client = client {
            await client.disconnect()
        }
        client = nil
        transport = nil
        supportsToolsCapability = false
        supportsResourcesCapability = false
        supportsPromptsCapability = false
        serverName = ""
        serverVersion = ""
        availableTools = []
        connectionState = .disconnected
        
        logger.info("🔌 [MCP] Desconectado")
    }
    
    // MARK: - Helper Methods
    
    /// Verifica si el servidor soporta herramientas
    public var supportsTools: Bool {
        supportsToolsCapability
    }
    
    /// Verifica si el servidor soporta recursos
    public var supportsResources: Bool {
        supportsResourcesCapability
    }
    
    /// Verifica si el servidor soporta prompts
    public var supportsPrompts: Bool {
        supportsPromptsCapability
    }
}

// MARK: - MCP Connection Errors

public enum MCPConnectionError: LocalizedError {
    case clientNotInitialized
    case notConnected
    case toolNotFound(String)
    case invalidArguments
    
    public var errorDescription: String? {
        switch self {
        case .clientNotInitialized:
            return "Cliente MCP no inicializado"
        case .notConnected:
            return "No conectado al servidor MCP"
        case .toolNotFound(let name):
            return "Herramienta no encontrada: \(name)"
        case .invalidArguments:
            return "Argumentos inválidos para la herramienta"
        }
    }
}
