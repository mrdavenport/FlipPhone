-- Shooting Star System Script
-- Protocol: Node
-- 
-- This script manages shooting stars that orbit around the daily milestone badge.
-- Each star represents a daily session with properties based on session duration and category.
--
-- Setup:
-- 1. Create ViewModel properties in "View Model 1":
--    - starCount (Number): Number of stars to display
--    - badgeShapeValue (Number): Badge shape identifier
--    - orbitRadius (Number): Shared orbit radius for all stars (ellipse-driven or Swift fallback)
--    - orbitHeight (Number): Shared orbit height for all stars (0-1 or pixels, ellipse-driven or Swift fallback)
--    - For each star (0-19): starN_duration, starN_size, starN_trailLength, starN_orbitAngle, starN_colorR, starN_colorG, starN_colorB
--    - For each star (0-19): starN_x, starN_y (position - output), starN_scale, starN_opacity, starN_drawOrder (output)
-- 2. Apply this script to the star container group in the artboard
-- 3. Create star nodes in the artboard (or use state machine to create them)
-- 4. Data-bind star node positions to starN_x and starN_y properties
-- 5. Data-bind star node scales to starN_scale properties
-- 6. Data-bind star node opacities to starN_opacity properties

-- Define the script's data structure
type ShootingStarSystem = {
    time: number,                      -- Time tracker for animations
    starCount: number,                  -- Number of stars to manage
    entranceComplete: boolean,           -- Whether entrance animation is complete
    baseOrbitalSpeed: number,            -- Base speed for orbital animation
    ellipseXScale: number,               -- X scale for elliptical orbit
    ellipseYScale: number,               -- Y scale for elliptical orbit
    centerX: number,                     -- Center X position (badge center)
    centerY: number,                     -- Center Y position (badge center)
    stars: {StarData},                   -- Array of star data (table)
    starCountProp: Property<number>?,    -- ViewModel property for star count
    orbitRadius: number,                 -- Shared orbit radius for all stars (pixels)
    orbitHeight: number,                 -- Shared orbit height (0-1 or pixels)
    orbitRadiusProp: Property<number>?,   -- ViewModel property for orbit radius (global)
    orbitHeightProp: Property<number>?,  -- ViewModel property for orbit height (global)
    -- Orbit visualization properties
    orbitEllipseWidthProp: Property<number>?,  -- ViewModel property for orbit ellipse width
    orbitEllipseHeightProp: Property<number>?, -- ViewModel property for orbit ellipse height
    orbitEllipseXProp: Property<number>?,       -- ViewModel property for orbit ellipse X position
    orbitEllipseYProp: Property<number>?,      -- ViewModel property for orbit ellipse Y position
}

type StarData = {
    index: number,                       -- Star index (0-19)
    duration: number,                    -- Session duration
    size: number,                        -- Star size
    trailLength: number,                 -- Particle trail length
    orbitAngle: number,                  -- Starting orbit angle (radians)
    colorR: number,                       -- Red color component
    colorG: number,                      -- Green color component
    colorB: number,                      -- Blue color component
    currentAngle: number,                 -- Current orbital angle
    orbitalSpeed: number,                -- Orbital speed multiplier (0.8-1.2)
    entranceDelay: number,               -- Delay before entrance animation starts
    entranceProgress: number,            -- Entrance animation progress (0-1)
    xProp: Property<number>?,            -- ViewModel property for X position
    yProp: Property<number>?,            -- ViewModel property for Y position
    scaleProp: Property<number>?,        -- ViewModel property for scale
    opacityProp: Property<number>?,      -- ViewModel property for opacity
    drawOrderProp: Property<number>?,    -- ViewModel property for draw order (0-1, for Rive draw order binding)
    durationProp: Property<number>?,    -- ViewModel property for duration (read-only)
    sizeProp: Property<number>?,         -- ViewModel property for size (read-only)
    trailLengthProp: Property<number>?,  -- ViewModel property for trail length (read-only)
    orbitAngleProp: Property<number>?,  -- ViewModel property for orbit angle (read-only)
    colorRProp: Property<number>?,       -- ViewModel property for color R (read-only)
    colorGProp: Property<number>?,       -- ViewModel property for color G (read-only)
    colorBProp: Property<number>?,       -- ViewModel property for color B (read-only)
    -- Trail particle positions (for separate trail nodes - up to 10 particles per star)
    trail0XProp: Property<number>?,     -- ViewModel property for trail particle 0 X
    trail0YProp: Property<number>?,     -- ViewModel property for trail particle 0 Y
    trail0OpacityProp: Property<number>?, -- ViewModel property for trail particle 0 opacity
    -- ... (add more trail particles as needed, or use a loop in init)
}

