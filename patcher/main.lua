-- Imports
local Talkies = require('talkies')


-- Constants
local fontPath = "assets/font/Minecraftia-Regular.ttf"
local baseFontSize = 12
local baseBoxThickness = 1
local baseBoxHeight = 32
local outputPaddingX = 12
local outputPaddingY = 6
local outputLineSpacing = 30
local outputTextColor = {0.314, 0.235, 0.482}
local spriteWidth, spriteHeight = 320, 240
local frameCount = 24
local frameRate = 12
local initialDialogDelay = 1
local gameName = "the game"
local patchTime = "5 minutes"
local patchScript = "patch_script.sh"  -- Default patch script

-- Variables
local patchOutput = {}
local patchInProgress = false
local showOutput = false
local font, cybion, spritesheet
local currentFrame = 1
local animationTimer = 0
local animationDuration = 1 / frameRate
local timer = 0
local dialogShown = false
local patchChannel = love.thread.getChannel("patch_output")  -- Channel for output 

local cloudImage
local cloudQuads = {}
local clouds = {}


-- Function to parse command-line arguments
local function parseCommandLineArguments()
    if arg and #arg > 0 then
        for i = 1, #arg do
            if arg[i] == "-f" and arg[i + 1] and arg[i + 1] ~= "" then
                patchScript = arg[i + 1] 
                i = i + 1 
            elseif arg[i] == "-g" and arg[i + 1] and arg[i + 1] ~= "" then
                gameName = arg[i + 1] 
                i = i + 1  
            elseif arg[i] == "-t" and arg[i + 1] and arg[i + 1] ~= "" then
                patchTime = arg[i + 1] 
                i = i + 1  
            end
        end
    end
end


-- Function to wrap text to a maximum line length
function wrapText(text, limit)
    local wrappedText = {}
    local currentLine = ""

    for word in text:gmatch("%S+") do
        if #currentLine + #word + 1 > limit then
            table.insert(wrappedText, currentLine)
            currentLine = word
        else
            currentLine = (currentLine ~= "") and (currentLine .. " " .. word) or word
        end
    end

    table.insert(wrappedText, currentLine)
    return wrappedText
end

-- Read patch output from the channel
function readPatchOutput()
    local line = patchChannel:pop()  -- Attempt to read output
    if line then
        local wrappedLines = wrapText(line, 62)
        for _, wrappedLine in ipairs(wrappedLines) do
            table.insert(patchOutput, wrappedLine)
            if #patchOutput > 3 then
                table.remove(patchOutput, 1)  -- Keep the output limited to the last 3 lines
            end
        end

        -- Check for completion
        if line:find("Patching completed successfully!") then
            patchInProgress = false
            showOutput = false
            PatchComplete() 
            return
        end
        
        -- Check for failure message
        if line:find("Patching process failed!") then
            patchInProgress = false
            showOutput = false
            PatchFailed()
            return
        end
    end
end


-- Function to start patching in a new thread
function startPatchThread()
    local thread = love.thread.newThread("patch_thread.lua")  -- Create new thread for patching
    thread:start(patchScript)  -- Pass the patch script as an argument
    patchInProgress = true
    showOutput = true
end

-- Function to show the initial Talkies dialog with two messages
function showInitialTalkiesDialog()
    Talkies.say("Cybion", "Hello! Welcome to the PortMaster patching shop. Today we will be patching " .. gameName .. " for you.", {
        image = cybion,
        oncomplete = function()
            Talkies.say("Cybion", "The patch will take " .. patchTime .. ". So grab some coffee while you wait. Press A to start the patching process.", {
                image = cybion,
                oncomplete = startPatchThread  -- Start the patching in a new thread
            })
        end
    })
end

-- Function to show patch complete dialog
function PatchComplete()
    Talkies.say("Cybion", "Thank you for waiting, the patching process is complete! Press A to proceed to " .. gameName .. ".", {
        thickness = scaledBoxThickness,
        image = cybion,
        oncomplete = function()
            love.event.quit()  
        end
    })
end

-- Function to show patch failed dialog
function PatchFailed()
    Talkies.say("Cybion", "Patching failed! Please go to the PortMaster Discord for help.", {
        thickness = scaledBoxThickness,
		height = scaledBoxHeight,
        image = cybion,
        oncomplete = function()
            love.event.quit()  
        end
    })
end

