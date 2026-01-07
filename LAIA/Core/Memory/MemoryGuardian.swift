//
//  MemoryGuardian.swift
//  LAIA - Local AI Assistant
//
//  Active memory management system that monitors memory pressure
//  and thermal state to trigger model unloading and cache purging.
//  Critical for A19 chip with limited RAM.
//

import Foundation
import UIKit
import os

/// Memory management coordinator for aggressive cleanup under pressure
/// Monitors system notifications and provides APIs for forced cleanup
@MainActor
public final class MemoryGuardian: Sendable {
    
    // MARK: - Singleton
    
    /// Shared instance for app-wide memory management
    public static let shared = MemoryGuardian()
    
    // MARK: - Configuration
    
    /// Memory thresholds for proactive cleanup
    public struct MemoryThresholds: Sendable {
        /// Start warning at this percentage of available memory
        public let warningThreshold: Double = 0.7
        
        /// Critical threshold triggering aggressive unload
        public let criticalThreshold: Double = 0.85
        
        /// Idle time before unloading inactive models (seconds)
        public let modelIdleTimeout: TimeInterval = 30.0
    }
    
    public let thresholds = MemoryThresholds()
    
    // MARK: - Properties
    
    /// Logger for memory events
    private let logger = Logger(subsystem: "com.laia.memory", category: "MemoryGuardian")
    
    /// Registered cleanup handlers
    private var cleanupHandlers: [String: @Sendable () async -> Void] = [:]
    
    /// Current thermal state
    private(set) var currentThermalState: ProcessInfo.ThermalState = .nominal
    
    /// Whether memory warning is active
    private(set) var isUnderMemoryPressure: Bool = false
    
    /// Observation tokens for cleanup
    nonisolated(unsafe) private var memoryWarningObserver: NSObjectProtocol?
    nonisolated(unsafe) private var thermalStateObserver: NSObjectProtocol?
    
    /// Last cleanup timestamp
    private var lastCleanupTime: Date?
    
    /// Minimum interval between cleanups (prevent thrashing)
    private let minimumCleanupInterval: TimeInterval = 5.0
    
    // MARK: - Initialization
    
    private init() {
        setupObservers()
        logger.info("MemoryGuardian initialized")
    }
    
    deinit {
        if let observer = memoryWarningObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = thermalStateObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    // MARK: - Observer Setup
    
    private func setupObservers() {
        // Memory warning notification
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.handleMemoryWarning()
            }
        }
        