local TWO_PI = 2 * math.pi
local MAX_STARS = 20

-- Ease-out cubic function for entrance animation
local function easeOutCubic(t: number): number
    return 1 - math.pow(1 - t, 3)
end

-- Called once when the script initializes
function init(self: ShootingStarSystem, context: Context): boolean
    self.time = 0.0
    self.starCount = 0
    self.entranceComplete = false
    self.baseOrbitalSpeed = 0.3  -- Base orbital speed (radians per second)
    self.ellipseXScale = 1.0
    self.ellipseYScale = 0.8  -- Make orbits elliptical
    self.centerX = 0.0  -- Will be set based on artboard center
    self.centerY = 0.0
    self.stars = {}
    self.starCountProp = nil
    self.orbitRadius = 175.0
    self.orbitHeight = 1.0
    self.orbitRadiusProp = nil
    self.orbitHeightProp = nil
    self.orbitEllipseWidthProp = nil
    self.orbitEllipseHeightProp = nil
    self.orbitEllipseXProp = nil
    self.orbitEllipseYProp = nil
    
    -- Access the ViewModel through context
    local vm = context:viewModel()
    if vm then
        self.starCountProp = vm:getNumber("starCount")
        self.orbitRadiusProp = vm:getNumber("orbitRadius")
        self.orbitHeightProp = vm:getNumber("orbitHeight")
        -- Get orbit visualization properties
        self.orbitEllipseWidthProp = vm:getNumber("orbitEllipseWidth")
        self.orbitEllipseHeightProp = vm:getNumber("orbitEllipseHeight")
        self.orbitEllipseXProp = vm:getNumber("orbitEllipseX")
        self.orbitEllipseYProp = vm:getNumber("orbitEllipseY")
        
        -- Initialize star data structures
        for i = 0, MAX_STARS - 1 do
            local idxStr = tostring(i)
            local star: StarData = {
                index = i,
                duration = 0.0,
                size = 1.0,
                trailLength = 0.0,
                orbitAngle = 0.0,
                colorR = 1.0,
                colorG = 1.0,
                colorB = 1.0,
                currentAngle = 0.0,
                orbitalSpeed = 1.0,
                entranceDelay = i * 0.1,  -- Stagger entrance by 0.1s per star
                entranceProgress = 0.0,
                xProp = vm:getNumber("star" .. idxStr .. "_x"),
                yProp = vm:getNumber("star" .. idxStr .. "_y"),
                scaleProp = vm:getNumber("star" .. idxStr .. "_scale"),
                opacityProp = vm:getNumber("star" .. idxStr .. "_opacity"),
                drawOrderProp = vm:getNumber("star" .. idxStr .. "_drawOrder"),
                durationProp = vm:getNumber("star" .. idxStr .. "_duration"),
                sizeProp = vm:getNumber("star" .. idxStr .. "_size"),
                trailLengthProp = vm:getNumber("star" .. idxStr .. "_trailLength"),
                orbitAngleProp = vm:getNumber("star" .. idxStr .. "_orbitAngle"),
                colorRProp = vm:getNumber("star" .. idxStr .. "_colorR"),
                colorGProp = vm:getNumber("star" .. idxStr .. "_colorG"),
                colorBProp = vm:getNumber("star" .. idxStr .. "_colorB"),
            }
            table.insert(self.stars, star)
        end
    end
    
    return true
end

