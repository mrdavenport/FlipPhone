import SwiftUI
import GameKit
import ObjectiveC

struct LeaderboardView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var gameCenterService = GameCenterService.shared
    @State private var leaderboardEntries: [GKLeaderboard.Entry] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var playerPhoto: UIImage?
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else if let errorMessage = errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 48))
                            .foregroundColor(.white.opacity(0.6))
                        
                        Text(errorMessage)
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        
                        if !gameCenterService.isAuthenticated {
                            VStack(spacing: 12) {
                                Button("Sign In to Game Center") {
                                    print("🔵 Sign In button tapped")
                                    gameCenterService.authenticatePlayer()
                                    // Check authentication status after a brief delay
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                        if gameCenterService.isAuthenticated {
                                            loadLeaderboard()
                                        }
                                    }
                                }
                                
                                Button("Open Game Center") {
                                    openGameCenterDashboard()
                                }
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.7))
                            }
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.69, green: 0.49, blue: 1.0),
                                        Color(red: 0.55, green: 0.39, blue: 1.0)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(24)
                        }
                    }
                } else if leaderboardEntries.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.white.opacity(0.6))
                        
                        Text("No friends on the leaderboard yet")
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        
                        Text("Add friends in Game Center to compete!")
                            .font(.system(size: 14, design: .rounded))
                            .foregroundColor(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            // Game Center Profile Header
                            if let localPlayer = gameCenterService.localPlayer {
                                GameCenterProfileHeader(
                                    player: localPlayer,
                                    photo: playerPhoto,
                                    onTap: {
                                        openGameCenterDashboard()
                                    }
                                )
                                .padding(.top, 20)
                                .padding(.bottom, 8)
                            }
                            
                            // Header
                            VStack(spacing: 8) {
                                Text("Weekly Focus Time")
                                    .font(.system(size: 24, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                
                                Text("Compete with friends")
                                    .font(.system(size: 14, design: .rounded))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                            .padding(.top, 8)
                            .padding(.bottom, 24)
                            
                            // Leaderboard entries
                            ForEach(Array(leaderboardEntries.enumerated()), id: \.element.player.gamePlayerID) { index, entry in
                                LeaderboardRow(
                                    rank: index + 1,
                                    entry: entry,
                                    isCurrentPlayer: entry.player.gamePlayerID == gameCenterService.localPlayer?.gamePlayerID
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 32)
                    }
                }
            }
            .navigationTitle("Leaderboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
            .onAppear {
                loadLeaderboard()
                loadPlayerPhoto()
            }
            .onChange(of: gameCenterService.isAuthenticated) { _, newValue in
                if newValue {
                    loadLeaderboard()
                    loadPlayerPhoto()
                }
            }
            .onChange(of: gameCenterService.localPlayer) { _, _ in
                loadPlayerPhoto()
            }
        }
    }
    
    private func loadLeaderboard() {
        isLoading = true
        errorMessage = nil
        
        if !gameCenterService.isAuthenticated {
            gameCenterService.authenticatePlayer()
            // Wait a moment for authentication
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if gameCenterService.isAuthenticated {
                    performLoad()
                } else {
                    isLoading = false
                    errorMessage = "Please sign in to Game Center to view leaderboards"
                }
            }
        } else {
            performLoad()
        }
    }
    
    private func performLoad() {
        gameCenterService.loadLeaderboard { result in
            isLoading = false
            
            switch result {
            case .success(let entries):
                leaderboardEntries = entries
            case .failure(let error):
                errorMessage = error.localizedDescription
                leaderboardEntries = []
            }
        }
    }
    
    private func loadPlayerPhoto() {
        guard let localPlayer = gameCenterService.localPlayer else {
            playerPhoto = nil
            return
        }
        
        // Load player photo
        localPlayer.loadPhoto(for: .normal) { photo, error in
            DispatchQueue.main.async {
                if let photo = photo {
                    self.playerPhoto = photo
                } else {
                    self.playerPhoto = nil
                }
            }
        }
    }
    
    private func openGameCenterDashboard() {
        guard gameCenterService.localPlayer != nil else { return }
        
        // Use GKGameCenterViewController for proper Game Center dashboard
        let gameCenterViewController = GKGameCenterViewController(
            leaderboardID: gameCenterService.leaderboardID,
            playerScope: .friendsOnly,
            timeScope: .allTime
        )
        
        let delegate = GameCenterDelegate {
            gameCenterViewController.dismiss(animated: true)
        }
        gameCenterViewController.gameCenterDelegate = delegate
        
        // Retain the delegate
        objc_setAssociatedObject(gameCenterViewController, "delegate", delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            var topController = rootViewController
            while let presented = topController.presentedViewController {
                topController = presented
            }
            topController.present(gameCenterViewController, animated: true)
        }
    }
}

