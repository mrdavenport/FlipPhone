import Foundation
import CoreMotion
import UIKit

@MainActor
final class OrientationManager: ObservableObject {
    @Published private(set) var isFaceDown: Bool = false
    @Published private(set) var gravityX: Double = 0
    @Published private(set) var gravityY: Double = 0
    @Published private(set) var gravityZ: Double = 0
    
    private let motionManager = CMMotionManager()
    private let motionQueue = OperationQueue()
    private var updateTimer: Timer?
    private var isScreenSleeping: Bool = false
    
    private(set) var sessionStartTime: Date?
    private(set) var currentDuration: TimeInterval = 0
    
    // Pause/resume tracking for Solution A
    private var pausedTime: TimeInterval = 0 // Total time paused
    private var pauseStartTime: Date? // When current pause started
    private(set) var pauseCount: Int = 0 // Number of times session was paused
    
    /// Get the current session duration, calculating on-demand if timer is paused
    var sessionDuration: TimeInterval {
        guard let startTime = sessionStartTime else { return 0 }
        let totalTime = Date().timeIntervalSince(startTime)
        // Subtract paused time
        if let pauseStart = pauseStartTime {
            let currentPause = Date().timeIntervalSince(pauseStart)
            return totalTime - pausedTime - currentPause
        }
        return totalTime - pausedTime
    }
    
    private let startHapticGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let endHapticGenerator = UINotificationFeedbackGenerator()
    
    // UserDefaults keys for session persistence
    private let activeSessionStartTimeKey = "com.focusflip.activeSessionStartTime"
    
    init() {
        motionQueue.qualityOfService = .userInitiated
        // Don't recover session in init - let FocusTrackingView handle it after monitoring starts
    }
    
    func startMonitoring() {
        guard motionManager.isDeviceMotionAvailable else { return }
        
        // Use 1.0 second interval for responsive orientation detection
        let interval: TimeInterval = 1.0
        motionManager.deviceMotionUpdateInterval = interval
        startMotionUpdates(withInterval: interval)
    }
    
    func startMonitoringWithFastInterval() {
        guard motionManager.isDeviceMotionAvailable else { return }
        
        // Use fast interval (0.2s) for quick detection when screen wakes
        startMotionUpdates(withInterval: 0.2)
    }
    
    func resumeNormalMonitoring() {
        guard motionManager.isDeviceMotionAvailable else { return }
        
        // Resume normal interval after quick check
        if motionManager.isDeviceMotionActive {
            motionManager.stopDeviceMotionUpdates()
        }
        startMotionUpdates(withInterval: 1.0)
    }
    
    /// Immediately check current orientation (useful when app becomes active)
    /// Returns true if phone is face down
    /// This will also trigger handleOrientationChange if orientation has changed
    func checkCurrentOrientationImmediately() -> Bool {
        guard motionManager.isDeviceMotionAvailable else { return false }
        
        // Get a single motion update synchronously
        var isFaceDown = false
        let semaphore = DispatchSemaphore(value: 0)
        
        // Stop any existing updates temporarily
        let wasActive = motionManager.isDeviceMotionActive
        if wasActive {
            motionManager.stopDeviceMotionUpdates()
        }
        
        motionManager.deviceMotionUpdateInterval = 0.1
        motionManager.startDeviceMotionUpdates(to: motionQueue) { motion, error in
            guard let motion = motion, error == nil else {
                semaphore.signal()
                return
            }
            
            let gravity = motion.gravity
            let isFlat = abs(gravity.x) < 0.5 && abs(gravity.y) < 0.5
            isFaceDown = gravity.z > 0.5 && isFlat
            
            // Update published properties immediately
            Task { @MainActor [weak self] in
                guard let self else {
                    semaphore.signal()
                    return
                }
                self.gravityX = gravity.x
                self.gravityY = gravity.y
                self.gravityZ = gravity.z
                
                // Always update isFaceDown and trigger handleOrientationChange if needed
                // This ensures session starts immediately if phone is face down
                if isFaceDown != self.isFaceDown {
                    self.handleOrientationChange(isFaceDownNow: isFaceDown)
                } else {
                    // Even if orientation hasn't changed, update the property to ensure consistency
                    self.isFaceDown = isFaceDown
                }
            }
            
            semaphore.signal()
        }
        
        // Wait for the update (with timeout)
        _ = semaphore.wait(timeout: .now() + 0.5)
        
        // Stop the one-time update
        motionManager.stopDeviceMotionUpdates()
        
        // If motion updates were active before, they'll be restarted by the caller
        // (e.g., via startMonitoringWithFastInterval or resumeNormalMonitoring)
        
        return isFaceDown
    }
    
