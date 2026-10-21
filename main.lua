--[[
    Solar2D Mini Golf Prototype
    Runtime-created display objects only. No images, sounds, plugins, or custom fonts.
    Content area: 1024x768.
--]]

print("Mini Golf: main.lua started")

display.setStatusBar(display.HiddenStatusBar)

local physics = require("physics")
physics.start()
physics.setGravity(0, 0)
physics.setDrawMode("normal")

-- ------------------------------------------------------------
-- Constants
-- ------------------------------------------------------------

local CONTENT_WIDTH = 1024
local CONTENT_HEIGHT = 768

local STATE_AIMING = "aiming"
local STATE_CHARGING = "charging"
local STATE_MOVING = "moving"
local STATE_VICTORY = "victory"

local BALL_RADIUS = 11
local HOLE_RADIUS = 17
local AIM_LINE_LENGTH = 60

local CHARGE_DURATION_MS = 1200
local MIN_LAUNCH_SPEED = 150
local MAX_LAUNCH_SPEED = 900

local STOP_SPEED = 10
local SCORING_MAX_SPEED = 120
local FRICTION_DAMPING_PER_SECOND = 1.35
local WALL_THICKNESS = 24

local COURSE = {
    left = 120,
    top = 120,
    verticalRight = 330,
    turnTop = 400,
    bottom = 610,
    right = 850,
}

local BALL_START_X = 225
local BALL_START_Y = 225
local HOLE_X = 770
local HOLE_Y = 515

-- ------------------------------------------------------------
-- Display groups, created in visible back-to-front order.
-- This matters. If background is inserted last, it covers everything.
-- ------------------------------------------------------------

local backgroundGroup = display.newGroup()
local courseGroup = display.newGroup()
local wallGroup = display.newGroup()
local objectGroup = display.newGroup()
local aimGroup = display.newGroup()
local uiGroup = display.newGroup()
local overlayGroup = display.newGroup()

-- ------------------------------------------------------------
-- Game state
-- ------------------------------------------------------------

local gameState = STATE_AIMING
local shots = 0
local chargePercent = 0
local chargeStartTime = 0
local mouseX = BALL_START_X + 120
local mouseY = BALL_START_Y
local lockedDirX = 1
local lockedDirY = 0
local activePointer = nil
local lastFrameTime = system.getTimer()
local shotLaunchedThisPress = false

local ball
local hole
local aimLine
local gaugeGroup
local gaugeFill
local shotsText
local victoryShotsText
local resetGame

-- ------------------------------------------------------------
-- Utility
-- ------------------------------------------------------------

local function clamp(value, minValue, maxValue)
    if value < minValue then
        return minValue
    elseif value > maxValue then
        return maxValue
    end
    return value
end

local function distance(x1, y1, x2, y2)
    local dx = x2 - x1
    local dy = y2 - y1
    return math.sqrt(dx * dx + dy * dy)
end

local function getDirectionFromBallToPoint(x, y)
    local dx = x - ball.x
    local dy = y - ball.y
    local length = math.sqrt(dx * dx + dy * dy)

    if length < 0.001 then
        return 1, 0
    end

    return dx / length, dy / length
end

local function getBallSpeed()
    local vx, vy = ball:getLinearVelocity()
    return math.sqrt(vx * vx + vy * vy), vx, vy
end

local function ballOverlapsHole()
    return distance(ball.x, ball.y, hole.x, hole.y) <= (BALL_RADIUS + HOLE_RADIUS)
end

local function updateShotsText()
    if shotsText then
        shotsText.text = "SHOTS: " .. tostring(shots)
    end
end

-- ------------------------------------------------------------
-- Course visuals and physics
-- ------------------------------------------------------------

