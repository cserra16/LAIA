//
//  MCPSSEClient.swift
//  LAIA
//
//  Cliente MCP para servidores con SSE transport (protocolo FastMCP).
//  - GET /sse → Stream SSE persistente (recibe respuestas)
//  - POST /messages/?session_id=... → Envío de mensajes JSON-RPC
//  - Las respuestas llegan por el stream SSE, no por HTTP response
//
//  Created by LAIA Team on 08/01/26.
//

import Foundation
import Combine
import os

// MARK: - MCP SSE Client

/// Cliente MCP para el protocolo SSE (FastMCP compatible)
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
    
    /// URL para enviar mensajes (POST)
    private var messagesURL: URL?
    
    /// ID para mensajes JSON-RPC
    private var messageId: Int = 0
    
    /// Continuations pendientes para respuestas (correlación por ID)
    private var pendingRequests: [Int: CheckedContinuation<[String: Any], Error>] = [:]
    
    /// Tarea del stream SSE
    private var sseStreamTask: Task<Void, Never>?
    
    /// AsyncBytes para el stream
    private var streamBytes: URLSession.AsyncBytes?
    
    // MARK: - Initialization
    
    public init() {}
    
    // MARK: - Connection
    
    /// Conecta al servidor MCP usando el protocolo SSE
    public func connect(serverIP: String, port: Int = 8000) async {
        guard connectionState != .connecting else { return }
        
        connectionState = .connecting
        logger.info("🔌 [SSE] Conectando a \(serverIP):\(port)...")
        
        guard let sseURL = URL(string: "http://\(serverIP):\(port)/sse") else {
            connectionState = .error("URL inválida")
            return
        }
        
        do {
            // 1. Establecer stream SSE y obtener session_id
            let (bytes, sid) = try await establishSSEAndGetSessionId(sseURL: sseURL)
            
            sessionId = sid
            messagesURL = URL(string: "http://\(serverIP):\(port)/messages/?session_id=\(sid)")
            
            logger.info("✅ [SSE] Session ID: \(sid.prefix(20))...")
            
            // 2. Iniciar background task para escuchar respuestas
            startBackgroundListener(bytes: bytes)
            
            // 3. Pequeña pausa para que el listener esté listo
            try await Task.sleep(for: .milliseconds(200))
            
            // 4. Enviar initialize
            let initResult = try await sendInitialize()
            
            serverName = initResult.serverInfo?.name ?? "MCP Server"
            serverVersion = initResult.serverInfo?.version ?? "1.0"
            
            logger.info("✅ [SSE] Conectado a '\(self.serverName)' v\(self.serverVersion)")
            
            // 5. Enviar initialized notification
            try await sendInitialized()
            
            // 6. Descubrir herramientas
            await discoverTools()
            
            connectionState = .connected
            
        } catch {
            connectionState = .error(error.localizedDescription)
            logger.error("❌ [SSE] Error: \(error.localizedDescription)")
        }
    }
    
    // MARK: - SSE Connection Setup
    
    /// Establece conexión SSE y obtiene session_id del primer evento
    private func establishSSEAndGetSessionId(sseURL: URL) async throws -> (URLSession.AsyncBytes, String) {
        var request = URLRequest(url: sseURL)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 300
        
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw MCPSSEError.connectionFailed
        }
        
        logger.info("📡 [SSE] Stream conectado, esperando endpoint...")
        
        // Leer líneas hasta encontrar el session_id
        var foundSessionId: String?
        
        for try await line in bytes.lines {
            logger.debug("[SSE] Línea: \(line)")
            
            // Ignorar líneas de comentario/ping
            if line.hasPrefix(":") {
                continue
            }
            
            // Buscar data: con session_id
            if line.hasPrefix("data:") {
                let data = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                
                if data.contains("session_id=") {
                    if let range = data.range(of: "session_id=") {
                        let sidStart = data[range.upperBound...]
                        if let endRange = sidStart.range(of: "&") {
                            foundSessionId = String(sidStart[..<endRange.lowerBound])
                        } else {
                            foundSessionId = String(sidStart)
                        }
                        
                        logger.info("✅ [SSE] Endpoint encontrado!")
                        break
                    }
                }
            }
        }
        
        guard let sid = foundSessionId else {
            throw MCPSSEError.noSessionId
        }
        
        return (bytes, sid)
    }
    
    /// Inicia listener en background para respuestas
    private func startBackgroundListener(bytes: URLSession.AsyncBytes) {
        sseStreamTask = Task { [weak self] in
            do {
                for try await line in bytes.lines {
                    guard let self = self, !Task.isCancelled else { break }
                    await self.processSSELine(line)
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.logger.warning("⚠️ [SSE] Stream cerrado: \(error.localizedDescription)")
                }
            }
        }
    }
    
    /// Procesa cada línea del stream SSE
    private func processSSELine(_ line: String) async {
        // Ignorar comentarios/pings
        if line.hasPrefix(":") {
            return
        }
        
        // Procesar data: con JSON-RPC response
        if line.hasPrefix("data:") {
            let data = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            
            // Intentar parsear como JSON-RPC response
            if let jsonData = data.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                
                // Verificar si es una respuesta con ID
                if let id = json["id"] as? Int {
                    logger.debug("📥 [SSE] Response id=\(id)")
                    
                    // Buscar continuation pendiente
                    if let continuation = pendingRequests.removeValue(forKey: id) {
                        if let error = json["error"] as? [String: Any] {
                            let message = error["message"] as? String ?? "Unknown error"
                            continuation.resume(throwing: MCPSSEError.serverError(message))
                        } else if let result = json["result"] as? [String: Any] {
                            continuation.resume(returning: result)
                        } else {
                            // Respuesta vacía pero válida
                            continuation.resume(returning: [:])
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - JSON-RPC Messages
    
    /// Envía el mensaje initialize
    private func sendInitialize() async throws -> SSEInitializeResult {
        let params: [String: Any] = [
            "protocolVersion": "2024-11-05",
            "capabilities": [:],
            "clientInfo": [
                "name": "LAIA",
                "version": "1.0.0"
            ]
        ]
        
        let result = try await sendRequest(method: "initialize", params: params)
        
        var initResult = SSEInitializeResult()
        
        if let serverInfo = result["serverInfo"] as? [String: Any] {
            initResult.serverInfo = SSEServerInfo(
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
            let result = try await sendRequest(method: "tools/list", params: [:])
            
            guard let tools = result["tools"] as? [[String: Any]] else {
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
        
        let result = try await sendRequest(method: "tools/call", params: params)
        
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
    
    /// Envía una solicitud JSON-RPC y espera respuesta del stream SSE
    private func sendRequest(method: String, params: [String: Any]) async throws -> [String: Any] {
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
        
        logger.debug("📤 [SSE] POST \(method) id=\(id)")
        
        // Registrar continuation ANTES de enviar
        return try await withCheckedThrowingContinuation { continuation in
            // Registrar primero
            pendingRequests[id] = continuation
            
            // Luego enviar
            Task {
                do {
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)
                    request.timeoutInterval = 30
                    
                    let (_, response) = try await URLSession.shared.data(for: request)
                    
                    guard let httpResponse = response as? HTTPURLResponse,
                          (200...299).contains(httpResponse.statusCode) else {
                        await MainActor.run { [weak self] in
                            if let cont = self?.pendingRequests.removeValue(forKey: id) {
                                cont.resume(throwing: MCPSSEError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0))
                            }
                        }
                        return
                    }
                    
                    await MainActor.run { [weak self] in
                        self?.logger.debug("📬 [SSE] Enviado id=\(id), esperando stream...")
                    }
                    
                } catch {
                    await MainActor.run { [weak self] in
                        if let cont = self?.pendingRequests.removeValue(forKey: id) {
                            cont.resume(throwing: error)
                        }
                    }
                }
            }
            
            // Timeout de 30 segundos
            Task {
                try? await Task.sleep(for: .seconds(30))
                await MainActor.run { [weak self] in
                    if let cont = self?.pendingRequests.removeValue(forKey: id) {
                        self?.logger.warning("⏰ [SSE] Timeout para id=\(id)")
                        cont.resume(throwing: MCPSSEError.timeout)
                    }
                }
            }
        }
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
        
        logger.debug("📤 [SSE] Notificación enviada: \(method)")
    }
    
    // MARK: - Disconnect
    
    /// Desconecta del servidor
    public func disconnect() {
        sseStreamTask?.cancel()
        sseStreamTask = nil
        sessionId = nil
        messagesURL = nil
        availableTools = []
        serverName = ""
        serverVersion = ""
        connectionState = .disconnected
        
        // Cancelar requests pendientes
        for (_, continuation) in pendingRequests {
            continuation.resume(throwing: MCPSSEError.notConnected)
        }
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

private struct SSEInitializeResult {
    var serverInfo: SSEServerInfo?
    var hasTools: Bool = false
}

private struct SSEServerInfo {
    var name: String
    var version: String
}

// MARK: - Errors

enum MCPSSEError: LocalizedError {
    case connectionFailed
    case noSessionId
    case notConnected
    case invalidResponse
    case httpError(Int)
    case timeout
    case serverError(String)
    
    var errorDescription: String? {
        switch self {
        case .connectionFailed: return "Error de conexión SSE"
        case .noSessionId: return "No se obtuvo session_id"
        case .notConnected: return "No conectado al servidor"
        case .invalidResponse: return "Respuesta inválida del servidor"
        case .httpError(let code): return "Error HTTP: \(code)"
        case .timeout: return "Timeout esperando respuesta"
        case .serverError(let msg): return "Error del servidor: \(msg)"
        }
    }
}