-- Function to initialize and start the background music
function startBackgroundMusic()
    if not altLoopSound then
        altLoopSound = love.audio.newSource("assets/sfx/Eternity.ogg", "stream")
        altLoopSound:setLooping(true)
    end
    altLoopSound:play()
end

function love.load()
    parseCommandLineArguments()
    love.graphics.setDefaultFilter("nearest", "nearest") -- Sets filtering globally

    -- Get the screen resolution
    windowWidth, windowHeight = love.window.getDesktopDimensions()

    -- Set fullscreen mode
   -- Set a fixed window size for testing (480x320)
	windowWidth, windowHeight = 640, 480
	love.window.setMode(windowWidth, windowHeight, {fullscreen = false, resizable = false})


	scale, scaleX, scaleY, maxScale, scaledBoxThickness, scaledBoxHeight, fontSize = calculateScale(windowWidth, windowHeight, spriteWidth, spriteHeight)

    initClouds()
  

    -- Load font using calculated fontSize
    font = love.graphics.newFont(fontPath, fontSize or baseFontSize)  -- Ensure fontSize is used if calculated

    -- Load assets
    cybion = love.graphics.newImage("assets/gfx/cybionImage.png")
    spritesheet = love.graphics.newImage("assets/gfx/backgroundSheet.png")

    -- Load sounds
    Talkies.talkSound = love.audio.newSource("assets/sfx/typeSound.ogg", "static")
    Talkies.optionOnSelectSound = love.audio.newSource("assets/sfx/optionSelect.ogg", "static")
    Talkies.optionSwitchSound = love.audio.newSource("assets/sfx/optionSwitch.ogg", "static")

    -- Set Talkies configuration
    Talkies.font = font
    Talkies.characterImage = cybion
    Talkies.textSpeed = "fast"
    Talkies.inlineOptions = true
    Talkies.messageBackgroundColor = {1.000, 0.851, 0.910}
    Talkies.messageColor = outputTextColor
    Talkies.messageBorderColor = outputTextColor
    Talkies.titleColor = outputTextColor
	Talkies.height = scaledBoxHeight
	Talkies.thickness = scaledBoxThickness


   -- startBackgroundMusic()
end




-- Add a new variable for controlling the animation updates
local animationUpdateInterval = 1 / frameRate 
local animationTimer = 0 

function love.update(dt)
    Talkies.update(dt)
	 updateClouds(dt)  -- Update cloud positions
    -- Update animation timer every frame
    animationTimer = animationTimer + dt
    if animationTimer >= animationUpdateInterval then
        animationTimer = animationTimer - animationUpdateInterval
        currentFrame = (currentFrame % frameCount) + 1 
    end

    -- Handle dialog showing with a separate timer
    timer = timer + dt
    if not dialogShown and timer >= initialDialogDelay then
        showInitialTalkiesDialog()
        dialogShown = true
    end

    -- Read patch output from the thread
    if patchInProgress then
        readPatchOutput()  -- Check for output from the patch thread
    end
end


function calculateScale(windowWidth, windowHeight, spriteWidth, spriteHeight)
    local scale = math.min(windowWidth / spriteWidth, windowHeight / spriteHeight)
    local scaleX = windowWidth / spriteWidth
    local scaleY = windowHeight / spriteHeight
    local maxScale = math.min(scaleX, scaleY)

    local scaledBoxThickness = math.floor(baseBoxThickness * maxScale) 
	local scaledBoxHeight = math.floor(baseBoxHeight * scale) 



    if windowWidth >= 640 and windowHeight >= 480 then
        fontSize = math.floor(baseFontSize * maxScale / 14) * 14 -- Ensure multiples of 14
    else
        fontSize = math.max(12, math.floor(baseFontSize * maxScale)) -- Round to integers, minimum 12
    end

    print("Window:", windowWidth, windowHeight)
    print("Sprite:", spriteWidth, spriteHeight)
    print("Scale:", scale, "ScaleX:", scaleX, "ScaleY:", scaleY, "maxScale:", maxScale)
    print("Scaled Box Thickness:", scaledBoxThickness)
    print("Font Size:", fontSize)

    return math.floor(scale), scaleX, scaleY, maxScale, scaledBoxThickness, scaledBoxHeight, fontSize
end