local function createBackground()
    local bg = display.newRect(backgroundGroup, CONTENT_WIDTH * 0.5, CONTENT_HEIGHT * 0.5, CONTENT_WIDTH, CONTENT_HEIGHT)
    bg:setFillColor(0.055, 0.075, 0.085)

    local title = display.newText({
        parent = backgroundGroup,
        text = "MINI GOLF PROTOTYPE",
        x = CONTENT_WIDTH * 0.5,
        y = 42,
        font = native.systemFontBold,
        fontSize = 30,
        align = "center",
    })
    title:setFillColor(0.95, 0.95, 0.95)
end

local function createFloorRect(x, y, width, height)
    local rect = display.newRect(courseGroup, x, y, width, height)
    rect:setFillColor(0.25, 0.68, 0.22)
    rect.strokeWidth = 3
    rect:setStrokeColor(0.10, 0.32, 0.08)
    return rect
end

local function createWall(x, y, width, height)
    local wall = display.newRect(wallGroup, x, y, width, height)
    wall:setFillColor(0.50, 0.52, 0.52)
    wall.strokeWidth = 2
    wall:setStrokeColor(0.12, 0.13, 0.13)

    physics.addBody(wall, "static", {
        bounce = 0.88,
        friction = 0.0,
    })

    return wall
end

local function createCourse()
    -- L-shaped floor from two rectangles.
    createFloorRect(
        (COURSE.left + COURSE.verticalRight) * 0.5,
        (COURSE.top + COURSE.bottom) * 0.5,
        COURSE.verticalRight - COURSE.left,
        COURSE.bottom - COURSE.top
    )

    createFloorRect(
        (COURSE.left + COURSE.right) * 0.5,
        (COURSE.turnTop + COURSE.bottom) * 0.5,
        COURSE.right - COURSE.left,
        COURSE.bottom - COURSE.turnTop
    )

    -- Outer and inner L borders.
    createWall(
        COURSE.left - WALL_THICKNESS * 0.5,
        (COURSE.top + COURSE.bottom) * 0.5,
        WALL_THICKNESS,
        COURSE.bottom - COURSE.top + WALL_THICKNESS
    )

    createWall(
        (COURSE.left + COURSE.verticalRight) * 0.5,
        COURSE.top - WALL_THICKNESS * 0.5,
        COURSE.verticalRight - COURSE.left + WALL_THICKNESS,
        WALL_THICKNESS
    )

    createWall(
        COURSE.verticalRight + WALL_THICKNESS * 0.5,
        (COURSE.top + COURSE.turnTop) * 0.5,
        WALL_THICKNESS,
        COURSE.turnTop - COURSE.top + WALL_THICKNESS
    )

    createWall(
        (COURSE.verticalRight + COURSE.right) * 0.5,
        COURSE.turnTop - WALL_THICKNESS * 0.5,
        COURSE.right - COURSE.verticalRight + WALL_THICKNESS,
        WALL_THICKNESS
    )

    createWall(
        COURSE.right + WALL_THICKNESS * 0.5,
        (COURSE.turnTop + COURSE.bottom) * 0.5,
        WALL_THICKNESS,
        COURSE.bottom - COURSE.turnTop + WALL_THICKNESS
    )

    createWall(
        (COURSE.left + COURSE.right) * 0.5,
        COURSE.bottom + WALL_THICKNESS * 0.5,
        COURSE.right - COURSE.left + WALL_THICKNESS,
        WALL_THICKNESS
    )
end

local function createHole()
    hole = display.newCircle(objectGroup, HOLE_X, HOLE_Y, HOLE_RADIUS)
    hole:setFillColor(0.01, 0.01, 0.01)
    hole.strokeWidth = 4
    hole:setStrokeColor(0.95, 0.95, 0.95)

    local inner = display.newCircle(objectGroup, HOLE_X, HOLE_Y, HOLE_RADIUS * 0.55)
    inner:setFillColor(0, 0, 0)
end

