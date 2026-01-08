# LAIA (Local AI Assistant) v0.75

LAIA es un asistente de inteligencia artificial local diseñado para dispositivos Apple Silicon, priorizando la privacidad, la baja latencia y una experiencia de usuario fluida y etérea.

El proyecto integra un pipeline completo de voz (Speech-to-Text, LLM, Text-to-Speech) funcionando completamente en el dispositivo (on-device), aprovechando la potencia de los chips Apple Silicon mediante el framework MLX.

## 🌟 Características Principales

### 🧠 Inteligencia Artificial Local
*   **LLM (Qwen 2.5)**: Utiliza `MLX Swift` para ejecutar modelos de lenguaje grandes de forma eficiente en el dispositivo.
*   **Privacidad Total**: Todo el procesamiento (voz y texto) ocurre localmente; ningún dato de audio o conversación se envía a la nube.

### 🔧 Model Context Protocol (MCP) - NUEVO
*   **Herramientas Externas**: LAIA puede conectarse a servidores MCP para ejecutar herramientas externas.
*   **Agent Tool Loop**: El LLM detecta automáticamente cuándo usar una herramienta, la ejecuta y responde con los datos reales.
*   **SSE Protocol**: Compatible con servidores Python (FastMCP) usando Server-Sent Events.

### 🗣️ Interacción de Voz Natural
*   **Speech-to-Text (STT)**: Implementación dual con soporte para `SFSpeechRecognizer` (nativo) y `Whisper` (vía WhisperKit) para transcripción precisa en tiempo real.
*   **Text-to-Speech (TTS)**: Síntesis de voz ultra-rápida utilizando voces neuronales "Enhanced" de Apple, optimizadas para español.
*   **Detectores de Voz (VAD)**: Sistema inteligente de detección de actividad de voz para conversaciones fluidas sin necesidad de tocar botones constantemente.

### 🎨 Experiencia de Usuario "Etérea"
*   **Interfaz Fluida**: Diseño minimalista con fondo "True Black" para pantallas OLED.
*   **Orbe Neural**: Visualización reactiva basada en partículas (Metal) que responde a la amplitud del audio y al estado del asistente (escuchando, pensando, hablando).
*   **Gestos Intuitivos**:
    *   **Toque**: Activar/Interrumpir.
    *   **Mantener pulsado**: Modo "Walkie-Talkie" para comandos rápidos.
*   **Feedback Háptico**: Respuestas táctiles sutiles para confirmar interacciones.

## 🛠 Stack Tecnológico

*   **Lenguaje**: Swift 5+
*   **UI Framework**: SwiftUI
*   **AI/ML Frameworks**:
    *   [MLX Swift](https://github.com/ml-explore/mlx-swift): Inferencia de modelos ML en Apple Silicon.
    *   `Speech`: Reconocimiento de voz nativo.
    *   `AVFoundation`: Gestión de audio y síntesis de voz.
*   **Protocolos**:
    *   [MCP Swift SDK](https://github.com/modelcontextprotocol/swift-sdk): Model Context Protocol para herramientas externas.
*   **Arquitectura**: MVVM (Model-View-ViewModel).

## 📂 Estructura del Proyecto

El código fuente se encuentra principalmente en el directorio `LAIA/`.

*   **Core/**: Lógica fundamental del sistema (Audio, Memoria, Estado, Observabilidad).
    *   **MCP/**: Integración con Model Context Protocol.
        *   `MCPSSEClient.swift`: Cliente SSE para servidores FastMCP (Python).
        *   `AgentToolLoop.swift`: Orquestación del ciclo LLM → Tool → Response.
        *   `ToolCallParser.swift`: Parser de llamadas a herramientas del LLM.
        *   `MCPPreferences.swift`: Configuración del servidor MCP.
*   **Providers/**: Implementaciones de los servicios de IA.
    *   `LLM/`: Integración con MLX y modelos Qwen.
    *   `STT/`: Proveedores de transcripción (Whisper/Nativo).
    *   `TTS/`: Proveedores de síntesis de voz.
*   **Views/**: Componentes de la interfaz de usuario.
    *   `ActiveSessionView.swift`: Vista principal de la sesión de voz.
    *   `Components/`: Elementos reutilizables (Orbe, Textos animados).

## 🔧 Configuración MCP

### Servidor Python (FastMCP)

LAIA se conecta a servidores MCP usando el protocolo SSE. Ejemplo de servidor:

```python
from mcp.server.fastmcp import FastMCP

mcp = FastMCP("WeatherService")

@mcp.tool()
def get_weather_lhospitalet() -> str:
    """Obtiene el clima de L'Hospitalet de Llobregat."""
    # ... implementación ...
    return f"Temperatura: {temp}°C, Humedad: {humidity}%"

mcp.run(transport="sse", host="0.0.0.0", port=8000)
```

### Configuración en LAIA

Por defecto, LAIA se conecta a:
- **IP**: `192.168.1.13`
- **Puerto**: `8000`
- **MCP Habilitado**: `true`

Para cambiar la configuración, editar `MCPPreferences.swift`:

```swift
MCPPreferences.shared.serverIP = "tu.ip.local"
MCPPreferences.shared.serverPort = 8000
MCPPreferences.shared.isEnabled = true
```

### Flujo de Ejecución

```
Usuario: "¿Qué tiempo hace?"
    ↓
LLM genera: {"name": "get_weather_lhospitalet", "arguments": {}}
    ↓
Parser detecta: Tool call encontrada
    ↓
MCP ejecuta: POST /messages/?session_id=xxx
    ↓
Servidor responde: "11.7°C, Humedad: 61%, Parcialmente nublado"
    ↓
LLM regenera: "En L'Hospitalet hace once coma siete grados..."
    ↓
TTS habla: Respuesta con datos reales
```

## 🚀 Requisitos

*   **Hardware**: Mac con Apple Silicon (M1/M2/M3) o dispositivo iOS compatible (iPhone con A16/A17+ recomendado para modelos locales pesados).
*   **OS**: macOS 14.0+ / iOS 17.0+
*   **Xcode**: 15.0+

## 📝 Notas de Versión (0.75)

### Nuevas Características
*   **🔧 Integración MCP**: Soporte completo para Model Context Protocol con herramientas externas.
*   **🤖 Agent Tool Loop**: El LLM detecta y ejecuta herramientas automáticamente.
*   **🌐 Cliente SSE**: Compatible con servidores FastMCP (Python).
*   **📋 Prompt Dinámico**: Inyección automática de herramientas disponibles en el system prompt.

### Mejoras Técnicas
*   Integración inicial de MLX Swift.
*   Optimización del pipeline de TTS para reducir latencia.
*   Mejoras en la visualización del Orbe Neural.
*   Soporte preliminar para selección de modelos.
*   Parser de tool calls con soporte para JSON directo (sin tags).

---
Desarrollado con ❤️ para la comunidad de IA Local.
