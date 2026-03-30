# SVG Template Approach for Shareable Graphics

## Overview
Instead of rendering SwiftUI views to images (which can be complex and cause performance issues), we'll use an SVG template that can be dynamically updated with text, colors, and other content.

## Approach

1. **Create SVG Template**
   - User provides an SVG template file (e.g., `shareable-graphic-template.svg`)
   - Template includes placeholder text/values that will be replaced:
     - `{{SESSION_DURATION}}` - Session duration (e.g., "30m")
     - `{{CATEGORY_NAME}}` - Category name (e.g., "Work")
     - `{{CATEGORY_COLOR}}` - Category color hex (e.g., "#f5793b")
     - `{{NOTE}}` - Session note or "total focus time"
     - `{{DATE}}` - Formatted date
     - `{{TIME_RANGE}}` - Time range (e.g., "2:00pm - 2:30pm")
     - `{{POINTS}}` - Points earned
     - `{{MILESTONE_LABEL}}` - Milestone label (if applicable, e.g., "30m")
     - `{{MILESTONE_BADGE_SVG}}` - Inline badge SVG (if milestone)

2. **Dynamic Replacement**
   - Load SVG template as string
   - Replace placeholder values with actual session data
   - Replace color values with category color
   - If milestone exists, embed badge SVG inline

3. **SVG to UIImage Conversion**
   - Use `WKWebView` to render SVG (already have this pattern)
   - Capture the rendered view as UIImage
   - Or use a library like `SVGKit` for direct conversion

## Implementation Steps

### Step 1: Create SVG Template File
User provides SVG template with placeholders like:
```svg
<svg width="544" height="953" xmlns="http://www.w3.org/2000/svg">
  <rect width="544" height="953" fill="#000000"/>
  <text x="272" y="100" font-family="Arial" font-size="24" fill="{{CATEGORY_COLOR}}" text-anchor="middle">{{SESSION_DURATION}}</text>
  <!-- More elements with placeholders -->
</svg>
```

### Step 2: Load and Replace Template
```swift
private func loadSVGTemplate() -> String? {
    guard let url = Bundle.main.url(forResource: "shareable-graphic-template", withExtension: "svg"),
          let svgString = try? String(contentsOf: url) else {
        return nil
    }
    return svgString
}

private func replaceTemplatePlaceholders(template: String) -> String {
    var result = template
    
    // Replace text placeholders
    result = result.replacingOccurrences(of: "{{SESSION_DURATION}}", with: session.formattedDuration)
    result = result.replacingOccurrences(of: "{{CATEGORY_NAME}}", with: session.category.displayName)
    result = result.replacingOccurrences(of: "{{CATEGORY_COLOR}}", with: categoryColor.toHexString())
    result = result.replacingOccurrences(of: "{{NOTE}}", with: !session.note.isEmpty ? session.note : "total focus time")
    result = result.replacingOccurrences(of: "{{DATE}}", with: formattedSessionDate)
    result = result.replacingOccurrences(of: "{{TIME_RANGE}}", with: formattedTimeRange)
    result = result.replacingOccurrences(of: "{{POINTS}}", with: "\(session.points)")
    
    // Replace milestone placeholders if applicable
    if let milestone = milestone {
        result = result.replacingOccurrences(of: "{{MILESTONE_LABEL}}", with: milestone.label)
        
        // Load badge SVG and inline it
        if let badgeSVG = loadBadgeSVG(for: milestone) {
            result = result.replacingOccurrences(of: "{{MILESTONE_BADGE_SVG}}", with: badgeSVG)
        }
    }
    
    return result
}
```

### Step 3: Convert SVG to UIImage
```swift
private func svgToUIImage(svgString: String, size: CGSize) -> UIImage? {
    // Option 1: Use WKWebView to render and capture
    // Option 2: Use SVGKit library for direct conversion
    // Option 3: Use Core Graphics with SVG rendering
    
    // For now, we can use the existing SVGWebView pattern but capture it
    // This requires async rendering and snapshot
}
```

## File Structure
```
FocusFlip/
├── Assets/
│   └── shareable-graphic-template.svg (user provided)
└── Views/
    └── ShareableGraphicView.swift (updated to use template)
```

## Next Steps
1. User provides SVG template file
2. Place template in bundle (Assets.xcassets or Bundle)
3. Implement template loading and replacement
4. Implement SVG to UIImage conversion
5. Update ShareableGraphicView to use template approach

