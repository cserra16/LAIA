//
//  ToolCallParser.swift
//  LAIA
//
//  Parser para detectar y extraer llamadas a herramientas del output del LLM.
//  Soporta el formato <tool_call>{"name": "...", "arguments": {...}}</tool_call>
//
//  Created by LAIA Team on 08/01/26.
//

import Foundation

// MARK: - Tool Call Model

/// Representa una llamada a herramienta parseada del output del LLM
public struct ToolCall: Sendable, Equatable {
    public let name: String
    public let arguments: [String: Any]
    public let rawJSON: String
    
    public init(name: String, arguments: [String: Any] = [:], rawJSON: String = "") {
        self.name = name
        self.arguments = arguments
        self.rawJSON = rawJSON
    }
    
    public static func == (lhs: ToolCall, rhs: ToolCall) -> Bool {
        lhs.name == rhs.name && lhs.rawJSON == rhs.rawJSON
    }
}

// MARK: - Parse Result

/// Resultado del parsing del output del LLM
public enum LLMOutputParseResult: Sendable {
    /// El output contiene solo texto, sin llamadas a herramientas
    case textOnly(String)
    
    /// El output contiene una llamada a herramienta
    /// - textBefore: Texto antes de la llamada (puede estar vacío)
    /// - toolCall: La llamada parseada
    /// - textAfter: Texto después de la llamada (normalmente vacío)
    case toolCall(textBefore: String, toolCall: ToolCall, textAfter: String)
    
    /// Se detectó una llamada pero hubo error en el parsing
    case parseError(String, originalText: String)
}

// MARK: - Tool Call Parser

/// Parser para extraer llamadas a herramientas del output del LLM
public struct ToolCallParser {
    
    // MARK: - Regex Patterns
    
    /// Pattern para detectar <tool_call>...</tool_call>
    private static let toolCallPattern = #"<tool_call>(.*?)</tool_call>"#
    
    /// Pattern para detectar inicio de tool_call (streaming)
    private static let toolCallStartPattern = #"<tool_call>"#
    
    // MARK: - Main Parsing
    
    /// Parsea el output completo del LLM buscando llamadas a herramientas
    /// - Parameter output: El texto generado por el LLM
    /// - Returns: Resultado del parsing
    public static func parse(_ output: String) -> LLMOutputParseResult {
        guard let regex = try? NSRegularExpression(
            pattern: toolCallPattern,
            options: .dotMatchesLineSeparators
        ) else {
            return .textOnly(output)
        }
        
        let range = NSRange(output.startIndex..., in: output)
        
        guard let match = regex.firstMatch(in: output, range: range),
              let jsonRange = Range(match.range(at: 1), in: output) else {
            return .textOnly(output)
        }
        
        let jsonString = String(output[jsonRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Extraer texto antes y después de la llamada
        let fullMatchRange = Range(match.range, in: output)!
        let textBefore = String(output[..<fullMatchRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let textAfter = String(output[fullMatchRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Parsear el JSON
        guard let toolCall = parseToolCallJSON(jsonString) else {
            return .parseError("JSON inválido: \(jsonString)", originalText: output)
        }
        
        return .toolCall(textBefore: textBefore, toolCall: toolCall, textAfter: textAfter)
    }
    
    /// Parsea el contenido JSON de una tool_call
    private static func parseToolCallJSON(_ jsonString: String) -> ToolCall? {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = json["name"] as? String else {
            return nil
        }
        
        let arguments = json["arguments"] as? [String: Any] ?? [:]
        
        return ToolCall(name: name, arguments: arguments, rawJSON: jsonString)
    }
    
    // MARK: - Streaming Detection
    
    /// Detecta si el texto contiene el inicio de una tool_call (para streaming)
    /// Útil para pausar el TTS mientras se genera la llamada
    public static func containsToolCallStart(_ text: String) -> Bool {
        text.contains("<tool_call>")
    }
    
    /// Detecta si una llamada a herramienta está completa
    public static func isToolCallComplete(_ text: String) -> Bool {
        text.contains("<tool_call>") && text.contains("</tool_call>")
    }
    
    /// Extrae el texto parcial antes de una tool_call incompleta
    /// Útil para mostrar al usuario mientras se espera la llamada completa
    public static func extractTextBeforeToolCall(_ text: String) -> String? {
        guard let startRange = text.range(of: "<tool_call>") else {
            return nil
        }
        
        let textBefore = String(text[..<startRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        return textBefore.isEmpty ? nil : textBefore
    }
    
    // MARK: - Tool Response Formatting
    
    /// Formatea la respuesta de una herramienta para inyectarla en el contexto
    /// - Parameters:
    ///   - toolName: Nombre de la herramienta ejecutada
    ///   - response: Contenido de la respuesta
    ///   - isError: Si la respuesta es un error
    /// - Returns: Texto formateado para añadir al historial
    public static func formatToolResponse(
        toolName: String,
        response: String,
        isError: Bool = false
    ) -> String {
        if isError {
            return "<tool_response>\n[Error en \(toolName)]: \(response)\n</tool_response>"
        }
        return "<tool_response>\n[\(toolName)]: \(response)\n</tool_response>"
    }
}

// MARK: - String Extension for Tool Detection

extension String {
    /// Verifica si la cadena contiene una llamada a herramienta
    public var containsToolCall: Bool {
        ToolCallParser.containsToolCallStart(self)
    }
    
    /// Verifica si la llamada a herramienta está completa
    public var hasCompleteToolCall: Bool {
        ToolCallParser.isToolCallComplete(self)
    }
}
