//
//  AgentToolLoop.swift
//  LAIA
//
//  Implementa el "Tool Loop" para agentes con capacidad de usar herramientas.
//  Coordina la interacción entre el LLM (Qwen 2.5) y el cliente MCP.
//
//  Flujo:
//  1. Usuario pregunta → 2. LLM genera → 3. Detectar <tool_call> →
//  4. Ejecutar MCP → 5. Re-inyectar resultado → 6. LLM responde
//
//  Created by LAIA Team on 08/01/26.
//

import Foundation
import Combine
import os

// MARK: - Agent State

/// Estado del agente durante el Tool Loop
public enum AgentLoopState: Sendable, Equatable {
    case idle
    case thinking           // LLM generando respuesta inicial
    case callingTool(String) // Ejecutando herramienta MCP (nombre)
    case processingResult    // Re-procesando con resultado de herramienta
    case responding          // Generando respuesta final
    case error(String)
}

// MARK: - Agent Tool Loop

/// Orquestador del Tool Loop para agentes con herramientas MCP
@MainActor
public class AgentToolLoop: ObservableObject {
    
    // MARK: - Published State
    
    @Published public private(set) var state: AgentLoopState = .idle
    @Published public private(set) var currentToolName: String?
    @Published public private(set) var lastToolResult: String?
    
    // MARK: - Configuration
    
    /// Máximo de llamadas a herramientas por turno (previene loops infinitos)
    public var maxToolCallsPerTurn: Int = 3
    
    // MARK: - Private Properties
    
    private let logger = Logger(subsystem: "com.laia.agent", category: "ToolLoop")
    private let mcpManager: MCPNetworkManager
    private var toolCallCount: Int = 0
    
    // MARK: - Callbacks
    
    /// Callback cuando el agente cambia de estado
    public var onStateChange: ((AgentLoopState) -> Void)?
    
    /// Callback para texto parcial generado (streaming UI)
    public var onPartialText: ((String) -> Void)?
    
    /// Callback cuando se inicia una llamada a herramienta
    public var onToolCallStart: ((String) -> Void)?
    
    /// Callback cuando se completa una llamada a herramienta
    public var onToolCallComplete: ((String, String) -> Void)?
    
    // MARK: - Initialization
    
    public init(mcpManager: MCPNetworkManager) {
        self.mcpManager = mcpManager
    }
    
    // MARK: - System Prompt Building
    
    /// Construye el prompt de sistema con las herramientas MCP disponibles
    public func buildAgentSystemPrompt() -> String {
        // Cargar el template base
        let basePrompt = loadSystemPromptTemplate()
        
        // Generar JSON de herramientas
        let toolsJSON = generateToolsJSON()
        
        // Reemplazar placeholder
        let finalPrompt = basePrompt.replacingOccurrences(
            of: "{{TOOLS_PLACEHOLDER}}",
            with: toolsJSON
        )
        
        logger.info("📋 System prompt construido con \(self.mcpManager.availableTools.count) herramientas")
        
        return finalPrompt
    }
    
