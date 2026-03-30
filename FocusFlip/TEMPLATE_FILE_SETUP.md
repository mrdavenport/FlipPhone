# Setting Up the SVG Template File

## Important: File Location

Your SVG template file needs to be in the **bundle resources**, not in `Assets.xcassets`.

### Current Situation
- Your file is currently in: `Assets.xcassets/shareable-template.imageset/shareable-template_milestone3.svg`
- Files in Assets.xcassets are meant for images, not for loading as raw strings

### Solution: Move File to Bundle Resources

1. **In Xcode:**
   - Right-click on your `FocusFlip` folder (or any folder in your project, like `Badges/`)
   - Choose "Add Files to FocusFlip..."
   - Navigate to and select `shareable-template_milestone3.svg`
   - **Important checkboxes:**
     - ✅ "Copy items if needed" (checked)
     - ✅ "Add to targets: FocusFlip" (checked)
     - ❌ Do NOT add it to an `.imageset` folder

2. **Or drag and drop:**
   - Drag `shareable-template_milestone3.svg` from Finder into your Xcode project
   - Make sure it's outside of `Assets.xcassets`
   - Ensure "Copy items if needed" and your app target are selected

3. **Good locations to place it:**
   - In the root `FocusFlip/` folder (alongside your other `.swift` files)
   - In the `FocusFlip/Badges/` folder (if you want to keep templates with badges)
   - Create a new `FocusFlip/Templates/` folder

### After Moving the File

The code will automatically look for `shareable-template_milestone3.svg` in these locations:
- Root bundle (wherever you placed it)
- `Templates/` subdirectory
- `Assets/` subdirectory  
- `Badges/` folder

### Testing

Once the file is in the right place:
1. Build and run the app
2. Complete a focus session
3. Tap "Share" button
4. In the shareable graphic view, tap "Messages" button
5. Check the Xcode console for:
   - ✅ "Loaded SVG template from: [path]" (success!)
   - ⚠️ "SVG template file not found" (file not in bundle yet)

The "Messages" button will currently show debug info to help you verify the template is loading correctly.

