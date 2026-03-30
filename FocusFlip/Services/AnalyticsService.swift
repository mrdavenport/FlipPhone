import Foundation

#if canImport(FirebaseAnalytics)
import FirebaseAnalytics
#endif

class AnalyticsService {
    static let shared = AnalyticsService()
    
    private init() {}
    
    // MARK: - Screen Views
    func logScreenView(_ screenName: String) {
        #if canImport(FirebaseAnalytics)
        Analytics.logEvent(AnalyticsEventScreenView, parameters: [
            AnalyticsParameterScreenName: screenName
        ])
        #else
        print("📊 [Analytics] Screen view: \(screenName)")
        #endif
    }
    
    // MARK: - Session Events
    func logSessionStart() {
        #if canImport(FirebaseAnalytics)
        Analytics.logEvent("session_start", parameters: nil)
        #else
        print("📊 [Analytics] Session started")
        #endif
    }
    
    func logSessionComplete(duration: TimeInterval, points: Int, category: String) {
        #if canImport(FirebaseAnalytics)
        Analytics.logEvent("session_complete", parameters: [
            "duration_seconds": duration,
            "points": points,
            "category": category
        ])
        #else
        print("📊 [Analytics] Session completed: \(duration)s, \(points) pts, \(category)")
        #endif
    }
    
    // MARK: - User Actions
    func logCategorySelected(_ category: String) {
        #if canImport(FirebaseAnalytics)
        Analytics.logEvent("category_selected", parameters: [
            "category": category
        ])
        #else
        print("📊 [Analytics] Category selected: \(category)")
        #endif
    }
    
    func logTimeframeChanged(_ timeframe: String) {
        #if canImport(FirebaseAnalytics)
        Analytics.logEvent("timeframe_changed", parameters: [
            "timeframe": timeframe
        ])
        #else
        print("📊 [Analytics] Timeframe changed: \(timeframe)")
        #endif
    }
    
    func logButtonTap(_ buttonName: String) {
        #if canImport(FirebaseAnalytics)
        Analytics.logEvent("button_tap", parameters: [
            "button_name": buttonName
        ])
        #else
        print("📊 [Analytics] Button tapped: \(buttonName)")
        #endif
    }
    
    func logShareSession() {
        #if canImport(FirebaseAnalytics)
        Analytics.logEvent("share_session", parameters: nil)
        #else
        print("📊 [Analytics] Session shared")
        #endif
    }
    
    func logFeedbackSubmitted() {
        #if canImport(FirebaseAnalytics)
        Analytics.logEvent("feedback_submitted", parameters: nil)
        #else
        print("📊 [Analytics] Feedback submitted")
        #endif
    }
    
    func logPersonalBestAchieved(duration: TimeInterval) {
        #if canImport(FirebaseAnalytics)
        Analytics.logEvent("personal_best_achieved", parameters: [
            "duration_seconds": duration
        ])
        #else
        print("📊 [Analytics] Personal best achieved: \(duration)s")
        #endif
    }
}