    private func startMotionUpdates(withInterval interval: TimeInterval) {
        // Stop any existing updates first
        if motionManager.isDeviceMotionActive {
            motionManager.stopDeviceMotionUpdates()
        }
        
        motionManager.deviceMotionUpdateInterval = interval
        motionManager.startDeviceMotionUpdates(to: motionQueue) { [weak self] motion, _ in
            guard let self, let motion else { return }
            let gravity = motion.gravity
            let isFlat = abs(gravity.x) < 0.5 && abs(gravity.y) < 0.5
            let faceDownNow = gravity.z > 0.5 && isFlat
            
            Task { @MainActor [weak self] in
                guard let self else { return }
                
                // Only update @Published properties when orientation actually changes
                // This reduces SwiftUI updates and allows the device to respect auto-lock
                let orientationChanged = (faceDownNow && !self.isFaceDown) || (!faceDownNow && self.isFaceDown)
                
                if orientationChanged {
                    gravityX = gravity.x
                    gravityY = gravity.y
                    gravityZ = gravity.z
                    handleOrientationChange(isFaceDownNow: faceDownNow)
                }
            }
        }
    }
    
    func stopMonitoring() {
        motionManager.stopDeviceMotionUpdates()
        invalidateTimer()
        isFaceDown = false
    }
    
    func hasActiveSession() -> Bool {
        sessionStartTime != nil
    }
    
    /// After a session begins, scene transitions (`.active`) and one-shot orientation checks can briefly
    /// read "face up" before Core Motion stabilizes. Skip auto-complete / cancel in that window.
    private static let scenePhaseFaceUpIgnoreGracePeriod: TimeInterval = 3.0
    
    func shouldIgnoreFaceUpFromScenePhaseCheck(now: Date = Date()) -> Bool {
        guard let start = sessionStartTime else { return false }
        return now.timeIntervalSince(start) < Self.scenePhaseFaceUpIgnoreGracePeriod
    }
    
    func endSession() {
        guard let startTime = sessionStartTime else { return }
        endHapticGenerator.notificationOccurred(.success)
        invalidateTimer()
        
        // Calculate final duration including any pause time
        let totalTime = Date().timeIntervalSince(startTime)
        if let pauseStart = pauseStartTime {
            let currentPause = Date().timeIntervalSince(pauseStart)
            currentDuration = totalTime - pausedTime - currentPause
        } else {
            currentDuration = totalTime - pausedTime
        }
        
        sessionStartTime = nil
        pausedTime = 0
        pauseStartTime = nil
        clearPersistedSession()
    }
    
    func resetSession() {
        invalidateTimer()
        sessionStartTime = nil
        currentDuration = 0
        pausedTime = 0
        pauseStartTime = nil
        pauseCount = 0
        clearPersistedSession()
    }
    
    /// Pause the session (when phone is flipped back up)
    func pauseSession() {
        guard sessionStartTime != nil, pauseStartTime == nil else { return }
        // Record when pause started
        pauseStartTime = Date()
        // Stop the timer
        invalidateTimer()
    }
    