        // Thermal state changes
        thermalStateObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.handleThermalStateChange()
            }
        }
        
        // Initialize thermal state
        currentThermalState = ProcessInfo.processInfo.thermalState
    }
    
    private func removeObservers() {
        if let observer = memoryWarningObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = thermalStateObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    // MARK: - Handler Registration
    
    /// Register a cleanup handler for a specific component
    /// - Parameters:
    ///   - identifier: Unique identifier for the handler
    ///   - handler: Async cleanup closure
    public func registerCleanupHandler(
        identifier: String,
        handler: @escaping @Sendable () async -> Void
    ) {
        cleanupHandlers[identifier] = handler
        logger.debug("Registered cleanup handler: \(identifier)")
    }
    
    /// Unregister a cleanup handler
    public func unregisterCleanupHandler(identifier: String) {
        cleanupHandlers.removeValue(forKey: identifier)
        logger.debug("Unregistered cleanup handler: \(identifier)")
    }
    
    // MARK: - Memory Warning Handling
    
    private func handleMemoryWarning() async {
        logger.warning("⚠️ Memory warning received")
        isUnderMemoryPressure = true
        
        // Check minimum cleanup interval
        if let lastTime = lastCleanupTime,
           Date().timeIntervalSince(lastTime) < minimumCleanupInterval {
            logger.debug("Skipping cleanup - too soon since last cleanup")
            return
        }
        
        await executeCleanup(level: .warning)
        lastCleanupTime = Date()
    }
    
    private func handleThermalStateChange() async {
        let newState = ProcessInfo.processInfo.thermalState
        let previousState = currentThermalState
        currentThermalState = newState
        
        logger.info("Thermal state changed: \(self.thermalStateDescription(previousState)) → \(self.thermalStateDescription(newState))")
        
        // Take action on serious or critical thermal state
        if newState == .serious || newState == .critical {
            await executeCleanup(level: newState == .critical ? .critical : .warning)
        }
    }
    
    // MARK: - Cleanup Execution
    
    /// Cleanup levels for different urgency
    public enum CleanupLevel: Sendable {
        case warning    // First level - purge caches
        case critical   // Second level - unload models
        case emergency  // Third level - unload everything
    }
    
    /// Execute cleanup at specified level
    public func executeCleanup(level: CleanupLevel) async {
        logger.info("🧹 Executing cleanup at level: \(String(describing: level))")
        
        let startTime = Date()
        
        // Execute all registered handlers concurrently
        await withTaskGroup(of: Void.self) { group in
            for (identifier, handler) in cleanupHandlers {
                group.addTask {
                    self.logger.debug("Running cleanup handler: \(identifier)")
                    await handler()
                }
            }
        }
        
        // Force garbage collection hint
        autoreleasepool { }
        
        let elapsed = Date().timeIntervalSince(startTime)
        logger.info("✅ Cleanup completed in \(String(format: "%.2f", elapsed))s")
        
        // Reset pressure flag after cleanup
        if level != .emergency {
            isUnderMemoryPressure = false
        }
    }
    
    /// Force immediate cleanup (called by external components)
    public func forceCleanup() async {
        await executeCleanup(level: .critical)
    }
    
    // MARK: - Thermal State Queries
    
    /// Whether thermal state allows intensive operations
    public var allowsIntensiveOperations: Bool {
        switch currentThermalState {
        case .nominal, .fair:
            return true
        case .serious, .critical:
            return false
        @unknown default:
            return true
        }
    }
    
    /// Recommended delay for next intensive operation
    public var recommendedThrottleDelay: TimeInterval {
        switch currentThermalState {
        case .nominal:
            return 0
        case .fair:
            return 0.1
        case .serious:
            return 0.5
        case .critical:
            return 2.0
        @unknown default:
            return 0
        }
    }
    
    // MARK: - Memory Information
    
    /// Get current memory usage statistics
    public var memoryUsage: MemoryUsage {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if result == KERN_SUCCESS {
            return MemoryUsage(
                resident: info.resident_size,
                virtual: info.virtual_size
            )
        }
        
        return MemoryUsage(resident: 0, virtual: 0)
    }
    
    /// Memory usage statistics
    public struct MemoryUsage: Sendable {
        public let resident: UInt64
        public let virtual: UInt64
        
        public var residentMB: Double {
            Double(resident) / (1024 * 1024)
        }
        
        public var virtualMB: Double {
            Double(virtual) / (1024 * 1024)
        }
    }
    
    // MARK: - Helpers
    
    private func thermalStateDescription(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal:
            return "nominal"
        case .fair:
            return "fair"
        case .serious:
            return "serious"
        case .critical:
            return "critical"
        @unknown default:
            return "unknown"
        }
    }
}

// MARK: - MLX Cleanup Extension

extension MemoryGuardian {
    
    /// Register MLX-specific cleanup handler
    /// Call this during app initialization with actual MLX cleanup code
    public func registerMLXCleanup(purgeCache: @escaping @Sendable () async -> Void) {
        registerCleanupHandler(identifier: "mlx-cache") {
            await purgeCache()
        }
    }
    
    /// Register WhisperKit cleanup handler
    public func registerWhisperCleanup(unload: @escaping @Sendable () async -> Void) {
        registerCleanupHandler(identifier: "whisperkit-model") {
            await unload()
        }
    }
}
