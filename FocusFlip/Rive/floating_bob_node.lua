    -- Floating/Bobbing Node Script for Hero Animation
    -- Protocol: Node
    -- 
    -- This script directly modifies the transform of a node to create a floating/bobbing effect.
    -- It's simpler to use than a converter and has direct access to time.
    --
    -- Usage in Rive Editor:
    -- 1. Add this as a Node script to your ARTBOARD (not individual nodes)
    -- 2. In the Inspector, you should see "Inputs" section with target, amplitude, frequency, offset
    -- 3. Bind the "target" input to the node you want to float
    -- 4. Adjust the amplitude and frequency values in the Inspector

    -- Script type definition
    export type FloatingBob = {
        target: Input<NodeReadData>,   -- The node we want to float (set in Inspector)
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
        
        -- Store original Y position if target is available
        -- We'll capture this in the first draw call to avoid type checking issues
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
    function draw(self: FloatingBob, renderer)
        -- Ensure we have target bound
        -- Note: Can't use == nil for Input types, use 'not' instead
        if not self.target then
            return
        end
        
        -- Get input values (with defaults if not set)
        local amp = self.amplitude or 2.0
        local freq = self.frequency or 0.6
        local off = self.offset or 0.0
        
        -- Calculate sine wave offset
        -- This creates smooth up/down motion
        local offsetY = amp * math.sin(TWO_PI * freq * self.elapsedTime + off * TWO_PI)
        
        -- Capture original Y position on first draw (if not already captured)
        if self.originalY == nil then
            self.originalY = self.target.y or 0.0
        end
        
        -- Get the original Y as a number (guaranteed to be set at this point)
        local baseY = self.originalY or 0.0
        
        -- Apply offset to target node's Y position (relative to original)
        self.target.y = baseY + offsetY
    end

    -- Factory function: Rive uses this to create script instances
    return function(): Node<FloatingBob>
        return {
            init = init,
            advance = advance,
            draw = draw,
            target = late(),            -- Set this in Inspector by dragging your hero node
            amplitude = 2.0,            -- Subtle: 1-3 pixels, More pronounced: 5-10 pixels
            frequency = 0.6,            -- Subtle: 0.4-0.8, Faster: 1.0-2.0
            offset = 0.0,
            elapsedTime = 0.0,
            originalY = nil,
        }
    end
