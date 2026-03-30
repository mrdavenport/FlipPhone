-- Floating/Bobbing Node Script - Unified Version
-- Protocol: Node
-- 
-- This is a single script that can be used for multiple elements.
-- Each script instance uses different 'propertyName' and 'offset' values.
--
-- Setup:
-- 1. Create ViewModel properties (bobY_F, bobY_L, etc.) for each element
-- 2. Apply this script multiple times to the artboard (one per element)
-- 3. For each instance, set:
--    - propertyName: "bobY_F", "bobY_L", etc.
--    - offset: different value for wave effect (0.0 to 1.0)
-- 4. Data-bind each property to its corresponding element's Y position

-- Define the script's data and inputs.
type FloatingBob = {
    propertyName: Input<string>,   -- Name of the ViewModel property (e.g., "bobY_F")
    amplitude: Input<number>,      -- How far up/down (pixels or %)
    usePercent: Input<boolean>,    -- If true, amplitude is % of base position
    frequency: Input<number>,      -- How fast (cycles per second)
    phaseOffset: Input<number>,    -- Phase offset for wave effect (0.0 to 1.0)
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
    if vm and self.propertyName then
        -- Get the property name (default to "bobY" if not set)
        local propName = self.propertyName or "bobY"
        
        -- Get the Y position property from ViewModel using the input property name
        self.yPositionProp = vm:getNumber(propName)
        
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
    local phaseOff = self.phaseOffset or 0.0
    local usePercent = self.usePercent or false
    local smoothFactor = self.smoothing or 0.15
    
    -- Calculate sine wave with phase offset
    local sineValue = math.sin(TWO_PI * freq * self.time + phaseOff * TWO_PI)
    
    -- Apply smooth step for more organic motion
    local smoothedSine = smoothStep((sineValue + 1.0) / 2.0) * 2.0 - 1.0
    
    -- Calculate offset - either absolute pixels or percentage of base position
    local offset: number
    if usePercent then
        -- Percentage: amplitude is a % of baseY (e.g., 0.1 = 10% of base position)
        offset = self.baseY * amp * 0.01 * smoothedSine
    else
        -- Absolute: amplitude is in pixels
        offset = amp * smoothedSine
    end
    
    -- Calculate target Y position
    self.targetY = self.baseY + offset
    
    -- Smooth interpolation between current and target position
    self.currentY = self.currentY + (self.targetY - self.currentY) * smoothFactor
    
    -- Update the ViewModel property (which is data-bound to node's Y position)
    if self.yPositionProp then
        self.yPositionProp.value = self.currentY
    end
    
    return true  -- Keep running
end

-- Called when any input value changes.
function update(self: FloatingBob)
    -- If property name changes, re-initialize
    if self.propertyName then
        local vm = self -- We'll need context, but this might need adjustment
        -- For now, just reset smoothing when inputs change
    end
    
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
        propertyName = "bobY",       -- Default property name (change per instance)
        amplitude = 2.0,             -- Subtle: 1-3 pixels, More pronounced: 5-10 pixels
        usePercent = false,          -- false = pixels, true = percentage of base
        frequency = 0.6,             -- Subtle: 0.4-0.8, Faster: 1.0-2.0
        phaseOffset = 0.0,           -- Phase offset: 0.0 to 1.0 (creates wave effect)
        smoothing = 0.15,            -- Smoothing factor (0.0 = instant, 0.3 = very smooth)
        time = 0.0,
        baseY = 0.0,
        currentY = 0.0,
        targetY = 0.0,
        yPositionProp = nil,
    }
end