    /// Resume the session (when phone is flipped back down)
    func resumeSession() {
        guard sessionStartTime != nil, let pauseStart = pauseStartTime else { return }
        // Calculate how long we were paused
        let pauseDuration = Date().timeIntervalSince(pauseStart)
        pausedTime += pauseDuration
        pauseCount += 1 // Increment pause count
        pauseStartTime = nil
        
        // Restart the timer with correct current duration
        invalidateTimer()
        // Update currentDuration to the correct value before starting timer
        let totalTime = Date().timeIntervalSince(sessionStartTime!)
        currentDuration = totalTime - pausedTime
        
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, let startTime = sessionStartTime else { return }
            // Calculate duration excluding paused time
            let totalTime = Date().timeIntervalSince(startTime)
            self.currentDuration = totalTime - self.pausedTime
        }
    }
    
    // MARK: - Session Persistence
    
    /// Persist the current session start time to UserDefaults
    func persistSession() {
        guard let startTime = sessionStartTime else {
            clearPersistedSession()
            return
        }
        UserDefaults.standard.set(startTime, forKey: activeSessionStartTimeKey)
    }
    
    /// Clear persisted session from UserDefaults
    func clearPersistedSession() {
        UserDefaults.standard.removeObject(forKey: activeSessionStartTimeKey)
    }
    
    /// Recover session from UserDefaults if it exists
    func recoverSessionIfNeeded() {
        guard let persistedStartTime = UserDefaults.standard.object(forKey: activeSessionStartTimeKey) as? Date else {
            return
        }
        
        // Only recover if the session is recent (within last 24 hours)
        // This prevents recovering very old sessions from previous app installs
        let timeSinceStart = Date().timeIntervalSince(persistedStartTime)
        guard timeSinceStart > 0 && timeSinceStart < 86400 else {
            clearPersistedSession()
            return
        }
        
        // Restore the session
        sessionStartTime = persistedStartTime
        pausedTime = 0 // Reset paused time on recovery
        pauseStartTime = nil
        pauseCount = 0 // Reset pause count on recovery (pauses aren't persisted)
        currentDuration = Date().timeIntervalSince(persistedStartTime)
        
        // Restart the timer
        invalidateTimer()
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, let startTime = sessionStartTime else { return }
            // Calculate duration excluding paused time
            let totalTime = Date().timeIntervalSince(startTime)
            if let pauseStart = pauseStartTime {
                let currentPause = Date().timeIntervalSince(pauseStart)
                currentDuration = totalTime - self.pausedTime - currentPause
            } else {
                currentDuration = totalTime - self.pausedTime
            }
        }
    }
    
    /// Get the persisted session start time without restoring it
    static func getPersistedSessionStartTime() -> Date? {
        guard let persistedStartTime = UserDefaults.standard.object(forKey: "com.focusflip.activeSessionStartTime") as? Date else {
            return nil
        }
        
        // Only return if the session is recent (within last 24 hours)
        let timeSinceStart = Date().timeIntervalSince(persistedStartTime)
        guard timeSinceStart > 0 && timeSinceStart < 86400 else {
            return nil
        }
        
        return persistedStartTime
    }
    
    func setScreenSleeping(_ sleeping: Bool) {
        isScreenSleeping = sleeping
        
        if sleeping {
            // When screen is sleeping, reduce motion update frequency to save battery
            // and reduce the chance of iOS terminating the app
            // 5 second interval is still responsive enough to detect flip-back
            if motionManager.isDeviceMotionActive {
                motionManager.stopDeviceMotionUpdates()
            }
            startMotionUpdates(withInterval: 5.0)
            
            // Pause the duration timer when screen is sleeping to save resources
            // Duration will be calculated on-demand when needed
            invalidateTimer()
        } else {
            // When screen wakes, immediately check orientation for quick detection
            // This ensures we detect if phone was flipped while screen was sleeping
            let wasFaceDown = isFaceDown
            let isFaceDownNow = checkCurrentOrientationImmediately()
            
            // If orientation changed while screen was sleeping, handle it
            if wasFaceDown != isFaceDownNow {
                // Orientation change will be handled by checkCurrentOrientationImmediately
                // but we need to ensure motion updates continue
            }
            
            // Resume normal 1 second interval for responsive detection
            if motionManager.isDeviceMotionActive {
                motionManager.stopDeviceMotionUpdates()
            }
            startMotionUpdates(withInterval: 1.0)
            
            // Restart the duration timer when screen wakes (only if session is active and not paused)
            if sessionStartTime != nil && pauseStartTime == nil {
                invalidateTimer()
                // Update currentDuration to the correct value before starting timer
                let totalTime = Date().timeIntervalSince(sessionStartTime!)
                currentDuration = totalTime - pausedTime
                
                updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                    guard let self, let startTime = sessionStartTime else { return }
                    // Calculate duration excluding paused time
                    let totalTime = Date().timeIntervalSince(startTime)
                    if let pauseStart = pauseStartTime {
                        let currentPause = Date().timeIntervalSince(pauseStart)
                        currentDuration = totalTime - self.pausedTime - currentPause
                    } else {
                        currentDuration = totalTime - self.pausedTime
                    }
                }
            }
        }
    }
    
    private func handleOrientationChange(isFaceDownNow: Bool) {
        if isFaceDownNow {
            if !isFaceDown {
                // Starting or resuming a session
                if sessionStartTime != nil {
                    // Resuming existing session
                    resumeSession()
                } else {
                    // Starting new session
                    startSessionIfNeeded()
                }
            }
        } else {
            // Phone flipped back up - pause session if active
            if sessionStartTime != nil {
                pauseSession()
            }
        }
        // Don't call endSession() here - let the onChange handler in FocusTrackingView handle it
        // so it can capture the sessionStartTime before it's cleared
        
        isFaceDown = isFaceDownNow
    }
    
    private func startSessionIfNeeded() {
        guard sessionStartTime == nil else { return }
        sessionStartTime = Date()
        currentDuration = 0
        pausedTime = 0 // Reset paused time for new session
        pauseStartTime = nil
        pauseCount = 0 // Reset pause count for new session
        startHapticGenerator.impactOccurred()
        
        // Play start chime
        AudioService.shared.playStartChime()
        
        // Persist the session start time
        persistSession()
        
        invalidateTimer()
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, let startTime = sessionStartTime else { return }
            // Calculate duration excluding paused time
            let totalTime = Date().timeIntervalSince(startTime)
            if let pauseStart = pauseStartTime {
                let currentPause = Date().timeIntervalSince(pauseStart)
                currentDuration = totalTime - self.pausedTime - currentPause
            } else {
                currentDuration = totalTime - self.pausedTime
            }
        }
    }
    
    func invalidateTimer() {
        updateTimer?.invalidate()
        updateTimer = nil
    }
    
    // MARK: - Debug Methods
    
    #if DEBUG
    /// Debug method to simulate face down state (for simulator testing)
    func simulateFaceDown(_ isDown: Bool) {
        if isDown {
            isFaceDown = true
            startSessionIfNeeded()
        } else {
            isFaceDown = false
        }
    }
    
    /// Debug method to manually start a session
    func debugStartSession() {
        isFaceDown = true
        startSessionIfNeeded()
    }
    
    /// Debug method to manually end a session
    /// Note: This just sets isFaceDown to false, letting the onChange handler in FocusTrackingView
    /// capture the session data before calling endSession()
    func debugEndSession() {
        isFaceDown = false
    }
    #endif
}

