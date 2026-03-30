# SVG Text Replacement Helper

## Quick Reference: What to Search For

When you open your SVG file in a text editor, use these search terms to find text elements:

### Search Terms (in order of usefulness):

1. **Your actual sample text** (most reliable):
   - `30m` (or whatever duration you used)
   - `Work` (or whatever category name)
   - `pm` (to find time text)
   - `pts` (to find points text)
   - `Monday` (to find date text)

2. **SVG text element tag**:
   - `<text` (finds all text elements)

3. **Color codes** (to find where colors are):
   - `#f5793b` (Work color - replace with `{{CATEGORY_COLOR}}`)
   - `#f296bd` (Family color)
   - `#99b7f5` (Sleep color)
   - Any hex color code you used

4. **Font attributes**:
   - `font-family`
   - `font-size`
   - `font-weight`

## Example: Step-by-Step Search

Let's say you have sample text "30m" in your Figma design:

1. **Open SVG in VS Code**
2. **Press Cmd+F (Find)**
3. **Type: `30m`**
4. **Look at the context around the match:**

```xml
<!-- You might see something like this: -->
<text x="272" y="300" font-family="Inter" font-size="72" fill="#f5793b">30m</text>
```

5. **Replace it:**
   - Change `30m` → `{{SESSION_DURATION}}`
   - Change `#f5793b` → `{{CATEGORY_COLOR}}` (if this color should be dynamic)

```xml
<!-- After replacement: -->
<text x="272" y="300" font-family="Inter" font-size="72" fill="{{CATEGORY_COLOR}}">{{SESSION_DURATION}}</text>
```

## If Text is in a Group

Sometimes the text is wrapped in a `<g>` (group) tag:

```xml
<g transform="translate(272,300)">
  <text font-family="Inter" font-size="72" fill="#f5793b">30m</text>
</g>
```

**Same process:** Search for `30m`, find it inside the group, replace the text and color.

## Color Replacement Only

If you can only find colors (which you mentioned you were able to do), that's actually a great start! You can:

1. **Find all color instances** by searching for the hex code (e.g., `#f5793b`)
2. **Replace with `{{CATEGORY_COLOR}}`**
3. **For text content**, you might need to:
   - Re-export from Figma with "Copy as SVG" (better text preservation)
   - Or manually add `<text>` elements where needed

## Alternative: Manual Text Element Addition

If you can't find text elements, you can manually add them:

1. Find where in your SVG layout you want the text (by coordinates)
2. Add a `<text>` element manually:

```xml
<!-- Find a good position in your SVG (look for other elements' x/y coordinates) -->
<!-- Then add: -->
<text x="272" y="300" font-family="Inter" font-size="72" fill="{{CATEGORY_COLOR}}" text-anchor="middle">{{SESSION_DURATION}}</text>
```

Use the coordinates from your design to position it correctly.

## Debug: Print Your SVG Structure

If you want to see what your SVG actually contains, you can temporarily add this to see the structure:

1. Load your SVG in a browser (drag and drop)
2. Right-click → Inspect Element
3. Or, use an SVG viewer/editor online

## Recommended Tool: SVG Viewer

Use an online SVG viewer to see your template:
- https://www.svgviewer.dev/
- Upload your SVG
- See the visual structure
- Use browser dev tools to inspect elements

This helps you understand where text elements are positioned.

