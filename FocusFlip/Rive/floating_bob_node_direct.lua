-- Floating/Bobbing Node Script - Direct Version
-- Protocol: Node
-- 
-- Apply this script DIRECTLY to the group/element you want to float.
-- No target input needed - it automatically floats the node it's applied to!
--
-- Usage:
-- 1. Apply this script to the "(S) letter" group (not the artboard)
-- 2. Adjust amplitude and frequency in the Property Group
-- 3. Done! The group will float automatically.

-- Script type definition
export type FloatingBob = {
    amplitude: Input<number>,      -- How far up/down (pixels)
    frequency: Input<number>,      -- How fast (cycles per second)
    offset: Input<number>,         -- Phase offset (0.0 - 1.0)
    elapsedTime: number,           -- Elapsed time tracker
    originalY: number?,            -- Store original Y position
}

local TWO_PI = 2 * math.pi

-- init: Called once when script is initialized
function init(self: FloatingBob): boolean
    -- Initialize elapsed time
    self.elapsedTime = 0.0
    self.originalY = nil
    
    return true
end

-- advance: Called every frame with time delta
function advance(self: FloatingBob, seconds: number): boolean
    -- Update elapsed time
    self.elapsedTime = self.elapsedTime + seconds
    
    -- Continue running (return true to keep getting advance calls)
    return true
end

-- draw: Called every frame to render/apply transformations
-- Note: In Node scripts, we can modify the node's transform via renderer
function draw(self: FloatingBob, renderer)
    -- Get input values (with defaults if not set)
    local amp = self.amplitude or 2.0
    local freq = self.frequency or 0.6
    local off = self.offset or 0.0
    
    -- Calculate sine wave offset
    local offsetY = amp * math.sin(TWO_PI * freq * self.elapsedTime + off * TWO_PI)
    
    -- Apply transform via renderer
    -- This will affect the node this script is applied to
    if renderer then
        renderer.translate(0, offsetY)
    end
end

-- Factory function: Rive uses this to create script instances
return function(): Node<FloatingBob>
    return {
        init = init,
        advance = advance,
        draw = draw,
        amplitude = 2.0,            -- Subtle: 1-3 pixels, More pronounced: 5-10 pixels
        frequency = 0.6,            -- Subtle: 0.4-0.8, Faster: 1.0-2.0
        offset = 0.0,
        elapsedTime = 0.0,
        originalY = nil,
    }
end
