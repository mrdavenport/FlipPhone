-- Floating/Bobbing Script - Direct Transform (No Data Binding Required)
-- Protocol: Node
-- 
-- This script directly modifies the node's transform using renderer.translate()
-- It does NOT rely on ViewModel data binding, which doesn't work in iOS runtime.
--
-- Setup:
-- 1. Apply this script to each letter/node you want to float
-- 2. Set the phaseOffset input to create a wave effect (0.0 to 1.0)
-- 3. The script reads shared values from ViewModel (frequency, amplitude, smoothing)
--    but applies the transform directly, bypassing data binding

type FloatingBob = {
    phaseOffset: Input<number>,    -- Phase offset for wave effect (0.0 to 1.0) - UNIQUE PER LETTER
    time: number,                  -- Time tracker
    baseY: number,                 -- Base Y position (captured at init)
    frequencyProp: Property<number>?, -- ViewModel property for frequency (shared)
    amplitudeProp: Property<number>?, -- ViewModel property for amplitude (shared)
    smoothingProp: Property<number>?, -- ViewModel property for smoothing (shared)
    currentY: number,              -- Current smoothed Y position
    targetY: number,               -- Target Y position (for smoothing)
    yOffset: number,               -- Current Y offset to apply
}

local TWO_PI = 2 * math.pi
local DEBUG = true
local DEBUG_FRAME_COUNT = 0

-- Smooth interpolation function (ease-in-out)
local function smoothStep(t: number): number
    return t * t * (3.0 - 2.0 * t)
end

-- Helper to safely get Input value
local function getInputValue(input: any): any
    if input == nil then
        return nil
    end
    if typeof(input) == "table" and input.value ~= nil then
        return input.value
    end
    return input
end

-- Called once when the script initializes.
function init(self: FloatingBob, context: Context): boolean
    if DEBUG then
        print("[FloatingBob Direct] init() called")
    end
    
    self.time = 0.0
    self.baseY = 0.0
    self.currentY = 0.0
    self.targetY = 0.0
    self.yOffset = 0.0
    self.frequencyProp = nil
    self.amplitudeProp = nil
    self.smoothingProp = nil
    
    -- Access the ViewModel through context for shared values
    local vm = context:viewModel()
    if vm then
        if DEBUG then
            print("[FloatingBob Direct] ViewModel found")
        end
        
        self.frequencyProp = vm:getNumber("bobFrequency")
        self.amplitudeProp = vm:getNumber("bobAmplitude")
        self.smoothingProp = vm:getNumber("bobSmoothing")
        
        if DEBUG then
            print("[FloatingBob Direct] Property lookup:")
            print("  - frequencyProp: " .. tostring(self.frequencyProp ~= nil))
            print("  - amplitudeProp: " .. tostring(self.amplitudeProp ~= nil))
            print("  - smoothingProp: " .. tostring(self.smoothingProp ~= nil))
        end
    else
        if DEBUG then
            print("[FloatingBob Direct] ERROR: ViewModel not found!")
        end
    end
    
    return true
end

-- Called every frame to advance the simulation.
function advance(self: FloatingBob, seconds: number): boolean
    self.time = self.time + seconds
    DEBUG_FRAME_COUNT = DEBUG_FRAME_COUNT + 1
    
    -- Get shared values from ViewModel
    local freq = (self.frequencyProp and self.frequencyProp.value) or 0.6
    local amp = (self.amplitudeProp and self.amplitudeProp.value) or 2.0
    local smoothFactor = (self.smoothingProp and self.smoothingProp.value) or 0.15
    
    -- Get per-instance phase offset
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
    
    -- Calculate target Y offset
    self.targetY = amp * smoothedSine
    
    -- Smooth interpolation between current and target position
    self.currentY = self.currentY + (self.targetY - self.currentY) * smoothFactor
    
    -- Store the offset to apply in draw()
    self.yOffset = self.currentY
    
    -- Log every 60 frames
    if DEBUG and DEBUG_FRAME_COUNT % 60 == 0 then
        print("[FloatingBob Direct] Frame " .. tostring(DEBUG_FRAME_COUNT) .. ":")
        print("  - time: " .. string.format("%.2f", self.time))
        print("  - freq: " .. string.format("%.2f", freq) .. ", amp: " .. string.format("%.2f", amp))
        print("  - phaseOffset: " .. string.format("%.2f", phaseOff))
        print("  - yOffset: " .. string.format("%.2f", self.yOffset))
    end
    
    return true
end

-- Called when any input value changes.
function update(self: FloatingBob)
    -- Reset smoothing when inputs change
    self.currentY = 0.0
    self.targetY = 0.0
    self.yOffset = 0.0
end

-- Called every frame (after advance) to render the content.
-- This is where we apply the transform directly!
function draw(self: FloatingBob, renderer: Renderer)
    -- Apply Y translation directly using renderer
    if self.yOffset ~= 0.0 then
        renderer:save()
        renderer:translate(0.0, self.yOffset)
        -- The node's content will be drawn with this translation applied
        renderer:restore()
    end
end

-- Return a factory function that Rive uses to build the Node instance.
return function(): Node<FloatingBob>
    return {
        init = init,
        advance = advance,
        update = update,
        draw = draw,
        phaseOffset = 0.0,           -- Per-instance: phase offset for wave effect
        time = 0.0,
        baseY = 0.0,
        currentY = 0.0,
        targetY = 0.0,
        yOffset = 0.0,
        frequencyProp = nil,
        amplitudeProp = nil,
        smoothingProp = nil,
    }
end
