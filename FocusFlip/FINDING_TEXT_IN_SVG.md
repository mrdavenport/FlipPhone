# Finding and Replacing Text in SVG Files from Figma

## Common Issues

Figma can export text in several different ways, making it hard to find:
1. **As `<text>` elements** (ideal, but not always)
2. **As `<path>` elements** (text converted to outlines)
3. **Inside `<g>` (group) elements** with transforms
4. **With complex styling** or multiple elements

## Strategies to Find Text

### Method 1: Search for Text Content

1. Open your SVG in a text editor
2. Use **Find** (Cmd+F / Ctrl+F) and search for the actual text you wrote in Figma:
   - Search for: `30m` (or whatever sample text you used)
   - Search for: `Work` (your category name)
   - Search for: `2:00pm` (your time range)

### Method 2: Search for Common SVG Text Patterns

Search for these patterns in your SVG:

**Search for `<text`:**
```
<text
```

**Search for `fill=` or `stroke=`** (to find color attributes):
```
fill=
```

**Search for font-related attributes:**
```
font-family
font-size
```

### Method 3: Use a Better Export Method

#### Option A: Use Figma's "Copy as SVG" with Better Settings

1. In Figma, select your frame
2. Right-click → **Copy/Paste as** → **Copy as SVG**
3. This sometimes gives cleaner output than Export
4. Paste into your text editor and save

#### Option B: Use a Figma Plugin

Try these plugins for better SVG export:
- **"SVG Export"** - Gives more control over export
- **"SVG Export Optimizer"** - Optimizes and may preserve text better
- **"Figma to SVG"** - Alternative exporter

#### Option C: Export with Specific Settings

1. Select your frame
2. Right-click → **Export**
3. Select **SVG**
4. Click the settings icon (gear) if available
5. Try enabling/disabling:
   - "Outline Text" (disable this if possible - keeps text as `<text>`)
   - "Simplify Stroke" 
   - "Include 'id' attribute"

### Method 4: Simplify Your Approach

Instead of trying to find every text element, you can:

1. **Add unique IDs or classes** in Figma (if your export supports it)
2. **Use simpler placeholder text** in Figma that's easier to find
3. **Export layers separately** if needed

## Common SVG Text Patterns

Here are different ways Figma might export text:

### Pattern 1: Simple Text (Best Case)
```xml
<text x="272" y="100" font-family="Inter" font-size="24" fill="#000000">30m</text>
```
**Easy to find:** Just search for `30m`

### Pattern 2: Text in a Group
```xml
<g transform="translate(272,100)">
  <text font-family="Inter" font-size="24" fill="#000000">30m</text>
</g>
```
**How to find:** Search for the text content `30m` and look for the parent `<g>` tag

### Pattern 3: Text as Path (Worst Case)
```xml
<path d="M100,100 L200,100 L200,150 L100,150 Z" fill="#000000"/>
```
**Problem:** Text is converted to vector paths - can't replace with text placeholders
**Solution:** Avoid "Outline Text" option when exporting

### Pattern 4: Text with Transform
```xml
<text transform="translate(272,100)" font-family="Inter" font-size="24" fill="#000000">30m</text>
```
**Easy to find:** Search for `30m` - the transform doesn't matter

## Step-by-Step: Finding Your Text

1. **Open SVG in VS Code** (or any text editor with syntax highlighting)
2. **Enable word wrap** (View → Word Wrap)
3. **Use Find** (Cmd+F)
4. **Search for your sample text** (what you typed in Figma):
   - Type: `30m` (or whatever duration you used)
   - Type: `Work` (or whatever category you used)
   - Type: `pm` (to find time ranges)

5. **When you find the text:**
   - Look at the element it's in: `<text>` or inside `<g>`
   - Note the `fill` attribute (for colors)
   - Replace the text content with `{{PLACEHOLDER}}`
   - Replace color with `{{CATEGORY_COLOR}}` if needed

## Example: Real-World SVG Structure

Here's what a more complex Figma export might look like:

```xml
<svg width="544" height="953">
  <!-- Background -->
  <rect width="544" height="953" fill="#000000"/>
  
  <!-- Group containing duration text -->
  <g id="duration" transform="translate(272,300)">
    <text font-family="Inter, sans-serif" font-size="72" font-weight="700" 
          fill="#f5793b" text-anchor="middle" dominant-baseline="central">30m</text>
  </g>
  
  <!-- Category name -->
  <g id="category" transform="translate(272,400)">
    <text font-family="Inter, sans-serif" font-size="24" font-weight="600" 
          fill="#ffffff" text-anchor="middle">Work</text>
  </g>
</svg>
```

**To replace:**
1. Find `30m` → Replace with `{{SESSION_DURATION}}`
2. Find `#f5793b` (in the same element) → Replace with `{{CATEGORY_COLOR}}`
3. Find `Work` → Replace with `{{CATEGORY_NAME}}`

## Pro Tip: Use Comments to Mark Sections

After you edit, add comments to make future edits easier:

```xml
<!-- SESSION DURATION -->
<text x="272" y="300" fill="{{CATEGORY_COLOR}}">{{SESSION_DURATION}}</text>

<!-- CATEGORY NAME -->
<text x="272" y="400" fill="#ffffff">{{CATEGORY_NAME}}</text>

<!-- TIME RANGE -->
<text x="272" y="450" fill="#ffffff">{{TIME_RANGE}}</text>
```

## If Text is Exported as Paths

If your text appears as `<path>` elements instead of `<text>`:

1. **Re-export from Figma** with different settings:
   - Make sure "Outline Text" is OFF
   - Try "Copy as SVG" instead of Export
   - Use an SVG export plugin

2. **Alternative approach:** Keep the paths but replace the `fill` color value:
   ```xml
   <!-- Duration text as path -->
   <g id="duration-text">
     <path d="..." fill="{{CATEGORY_COLOR}}"/>
   </g>
   ```
   This works for colors but not for changing the actual text content.

## Quick Checklist

- [ ] Opened SVG in text editor (VS Code recommended)
- [ ] Used Find (Cmd+F) to search for sample text from Figma
- [ ] Found `<text>` elements (not `<path>`)
- [ ] Replaced text content with `{{PLACEHOLDER}}`
- [ ] Replaced color values with `{{CATEGORY_COLOR}}` where needed
- [ ] Saved file as `shareable-graphic-template.svg`

## Still Having Trouble?

If you can't find the text elements:
1. Share a snippet of your SVG (the parts you can't find)
2. Or try re-exporting with "Copy as SVG" method
3. Or use a different export plugin

