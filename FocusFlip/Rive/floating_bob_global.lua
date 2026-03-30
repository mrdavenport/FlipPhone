-- Floating/Bobbing Node Script - Global Controls via ViewModel
-- Protocol: Node
-- 
-- This script reads shared values (frequency, amplitude, smoothing) from ViewModel properties,
-- so you can change them once and all instances update automatically.
-- Only propertyName and phaseOffset are per-instance inputs.
--
-- Setup:
-- 1. Create ViewModel properties:
--    - Shared: "bobFrequency", "bobAmplitude", "bobSmoothing"
--    - Per-letter: "bobY_F", "bobY_L", etc.
-- 2. Apply this script multiple times to the artboard
-- 3. For each instance, set:
--    - propertyName: "bobY_F", "bobY_L", etc.
--    - phaseOffset: different value for wave effect (0.0 to 1.0)
-- 4. Data-bind each bobY property to its letter's Y position

-- Define the script's data and inputs.
type FloatingBob = {
    propertyName: Input<string>,   -- Name of the Y position property (e.g., "bobY_F")
    phaseOffset: Input<number>,    -- Phase offset for wave effect (0.0 to 1.0) - UNIQUE PER LETTER
    -- Shared values are read from ViewModel, not inputs!
    time: number,                  -- Time tracker
    baseY: number,                 -- Base Y position
    yPositionProp: Property<number>?, -- ViewModel property for Y position
    frequencyProp: Property<number>?, -- ViewModel property for frequency (shared)
    amplitudeProp: Property<number>?, -- ViewModel property for amplitude (shared)
    smoothingProp: Property<number>?, -- ViewModel property for smoothing (shared)
    currentY: number,              -- Current smoothed Y position
    targetY: number,               -- Target Y position (for smoothing)
}

local TWO_PI = 2 * math.pi

-- Smooth interpolation function (ease-in-out)
local function smoothStep(t: number): number
    return t * t * (3.0 - 2.0 * t)
end

-- Helper function to safely get value from Input<T> or primitive
-- Works in both Rive Editor (where Input might be direct value) and iOS runtime (where Input has .value)
local function getInputValue(input: any): any
    if input == nil then
        return nil
    end
    -- Check if input has a .value property (iOS runtime Input<T>)
    local inputType = typeof(input)
    if inputType == "table" then
        local hasValue = false
        for k, v in pairs(input) do
            if k == "value" then
                hasValue = true
                break
            end
        end
        if hasValue then
            return input.value
        end
    end
    -- Otherwise return as-is (Rive Editor might give us the value directly)
    return input
end

-- Called once when the script initializes.
function init(self: FloatingBob, context: Context): boolean
    self.time = 0.0
    self.baseY = 0.0
    self.currentY = 0.0
    self.targetY = 0.0
    self.yPositionProp = nil
    self.frequencyProp = nil
    self.amplitudeProp = nil
    self.smoothingProp = nil
    
    -- Access the ViewModel through context
    local vm = context:viewModel()
    if vm then
        -- Get the Y position property (unique per letter)
        -- Safely extract string value from Input<string>
        local propNameStr = "bobY"  -- Default fallback
        if self.propertyName then
            -- Try to get value safely (works in both editor and runtime)
            local propName = getInputValue(self.propertyName)
            if propName then
                local propStr = tostring(propName)
                if propStr ~= "" and propStr ~= "nil" then
                    propNameStr = propStr
                end
            end
        end
        self.yPositionProp = vm:getNumber(propNameStr)
        
        -- Get shared properties (same for all instances)
        self.frequencyProp = vm:getNumber("bobFrequency")
        self.amplitudeProp = vm:getNumber("bobAmplitude")
        self.smoothingProp = vm:getNumber("bobSmoothing")
        
        -- Capture the base Y position
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
    
    -- Get shared values from ViewModel (read once, applies to all instances)
    local freq = (self.frequencyProp and self.frequencyProp.value) or 0.6
    local amp = (self.amplitudeProp and self.amplitudeProp.value) or 2.0
    local smoothFactor = (self.smoothingProp and self.smoothingProp.value) or 0.15
    
    -- Get per-instance phase offset (unique per letter)
    -- Safely extract number value from Input<number>
    local phaseOff: number = 0.0
    if self.phaseOffset then
        local offsetValue = getInputValue(self.phaseOffset)
        if offsetValue then
            phaseOff = tonumber(offsetValue) or 0.0
        end
    end
    
    -- Calculate sine wave with phase offset
    local sineValue = math.sin(TWO_PI * freq * self.time + phaseOff * TWO_PI)
    
    -- Apply smooth step for more organic motion
    local smoothedSine = smoothStep((sineValue + 1.0) / 2.0) * 2.0 - 1.0
    
    -- Calculate target Y position
    self.targetY = self.baseY + (amp * smoothedSine)
    
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
    -- Reset smoothing when inputs change
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
        propertyName = "bobY",       -- Per-instance: which letter's property
        phaseOffset = 0.0,           -- Per-instance: phase offset for wave effect
        time = 0.0,
        baseY = 0.0,
        currentY = 0.0,
        targetY = 0.0,
        yPositionProp = nil,
        frequencyProp = nil,
        amplitudeProp = nil,
        smoothingProp = nil,
    }
end
