# Category Icon Placeholder for SVG Template

## Recommended Approach: Static Icon with Dynamic Color

**Best solution:** Design a simple icon shape in Figma and use `{{CATEGORY_COLOR}}` for the fill color.

### Why This Works Best

Since category icons are SF Symbols (system icons like "briefcase.fill", "heart.fill", etc.), they can't be directly embedded as SVG text. The simplest approach is:

1. **In Figma:** Design a simple, generic icon shape (circle, square, or a stylized geometric shape)
2. **Use dynamic color:** Set the fill to use `{{CATEGORY_COLOR}}` placeholder
3. **Keep it simple:** The icon shape stays the same, only the color changes dynamically

### Example in SVG

```xml
<!-- Simple circle icon with dynamic category color -->
<circle cx="272" cy="100" r="24" fill="{{CATEGORY_COLOR}}"/>

<!-- Or a more stylized shape -->
<path d="M250,85 L294,85 L272,120 Z" fill="{{CATEGORY_COLOR}}"/>
```

### Alternative: Use Placeholder (For Future Enhancement)

If you want to use a placeholder now and add proper icons later, you can use:

```xml
<!-- Category Icon placeholder -->
{{CATEGORY_ICON_SVG}}
```

**Note:** The code currently removes this placeholder (replaces with empty string). If we want to add proper icon SVGs later, we can implement that.

### Current Category Icons (for reference)

If you want to design SVG versions of these later:
- Work: `briefcase.fill`
- Family: `heart.fill`  
- Sleep: `moon.stars.fill`
- Chores: `house.fill`
- Chilling: `cup.and.saucer.fill`
- Other: `iphone.rear.camera`

But for now, a simple colored shape works perfectly!

