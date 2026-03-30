import Foundation
import StoreKit
import UIKit

final class ReviewPromptService {
    static let shared = ReviewPromptService()
    
    private let userDefaults = UserDefaults.standard
    
    // Keys for UserDefaults
    private let lastPromptDateKey = "reviewPromptLastDate"
    private let promptCountKey = "reviewPromptCount"
    private let hasCustomizedSessionKey = "reviewPromptHasCustomizedSession"
    private let sessionCountKey = "reviewPromptSessionCount"
    private let hasReviewedKey = "reviewPromptHasReviewed"
    private let hasDismissedPermanentlyKey = "reviewPromptDismissedPermanently"
    
    // Constants
    private let maxPromptsPerYear = 3
    private let minimumSessionDuration: TimeInterval = 60.0 // 1 minute
    private let minimumSessionCount = 5
    private let minimumStreakDays = 7
    
    private init() {}
    
    /// Check if review prompt should be shown and display it if eligible
    /// - Parameters:
    ///   - sessionDuration: Duration of the completed session in seconds
    ///   - isPersonalBest: Whether this session is a personal best
    ///   - hasCustomizedSession: Whether user customized category/description
    ///   - currentStreak: Current streak count
    func checkAndPromptIfEligible(
        sessionDuration: TimeInterval,
        isPersonalBest: Bool,
        hasCustomizedSession: Bool,
        currentStreak: Int
    ) {
        print("🔍 ReviewPromptService: Checking eligibility...")
        print("   - Session duration: \(sessionDuration)s")
        print("   - Is personal best: \(isPersonalBest)")
        print("   - Has customized: \(hasCustomizedSession)")
        print("   - Current streak: \(currentStreak)")
        print("   - Session count: \(userDefaults.integer(forKey: sessionCountKey))")
        print("   - Has reviewed: \(hasReviewed())")
        print("   - Dismissed permanently: \(hasDismissedPermanently())")
        
        // Don't show if user already reviewed or dismissed permanently
        guard !hasReviewed() && !hasDismissedPermanently() else {
            print("❌ ReviewPromptService: User already reviewed or dismissed")
            return
        }
        
        // Don't show if session is too short (must be > 1 minute)
        guard sessionDuration > minimumSessionDuration else {
            print("❌ ReviewPromptService: Session too short (\(sessionDuration)s < \(minimumSessionDuration)s)")
            return
        }
        
        // Check rate limiting (max 3 per year)
        guard canShowPrompt() else {
            print("❌ ReviewPromptService: Rate limited")
            return
        }
        
        // Check eligibility criteria
        guard isEligible(
            sessionDuration: sessionDuration,
            isPersonalBest: isPersonalBest,
            hasCustomizedSession: hasCustomizedSession,
            currentStreak: currentStreak
        ) else {
            print("❌ ReviewPromptService: Not eligible")
            return
        }
        
        print("✅ ReviewPromptService: Eligible! Showing prompt...")
        // Show the review prompt
        showReviewPrompt()
    }
    
    /// Mark that user has customized a session (called when they save details)
    func markSessionCustomized() {
        userDefaults.set(true, forKey: hasCustomizedSessionKey)
    }
    
    /// Increment session count (only for sessions > 1 minute)
    func incrementSessionCount() {
        let currentCount = userDefaults.integer(forKey: sessionCountKey)
        userDefaults.set(currentCount + 1, forKey: sessionCountKey)
    }
    
    /// Mark that user has reviewed (called if they tap review)
    func markAsReviewed() {
        userDefaults.set(true, forKey: hasReviewedKey)
    }
    
    /// Mark that user dismissed permanently (called if they dismiss)
    func markAsDismissedPermanently() {
        userDefaults.set(true, forKey: hasDismissedPermanentlyKey)
    }
    
    // MARK: - Private Methods
    
    private func isEligible(
        sessionDuration: TimeInterval,
        isPersonalBest: Bool,
        hasCustomizedSession: Bool,
        currentStreak: Int
    ) -> Bool {
        // Check if user has ever customized a session (either this one or previously)
        let hasEverCustomized = hasCustomizedSession || userDefaults.bool(forKey: hasCustomizedSessionKey)
        
        let sessionCount = userDefaults.integer(forKey: sessionCountKey)
        
        // Check if any eligibility criteria is met:
        // 1. Personal best (with session > 1 minute) - no customization required
        if isPersonalBest && sessionDuration > minimumSessionDuration {
            print("   ✅ Eligible: Personal best")
            return true
        }
        
        // 2. 5+ sessions total (all must be > 1 minute) - requires customization
        if sessionCount >= minimumSessionCount && hasEverCustomized {
            print("   ✅ Eligible: \(sessionCount) sessions and customized")
            return true
        }
        
        // 3. 7+ day streak (with at least one session > 1 minute per day) - requires customization
        if currentStreak >= minimumStreakDays && hasEverCustomized {
            print("   ✅ Eligible: \(currentStreak) day streak and customized")
            return true
        }
        
        print("   ❌ Not eligible: sessionCount=\(sessionCount), streak=\(currentStreak), customized=\(hasEverCustomized)")
        return false
    }
    
    private func canShowPrompt() -> Bool {
        // Check if we've exceeded max prompts per year
        let promptCount = userDefaults.integer(forKey: promptCountKey)
        if promptCount >= maxPromptsPerYear {
            // Check if it's been a year since last prompt
            if let lastDate = userDefaults.object(forKey: lastPromptDateKey) as? Date {
                let calendar = Calendar.current
                if let daysSince = calendar.dateComponents([.day], from: lastDate, to: Date()).day,
                   daysSince < 365 {
                    return false
                }
            }
        }
        
        return true
    }
    
    private func showReviewPrompt() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            print("⚠️ ReviewPromptService: Could not get window scene")
            return
        }
        
        // Update tracking
        let currentCount = userDefaults.integer(forKey: promptCountKey)
        userDefaults.set(currentCount + 1, forKey: promptCountKey)
        userDefaults.set(Date(), forKey: lastPromptDateKey)
        
        print("✅ ReviewPromptService: Requesting review prompt (count: \(currentCount + 1))")
        
        // Show the review prompt
        SKStoreReviewController.requestReview(in: windowScene)
        
        // Log analytics
        AnalyticsService.shared.logButtonTap("review_prompt_shown")
    }
    
    private func hasReviewed() -> Bool {
        return userDefaults.bool(forKey: hasReviewedKey)
    }
    
    private func hasDismissedPermanently() -> Bool {
        return userDefaults.bool(forKey: hasDismissedPermanentlyKey)
    }
}

