import Foundation
import AVFoundation
import UIKit
import AudioToolbox

final class AudioService {
    static let shared = AudioService()
    
    private var startChimePlayer: AVAudioPlayer?
    private var cancelChimePlayer: AVAudioPlayer?
    private var endChimePlayer: AVAudioPlayer?
    private var celebrationChimePlayer: AVAudioPlayer?
    
    private let userDefaults = UserDefaults.standard
    private let soundEffectsEnabledKey = "soundEffectsEnabled"
    
    // Custom sound file names - add these files to your project bundle
    // Supported formats: .caf, .m4a, .mp3, .wav
    private let startSoundFileName = "session-start"
    private let cancelSoundFileName = "session-cancel"
    private let endSoundFileName = "session-end"
    private let celebrationSoundFileName = "milestone-celebration"
    
    private init() {
        setupAudioSession()
        loadSounds()
    }
    
    // MARK: - Public Methods
    
    /// Check if sound effects are enabled
    var isSoundEffectsEnabled: Bool {
        get {
            // Default to true if not set
            if userDefaults.object(forKey: soundEffectsEnabledKey) == nil {
                return true
            }
            return userDefaults.bool(forKey: soundEffectsEnabledKey)
        }
        set {
            userDefaults.set(newValue, forKey: soundEffectsEnabledKey)
        }
    }
    
    /// Play the session start chime
    func playStartChime() {
        guard isSoundEffectsEnabled else { return }
        
        // Try custom sound first, fallback to system sound
        if let player = startChimePlayer {
            player.currentTime = 0
            player.play()
        } else {
            // Fallback to system sound
            AudioServicesPlaySystemSound(1000) // New Mail sound
        }
    }
    
    /// Play the session cancel chime
    func playCancelChime() {
        guard isSoundEffectsEnabled else { return }
        
        // Try custom sound first, fallback to system sound
        if let player = cancelChimePlayer {
            player.currentTime = 0
            player.play()
        } else {
            // Fallback to system sound
            AudioServicesPlaySystemSound(1001) // Mail Sent sound
        }
    }
    
    /// Play the session completion chime
    func playEndChime() {
        guard isSoundEffectsEnabled else { return }
        
        // Try custom sound first, fallback to system sound
        if let player = endChimePlayer {
            player.currentTime = 0
            player.play()
        } else {
            // Fallback to system sound
            AudioServicesPlaySystemSound(1054) // Tink success sound
        }
    }
    
    /// Play a celebration fanfare when a new daily milestone badge is unlocked.
    /// Drop a custom "milestone-celebration" audio file into the SFX folder to override.
    func playCelebrationChime() {
        guard isSoundEffectsEnabled else { return }
        
        if let player = celebrationChimePlayer {
            player.currentTime = 0
            player.play()
        } else {
            // Fanfare-style system sound fallback
            AudioServicesPlaySystemSound(1322)
        }
    }
    
    // MARK: - Private Methods
    
    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            // Silently fail - audio will fall back to system sounds
        }
    }
    
    private func loadSounds() {
        // Try to load custom sound files
        // Try .caf and .m4a first (most compatible), then .wav, then .mp3
        // Note: .mp3 files may have format issues - prefer .caf or .m4a
        let soundExtensions = ["caf", "m4a", "wav", "mp3"]
        
        // Load start sound
        startChimePlayer = loadSoundFile(named: startSoundFileName, extensions: soundExtensions)
        
        // Load cancel sound
        cancelChimePlayer = loadSoundFile(named: cancelSoundFileName, extensions: soundExtensions)
        
        // Load end sound
        endChimePlayer = loadSoundFile(named: endSoundFileName, extensions: soundExtensions)
        
        // Load celebration sound
        celebrationChimePlayer = loadSoundFile(named: celebrationSoundFileName, extensions: soundExtensions)
    }
    
    private func loadSoundFile(named fileName: String, extensions: [String]) -> AVAudioPlayer? {
        for ext in extensions {
            // Try direct path first
            if let url = Bundle.main.url(forResource: fileName, withExtension: ext) {
                if let player = try? AVAudioPlayer(contentsOf: url) {
                    player.prepareToPlay()
                    return player
                }
            }
            // Try in SFX subfolder
            if let url = Bundle.main.url(forResource: fileName, withExtension: ext, subdirectory: "SFX") {
                if let player = try? AVAudioPlayer(contentsOf: url) {
                    player.prepareToPlay()
                    return player
                }
            }
        }
        return nil
    }
    
}

