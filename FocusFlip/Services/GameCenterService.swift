import Foundation
import GameKit

@MainActor
class GameCenterService: ObservableObject {
    static let shared = GameCenterService()
    
    @Published var isAuthenticated = false
    @Published var localPlayer: GKLocalPlayer?
    
    // Leaderboard ID - will be set after creating in App Store Connect
    // Update this with your actual leaderboard ID from App Store Connect
    let leaderboardID = "weekly_focus_time" // TODO: Update with actual ID
    
    private init() {
        authenticatePlayer()
    }
    
    func authenticatePlayer() {
        let localPlayer = GKLocalPlayer.local
        
        print("🔵 authenticatePlayer() called")
        
        // If already authenticated, update state and return
        if localPlayer.isAuthenticated {
            print("✅ Game Center already authenticated: \(localPlayer.displayName)")
            isAuthenticated = true
            self.localPlayer = localPlayer
            return
        }
        
        print("🔵 Setting authentication handler...")
        
        // Set authentication handler
        localPlayer.authenticateHandler = { [weak self] viewController, error in
            print("🔵 Authentication handler called - viewController: \(viewController != nil), error: \(error?.localizedDescription ?? "none")")
            
            Task { @MainActor in
                if let viewController = viewController {
                    print("🔵 Presenting Game Center authentication view controller")
                    // Present authentication view controller on main thread
                    await self?.presentAuthenticationViewController(viewController)
                    return
                }
                
                if let error = error {
                    print("⚠️ Game Center authentication error: \(error.localizedDescription)")
                    self?.isAuthenticated = false
                    return
                }
                
                if localPlayer.isAuthenticated {
                    print("✅ Game Center authenticated: \(localPlayer.displayName)")
                    self?.isAuthenticated = true
                    self?.localPlayer = localPlayer
                } else {
                    print("ℹ️ Game Center not authenticated (user may have declined)")
                    self?.isAuthenticated = false
                    self?.localPlayer = nil
                }
            }
        }
        
        // Check if we're on simulator (Game Center doesn't work on simulator)
        #if targetEnvironment(simulator)
        print("⚠️ Game Center authentication may not work on iOS Simulator. Please test on a physical device.")
        #endif
        
        // The handler will be called automatically by Game Center
        // We don't need to manually trigger it
    }
    
    @MainActor
    private func presentAuthenticationViewController(_ viewController: UIViewController) async {
        // Use DispatchQueue to ensure we're on the main thread
        DispatchQueue.main.async {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let rootViewController = windowScene.windows.first?.rootViewController else {
                print("⚠️ Could not find root view controller to present Game Center authentication")
                return
            }
            
            // Find the topmost presented view controller
            var topController = rootViewController
            while let presented = topController.presentedViewController {
                topController = presented
            }
            
            // Present the Game Center authentication view controller
            topController.present(viewController, animated: true) {
                print("✅ Game Center authentication view controller presented")
            }
        }
    }
    
    func submitWeeklyFocusTime(_ totalSeconds: TimeInterval) {
        guard isAuthenticated else {
            print("⚠️ Cannot submit score: Not authenticated with Game Center")
            return
        }
        
        // Convert to Int64 (Game Center scores are Int64)
        // Using seconds as the score value
        let score = Int64(totalSeconds)
        
        let scoreReporter = GKScore(leaderboardIdentifier: leaderboardID)
        scoreReporter.value = score
        
        GKScore.report([scoreReporter]) { error in
            if let error = error {
                print("⚠️ Failed to submit Game Center score: \(error.localizedDescription)")
            } else {
                print("✅ Submitted weekly focus time: \(score) seconds")
            }
        }
    }
    
    func loadLeaderboard(completion: @escaping (Result<[GKLeaderboard.Entry], Error>) -> Void) {
        guard isAuthenticated else {
            completion(.failure(GameCenterError.notAuthenticated))
            return
        }
        
        print("🔵 Loading leaderboard with ID: \(leaderboardID)")
        
        // Create leaderboard with identifier
        let leaderboard = GKLeaderboard()
        leaderboard.identifier = leaderboardID
        
        // First, try to load just the local player entry
        leaderboard.loadEntries(for: [GKLocalPlayer.local], timeScope: .allTime) { [weak self] localPlayerEntry, _, localError in
            guard let self = self else { return }
            
            if let localError = localError {
                print("⚠️ Error loading local player entry: \(localError.localizedDescription)")
                if let nsError = localError as NSError? {
                    print("   Error domain: \(nsError.domain), code: \(nsError.code)")
                }
                // Try to continue with friends anyway
            }
            
            var allEntries: [GKLeaderboard.Entry] = []
            
            // Add local player entry if available
            if let localEntry = localPlayerEntry {
                print("✅ Found local player entry with score: \(localEntry.score)")
                allEntries.append(localEntry)
            }
            
            // Now try to load friends
            GKLocalPlayer.local.loadFriends { friends, friendsError in
                if let friendsError = friendsError {
                    print("⚠️ Error loading friends: \(friendsError.localizedDescription)")
                    // Return what we have (just local player)
                    allEntries.sort { $0.score > $1.score }
                    print("✅ Returning \(allEntries.count) entries (local player only)")
                    completion(.success(allEntries))
                    return
                }
                
                guard let friends = friends, !friends.isEmpty else {
                    print("ℹ️ No friends found")
                    // Return what we have (just local player)
                    allEntries.sort { $0.score > $1.score }
                    print("✅ Returning \(allEntries.count) entries (local player only, no friends)")
                    completion(.success(allEntries))
                    return
                }
                
                print("🔵 Loading entries for \(friends.count) friends")
                
                // Load entries for friends
                let friendsLeaderboard = GKLeaderboard()
                friendsLeaderboard.identifier = self.leaderboardID
                friendsLeaderboard.loadEntries(for: friends, timeScope: .allTime) { _, friendEntries, friendError in
                    if let friendError = friendError {
                        print("⚠️ Error loading friend entries: \(friendError.localizedDescription)")
                        // Return what we have (just local player)
                        allEntries.sort { $0.score > $1.score }
                        completion(.success(allEntries))
                        return
                    }
                    
                    // Add friend entries if available
                    if let friendEntries = friendEntries, !friendEntries.isEmpty {
                        print("✅ Found \(friendEntries.count) friend entries")
                        allEntries.append(contentsOf: friendEntries)
                    }
                    
                    // Sort by score (descending - highest first)
                    allEntries.sort { $0.score > $1.score }
                    
                    print("✅ Loaded \(allEntries.count) total leaderboard entries")
                    completion(.success(allEntries))
                }
            }
        }
    }
    
    func calculateWeeklyFocusTime(from sessions: [FocusSession]) -> TimeInterval {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        
        guard let weekStart = calendar.date(byAdding: .day, value: -6, to: today) else {
            return 0
        }
        
        let weekEnd = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        
        return sessions
            .filter { $0.endTime >= weekStart && $0.endTime < weekEnd }
            .reduce(0) { $0 + $1.duration }
    }
}

enum GameCenterError: LocalizedError {
    case notAuthenticated
    case leaderboardNotFound
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Please sign in to Game Center to view leaderboards"
        case .leaderboardNotFound:
            return "Leaderboard not found"
        }
    }
}