function love.draw()
    -- Get the scaling factors
    local scale, scaleX, scaleY, maxScale = calculateScale(windowWidth, windowHeight, spriteWidth, spriteHeight)

    -- Calculate centering offsets based on uniform scale
    local offsetX = math.floor((windowWidth - spriteWidth * scale) / 2)
    local offsetY = windowHeight - (spriteHeight * scale)

    -- Draw white on top
    love.graphics.setColor(0.502, 0.816, 1.0)

    love.graphics.rectangle("fill", 0, 0, windowWidth, windowHeight)

    -- Draw black on bottom
    love.graphics.setColor(1.0, 0.858, 0.686)

    love.graphics.rectangle("fill", 0, windowHeight - ( 46 * scale), windowWidth, windowHeight)
	
	 -- Draw clouds
    drawClouds()
	
	
    -- Reset color before drawing the sprite
    love.graphics.setColor(1, 1, 1)

    -- Calculate the position of the current frame on the spritesheet
    local frameX = (currentFrame - 1) * spriteWidth

    -- Create a new quad for the current frame
    local frameQuad = love.graphics.newQuad(frameX, 0, spriteWidth, spriteHeight, spritesheet:getDimensions())

    -- Draw the frame from the spritesheet
    love.graphics.draw(
       spritesheet,  -- The spritesheet image
        frameQuad,    -- The current frame's quad
        offsetX, offsetY,  -- Offsets for centering
        0, scale, scale    -- Rotation (0) and uniform scaling
		)

    -- Draw dialogue using Talkies
    Talkies.draw()

    -- Draw output text if needed
    if showOutput then
        love.graphics.setFont(font)  -- Set the font for drawing text
        local lineSpacing = outputLineSpacing / scaleY
        local outputHeight = #patchOutput * lineSpacing
        local outputY = math.max(windowHeight - outputHeight - (outputPaddingY * scaleY), 0)

        for i, line in ipairs(patchOutput) do
            love.graphics.setColor(outputTextColor)  -- Set text color
            love.graphics.print(line, outputPaddingX * scaleX, outputY + (i - 1) * lineSpacing)
        end

        -- Reset the color back to white
        love.graphics.setColor(1, 1, 1)
    end
end

function drawClouds()
    love.graphics.setColor(1, 1, 1)  -- Set color for clouds
    
    -- Draw each cloud using its calculated scale
    for _, cloud in ipairs(clouds) do
        love.graphics.draw(cloudImage, cloud.quad, cloud.x, cloud.y, 0, scale, scale)
    end

    love.graphics.setColor(1, 1, 1)  -- Reset color
end

function updateClouds(dt)
    for _, cloud in ipairs(clouds) do
        -- Move clouds leftward based on speed
        cloud.x = cloud.x - cloud.speed * dt

        -- If the cloud moves off the left side, bring it back from the right with a random Y position
        if cloud.x < -64 * scale then
            cloud.x = love.math.random(windowWidth, windowWidth * 2)  -- Start from the right again
            cloud.y = love.math.random(20, windowHeight / 3)  -- Random Y position
        end
    end
end


function initClouds()
    cloudImage = love.graphics.newImage("assets/gfx/clouds-1.png")  -- Load cloud spritesheet

    -- Create quads (each cloud is 64x64, 6 clouds in a row)
    for i = 0, 5 do
        cloudQuads[i + 1] = love.graphics.newQuad(i * 64, 0, 64, 64, cloudImage:getDimensions())
    end

    -- Define a minimum height for clouds, ensuring they stay above the ground (bottom 20%)
    local minCloudY = windowHeight * 0.4  -- Clouds will be within the top 80% of the screen height

    -- Increase number of clouds based on scaleY (higher scaleY, more clouds)
    local numClouds = math.floor(10 * scaleY)  -- More clouds for taller screens

    -- Generate random clouds, but now start them directly on screen
    for i = 1, numClouds do  -- Adjusted cloud count based on scaleY
        -- Calculate the Y-position with a preference for the top of the screen
        local yPos = math.random() ^ 2 * minCloudY -50 -- Exponential bias, more clouds at the top

        -- Ensure clouds start within the top 80% of the screen, above the bottom 20%
        table.insert(clouds, {
            x = love.math.random(0, windowWidth * 1.5),  -- Cloud starts on screen, not offscreen
            y = yPos,  -- Y-position with preference for the top
            quad = cloudQuads[love.math.random(1, 6)],  
            speed = love.math.random(5, 20) * scale  -- Scale speed
        })
    end
end




function love.gamepadpressed(joystick, button)
    if button == "a" then
        if not patchInProgress and dialogShown then
            Talkies.onAction() 
        end
    end
end

