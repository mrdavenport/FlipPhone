-- Floating/Bobbing Script for Letter F
-- Protocol: Node
-- Just copy/paste this into Rive - no need to edit anything!

type FloatingBob = {
    time: number,
    baseY: number,
    yPositionProp: Property<number>?,
    frequencyProp: Property<number>?,
    amplitudeProp: Property<number>?,
    smoothingProp: Property<number>?,
    currentY: number,
    targetY: number,
}

local TWO_PI = 2 * math.pi
local PROPERTY_NAME = "bobY_F"  -- Hardcoded for F
local PHASE_OFFSET = 0.22       -- Hardcoded phase offset
local DEBUG = false              -- Set to true to enable debug logs
local DEBUG_FRAME_COUNT = 0     -- Track frames for periodic logging

local function smoothStep(t: number): number
    return t * t * (3.0 - 2.0 * t)
end

function init(self: FloatingBob, context: Context): boolean
    if DEBUG then
        print("[FloatingBob F] init() called")
    end
    
    self.time = 0.0
    self.baseY = 0.0
    self.currentY = 0.0
    self.targetY = 0.0
    self.yPositionProp = nil
    self.frequencyProp = nil
    self.amplitudeProp = nil
    self.smoothingProp = nil
    
    local vm = context:viewModel()
    if DEBUG then
        print("[FloatingBob F] context:viewModel() returned: " .. tostring(vm))
        if vm then
            print("[FloatingBob F] ViewModel found - type: " .. typeof(vm))
        else
            print("[FloatingBob F] ViewModel is nil - checking if it exists on artboard...")
        end
    end
    if vm then
        if DEBUG then
            print("[FloatingBob F] ViewModel found")
        end
        
        self.yPositionProp = vm:getNumber(PROPERTY_NAME)
        self.frequencyProp = vm:getNumber("bobFrequency")
        self.amplitudeProp = vm:getNumber("bobAmplitude")
        self.smoothingProp = vm:getNumber("bobSmoothing")
        
        if DEBUG then
            print("[FloatingBob F] Property lookup:")
            print("  - yPositionProp (" .. PROPERTY_NAME .. "): " .. tostring(self.yPositionProp ~= nil))
            print("  - frequencyProp: " .. tostring(self.frequencyProp ~= nil))
            print("  - amplitudeProp: " .. tostring(self.amplitudeProp ~= nil))
            print("  - smoothingProp: " .. tostring(self.smoothingProp ~= nil))
        end
        
        if self.yPositionProp then
            self.baseY = self.yPositionProp.value
            self.currentY = self.baseY
            self.targetY = self.baseY
            
            if DEBUG then
                print("[FloatingBob F] Initial baseY: " .. tostring(self.baseY))
            end
        else
            if DEBUG then
                print("[FloatingBob F] ERROR: yPositionProp not found! Property name: " .. PROPERTY_NAME)
            end
        end
    else
        if DEBUG then
            print("[FloatingBob F] ERROR: ViewModel not found!")
        end
    end
    
    return true
end

function advance(self: FloatingBob, seconds: number): boolean
    self.time = self.time + seconds
    DEBUG_FRAME_COUNT = DEBUG_FRAME_COUNT + 1
    
    local freq = (self.frequencyProp and self.frequencyProp.value) or 0.6
    local amp = (self.amplitudeProp and self.amplitudeProp.value) or 2.0
    local smoothFactor = (self.smoothingProp and self.smoothingProp.value) or 0.15
    
    local sineValue = math.sin(TWO_PI * freq * self.time + PHASE_OFFSET * TWO_PI)
    local smoothedSine = smoothStep((sineValue + 1.0) / 2.0) * 2.0 - 1.0
    
    self.targetY = self.baseY + (amp * smoothedSine)
    self.currentY = self.currentY + (self.targetY - self.currentY) * smoothFactor
    
    -- Log frequently at start (first 10 frames), then every 60 frames
    local shouldLog = false
    if DEBUG_FRAME_COUNT <= 10 then
        shouldLog = true  -- Log first 10 frames
    elseif DEBUG_FRAME_COUNT % 60 == 0 then
        shouldLog = true  -- Then every 60 frames
    end
    
    if DEBUG and shouldLog then
        print("[FloatingBob F] Frame " .. tostring(DEBUG_FRAME_COUNT) .. ":")
        print("  - time: " .. string.format("%.2f", self.time))
        print("  - freq: " .. string.format("%.2f", freq) .. ", amp: " .. string.format("%.2f", amp))
        print("  - baseY: " .. string.format("%.2f", self.baseY))
        print("  - currentY: " .. string.format("%.2f", self.currentY))
        print("  - targetY: " .. string.format("%.2f", self.targetY))
        print("  - yPositionProp exists: " .. tostring(self.yPositionProp ~= nil))
        if self.yPositionProp then
            print("  - yPositionProp.value: " .. string.format("%.2f", self.yPositionProp.value))
        end
    end
    
    if self.yPositionProp then
        self.yPositionProp.value = self.currentY
    else
        if DEBUG and DEBUG_FRAME_COUNT % 60 == 0 then
            print("[FloatingBob F] ERROR: yPositionProp is nil! Cannot update position.")
        end
    end
    
    return true
end

function update(self: FloatingBob)
    if self.yPositionProp then
        self.currentY = self.yPositionProp.value
        self.targetY = self.currentY
    end
end

function draw(self: FloatingBob, renderer: Renderer)
end

return function(): Node<FloatingBob>
    return {
        init = init,
        advance = advance,
        update = update,
        draw = draw,
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
