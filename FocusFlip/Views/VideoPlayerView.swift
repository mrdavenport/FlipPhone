import SwiftUI
import AVKit
import AVFoundation

struct VideoPlayerView: UIViewRepresentable {
    let videoName: String
    let videoExtension: String
    
    func makeUIView(context: Context) -> VideoContainerView {
        let containerView = VideoContainerView()
        containerView.backgroundColor = .clear
        
        // Try to find the video file
        guard let url = Bundle.main.url(forResource: videoName, withExtension: videoExtension) else {
            print("⚠️ Video file not found: \(videoName).\(videoExtension)")
            // Try listing bundle contents for debugging
            if let resourcePath = Bundle.main.resourcePath {
                print("📦 Bundle path: \(resourcePath)")
                if let contents = try? FileManager.default.contentsOfDirectory(atPath: resourcePath) {
                    print("📋 Bundle contents: \(contents.filter { $0.contains("logo") || $0.contains(".mp4") })")
                }
            }
            return containerView
        }
        
        print("✅ Found video at: \(url.path)")
        
        let player = AVPlayer(url: url)
        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspect
        playerLayer.frame = containerView.bounds
        
        // Mute for autoplay (iOS requirement)
        player.isMuted = true
        
        containerView.layer.addSublayer(playerLayer)
        containerView.playerLayer = playerLayer
        
        // Auto-play and loop
        player.actionAtItemEnd = .none
        let observer = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { _ in
            player.seek(to: .zero)
            player.play()
        }
        
        // Start playing
        DispatchQueue.main.async {
            player.play()
        }
        
        // Store player and observer in context for cleanup
        context.coordinator.player = player
        context.coordinator.playerLayer = playerLayer
        context.coordinator.observer = observer
        context.coordinator.containerView = containerView
        
        return containerView
    }
    
    func updateUIView(_ uiView: VideoContainerView, context: Context) {
        // Update frame when view size changes
        DispatchQueue.main.async {
            if let playerLayer = context.coordinator.playerLayer {
                playerLayer.frame = uiView.bounds
            }
        }
    }
    
    static func dismantleUIView(_ uiView: VideoContainerView, coordinator: Coordinator) {
        coordinator.player?.pause()
        coordinator.player = nil
        if let observer = coordinator.observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject {
        var player: AVPlayer?
        var playerLayer: AVPlayerLayer?
        var observer: NSObjectProtocol?
        var containerView: VideoContainerView?
    }
}

// Custom UIView that handles layout updates
class VideoContainerView: UIView {
    var playerLayer: AVPlayerLayer?
    
    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer?.frame = bounds
    }
}

