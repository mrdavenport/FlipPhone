//
//  FocusFlipApp.swift
//  FocusFlip
//
//  Created by Zack Davenport on 11/7/25.
//

import SwiftUI
import SwiftData
import UIKit

@main
struct FlipPhoneApp: App {
    @State private var showSplash = true
    @State private var showThankYou = false
    
    init() {
        // Ensure idle timer is enabled when app launches
        UIApplication.shared.isIdleTimerDisabled = false
        // Diagnostic: always log whether .riv files are in the bundle (so we see logs even if Rive SDK isn’t linked)
        let heroURL = Bundle.main.url(forResource: "flipphone_hero", withExtension: "riv")
        let logoURL = Bundle.main.url(forResource: "flipphone_logo", withExtension: "riv")
        print("📦 [Bundle] flipphone_hero.riv in bundle: \(heroURL != nil ? "YES" : "NO") \(heroURL.map { $0.path } ?? "")")
        print("📦 [Bundle] flipphone_logo.riv in bundle: \(logoURL != nil ? "YES" : "NO") \(logoURL.map { $0.path } ?? "")")
        if heroURL == nil || logoURL == nil, let resourcePath = Bundle.main.resourcePath {
            let contents = (try? FileManager.default.contentsOfDirectory(atPath: resourcePath)) ?? []
            let rivs = contents.filter { $0.hasSuffix(".riv") }
            print("📦 [Bundle] Resource path: \(resourcePath)")
            print("📦 [Bundle] .riv files at bundle root: \(rivs)")
        }
        // Pre-warm Rive files in the background during the splash screen window (~2 s).
        #if canImport(RiveRuntime)
        RivePrewarmCache.shared.prewarm(fileName: "flipphone_hero")
        RivePrewarmCache.shared.prewarm(fileName: "flipphone_logo")
        #endif
    }
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            FocusSession.self,
            User.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // Log the error for debugging but don't delete user data
            print("❌ ModelContainer creation failed: \(error)")
            print("   Error details: \(error.localizedDescription)")
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
    var body: some Scene {
        WindowGroup {
            Group {
                if showSplash {
                    SplashScreenView(isPresented: $showSplash)
                } else if showThankYou {
                    ThankYouView(isPresented: $showThankYou)
                } else {
                    ContentView()
                        .onAppear {
                            // Check if we should show thank you screen when content appears
                            if Bundle.main.isTestFlight && !showThankYou {
                                showThankYou = true
                            }
                        }
                }
            }
            .preferredColorScheme(.dark) // Force dark mode across entire app
            .onChange(of: showSplash) { _, newValue in
                // When splash screen dismisses, check if we should show thank you
                if !newValue && Bundle.main.isTestFlight {
                    // Small delay to ensure smooth transition
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        showThankYou = true
                    }
                }
            }
        }
        .modelContainer(sharedModelContainer)
    }
}
