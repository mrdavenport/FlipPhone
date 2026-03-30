-- Floating/Bobbing Script for Letter H
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
local PROPERTY_NAME = "bobY_H"  -- Hardcoded for H
local PHASE_OFFSET = 0.66       -- Hardcoded phase offset

local function smoothStep(t: number): number
    return t * t * (3.0 - 2.0 * t)
end

function init(self: FloatingBob, context: Context): boolean
    self.time = 0.0
    self.baseY = 0.0
    self.currentY = 0.0
    self.targetY = 0.0
    self.yPositionProp = nil
    self.frequencyProp = nil
    self.amplitudeProp = nil
    self.smoothingProp = nil
    
    local vm = context:viewModel()
    if vm then
        self.yPositionProp = vm:getNumber(PROPERTY_NAME)
        self.frequencyProp = vm:getNumber("bobFrequency")
        self.amplitudeProp = vm:getNumber("bobAmplitude")
        self.smoothingProp = vm:getNumber("bobSmoothing")
        
        if self.yPositionProp then
            self.baseY = self.yPositionProp.value
            self.currentY = self.baseY
            self.targetY = self.baseY
        end
    end
    
    return true
end

function advance(self: FloatingBob, seconds: number): boolean
    self.time = self.time + seconds
    
    local freq = (self.frequencyProp and self.frequencyProp.value) or 0.6
    local amp = (self.amplitudeProp and self.amplitudeProp.value) or 2.0
    local smoothFactor = (self.smoothingProp and self.smoothingProp.value) or 0.15
    
    local sineValue = math.sin(TWO_PI * freq * self.time + PHASE_OFFSET * TWO_PI)
    local smoothedSine = smoothStep((sineValue + 1.0) / 2.0) * 2.0 - 1.0
    
    self.targetY = self.baseY + (amp * smoothedSine)
    self.currentY = self.currentY + (self.targetY - self.currentY) * smoothFactor
    
    if self.yPositionProp then
        self.yPositionProp.value = self.currentY
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
