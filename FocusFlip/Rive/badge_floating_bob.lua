-- Badge Floating Bob Script
-- Protocol: Node
--
-- A soft, gentle floating/bobbing effect for badges.
--
-- Usage in Rive Editor:
-- 1. Create a new Node script (Assets → Add Script → Node)
-- 2. Paste this script and save as "BadgeFloatingBob"
-- 3. Apply the script to your ARTBOARD (or a parent of the badge)
-- 4. Bind the "target" input: drag your badge group from Hierarchy onto the target field
-- 5. Adjust amplitude/frequency in the Inspector
--
-- Recommended for badges: amplitude 3–6, frequency 0.5–0.8

export type BadgeFloatingBob = {
    target: Input<NodeReadData>,  -- Badge/node to float (bind in Inspector)
    amplitude: Input<number>,
    frequency: Input<number>,
    offset: Input<number>,
    elapsedTime: number,
    originalY: number?,
}

local TWO_PI = 2 * math.pi

function init(self: BadgeFloatingBob): boolean
    self.elapsedTime = 0.0
    self.originalY = nil
    return true
end

function advance(self: BadgeFloatingBob, seconds: number): boolean
    self.elapsedTime = self.elapsedTime + seconds
    return true
end

function draw(self: BadgeFloatingBob, renderer: Renderer)
    if not self.target then return end

    local amp = self.amplitude or 4.0
    local freq = self.frequency or 0.6
    local off = self.offset or 0.0

    if self.originalY == nil then
        self.originalY = self.target.y or 0.0
    end
    local baseY = self.originalY or 0.0

    local offsetY = amp * math.sin(TWO_PI * freq * self.elapsedTime + off * TWO_PI)
    self.target.y = baseY + offsetY
end

return function(): Node<BadgeFloatingBob>
    return {
        init = init,
        advance = advance,
        draw = draw,
        target = late(),    -- Drag your badge group here
        amplitude = 4.0,    -- Soft: 3–6 px
        frequency = 0.6,    -- Gentle: 0.5–0.8
        offset = 0.0,
        elapsedTime = 0.0,
        originalY = nil,
    }
end
