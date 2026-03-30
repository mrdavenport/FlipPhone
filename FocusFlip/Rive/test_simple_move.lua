-- Simple Test Script - Just moves a node horizontally
-- Protocol: Node
-- 
-- This is a minimal test script to verify Node scripts work.
-- If this works, you'll see the node move horizontally back and forth.

-- Define the script's data and inputs.
type TestMove = {
    speed: Input<number>,    -- How fast it moves
    elapsedTime: number,      -- Time tracker
    originalX: number?,       -- Store original X position
}

-- Called once when the script initializes.
function init(self: TestMove, context: Context): boolean
    self.elapsedTime = 0.0
    self.originalX = nil
    return true
end

-- Called every frame to advance the simulation.
function advance(self: TestMove, seconds: number): boolean
    self.elapsedTime = self.elapsedTime + seconds
    return true  -- Keep running
end

-- Called when any input value changes.
function update(self: TestMove)
    -- Nothing needed
end

-- Called every frame (after advance) to render the content.
function draw(self: TestMove, renderer: Renderer)
    -- Minimal draw function - just to verify script runs
    -- We'll add node movement once we know the script works
end

-- Return a factory function that Rive uses to build the Node instance.
return function(): Node<TestMove>
    return {
        init = init,
        advance = advance,
        update = update,
        draw = draw,
        speed = 50.0,  -- Default: 50 pixels movement
        elapsedTime = 0.0,
        originalX = nil,
    }
end