// Game Center Delegate for GKGameCenterViewController
class GameCenterDelegate: NSObject, GKGameCenterControllerDelegate {
    let onDismiss: () -> Void
    
    init(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
    }
    
    func gameCenterViewControllerDidFinish(_ gameCenterViewController: GKGameCenterViewController) {
        onDismiss()
    }
}

// Game Center Profile Header Component
struct GameCenterProfileHeader: View {
    let player: GKLocalPlayer
    let photo: UIImage?
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 12) {
                // Profile Picture
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.69, green: 0.49, blue: 1.0),
                                    Color(red: 0.55, green: 0.39, blue: 1.0)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 80, height: 80)
                    
                    if let photo = photo {
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 80, height: 80)
                            .clipShape(Circle())
                    } else {
                        // Fallback to initials
                        Text(String(player.displayName.prefix(1)).uppercased())
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                }
                
                // Username
                Text(player.displayName)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                
                // Game Center Label
                HStack(spacing: 6) {
                    // Game Center icon (two overlapping circles)
                    ZStack {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 12, height: 12)
                            .offset(x: -3)
                        Circle()
                            .fill(Color.pink)
                            .frame(width: 12, height: 12)
                            .offset(x: 3)
                    }
                    .frame(width: 20, height: 12)
                    
                    Text("Game Center")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct LeaderboardRow: View {
    let rank: Int
    let entry: GKLeaderboard.Entry
    let isCurrentPlayer: Bool
    
    var body: some View {
        HStack(spacing: 16) {
            // Rank
            Text("\(rank)")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(isCurrentPlayer ? Color(red: 0.69, green: 0.49, blue: 1.0) : .white.opacity(0.6))
                .frame(width: 32)
            
            // Player avatar/initials
            ZStack {
                Circle()
                    .fill(isCurrentPlayer ? Color(red: 0.69, green: 0.49, blue: 1.0).opacity(0.3) : Color.white.opacity(0.1))
                    .frame(width: 44, height: 44)
                
                if isCurrentPlayer {
                    Image(systemName: "person.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Color(red: 0.69, green: 0.49, blue: 1.0))
                } else {
                    Text(String(entry.player.displayName.prefix(1)).uppercased())
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                }
            }
            
            // Player name
            Text(entry.player.displayName)
                .font(.system(size: 16, weight: isCurrentPlayer ? .semibold : .regular, design: .rounded))
                .foregroundColor(isCurrentPlayer ? .white : .white.opacity(0.9))
            
            Spacer()
            
            // Score (formatted as time)
            Text(formatTime(Int64(entry.score)))
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(isCurrentPlayer ? Color(red: 0.69, green: 0.49, blue: 1.0) : .white.opacity(0.8))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(isCurrentPlayer ? Color.white.opacity(0.08) : Color.white.opacity(0.04))
        .cornerRadius(16)
    }
    
    private func formatTime(_ seconds: Int64) -> String {
        let hours = Int(seconds) / 3600
        let minutes = Int(seconds) / 60 % 60
        
        if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        } else {
            return "\(minutes)m"
        }
    }
}

