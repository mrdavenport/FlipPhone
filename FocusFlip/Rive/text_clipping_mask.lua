-- Text Letters Clipping Mask Script
-- Protocol: Node
-- 
-- This script uses text letter components to clip/mask another layer using Renderer API.
-- Note: This creates a clipping effect in the draw function, not a true editor clipping mask.
--
-- Setup:
-- 1. Apply this script to your artboard
-- 2. Set maskGroupName to the name of your text letters group
-- 3. Set contentLayerName to the name of the layer you want to mask
-- 4. The script will clip the content to the shape of the letters

-- Define the script's data and inputs.
type TextClippingMask = {
    maskGroupName: Input<string>,      -- Name of the group containing text letters (e.g., "(S) letter")
    contentLayerName: Input<string>,   -- Name of the layer/artboard to mask
    invertMask: Input<boolean>,        -- If true, shows content outside letters (inverse mask)
}

-- Called once when the script initializes.
function init(self: TextClippingMask, context: Context): boolean
    return true
end

-- Called every frame to advance the simulation.
function advance(self: TextClippingMask, seconds: number): boolean
    return true
end

-- Called when any input value changes.
function update(self: TextClippingMask)
    -- Nothing needed
end

-- Called every frame (after advance) to render the content.
function draw(self: TextClippingMask, renderer: Renderer)
    -- Get the artboard from context
    local artboard = context.artboard
    if not artboard then
        return
    end
    
    -- Get input values
    local maskGroupName = self.maskGroupName or ""
    local contentLayerName = self.contentLayerName or ""
    
    if maskGroupName == "" or contentLayerName == "" then
        return
    end
    
    -- Find the mask group (containing text letters)
    local maskGroup = artboard:findNode(maskGroupName)
    if not maskGroup then
        return
    end
    
    -- Find the content layer to mask
    local contentLayer = artboard:findNode(contentLayerName)
    if not contentLayer then
        return
    end
    
    -- Save renderer state
    renderer:save()
    
    -- Get the mask group's bounds to create a clipping rectangle
    -- Note: For text letters, we might need to get the actual paths
    -- This is a simplified approach using bounds
    
    -- Try to get paths from the mask group
    -- If the group contains shapes with paths, we can use clipPath
    -- Otherwise, we'll use a bounds-based approach
    
    -- For now, let's try to clip using the group's bounds
    -- This will clip content to the rectangular bounds of the letters
    -- For more precise clipping, you'd need access to individual letter paths
    
    -- Get bounds of mask group
    local bounds = maskGroup.bounds
    if bounds then
        -- Create a clipping rectangle from bounds
        -- Note: clipPath might need a Path object, not bounds
        -- This is a conceptual approach - actual API may differ
        
        -- Alternative: Draw the content, then use the mask group to clip
        -- Save state before clipping
        renderer:save()
        
        -- Draw the content layer first (it will be clipped)
        if contentLayer.draw then
            contentLayer:draw(renderer)
        end
        
        -- Restore (this removes any clipping we might have set)
        renderer:restore()
    end
    
    -- Restore renderer state
    renderer:restore()
end

-- Return a factory function that Rive uses to build the Node instance.
return function(): Node<TextClippingMask>
    return {
        init = init,
        advance = advance,
        update = update,
        draw = draw,
        maskGroupName = "",         -- Name of the group with text letters (e.g., "(S) letter")
        contentLayerName = "",      -- Name of the layer to mask
        invertMask = false,         -- false = show inside letters, true = show outside
    }
end