local function createBall()
    ball = display.newCircle(objectGroup, BALL_START_X, BALL_START_Y, BALL_RADIUS)
    ball:setFillColor(0.96, 0.96, 0.94)
    ball.strokeWidth = 2
    ball:setStrokeColor(0.04, 0.04, 0.04)

    physics.addBody(ball, "dynamic", {
        radius = BALL_RADIUS,
        density = 1.0,
        bounce = 0.82,
        friction = 0.0,
    })

    ball.isBullet = true
    ball.linearDamping = 0
    ball.angularDamping = 3
end

-- ------------------------------------------------------------
-- Aim line and power gauge
-- ------------------------------------------------------------

local function removeAimLine()
    if aimLine then
        aimLine:removeSelf()
        aimLine = nil
    end
end

local function drawAimLine(dirX, dirY)
    removeAimLine()

    aimLine = display.newLine(
        aimGroup,
        ball.x,
        ball.y,
        ball.x + dirX * AIM_LINE_LENGTH,
        ball.y + dirY * AIM_LINE_LENGTH
    )
    aimLine.strokeWidth = 4
    aimLine:setStrokeColor(1, 1, 1, 0.92)
end

local function createPowerGauge()
    gaugeGroup = display.newGroup()
    aimGroup:insert(gaugeGroup)

    local back = display.newRoundedRect(gaugeGroup, 0, 0, 100, 18, 4)
    back:setFillColor(0.07, 0.09, 0.09)
    back.strokeWidth = 2
    back:setStrokeColor(0.90, 0.90, 0.90)

    gaugeFill = display.newRoundedRect(gaugeGroup, -48, 0, 1, 12, 3)
    gaugeFill.anchorX = 0
    gaugeFill:setFillColor(1.0, 0.82, 0.10)
    gaugeFill.isVisible = false

    gaugeGroup.isVisible = false
end

local function positionPowerGauge()
    local gaugeWidth = 100
    local gaugeHeight = 18
    local x = clamp(ball.x, gaugeWidth * 0.5 + 8, CONTENT_WIDTH - gaugeWidth * 0.5 - 8)
    local y = ball.y + 38

    if y + gaugeHeight * 0.5 > CONTENT_HEIGHT - 58 then
        y = ball.y - 38
    end

    y = clamp(y, gaugeHeight * 0.5 + 8, CONTENT_HEIGHT - gaugeHeight * 0.5 - 58)

    gaugeGroup.x = x
    gaugeGroup.y = y
end

local function updatePowerGauge()
    positionPowerGauge()
    gaugeFill.width = math.max(1, 96 * chargePercent)
    gaugeFill.isVisible = chargePercent > 0
end

local function hideAimingVisuals()
    removeAimLine()
    gaugeGroup.isVisible = false
    gaugeFill.isVisible = false
    chargePercent = 0
end

-- ------------------------------------------------------------
-- UI
-- ------------------------------------------------------------

local function createText(parent, text, x, y, size)
    local label = display.newText({
        parent = parent,
        text = text,
        x = x,
        y = y,
        font = native.systemFontBold,
        fontSize = size,
        align = "center",
    })
    label:setFillColor(0.95, 0.95, 0.95)
    return label
end

local function createButton(parent, label, x, y, width, height, onRelease)
    local group = display.newGroup()
    parent:insert(group)

    local rect = display.newRoundedRect(group, x, y, width, height, 8)
    rect:setFillColor(0.30, 0.72, 0.24)
    rect.strokeWidth = 2
    rect:setStrokeColor(0.08, 0.24, 0.06)

    local text = display.newText({
        parent = group,
        text = label,
        x = x,
        y = y,
        font = native.systemFontBold,
        fontSize = 24,
        align = "center",
    })
    text:setFillColor(0.02, 0.03, 0.02)

    local lastClickAt = 0
    local function fire()
        local now = system.getTimer()
        if now - lastClickAt < 150 then
            return true
        end
        lastClickAt = now
        if onRelease then
            onRelease()
        end
        return true
    end

    local function onMouseButton(event)
        if event.type == "up" then
            return fire()
        end
        return true
    end

    rect:addEventListener("tap", fire)
    text:addEventListener("tap", fire)
    rect:addEventListener("mouse", onMouseButton)
    text:addEventListener("mouse", onMouseButton)

    return group
