//
//  InferenceState.swift
//  LAIA - Local AI Assistant
//
//  Actor-based state management for inference pipeline coordination.
//  Provides atomic state transitions and observable state stream.
//

import Foundation

/// Actor managing inference pipeline state with atomic transitions
public actor InferenceState {
    
    // MARK: - Properties
    
    /// Current inference state
    private(set) var current: InferenceStateValue = .idle
    
    /// Previous state for transition validation
    private(set) var previous: InferenceStateValue = .idle
    
    /// Timestamp of last state change
    private(set) var lastTransitionTime: Date = Date()
    
    /// Continuation for state observation stream
    private var stateContinuation: AsyncStream<InferenceStateValue>.Continuation?
    
    /// Lock state to prevent transitions during critical operations
    private var isLocked: Bool = false
    
    // MARK: - Initialization
    
    public init(initialState: InferenceStateValue = .idle) {
        self.current = initialState
        self.previous = initialState
    }
    
    // MARK: - State Observation
    
    /// Observable stream of state changes
    public var stateStream: AsyncStream<InferenceStateValue> {
        AsyncStream { [weak self] continuation in
            Task { [weak self] in
                await self?.setStateContinuation(continuation)
            }
        }
    }
    
    private func setStateContinuation(_ continuation: AsyncStream<InferenceStateValue>.Continuation) {
        self.stateContinuation = continuation
        // Emit current state immediately
        continuation.yield(current)
    }
    
    // MARK: - State Transitions
    
    /// Transition to a new state with validation
    /// - Parameter newState: Target state
    /// - Returns: Whether transition was successful
    @discardableResult
    public func transition(to newState: InferenceStateValue) -> Bool {
        guard !isLocked else {
            return false
        }
        
        guard isValidTransition(from: current, to: newState) else {
            return false
        }
        
        previous = current
        current = newState
        lastTransitionTime = Date()
        
        stateContinuation?.yield(newState)
        
        return true
    }
    
    /// Force transition (bypasses validation, use sparingly)
    public func forceTransition(to newState: InferenceStateValue) {
        previous = current
        current = newState
        lastTransitionTime = Date()
        isLocked = false
        
        stateContinuation?.yield(newState)
    }
    
    /// Lock state to prevent transitions
    public func lock() {
        isLocked = true
    }
    
    /// Unlock state to allow transitions
    public func unlock() {
        isLocked = false
    }
    
    /// Reset to idle state
    public func reset() {
        isLocked = false
        previous = current
        current = .idle
        lastTransitionTime = Date()
        
        stateContinuation?.yield(.idle)
    }
    
    // MARK: - Transition Validation
    
    /// Validate state transition according to pipeline rules
    private func isValidTransition(from: InferenceStateValue, to: InferenceStateValue) -> Bool {
        // Allow reset to idle from any state
        if to == .idle {
            return true
        }
        
        // Allow transition to error from any state
        if to == .error {
            return true
        }
        
        // Define valid transitions
        switch from {
        case .idle:
            return to == .listening
            
        case .listening:
            return to == .detectingVoice || to == .idle
            
        case .detectingVoice:
            return to == .transcribing || to == .listening || to == .idle
            
        case .transcribing:
            return to == .thinking || to == .idle
            
        case .thinking:
            return to == .speaking || to == .idle
            
        case .speaking:
            return to == .listening || to == .idle
            
        case .error:
            return to == .idle || to == .listening
        }
    }
    
    // MARK: - State Queries
    
    /// Whether currently in an active inference state
    public var isInferencing: Bool {
        switch current {
        case .transcribing, .thinking, .speaking:
            return true
        default:
            return false
        }
    }
    
    /// Whether audio capture should be active
    public var shouldCaptureAudio: Bool {
        current.shouldCaptureAudio
    }
    
    /// Whether current state allows interruption
    public var isInterruptible: Bool {
        current.isInterruptible && !isLocked
    }
    
    /// Time spent in current state
    public var timeInCurrentState: TimeInterval {
        Date().timeIntervalSince(lastTransitionTime)
    }
    
    // MARK: - Cleanup
    
    /// Finish state stream
    public func finish() {
        stateContinuation?.finish()
        stateContinuation = nil
    }
}

// MARK: - State Transition Extensions

extension InferenceState {
    
    /// Convenience method to start listening
    @discardableResult
    public func startListening() -> Bool {
        transition(to: .listening)
    }
    
    /// Convenience method to indicate voice detected
    @discardableResult
    public func voiceDetected() -> Bool {
        transition(to: .detectingVoice)
    }
    
    /// Convenience method to start transcription
    @discardableResult
    public func startTranscription() -> Bool {
        transition(to: .transcribing)
    }
    
    /// Convenience method to start LLM inference
    @discardableResult
    public func startThinking() -> Bool {
        transition(to: .thinking)
    }
    
    /// Convenience method to start speaking
    @discardableResult
    public func startSpeaking() -> Bool {
        transition(to: .speaking)
    }
    
    /// Convenience method to report error
    public func reportError() {
        forceTransition(to: .error)
    }
}
