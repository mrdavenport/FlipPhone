# Figma to SVG Template Guide

## Workflow Overview

1. **Design in Figma** → 2. **Export SVG** → 3. **Add placeholders in text editor** → 4. **Save as template**

## Step-by-Step Process

### Step 1: Design in Figma

1. Create a frame/artboard with dimensions **544 x 953** (width x height)
2. Design your graphic with **sample/placeholder text**:
   - Use actual text that represents what will be there (e.g., "30m", "Work", "2:00pm - 2:30pm")
   - This helps you:
     - See how the layout looks
     - Test font sizes and positioning
     - Ensure text fits properly
3. Use your actual fonts, colors, and styling
4. For colors that need to be dynamic (like category color), use a sample color (you'll replace the hex value with `{{CATEGORY_COLOR}}` later)

### Step 2: Export from Figma

**Option A: Manual Export**
1. Select your frame/artboard
2. In the right sidebar, click **Export** button (or right-click → Export)
3. Select **SVG** format
4. Click **Export** and save the file

**Option B: Using SVG Export Plugin**
1. Install plugin: "SVG Export" or "SVG Export Optimizer"
2. Run the plugin
3. Export your frame as SVG

### Step 3: Edit SVG to Add Placeholders

Open the exported SVG file in a text editor (VS Code, TextEdit, etc.)

#### Finding Text Elements

Look for `<text>` elements in the SVG. They'll look like:
```xml
<text x="272" y="100" font-family="Inter" font-size="24" fill="#000000">30m</text>
```

#### Replacing Text Content

Replace the actual text with placeholders:

**Text Placeholders:**
- `30m` → `{{SESSION_DURATION}}`
- `Work` → `{{CATEGORY_NAME}}`
- `2:00pm - 2:30pm` → `{{TIME_RANGE}}`
- `Monday, Jan 15th` → `{{DATE}}`
- `total focus time` or note → `{{NOTE}}`
- `150` → `{{POINTS}}`
- `30m` (for milestone) → `{{MILESTONE_LABEL}}`
- `New milestone achieved!` → `{{MILESTONE_TITLE}}`
- `New Personal Best!` → `{{PERSONAL_BEST}}`

**Color Placeholders:**
- `fill="#f5793b"` → `fill="{{CATEGORY_COLOR}}"`
- `fill="#000000"` → Keep as is if it should always be black
- Any color that should be dynamic → Replace hex with `{{CATEGORY_COLOR}}`

#### Example Transformation

**Before (Figma export):**
```xml
<svg width="544" height="953" xmlns="http://www.w3.org/2000/svg">
  <rect width="544" height="953" fill="#000000"/>
  
  <text x="272" y="100" font-family="Inter" font-size="48" fill="#f5793b" text-anchor="middle">30m</text>
  
  <text x="272" y="200" font-family="Inter" font-size="24" fill="#ffffff" text-anchor="middle">Work</text>
  
  <text x="272" y="250" font-family="Inter" font-size="16" fill="#ffffff" text-anchor="middle">2:00pm - 2:30pm</text>
</svg>
```

**After (with placeholders):**
```xml
<svg width="544" height="953" xmlns="http://www.w3.org/2000/svg">
  <rect width="544" height="953" fill="#000000"/>
  
  <text x="272" y="100" font-family="Inter" font-size="48" fill="{{CATEGORY_COLOR}}" text-anchor="middle">{{SESSION_DURATION}}</text>
  
  <text x="272" y="200" font-family="Inter" font-size="24" fill="#ffffff" text-anchor="middle">{{CATEGORY_NAME}}</text>
  
  <text x="272" y="250" font-family="Inter" font-size="16" fill="#ffffff" text-anchor="middle">{{TIME_RANGE}}</text>
</svg>
```

### Step 4: Handling Milestone Badge

For the milestone badge, you have two options:

**Option A: Leave a placeholder area**
- In Figma, create a placeholder rectangle/shape where the badge should go
- In the SVG, replace it with: `{{MILESTONE_BADGE_SVG}}`
- The code will inline the badge SVG here

**Option B: Add a comment marker**
- In Figma, create a placeholder shape
- In SVG, you can leave it and the code will replace a specific placeholder:
  ```xml
  <!-- {{MILESTONE_BADGE_SVG}} -->
  <rect x="150" y="300" width="200" height="200" fill="none"/> <!-- Placeholder for badge -->
  ```

### Step 5: Save Template File

1. Save the edited SVG file as: `shareable-graphic-template.svg`
2. Add it to your Xcode project:
   - Drag into Xcode project navigator
   - Make sure it's added to the app target
   - OR create a "Templates" folder and place it there

## Available Placeholders

| Placeholder | Replaced With |
|------------|---------------|
| `{{SESSION_DURATION}}` | Session duration (e.g., "30m", "1h 15m") |
| `{{CATEGORY_NAME}}` | Category name (e.g., "Work", "Family") |
| `{{CATEGORY_COLOR}}` | Category color hex (e.g., "#f5793b") |
| `{{NOTE}}` | Session note or "total focus time" |
| `{{DATE}}` | Formatted date (e.g., "Monday, Jan 15th") |
| `{{TIME_RANGE}}` | Time range (e.g., "2:00pm - 2:30pm") |
| `{{POINTS}}` | Points earned (e.g., "150") |
| `{{MILESTONE_LABEL}}` | Milestone label (e.g., "30m") - only if milestone |
| `{{MILESTONE_TITLE}}` | Milestone title (e.g., "New milestone achieved!") - only if milestone |
| `{{MILESTONE_BADGE_SVG}}` | Inline badge SVG - only if milestone |
| `{{PERSONAL_BEST}}` | "New Personal Best!" - only if personal best |

## Tips for Figma Design

1. **Use consistent fonts**: Make sure fonts used in Figma are available in your app, or the SVG will fall back to system fonts
2. **Position carefully**: Text positioning in SVG uses x/y coordinates - position carefully in Figma
3. **Test with long text**: Make sure your layout works with longer durations (e.g., "2h 45m") or longer category names
4. **Color considerations**: For colors that should be dynamic, use a sample color that's close to what you want
5. **Text alignment**: Use `text-anchor="middle"` for center-aligned text, `text-anchor="start"` for left, `text-anchor="end"` for right

## Quick Reference: SVG Text Attributes

When editing the SVG, you may want to adjust:
- `x` and `y`: Text position
- `font-family`: Font name (should match your app fonts)
- `font-size`: Text size
- `fill`: Text color (use `{{CATEGORY_COLOR}}` for dynamic colors)
- `text-anchor`: Alignment ("start", "middle", "end")
- `font-weight`: Boldness ("normal", "bold", or numeric like "600")

## After Adding Template

Once you've added `shareable-graphic-template.svg` to your project, the code will:
1. Load the template
2. Replace all placeholders with actual session data
3. Convert the SVG to UIImage
4. Share/save the image

The template approach makes it easy to update the design - just export a new SVG from Figma and update the placeholders!