end

local function createMainUI()
    createText(uiGroup, "Hold left mouse to charge • Release to shoot", CONTENT_WIDTH * 0.5, 78, 16)
    shotsText = createText(uiGroup, "SHOTS: 0", CONTENT_WIDTH * 0.5, 710, 30)
end

local function createVictoryOverlay()
    overlayGroup.isVisible = false

    local dim = display.newRect(overlayGroup, CONTENT_WIDTH * 0.5, CONTENT_HEIGHT * 0.5, CONTENT_WIDTH, CONTENT_HEIGHT)
    dim:setFillColor(0, 0, 0, 0.42)

    local panel = display.newRoundedRect(overlayGroup, CONTENT_WIDTH * 0.5, CONTENT_HEIGHT * 0.5, 340, 230, 10)
    panel:setFillColor(0.055, 0.065, 0.07)
    panel.strokeWidth = 3
    panel:setStrokeColor(0.28, 0.32, 0.32)

    local title = createText(overlayGroup, "BALL IN THE HOLE!", CONTENT_WIDTH * 0.5, CONTENT_HEIGHT * 0.5 - 72, 30)
    title:setFillColor(0.35, 0.88, 0.28)

    createText(overlayGroup, "SHOTS TAKEN:", CONTENT_WIDTH * 0.5, CONTENT_HEIGHT * 0.5 - 26, 20)
    victoryShotsText = createText(overlayGroup, "0", CONTENT_WIDTH * 0.5, CONTENT_HEIGHT * 0.5 + 20, 42)

    createButton(overlayGroup, "RETRY", CONTENT_WIDTH * 0.5, CONTENT_HEIGHT * 0.5 + 82, 170, 50, function()
        if resetGame then
            resetGame()
        end
    end)
end

-- ------------------------------------------------------------
-- State transitions
-- ------------------------------------------------------------

local function beginAiming()
    if gameState == STATE_VICTORY then
        return
    end

    gameState = STATE_AIMING
    activePointer = nil
    shotLaunchedThisPress = false
    chargePercent = 0
    chargeStartTime = 0
    gaugeGroup.isVisible = false
    gaugeFill.isVisible = false

    local dirX, dirY = getDirectionFromBallToPoint(mouseX, mouseY)
    drawAimLine(dirX, dirY)
end

local function beginCharging(source, x, y)
    if gameState ~= STATE_AIMING then
        return true
    end

    activePointer = source
    shotLaunchedThisPress = false
    mouseX = x
    mouseY = y
    lockedDirX, lockedDirY = getDirectionFromBallToPoint(x, y)
    chargePercent = 0
    chargeStartTime = system.getTimer()
    gameState = STATE_CHARGING

    drawAimLine(lockedDirX, lockedDirY)
    gaugeGroup.isVisible = true
    updatePowerGauge()
    return true
end

local function launchBall()
    if gameState ~= STATE_CHARGING or shotLaunchedThisPress then
        return true
    end

    shotLaunchedThisPress = true

    local speed = MIN_LAUNCH_SPEED + (MAX_LAUNCH_SPEED - MIN_LAUNCH_SPEED) * chargePercent
    speed = clamp(speed, MIN_LAUNCH_SPEED, MAX_LAUNCH_SPEED)

    shots = shots + 1
    updateShotsText()

    hideAimingVisuals()
    gameState = STATE_MOVING
    activePointer = nil

    ball:setLinearVelocity(lockedDirX * speed, lockedDirY * speed)
    return true
end

local function enterVictory()
    gameState = STATE_VICTORY
    activePointer = nil
    hideAimingVisuals()

    ball:setLinearVelocity(0, 0)
    ball.angularVelocity = 0

    victoryShotsText.text = tostring(shots)
    overlayGroup.isVisible = true
end