    /// Carga el template del system prompt desde el archivo
    private func loadSystemPromptTemplate() -> String {
        guard let url = Bundle.main.url(forResource: "systemPrompt", withExtension: "md"),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            // Fallback si no se encuentra el archivo
            return defaultSystemPrompt
        }
        return content
    }
    
    /// Genera el JSON de herramientas disponibles
    private func generateToolsJSON() -> String {
        let tools = mcpManager.availableTools
        
        if tools.isEmpty {
            return "No hay herramientas disponibles."
        }
        
        let toolDescriptions = tools.map { tool in
            """
            { "name": "\(tool.name)", "description": "\(tool.description)" }
            """
        }
        
        return toolDescriptions.joined(separator: "\n")
    }
    
    /// Prompt por defecto si no se encuentra el archivo
    private var defaultSystemPrompt: String {
        """
        Eres LAIA, un asistente de voz inteligente.
        
        <tools>
        {{TOOLS_PLACEHOLDER}}
        </tools>
        
        Si necesitas información externa, usa: <tool_call>{"name": "...", "arguments": {}}</tool_call>
        
        Responde en español, de forma breve y clara.
        """
    }
    
    // MARK: - Tool Loop Execution
    
    /// Procesa el output del LLM y ejecuta el Tool Loop si es necesario
    /// - Parameters:
    ///   - llmOutput: El texto generado por el LLM
    ///   - regenerateCallback: Función para regenerar con contexto adicional
    /// - Returns: Respuesta final (puede ser la original o post-herramienta)
    public func processLLMOutput(
        _ llmOutput: String,
        regenerateCallback: @escaping (String) async throws -> String
    ) async throws -> String {
        
        toolCallCount = 0
        return try await processOutputRecursively(
            llmOutput,
            regenerateCallback: regenerateCallback
        )
    }
    
    /// Procesa recursivamente el output buscando tool_calls
    private func processOutputRecursively(
        _ output: String,
        regenerateCallback: @escaping (String) async throws -> String
    ) async throws -> String {
        
        // Verificar límite de llamadas
        guard toolCallCount < maxToolCallsPerTurn else {
            logger.warning("⚠️ Límite de tool calls alcanzado (\(self.maxToolCallsPerTurn))")
            return output
        }
        
        // Parsear el output
        let parseResult = ToolCallParser.parse(output)
        
        switch parseResult {
        case .textOnly(let text):
            // No hay tool_call, retornar texto directo
            state = .responding
            onStateChange?(.responding)
            return text
            
        case .toolCall(let textBefore, let toolCall, _):
            // Hay una tool_call, ejecutarla
            toolCallCount += 1
            
            logger.info("🔧 Tool call detectada: \(toolCall.name)")
            
            // Notificar UI
            state = .callingTool(toolCall.name)
            currentToolName = toolCall.name
            onStateChange?(state)
            onToolCallStart?(toolCall.name)
            
            // Si hay texto antes, mostrarlo
            if !textBefore.isEmpty {
                onPartialText?(textBefore)
            }
            
            // Ejecutar herramienta via MCP
            let toolResult = await executeToolCall(toolCall)
            lastToolResult = toolResult.content
            
            // Notificar completado
            onToolCallComplete?(toolCall.name, toolResult.content)
            
            // Construir contexto con resultado
            let toolResponseMessage = ToolCallParser.formatToolResponse(
                toolName: toolCall.name,
                response: toolResult.content,
                isError: toolResult.isError
            )
            
            // Re-generar con el resultado de la herramienta
            state = .processingResult
            onStateChange?(.processingResult)
            
            logger.info("🔄 Re-generando con resultado de herramienta...")
            
            let newOutput = try await regenerateCallback(toolResponseMessage)
            
            // Procesar recursivamente por si hay más tool_calls
            return try await processOutputRecursively(
                newOutput,
                regenerateCallback: regenerateCallback
            )
            
        case .parseError(let error, let originalText):
            logger.error("❌ Error parseando tool_call: \(error)")
            state = .error(error)
            onStateChange?(.error(error))
            return originalText
        }
    }
    
    // MARK: - Tool Execution
    
    /// Ejecuta una llamada a herramienta via MCP
    private func executeToolCall(_ toolCall: ToolCall) async -> (content: String, isError: Bool) {
        logger.info("📤 Ejecutando MCP: \(toolCall.name)")
        
        do {
            let result = try await mcpManager.callTool(
                name: toolCall.name,
                arguments: toolCall.arguments
            )
            
            logger.info("✅ Resultado MCP: \(result.content.prefix(100))...")
            return result
            
        } catch {
            logger.error("❌ Error MCP: \(error.localizedDescription)")
            return (content: "Error: \(error.localizedDescription)", isError: true)
        }
    }
    
    // MARK: - Streaming Support
    
    /// Procesa tokens en streaming buscando inicio de tool_call
    /// Retorna true si se detectó inicio de tool_call (para pausar TTS)
    public func shouldPauseTTS(for accumulatedText: String) -> Bool {
        if ToolCallParser.containsToolCallStart(accumulatedText) {
            // Si la llamada no está completa, esperar
            if !ToolCallParser.isToolCallComplete(accumulatedText) {
                state = .thinking
                return true
            }
        }
        return false
    }
    
    // MARK: - Reset
    
    /// Resetea el estado del Tool Loop
    public func reset() {
        state = .idle
        currentToolName = nil
        lastToolResult = nil
        toolCallCount = 0
    }
}

// MARK: - Integration Helper

extension AgentToolLoop {
    
    /// Helper para verificar si MCP está conectado y listo
    public var isMCPReady: Bool {
        mcpManager.connectionState == .connected && !mcpManager.availableTools.isEmpty
    }
    
    /// Descripción del estado actual para debugging
    public var stateDescription: String {
        switch state {
        case .idle: return "Esperando"
        case .thinking: return "Pensando..."
        case .callingTool(let name): return "Consultando \(name)..."
        case .processingResult: return "Procesando datos..."
        case .responding: return "Respondiendo..."
        case .error(let msg): return "Error: \(msg)"
        }
    }
}
