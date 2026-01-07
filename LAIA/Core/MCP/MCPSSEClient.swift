//
//  MCPSSEClient.swift
//  LAIA
//
//  Cliente MCP manual para servidores con SSE transport (protocolo antiguo).
//  Compatible con servidores Python que usan:
//    - GET /sse → Handshake SSE (obtiene session_id)
//    - POST /messages/?session_id=... → Envío de mensajes JSON-RPC
//
//  Created by LAIA Team on 08/01/26.
//

import Foundation
import Combine
import os

// MARK: - MCP SSE Client

/// Cliente MCP manual para el protocolo SSE antiguo
@MainActor
public class MCPSSEClient: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published public private(set) var connectionState: MCPConnectionState = .disconnected
    @Published public private(set) var availableTools: [MCPToolInfo] = []
    @Published public private(set) var serverName: String = ""
    @Published public private(set) var serverVersion: String = ""
    
    // MARK: - Private Properties
    
    private let logger = Logger(subsystem: "com.laia.mcp", category: "SSEClient")
    
    /// Session ID obtenido del handshake SSE
    private var sessionId: String?
    
    /// URL base del servidor
    private var baseURL: URL?
    
    /// URL para enviar mensajes (POST)
    private var messagesURL: URL?
    
    /// Tarea de SSE activa
    private var sseTask: Task<Void, Never>?
    
    /// ID para mensajes JSON-RPC
    private var messageId: Int = 0
    
    /// Continuations pendientes para respuestas
    private var pendingRequests: [Int: CheckedContinuation<JSONRPCResponse, Error>] = [:]
    
    // MARK: - Initialization
    
    public init() {}
    
    // MARK: - Connection
    
    /// Conecta al servidor MCP usando el protocolo SSE
    public func connect(serverIP: String, port: Int = 8000) async {
        guard connectionState != .connecting else { return }
        
        connectionState = .connecting
        logger.info("🔌 [SSE] Conectando a \(serverIP):\(port)...")
        
        guard let sseURL = URL(string: "http://\(serverIP):\(port)/sse"),
              let base = URL(string: "http://\(serverIP):\(port)") else {
            connectionState = .error("URL inválida")
            return
        }
        
        baseURL = base
        
        do {
            // 1. Establecer conexión SSE y obtener session_id
            try await establishSSEConnection(sseURL: sseURL)
            
            guard let sid = sessionId else {
                throw MCPSSEError.noSessionId
            }
            
            // 2. Construir URL de mensajes con session_id
            messagesURL = URL(string: "http://\(serverIP):\(port)/messages/?session_id=\(sid)")
            
            logger.info("✅ [SSE] Session ID obtenido: \(sid.prefix(20))...")
            
            // 3. Enviar initialize
            let initResult = try await sendInitialize()
            
            serverName = initResult.serverInfo?.name ?? "MCP Server"
            serverVersion = initResult.serverInfo?.version ?? "1.0"
            
            logger.info("✅ [SSE] Conectado a '\(self.serverName)' v\(self.serverVersion)")
            
            // 4. Enviar initialized notification
            try await sendInitialized()
            
            // 5. Descubrir herramientas
            await discoverTools()
            
            connectionState = .connected
            
        } catch {
            connectionState = .error(error.localizedDescription)
            logger.error("❌ [SSE] Error: \(error.localizedDescription)")
        }
    }
    
    // MARK: - SSE Handshake
    
    /// Establece la conexión SSE y extrae el session_id
    private func establishSSEConnection(sseURL: URL) async throws {
        var request = URLRequest(url: sseURL)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30
        
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw MCPSSEError.connectionFailed
        }
        
        // Leer eventos SSE hasta obtener el endpoint con session_id
        for try await line in bytes.lines {
            logger.debug("[SSE] Línea: \(line)")
            
            // Buscar el evento "endpoint" que contiene el session_id
            if line.hasPrefix("data:") {
                let data = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                
                // El data contiene la URL del endpoint con session_id
                // Formato esperado: /messages/?session_id=xxx
                if data.contains("session_id=") {
                    if let range = data.range(of: "session_id=") {
                        let sidStart = data[range.upperBound...]
                        // Tomar hasta el final o hasta &
                        if let endRange = sidStart.range(of: "&") {
                            sessionId = String(sidStart[..<endRange.lowerBound])
                        } else {
                            sessionId = String(sidStart)
                        }
                        
                        // Tenemos el session_id, salir del loop
                        break
                    }
                }
            }
        }
        
        if sessionId == nil {
            throw MCPSSEError.noSessionId
        }
    }
    
    // MARK: - JSON-RPC Messages
    
    /// Envía el mensaje initialize
    private func sendInitialize() async throws -> InitializeResult {
        let params: [String: Any] = [
            "protocolVersion": "2024-11-05",
            "capabilities": [:],
            "clientInfo": [
                "name": "LAIA",
                "version": "1.0.0"
            ]
        ]
        
        let response = try await sendRequest(method: "initialize", params: params)
        
        // Parsear resultado
        guard let result = response.result as? [String: Any] else {
            throw MCPSSEError.invalidResponse
        }
        
        var initResult = InitializeResult()
        
        if let serverInfo = result["serverInfo"] as? [String: Any] {
            initResult.serverInfo = ServerInfo(
                name: serverInfo["name"] as? String ?? "Unknown",
                version: serverInfo["version"] as? String ?? "1.0"
            )
        }
        
        if let capabilities = result["capabilities"] as? [String: Any] {
            initResult.hasTools = capabilities["tools"] != nil
        }
        
        return initResult
    }
    
    /// Envía la notificación initialized
    private func sendInitialized() async throws {
        try await sendNotification(method: "notifications/initialized", params: [:])
    }
    
    // MARK: - Tool Discovery
    
    /// Descubre las herramientas disponibles
    public func discoverTools() async {
        do {
            let response = try await sendRequest(method: "tools/list", params: [:])
            
            guard let result = response.result as? [String: Any],
                  let tools = result["tools"] as? [[String: Any]] else {
                return
            }
            
            availableTools = tools.compactMap { tool in
                guard let name = tool["name"] as? String else { return nil }
                let description = tool["description"] as? String ?? ""
                return MCPToolInfo(name: name, description: description)
            }
            
            for tool in availableTools {
                logger.info("🔧 [SSE] Herramienta: \(tool.name) - \(tool.description)")
            }
            
        } catch {
            logger.error("❌ [SSE] Error listando herramientas: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Tool Execution
    
    /// Ejecuta una herramienta
    public func callTool(name: String, arguments: [String: Any] = [:]) async throws -> (content: String, isError: Bool) {
        guard connectionState == .connected else {
            throw MCPSSEError.notConnected
        }
        
        logger.info("📤 [SSE] Llamando herramienta: \(name)")
        
        let params: [String: Any] = [
            "name": name,
            "arguments": arguments
        ]
        
        let response = try await sendRequest(method: "tools/call", params: params)
        
        guard let result = response.result as? [String: Any] else {
            throw MCPSSEError.invalidResponse
        }
        
        let isError = result["isError"] as? Bool ?? false
        var contentText = ""
        
        if let content = result["content"] as? [[String: Any]] {
            for item in content {
                if let text = item["text"] as? String {
                    contentText += text
                }
            }
        }
        
        if isError {
            logger.error("❌ [SSE] Error en '\(name)': \(contentText)")
        } else {
            logger.info("✅ [SSE] Respuesta de '\(name)': \(contentText.prefix(100))...")
        }
        
        return (contentText, isError)
    }
    
    // MARK: - Low-Level Request/Response
    
    /// Envía una solicitud JSON-RPC y espera respuesta
    private func sendRequest(method: String, params: [String: Any]) async throws -> JSONRPCResponse {
        guard let url = messagesURL else {
            throw MCPSSEError.notConnected
        }
        
        messageId += 1
        let id = messageId
        
        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30
        
        logger.debug("📤 [SSE] POST \(method) id=\(id)")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MCPSSEError.invalidResponse
        }
        
        logger.debug("📥 [SSE] Response status: \(httpResponse.statusCode)")
        
        guard httpResponse.statusCode == 200 || httpResponse.statusCode == 202 else {
            throw MCPSSEError.httpError(httpResponse.statusCode)
        }
        
        // Parsear respuesta JSON-RPC
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MCPSSEError.invalidResponse
        }
        
        return JSONRPCResponse(
            id: json["id"] as? Int ?? id,
            result: json["result"],
            error: json["error"] as? [String: Any]
        )
    }
    
    /// Envía una notificación (sin esperar respuesta)
    private func sendNotification(method: String, params: [String: Any]) async throws {
        guard let url = messagesURL else {
            throw MCPSSEError.notConnected
        }
        
        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method,
            "params": params
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw MCPSSEError.invalidResponse
        }
    }
    
    // MARK: - Disconnect
    
    /// Desconecta del servidor
    public func disconnect() {
        sseTask?.cancel()
        sseTask = nil
        sessionId = nil
        messagesURL = nil
        availableTools = []
        serverName = ""
        serverVersion = ""
        connectionState = .disconnected
        pendingRequests.removeAll()
        
        logger.info("🔌 [SSE] Desconectado")
    }
    
    // MARK: - Test Method
    
    /// Prueba la herramienta de clima
    public func testWeatherTool() async {
        do {
            let (content, isError) = try await callTool(name: "get_weather_lhospitalet")
            if !isError {
                logger.info("✅ [TEST] Clima: \(content)")
                print("🌤️ Clima: \(content)")
            }
        } catch {
            logger.error("❌ [TEST] Error: \(error.localizedDescription)")
        }
    }
}

// MARK: - Supporting Types

struct InitializeResult {
    var serverInfo: ServerInfo?
    var hasTools: Bool = false
}

struct ServerInfo {
    var name: String
    var version: String
}

struct JSONRPCResponse {
    var id: Int
    var result: Any?
    var error: [String: Any]?
}

// MARK: - Errors

enum MCPSSEError: LocalizedError {
    case connectionFailed
    case noSessionId
    case notConnected
    case invalidResponse
    case httpError(Int)
    case timeout
    
    var errorDescription: String? {
        switch self {
        case .connectionFailed: return "Error de conexión SSE"
        case .noSessionId: return "No se obtuvo session_id"
        case .notConnected: return "No conectado al servidor"
        case .invalidResponse: return "Respuesta inválida del servidor"
        case .httpError(let code): return "Error HTTP: \(code)"
        case .timeout: return "Timeout de conexión"
        }
    }
}