resetGame = function()
    overlayGroup.isVisible = false

    shots = 0
    updateShotsText()

    chargePercent = 0
    chargeStartTime = 0
    activePointer = nil
    shotLaunchedThisPress = false

    ball.x = BALL_START_X
    ball.y = BALL_START_Y
    ball.rotation = 0
    ball:setLinearVelocity(0, 0)
    ball.angularVelocity = 0

    mouseX = BALL_START_X + 120
    mouseY = BALL_START_Y
    lockedDirX = 1
    lockedDirY = 0

    beginAiming()
end

-- ------------------------------------------------------------
-- Input
-- ------------------------------------------------------------

local function handlePointerMove(x, y)
    mouseX = x
    mouseY = y

    if gameState == STATE_AIMING then
        local dirX, dirY = getDirectionFromBallToPoint(mouseX, mouseY)
        drawAimLine(dirX, dirY)
    end

    return true
end

local function handlePointerUp(source)
    if activePointer and activePointer ~= source then
        return true
    end

    if gameState == STATE_CHARGING then
        launchBall()
    end

    activePointer = nil
    return true
end

local function onMouse(event)
    if gameState == STATE_VICTORY then
        return false
    end

    if event.x and event.y then
        mouseX = event.x
        mouseY = event.y
    end

    if event.type == "down" and event.isPrimaryButtonDown then
        return beginCharging("mouse", event.x, event.y)
    elseif event.type == "move" then
        return handlePointerMove(event.x, event.y)
    elseif event.type == "up" then
        return handlePointerUp("mouse")
    end

    return false
end

local function onTouch(event)
    if gameState == STATE_VICTORY then
        return false
    end

    if event.phase == "began" then
        display.getCurrentStage():setFocus(event.target)
        return beginCharging("touch", event.x, event.y)
    elseif event.phase == "moved" then
        return handlePointerMove(event.x, event.y)
    elseif event.phase == "ended" or event.phase == "cancelled" then
        display.getCurrentStage():setFocus(nil)
        return handlePointerUp("touch")
    end

    return false
end

-- ------------------------------------------------------------
-- Per-frame update
-- ------------------------------------------------------------

local function updateCharging()
    local elapsed = system.getTimer() - chargeStartTime
    chargePercent = clamp(elapsed / CHARGE_DURATION_MS, 0, 1)
    drawAimLine(lockedDirX, lockedDirY)
    updatePowerGauge()

    if chargePercent >= 1 then
        launchBall()
    end
end

local function updateMoving(dt)
    local speed, vx, vy = getBallSpeed()

    if speed > 0 then
        local damping = math.exp(-FRICTION_DAMPING_PER_SECOND * dt)
        ball:setLinearVelocity(vx * damping, vy * damping)
        speed = getBallSpeed()
    end

    if ballOverlapsHole() and speed <= SCORING_MAX_SPEED then
        enterVictory()
        return
    end

    if speed < STOP_SPEED then
        ball:setLinearVelocity(0, 0)
        ball.angularVelocity = 0

        if ballOverlapsHole() then
            enterVictory()
        else
            beginAiming()
        end
    end
end

local function onEnterFrame(event)
    local now = event.time or system.getTimer()
    local dt = math.max(0, (now - lastFrameTime) / 1000)
    lastFrameTime = now

    if gameState == STATE_AIMING then
        local dirX, dirY = getDirectionFromBallToPoint(mouseX, mouseY)
        drawAimLine(dirX, dirY)
    elseif gameState == STATE_CHARGING then
        updateCharging()
    elseif gameState == STATE_MOVING then
        updateMoving(dt)
    end
end

-- ------------------------------------------------------------
-- Startup
-- ------------------------------------------------------------

createBackground()
createCourse()
createHole()
createBall()
createPowerGauge()
createMainUI()
createVictoryOverlay()

Runtime:addEventListener("mouse", onMouse)
Runtime:addEventListener("touch", onTouch)
Runtime:addEventListener("enterFrame", onEnterFrame)

beginAiming()
print("Mini Golf: scene created, aiming state active")
