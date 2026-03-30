-- Test Script - Testing different ways to access the node
-- Protocol: Node
-- 
-- This script tests different approaches to access and modify the node
-- it's attached to. We'll try multiple API patterns to find what works.

-- Define the script's data and inputs.
type TestMove = {
    speed: Input<number>,    -- How fast it moves
    elapsedTime: number,     -- Time tracker
    originalX: number?,      -- Store original X position
}

-- Called once when the script initializes.
function init(self: TestMove, context: Context): boolean
    self.elapsedTime = 0.0
    self.originalX = nil
    
    -- Try to access the node through context
    -- Comment out lines that cause errors and try the next one
    
    -- Try 1: context might have the node
    -- if context.node then
    --     self.originalX = context.node.x or 0.0
    -- end
    
    -- Try 2: context might have an artboard
    -- if context.artboard then
    --     -- might need to find the node another way
    -- end
    
    return true
end

-- Called every frame to advance the simulation.
function advance(self: TestMove, seconds: number): boolean
    self.elapsedTime = self.elapsedTime + seconds
    return true
end

-- Called when any input value changes.
function update(self: TestMove)
    -- Nothing needed
end

-- Called every frame (after advance) to render the content.
function draw(self: TestMove, renderer: Renderer)
    -- Try different ways to access/modify the node
    -- Comment out what doesn't work, keep what does
    
    -- Get speed - Input<number> should be accessed directly
    local speed = self.speed or 50.0
    
    -- Calculate movement
    local offsetX = math.sin(self.elapsedTime) * speed
    
    -- Try 1: Check if self has a node property (it doesn't seem to)
    -- if self.node then
    --     if self.originalX == nil then
    --         self.originalX = self.node.x or 0.0
    --     end
    --     self.node.x = (self.originalX or 0.0) + offsetX
    -- end
    
    -- Try 2: Maybe the renderer has methods to translate
    -- (We know renderer.translate doesn't exist)
    
    -- Try 3: Maybe we need to store node reference in init via context
    -- (Test this if we find how to access it)
    
    -- For now, let's just make sure the script runs
    -- We'll need to figure out the correct API
end

-- Return a factory function that Rive uses to build the Node instance.
return function(): Node<TestMove>
    return {
        init = init,
        advance = advance,
        update = update,
        draw = draw,
        speed = 50.0,
        elapsedTime = 0.0,
        originalX = nil,
    }
end
