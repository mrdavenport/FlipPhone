import SwiftUI

struct InfoView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            // Split background: light blue top, vibrant green bottom
            VStack(spacing: 0) {
                // Light blue top section (sky blue)
                Color(red: 0.85, green: 0.95, blue: 1.0)
                    .frame(maxHeight: .infinity)
                
                // Vibrant green bottom section (lime green)
                Color(red: 0.5, green: 0.95, blue: 0.3)
                    .frame(maxHeight: .infinity)
            }
            .ignoresSafeArea()
            
            // Background texture overlay
            Group {
                if let texture = loadImage(named: "bg-texture") {
                    Image(uiImage: texture)
                        .resizable()
                        .scaledToFill()
                        .opacity(0.4)
                        .ignoresSafeArea()
                }
            }
            
            // Main content
            VStack(spacing: 0) {
                Spacer()
                
                // "FLIP PHONE" text at top (with PHONE mirrored)
                HStack(spacing: 4) {
                    Text("FLIP")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text("PHONE")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .scaleEffect(x: -1, y: 1) // Mirror horizontally
                }
                .padding(.top, 60)
                .padding(.bottom, 40)
                
                Spacer()
                
                // Central panel with phone image
                ZStack {
                    // Phone on table image
                    if let phoneImage = loadImage(named: "phone-on-table") {
                        Image(uiImage: phoneImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 320, maxHeight: 400)
                            .clipShape(RoundedRectangle(cornerRadius: 24))
                            .rotationEffect(.degrees(-8)) // Slight tilt
                            .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
                    } else {
                        // Fallback if image not found
                        RoundedRectangle(cornerRadius: 24)
                            .fill(Color.white.opacity(0.2))
                            .frame(width: 320, height: 400)
                            .rotationEffect(.degrees(-8))
                    }
                    
                    // Purple arrow overlay
                    if let arrowImage = loadImage(named: "arrow-overlay") {
                        Image(uiImage: arrowImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 120, height: 120)
                            .offset(x: -100, y: -50)
                    }
                }
                .padding(.vertical, 40)
                
                Spacer()
                
                // Bottom green button with attribution
                VStack(spacing: 4) {
                    Text("Built and designed by")
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundColor(.white.opacity(0.7))
                    
                    Text("Zack Davenport")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.3, green: 0.8, blue: 0.4),
                                    Color(red: 0.4, green: 0.9, blue: 0.5)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                )
                .padding(.bottom, 60)
            }
        }
        .overlay(alignment: .topTrailing) {
            // Close button
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.2))
                    .clipShape(Circle())
            }
            .padding(.top, 20)
            .padding(.trailing, 20)
        }
    }
    
    // Helper function to load images from bundle
    private func loadImage(named name: String) -> UIImage? {
        // Try 1: Standard Assets.xcassets lookup (if in .imageset)
        if let image = UIImage(named: name) {
            return image
        }
        
        // Try 2: Load from Heroi folder in Assets.xcassets (if files are accessible)
        // Note: This won't work if files aren't in .imageset folders
        // But we'll try the bundle path approach
        
        // Try 3: Load from main bundle with the exact filename
        if let imagePath = Bundle.main.path(forResource: name, ofType: "png"),
           let image = UIImage(contentsOfFile: imagePath) {
            return image
        }
        
        // Try 4: Load from Website/Assets folder if it's in the bundle
        if let imagePath = Bundle.main.path(forResource: name, ofType: "png", inDirectory: "Website/Assets"),
           let image = UIImage(contentsOfFile: imagePath) {
            return image
        }
        
        // Debug: Print available bundle resources
        #if DEBUG
        if let resourcePath = Bundle.main.resourcePath {
            print("📦 Available resources in bundle: \(try? FileManager.default.contentsOfDirectory(atPath: resourcePath)) ?? [])")
        }
        #endif
        
        return nil
    }
}

#Preview {
    InfoView()
}



