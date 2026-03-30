-- Floating/Bobbing Node Script for Hero Animation
-- Protocol: Node
-- 
-- This script creates a subtle floating/bobbing effect using a ViewModel bridge.
-- The script modifies a ViewModel property, which is data-bound to the node's Y position.
--
-- Setup required:
-- 1. Create a ViewModel in your artboard with a number property (e.g., "bobY")
-- 2. Data-bind that property to your node's Y position in Rive Editor
-- 3. Apply this script to the artboard

-- Define the script's data and inputs.
type FloatingBob = {
    amplitude: Input<number>,      -- How far up/down (pixels)
    frequency: Input<number>,      -- How fast (cycles per second)
    offset: Input<number>,         -- Phase offset (0.0 - 1.0)
    time: number,                  -- Time tracker
    baseY: number,                 -- Base Y position
    yPositionProp: Property<number>?, -- ViewModel property for Y position
    currentY: number,              -- Current smoothed Y position
    targetY: number,               -- Target Y position (for smoothing)
    smoothing: Input<number>,      -- Smoothing factor (0.0 = no smoothing, 1.0 = max smoothing)
}

local TWO_PI = 2 * math.pi

-- Smooth interpolation function (ease-in-out)
local function smoothStep(t: number): number
    return t * t * (3.0 - 2.0 * t)
end

-- Called once when the script initializes.
function init(self: FloatingBob, context: Context): boolean
    self.time = 0.0
    self.baseY = 0.0
    self.currentY = 0.0
    self.targetY = 0.0
    self.yPositionProp = nil
    
    -- Access the ViewModel through context
    local vm = context:viewModel()
    if vm then
        -- Get the Y position property from ViewModel
        -- Change "bobY" to match your ViewModel property name
        self.yPositionProp = vm:getNumber("bobY")
        
        -- Capture the base Y position from the property
        if self.yPositionProp then
            self.baseY = self.yPositionProp.value
            self.currentY = self.baseY
            self.targetY = self.baseY
        end
    end
    
    return true
end

-- Called every frame to advance the simulation.
function advance(self: FloatingBob, seconds: number): boolean
    -- Update time
    self.time = self.time + seconds
    
    -- Get input values (with defaults if not set)
    local amp = self.amplitude or 2.0
    local freq = self.frequency or 0.6
    local off = self.offset or 0.0
    local smoothFactor = self.smoothing or 0.15  -- Default: 15% smoothing per frame
    
    -- Calculate sine wave offset for Y translation
    -- Using a smoother curve with ease-in-out
    local sineValue = math.sin(TWO_PI * freq * self.time + off * TWO_PI)
    
    -- Apply smooth step to the sine wave for more organic motion
    local smoothedSine = smoothStep((sineValue + 1.0) / 2.0) * 2.0 - 1.0
    
    -- Calculate target Y position
    self.targetY = self.baseY + (amp * smoothedSine)
    
    -- Smooth interpolation between current and target position
    -- This creates a more fluid, less rigid motion
    self.currentY = self.currentY + (self.targetY - self.currentY) * smoothFactor
    
    -- Update the ViewModel property (which is data-bound to node's Y position)
    if self.yPositionProp then
        self.yPositionProp.value = self.currentY
    end
    
    return true  -- Keep running
end

-- Called when any input value changes.
function update(self: FloatingBob)
    -- Reset smoothing when inputs change dramatically
    if self.yPositionProp then
        self.currentY = self.yPositionProp.value
        self.targetY = self.currentY
    end
end

-- Called every frame (after advance) to render the content.
function draw(self: FloatingBob, renderer: Renderer)
    -- Nothing to draw - we're modifying the ViewModel property in advance()
end

-- Return a factory function that Rive uses to build the Node instance.
return function(): Node<FloatingBob>
    return {
        init = init,
        advance = advance,
        update = update,
        draw = draw,
        amplitude = 2.0,            -- Subtle: 1-3 pixels, More pronounced: 5-10 pixels
        frequency = 0.6,            -- Subtle: 0.4-0.8, Faster: 1.0-2.0
        offset = 0.0,
        smoothing = 0.15,           -- Smoothing factor (0.0 = instant, 0.3 = very smooth)
        time = 0.0,
        baseY = 0.0,
        currentY = 0.0,
        targetY = 0.0,
        yPositionProp = nil,
    }
end
