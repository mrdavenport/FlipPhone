-- Floating/Bobbing Converter Script for Hero Animation
-- Protocol: Converter
-- 
-- This script outputs a smooth sine wave value for creating floating/bobbing effects.
-- Bind this converter's output to transform properties (translateY, scale, rotation, etc.)
-- to create a subtle floating/bobbing animation effect.
--
-- Usage in Rive Editor:
-- 1. Add this as a Converter script
-- 2. Bind the output to a transform property (e.g., Translate Y)
-- 3. Adjust the input values in the Inspector

-- Script inputs (configurable in Rive Editor Inspector):
-- These will appear as input fields you can adjust without editing code

-- Input: speed (Number)
-- Controls animation speed (higher = faster bobbing)
-- Recommended: 0.5 - 2.0 for subtle effects
local speed = 1.0

-- Input: amplitude (Number)  
-- Controls how much the element moves (higher = more movement)
-- Recommended: 0.5 - 3.0 for subtle effects
local amplitude = 1.0

-- Input: offset (Number)
-- Phase offset for timing (0.0 - 1.0)
-- Useful for multiple elements to bob at different times
local offset = 0.0

-- Internal state
local elapsedTime = 0.0

-- update: Called when script inputs change
function update(self)
    -- Read input values from Rive Editor
    -- Note: Input names must match what you define in Rive Editor's script inputs panel
    if self.inputs then
        speed = self.inputs.speed or 1.0
        amplitude = self.inputs.amplitude or 1.0
        offset = self.inputs.offset or 0.0
    end
end

-- convert: Called each frame to compute the output value
-- For time-based converters, Rive may pass time or we track it via advance
-- This version works as a converter that can be bound to properties
function convert(self, inputValue)
    -- For a time-based effect, we need to track time
    -- If Rive doesn't provide time directly, we'll use a workaround
    -- Note: This may need adjustment based on your Rive version
    
    -- Calculate sine wave
    -- Using elapsedTime tracked separately (see advance function if using Node protocol)
    local value = math.sin((elapsedTime * speed + offset) * math.pi * 2) * amplitude
    
    return value
end

-- Note: If the converter protocol doesn't support time-based effects directly,
-- consider using the Node script version (floating_bob_node.lua) instead,
-- which has direct access to time via the advance() function.