-- Called every frame to advance the simulation
function advance(self: ShootingStarSystem, seconds: number): boolean
    -- Update time
    self.time = self.time + seconds
    
    -- Get star count from ViewModel
    local newStarCount = 0
    if self.starCountProp then
        newStarCount = math.floor(self.starCountProp.value + 0.5)  -- Round to nearest integer
        newStarCount = math.max(0, math.min(newStarCount, MAX_STARS))  -- Clamp to valid range
    end
    
    -- If star count changed, reset entrance animation and randomize orbit angles
    if newStarCount ~= self.starCount then
        self.starCount = newStarCount
        self.entranceComplete = false
        self.time = 0.0  -- Reset time for entrance animation
        
        -- Reset all stars and randomize orbit angle for each (0 to 2π)
        for i = 1, #self.stars do
            local star = self.stars[i]
            star.entranceProgress = 0.0
            star.orbitAngle = math.random() * TWO_PI
            star.currentAngle = star.orbitAngle
        end
    end
    
    -- Read global orbit properties from ViewModel
    if self.orbitRadiusProp then self.orbitRadius = self.orbitRadiusProp.value end
    if self.orbitHeightProp then self.orbitHeight = self.orbitHeightProp.value end
    
    -- Read star properties from ViewModel and update star data
    for i = 1, math.min(self.starCount, #self.stars) do
        local star = self.stars[i]
        local idx = star.index
        
        -- Read star properties from ViewModel (properties are cached from init)
        -- orbitAngle is randomized in script on reset, not read from ViewModel
        if star.durationProp then star.duration = star.durationProp.value end
        if star.sizeProp then star.size = star.sizeProp.value end
        if star.trailLengthProp then star.trailLength = star.trailLengthProp.value end
        if star.colorRProp then star.colorR = star.colorRProp.value end
        if star.colorGProp then star.colorG = star.colorGProp.value end
        if star.colorBProp then star.colorB = star.colorBProp.value end
        
        -- Calculate orbital speed relative to radius (Kepler's law: speed inversely proportional to sqrt(radius))
        -- Use a reference radius (175.0) to normalize speeds
        local referenceRadius = 175.0
        local radiusFactor = math.sqrt(referenceRadius / math.max(self.orbitRadius, 50.0))  -- Prevent division by zero
        -- Add slight variation for visual interest (0.9x to 1.1x)
        local variation = 0.9 + (idx % 3) * 0.1  -- Cycle through 0.9, 1.0, 1.1
        star.orbitalSpeed = radiusFactor * variation
        
        -- Initialize current angle from orbit angle if not set
        if star.currentAngle == 0.0 and star.orbitAngle ~= 0.0 then
            star.currentAngle = star.orbitAngle
        end
    end
    
    -- Update entrance animation
    if not self.entranceComplete then
        local allComplete = true
        for i = 1, math.min(self.starCount, #self.stars) do
            local star = self.stars[i]
            if self.time >= star.entranceDelay then
                local entranceTime = self.time - star.entranceDelay
                local entranceDuration = 0.5  -- 0.5 seconds for entrance
                star.entranceProgress = math.min(entranceTime / entranceDuration, 1.0)
                star.entranceProgress = easeOutCubic(star.entranceProgress)
            else
                star.entranceProgress = 0.0
            end
            
            if star.entranceProgress < 1.0 then
                allComplete = false
            end
        end
        self.entranceComplete = allComplete
    end
    
    -- Update orbit ellipse visualization (uses shared orbitRadius)
    if self.orbitRadius > 0.0 then
        -- Normalize orbitHeight for ellipse height calculation
        local referenceEllipseHeight = self.orbitRadius * 2.0 * self.ellipseYScale
        local normalizedOrbitHeightForViz = self.orbitHeight
        if self.orbitHeight > 1.0 then
            normalizedOrbitHeightForViz = math.min(1.0, math.max(0, self.orbitHeight / referenceEllipseHeight))
        end
        local ellipseWidth = self.orbitRadius * 2.0 * self.ellipseXScale
        local ellipseHeight = self.orbitRadius * 2.0 * self.ellipseYScale * normalizedOrbitHeightForViz
        if self.orbitEllipseWidthProp then self.orbitEllipseWidthProp.value = ellipseWidth end
        if self.orbitEllipseHeightProp then self.orbitEllipseHeightProp.value = ellipseHeight end
        if self.orbitEllipseXProp then self.orbitEllipseXProp.value = self.centerX end
        if self.orbitEllipseYProp then self.orbitEllipseYProp.value = self.centerY end
    end
    
    -- Update orbital positions for all active stars
    for i = 1, math.min(self.starCount, #self.stars) do
        local star = self.stars[i]
        
        -- Update orbital angle (speed is now relative to radius)
        star.currentAngle = star.currentAngle + (self.baseOrbitalSpeed * star.orbitalSpeed * seconds)
        
        -- Keep angle in 0-2π range
        while star.currentAngle >= TWO_PI do
            star.currentAngle = star.currentAngle - TWO_PI
        end
        while star.currentAngle < 0 do
            star.currentAngle = star.currentAngle + TWO_PI
        end
        
        -- Star position (shared orbit radius and height for all stars)
        -- orbitHeight: 0-1 multiplier, OR pixel height when data-bound to ellipse height in Rive
        -- If > 1, treat as pixels and normalize by reference (orbitRadius * 2 * ellipseYScale)
        local referenceEllipseHeight = self.orbitRadius * 2.0 * self.ellipseYScale
        local normalizedOrbitHeight = self.orbitHeight
        if self.orbitHeight > 1.0 then
            normalizedOrbitHeight = math.min(1.0, math.max(0, self.orbitHeight / referenceEllipseHeight))
        end
        local effectiveYScale = self.ellipseYScale * normalizedOrbitHeight
        local x = self.centerX + self.orbitRadius * math.cos(star.currentAngle) * self.ellipseXScale
        local y = self.centerY + self.orbitRadius * math.sin(star.currentAngle) * effectiveYScale
        
        -- Draw order: 1.0 at sides (in front), 0.0 at top/bottom (behind) - varies as star orbits
        local drawOrder = 1 - math.abs(math.sin(star.currentAngle))
        
        -- Calculate trail positions (for particle trail nodes)
        -- Trail uses same fixed ellipse height for this star
        local trailParticleCount = math.min(math.floor(star.trailLength / 3.0), 10)  -- Max 10 particles
        for trailIdx = 0, trailParticleCount - 1 do
            local trailAngle = star.currentAngle - (trailIdx + 1) * 0.1  -- Trail behind star
            local trailDistance = self.orbitRadius * (1.0 - trailIdx * 0.05)  -- Slightly closer to center
            
            local trailEffectiveYScale = self.ellipseYScale * normalizedOrbitHeight  -- same fixed height as star
            local _trailX = self.centerX + trailDistance * math.cos(trailAngle) * self.ellipseXScale
            local _trailY = self.centerY + trailDistance * math.sin(trailAngle) * trailEffectiveYScale
            local _trailOpacity = star.entranceProgress * (1.0 - trailIdx * 0.1)  -- Fade out
        end
        
        -- Apply entrance animation (scale and opacity)
        local scale = star.size * star.entranceProgress
        local opacity = star.entranceProgress
        
        -- Update ViewModel properties (which are data-bound to star nodes)
        if star.xProp then star.xProp.value = x end
        if star.yProp then star.yProp.value = y end
        if star.scaleProp then star.scaleProp.value = scale end
        if star.opacityProp then star.opacityProp.value = opacity end
        if star.drawOrderProp then star.drawOrderProp.value = drawOrder end
    end
    
    -- Hide inactive stars (beyond starCount)
    for i = self.starCount + 1, #self.stars do
        local star = self.stars[i]
        if star.xProp then star.xProp.value = self.centerX end
        if star.yProp then star.yProp.value = self.centerY end
        if star.scaleProp then star.scaleProp.value = 0.0 end
        if star.opacityProp then star.opacityProp.value = 0.0 end
        if star.drawOrderProp then star.drawOrderProp.value = 0.0 end
    end
    
    return true  -- Keep running
end

-- Called when any input value changes
function update(self: ShootingStarSystem)
    -- Reset entrance animation when star count changes
    self.entranceComplete = false
    self.time = 0.0
end

-- Called every frame (after advance) to render the content
function draw(self: ShootingStarSystem, renderer: Renderer)
    -- Note: Star rendering is handled by the star nodes themselves
    -- This script only updates their positions via ViewModel properties
    -- Particle trails would need to be implemented as separate nodes or via a particle system
end

-- Return a factory function that Rive uses to build the Node instance
return function(): Node<ShootingStarSystem>
    return {
        init = init,
        advance = advance,
        update = update,
        draw = draw,
        time = 0.0,
        starCount = 0,
        entranceComplete = false,
        baseOrbitalSpeed = 0.3,
        ellipseXScale = 1.0,
        ellipseYScale = 0.8,
        centerX = 0.0,
        centerY = 0.0,
        stars = {},
        starCountProp = nil,
        orbitRadius = 175.0,
        orbitHeight = 1.0,
        orbitRadiusProp = nil,
        orbitHeightProp = nil,
        orbitEllipseWidthProp = nil,
        orbitEllipseHeightProp = nil,
        orbitEllipseXProp = nil,
        orbitEllipseYProp = nil,
    }
end
