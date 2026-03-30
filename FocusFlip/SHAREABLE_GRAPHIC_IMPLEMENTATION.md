# Shareable Graphic Implementation Guide

## Overview
Create a downloadable, shareable graphic that matches the SessionResultView design with dynamic content (session time, description, category, color, milestone status, etc.).

## Implementation Steps

### 1. Create a Shareable Graphic View Component

**File: `FocusFlip/Views/ShareableGraphicView.swift`**

Create a new SwiftUI view that replicates the design from `SessionResultView.completionContent`, but optimized for image rendering:

```swift
struct ShareableGraphicView: View {
    let session: FocusSession
    let milestone: Milestone?
    let categoryColor: Color
    let isFirstTimeAchievingMilestone: Bool
    
    // Fixed dimensions for the graphic (e.g., 1080x1080 for square, or 1080x1350 for story format)
    let graphicSize: CGSize
    
    var body: some View {
        // Replicate the design from completionContent
        // Key differences:
        // - No interactive elements (buttons, etc.)
        // - Static Rive animation frame (or exported PNG)
        // - Fixed dimensions
        // - Optimized for image export
    }
}
```

**Key Considerations:**
- Use fixed dimensions (e.g., 1080x1080px for Instagram square, 1080x1920 for stories)
- Remove interactive elements (buttons, gestures)
- Handle Rive animations: either export a static frame or use a screenshot approach
- Match the visual design exactly from `completionContent`

### 2. SwiftUI View to UIImage Conversion

**Option A: Using `UIViewRepresentable` + `snapshot()` (Recommended)**
- Wrap the SwiftUI view in a `UIViewRepresentable`
- Use `snapshot()` method on the UIView to capture the image
- Works well for static content

**Option B: Using `ImageRenderer` (iOS 16+)**
- Use SwiftUI's built-in `ImageRenderer` API
- More modern and SwiftUI-native
- Better for async rendering

**File: `FocusFlip/Utils/ViewToImageRenderer.swift`**

```swift
import SwiftUI

@available(iOS 16.0, *)
struct ViewToImageRenderer {
    static func render<Content: View>(
        _ content: Content,
        size: CGSize,
        scale: CGFloat = 3.0 // For retina quality
    ) -> UIImage? {
        let renderer = ImageRenderer(content: content)
        renderer.scale = scale
        
        // Configure the view size
        // ... render logic
        
        return renderer.uiImage
    }
}
```

**Option C: Using `UIGraphicsImageRenderer` (For complex cases)**
- More control but more manual work
- Good for combining multiple views or adding overlays

### 3. Handle Rive Animation in the Graphic

**Challenge:** Rive animations can't be easily captured as static images.

**Solutions:**

**Option 1: Static Badge Image (Recommended)**
- Export badge designs as PNG/SVG from Rive
- Use the badge SVG files you already have in `FocusFlip/Badges/`
- Load and render the appropriate badge based on `milestone.badgeShape`
- Apply category color replacement (you already have this logic)

**Option 2: Capture Rive Frame**
- Wait for animation to reach a specific frame
- Use `UIView.snapshotView(afterScreenUpdates:)` to capture
- More complex but preserves animation look

**Option 3: Skip Rive, Use Static Design**
- Design a static version that matches the animated design
- Simpler but may look different

### 4. Update Share Functionality

**File: `FocusFlip/Views/SessionResultView.swift`**

Modify the `shareSession()` function:

```swift
private func shareSession() {
    AnalyticsService.shared.logShareSession()
    
    // Generate the shareable graphic
    if let image = generateShareableGraphic() {
        // Share the image instead of just text
        showShareSheet = true
        shareImage = image
    } else {
        // Fallback to text sharing
        showShareSheet = true
    }
}

private func generateShareableGraphic() -> UIImage? {
    // Create the shareable graphic view
    let graphicView = ShareableGraphicView(
        session: session,
        milestone: sessionMilestone,
        categoryColor: selectedCategory.color,
        isFirstTimeAchievingMilestone: isFirstTimeAchievingThisMilestone,
        graphicSize: CGSize(width: 1080, height: 1080) // Or your preferred size
    )
    
    // Convert to UIImage
    return ViewToImageRenderer.render(graphicView, size: CGSize(width: 1080, height: 1080))
}
```

**Update ShareSheet usage:**

```swift
.sheet(isPresented: $showShareSheet) {
    if let image = shareImage {
        ShareSheet(activityItems: [image])
    } else {
        ShareSheet(activityItems: [generateShareText()])
    }
}
```

### 5. Implementation Checklist

#### Phase 1: Core Structure
- [ ] Create `ShareableGraphicView.swift`
- [ ] Replicate the layout from `completionContent` (card design, spacing, typography)
- [ ] Set fixed dimensions for the graphic
- [ ] Test that the view renders correctly in preview

