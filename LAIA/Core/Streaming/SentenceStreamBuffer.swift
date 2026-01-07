//
//  SentenceStreamBuffer.swift
//  LAIA - Local AI Assistant
//
//  Token accumulation buffer with sentence detection.
//  Triggers TTS dispatch on punctuation boundaries.
//

import Foundation
import os

/// Buffer that accumulates LLM tokens and emits complete sentences
/// Implements punctuation-based segmentation for streaming TTS
public actor SentenceStreamBuffer {
    
    // MARK: - Configuration
    
    public struct Configuration: Sendable {
        /// Characters that end a sentence
        public var sentenceEnders: Set<Character> = [".", "!", "?"]
        
        /// Characters that create a pause (comma, semicolon)
        public var pauseMarkers: Set<Character> = [",", ";", ":"]
        
        /// Minimum characters before emitting on pause marker
        public var minCharsForPauseEmit: Int = 40
        
        /// Maximum buffer size before forced emit
        public var maxBufferSize: Int = 150
        
        /// Whether to emit on newline
        public var emitOnNewline: Bool = true
        
        public init() {}
    }
    
    // MARK: - Callback Types
    
    public typealias SentenceCallback = @Sendable (String) async -> Void
    public typealias CompletionCallback = @Sendable (String) async -> Void
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.laia.streaming", category: "SentenceBuffer")
    
    private let config: Configuration
    
    /// Current token buffer
    private var buffer: String = ""
    
    /// Accumulated full response
    private var fullResponse: String = ""
    
    /// Callback for each complete sentence
    private var onSentence: SentenceCallback?
    
    /// Callback for completion
    private var onComplete: CompletionCallback?
    
    /// Number of sentences emitted
    private var sentenceCount: Int = 0
    
    // MARK: - Initialization
    
    public init(configuration: Configuration = Configuration()) {
        self.config = configuration
    }
    
    // MARK: - Setup
    
    /// Configure callbacks
    public func configure(
        onSentence: @escaping SentenceCallback,
        onComplete: @escaping CompletionCallback
    ) {
        self.onSentence = onSentence
        self.onComplete = onComplete
    }
    
    // MARK: - Token Processing
    
    /// Add a token to the buffer
    /// - Parameter token: Token string from LLM
    /// - Returns: Sentence if one was completed, nil otherwise
    @discardableResult
    public func addToken(_ token: String) async -> String? {
        buffer += token
        fullResponse += token
        
        // Check for sentence boundaries
        return await checkAndEmit()
    }
    
    /// Process multiple tokens at once
    public func addTokens(_ tokens: [String]) async {
        for token in tokens {
            await addToken(token)
        }
    }
    
    // MARK: - Emission Logic
    
    private func checkAndEmit() async -> String? {
        // Check for newline
        if config.emitOnNewline, let newlineIndex = buffer.lastIndex(of: "\n") {
            let beforeNewline = String(buffer[..<newlineIndex]).trimmingCharacters(in: .whitespaces)
            let afterNewline = String(buffer[buffer.index(after: newlineIndex)...])
            
            if !beforeNewline.isEmpty {
                buffer = afterNewline
                sentenceCount += 1
                
                logger.debug("Emitting on newline: \"\(beforeNewline.prefix(30))...\"")
                await onSentence?(beforeNewline)
                return beforeNewline
            }
        }
        
        // Check for sentence enders
        for (index, char) in buffer.enumerated() {
            if config.sentenceEnders.contains(char) {
                // Check if it's followed by space or end of buffer
                let nextIndex = buffer.index(buffer.startIndex, offsetBy: index + 1)
                let isEnd = nextIndex >= buffer.endIndex
                let isFollowedBySpace = !isEnd && buffer[nextIndex].isWhitespace
                
                if isEnd || isFollowedBySpace {
                    let sentence = String(buffer[...buffer.index(buffer.startIndex, offsetBy: index)])
                        .trimmingCharacters(in: .whitespaces)
                    
                    if !sentence.isEmpty {
                        // Keep remainder
                        if isEnd {
                            buffer = ""
                        } else {
                            buffer = String(buffer[nextIndex...]).trimmingCharacters(in: .whitespaces)
                        }
                        
                        sentenceCount += 1
                        
                        logger.debug("Emitting sentence \(self.sentenceCount): \"\(sentence.prefix(30))...\"")
                        await onSentence?(sentence)
                        return sentence
                    }
                }
            }
        }
        
        // Check for pause markers with minimum length
        if buffer.count >= config.minCharsForPauseEmit {
            for (index, char) in buffer.enumerated() {
                if config.pauseMarkers.contains(char) {
                    let sentence = String(buffer[...buffer.index(buffer.startIndex, offsetBy: index)])
                        .trimmingCharacters(in: .whitespaces)
                    
                    if !sentence.isEmpty {
                        buffer = String(buffer[buffer.index(buffer.startIndex, offsetBy: index + 1)...])
                            .trimmingCharacters(in: .whitespaces)
                        
                        sentenceCount += 1
                        
                        logger.debug("Emitting on pause: \"\(sentence.prefix(30))...\"")
                        await onSentence?(sentence)
                        return sentence
                    }
                }
            }
        }
        
        // Force emit if buffer too large
        if buffer.count >= config.maxBufferSize {
            // Find best break point (last space)
            if let spaceIndex = buffer.lastIndex(of: " ") {
                let sentence = String(buffer[..<spaceIndex]).trimmingCharacters(in: .whitespaces)
                buffer = String(buffer[buffer.index(after: spaceIndex)...])
                
                if !sentence.isEmpty {
                    sentenceCount += 1
                    
                    logger.debug("Forced emit: \"\(sentence.prefix(30))...\"")
                    await onSentence?(sentence)
                    return sentence
                }
            }
        }
        
        return nil
    }
    
    // MARK: - Finalization
    
    /// Flush remaining buffer and complete
    public func flush() async {
        let remaining = buffer.trimmingCharacters(in: .whitespaces)
        
        if !remaining.isEmpty {
            sentenceCount += 1
            logger.debug("Flushing remaining: \"\(remaining.prefix(30))...\"")
            await onSentence?(remaining)
        }
        
        buffer = ""
        
        // Call completion with full response
        await onComplete?(fullResponse)
        
        logger.info("Stream complete: \(self.sentenceCount) sentences, \(self.fullResponse.count) chars")
    }
    
    /// Reset buffer state
    public func reset() {
        buffer = ""
        fullResponse = ""
        sentenceCount = 0
    }
    
    // MARK: - Queries
    
    /// Current buffer contents
    public var currentBuffer: String {
        buffer
    }
    
    /// Full accumulated response
    public var accumulatedResponse: String {
        fullResponse
    }
    
    /// Number of sentences emitted
    public var emittedSentenceCount: Int {
        sentenceCount
    }
    
    /// Whether buffer has content
    public var hasContent: Bool {
        !buffer.isEmpty
    }
}

// MARK: - Token Stream Processing

extension SentenceStreamBuffer {
    
    /// Process an async stream of tokens
    public func processStream<S: AsyncSequence>(
        _ stream: S
    ) async throws where S.Element == String {
        for try await token in stream {
            await addToken(token)
        }
        
        await flush()
    }
    
    /// Process async throwing stream
    public func processThrowingStream(
        _ stream: AsyncThrowingStream<String, Error>
    ) async throws {
        for try await token in stream {
            await addToken(token)
        }
        
        await flush()
    }
}
