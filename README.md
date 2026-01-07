# LAIA (Local AI Assistant) v0.75

LAIA es un asistente de inteligencia artificial local diseñado para dispositivos Apple Silicon, priorizando la privacidad, la baja latencia y una experiencia de usuario fluida y etérea.

El proyecto integra un pipeline completo de voz (Speech-to-Text, LLM, Text-to-Speech) funcionando completamente en el dispositivo (on-device), aprovechando la potencia de los chips Apple Silicon mediante el framework MLX.

## 🌟 Características Principales

### 🧠 Inteligencia Artificial Local
*   **LLM (Qwen 2.5)**: Utiliza `MLX Swift` para ejecutar modelos de lenguaje grandes de forma eficiente en el dispositivo.
*   **Privacidad Total**: Todo el procesamiento (voz y texto) ocurre localmente; ningún dato de audio o conversación se envía a la nube.

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
*   **Arquitectura**: MVVM (Model-View-ViewModel).

## 📂 Estructura del Proyecto

El código fuente se encuentra principalmente en el directorio `LAIA/`.

*   **Core/**: Lógica fundamental del sistema (Audio, Memoria, Estado, Observabilidad).
*   **Providers/**: Implementaciones de los servicios de IA.
    *   `LLM/`: Integración con MLX y modelos Qwen.
    *   `STT/`: Proveedores de transcripción (Whisper/Nativo).
    *   `TTS/`: Proveedores de síntesis de voz.
*   **Views/**: Componentes de la interfaz de usuario.
    *   `ActiveSessionView.swift`: Vista principal de la sesión de voz.
    *   `Components/`: Elementos reutilizables (Orbe, Textos animados).

## 🚀 Requisitos

*   **Hardware**: Mac con Apple Silicon (M1/M2/M3) o dispositivo iOS compatible (iPhone con A16/A17+ recomendado para modelos locales pesados).
*   **OS**: macOS 14.0+ / iOS 17.0+
*   **Xcode**: 15.0+

## 📝 Notas de Versión (0.75)

*   Integración inicial de MLX Swift.
*   Optimización del pipeline de TTS para reducir latencia.
*   Mejoras en la visualización del Orbe Neural.
*   Soporte preliminar para selección de modelos.

---
Desarrollado con ❤️ para la comunidad de IA Local.