#### Phase 2: Dynamic Content
- [ ] Pass session data (duration, category, note)
- [ ] Pass milestone data (if applicable)
- [ ] Apply category color dynamically
- [ ] Display milestone badge (using SVG from Badges folder)
- [ ] Show milestone title or regular completion message
- [ ] Format date/time correctly

#### Phase 3: Image Rendering
- [ ] Create `ViewToImageRenderer.swift` utility
- [ ] Implement view-to-UIImage conversion
- [ ] Test rendering quality (ensure @3x scale for retina)
- [ ] Handle edge cases (very long text, different milestone types)

#### Phase 4: Rive/Badge Handling
- [ ] Decide on approach (static SVG vs captured frame)
- [ ] Implement badge loading with color replacement (reuse existing logic)
- [ ] Position badge correctly in graphic
- [ ] Handle milestone vs non-milestone cases

#### Phase 5: Integration
- [ ] Update `shareSession()` function
- [ ] Add state variable for share image (`@State private var shareImage: UIImage?`)
- [ ] Update ShareSheet to accept UIImage
- [ ] Add error handling/fallback to text sharing
- [ ] Test sharing to different apps (Messages, Instagram, Twitter, etc.)

#### Phase 6: Polish
- [ ] Optimize image file size (consider compression)
- [ ] Ensure text is readable at different sizes
- [ ] Test on different device sizes
- [ ] Add loading indicator while generating graphic
- [ ] Handle long text gracefully (truncation/line wrapping)

### 6. Technical Considerations

**Image Dimensions:**
- **Square (1:1):** 1080x1080px - Good for Instagram posts, general sharing
- **Story (9:16):** 1080x1920px - Good for Instagram Stories, Snapchat
- **4:5:** 1080x1350px - Good for Instagram portrait posts
- Consider making it configurable or defaulting to square

**Text Handling:**
- Long notes might overflow - add truncation or multi-line handling
- Ensure fonts scale appropriately for the graphic size
- Consider minimum font sizes for readability

**Color Accuracy:**
- Ensure colors match exactly between view and graphic
- Test on different devices/color profiles
- Consider sRGB color space for consistent sharing

**Performance:**
- Image generation might take 100-500ms
- Consider async generation with loading indicator
- Cache generated images if user shares multiple times

**Rive Animation:**
- Since Rive can't be easily captured, use static badge SVGs
- Reuse `loadSVGWithColorReplacement` function from `MilestonesView`
- Match the badge size and positioning from the animation

### 7. File Structure

```
FocusFlip/
├── Views/
│   ├── SessionResultView.swift (update shareSession)
│   └── ShareableGraphicView.swift (new)
├── Utils/
│   └── ViewToImageRenderer.swift (new)
└── Badges/ (already exists - reuse for badges)
```

### 8. Example Code Structure

**ShareableGraphicView.swift (simplified structure):**

```swift
struct ShareableGraphicView: View {
    let session: FocusSession
    let milestone: Milestone?
    let categoryColor: Color
    let isFirstTimeAchievingMilestone: Bool
    let graphicSize: CGSize
    
    var body: some View {
        ZStack {
            // Background gradient matching completionContent
            categoryGradient
            
            VStack(spacing: 0) {
                // Date (if milestone)
                if milestone != nil {
                    Text(formattedDate)
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.top, 32)
                }
                
                // Title
                Text(milestoneTitle)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.top, milestone != nil ? 8 : 32)
                
                Spacer(minLength: 16)
                
                // Badge (from SVG) or duration display
                if let milestone = milestone {
                    badgeImage(for: milestone)
                        .frame(width: 200, height: 200)
                } else {
                    Text(session.formattedDuration)
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                
                Spacer(minLength: 16)
                
                // Category info
                categoryInfoCard
            }
            .padding(40)
        }
        .frame(width: graphicSize.width, height: graphicSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
    }
    
    private var badgeImage: some View {
        // Load badge SVG with color replacement (reuse MilestonesView logic)
    }
    
    private var categoryInfoCard: some View {
        // Category icon, name, duration, points
    }
}
```

### 9. Next Steps

1. **Start with Phase 1** - Create the basic ShareableGraphicView structure
2. **Design Decision** - Choose graphic dimensions (recommend starting with 1080x1080 square)
3. **Reuse Existing Code** - Leverage badge loading logic from MilestonesView
4. **Test Incrementally** - Build and test each phase before moving on
5. **Iterate on Design** - Adjust spacing, fonts, layout to match your design

### 10. Additional Considerations

- **Watermark/Branding:** Consider adding app logo or watermark
- **Export Quality:** Use @3x scale for crisp images on retina displays
- **File Format:** PNG for best quality, or JPEG for smaller file size
- **Accessibility:** Ensure text has sufficient contrast
- **Localization:** Handle different date/time formats if supporting multiple languages

