-- First, require any dependencies
local Talkies = require('talkies')

-- Configuration tables
local Config = {
    WINDOW = {
        DEFAULT_WIDTH = 640,
        DEFAULT_HEIGHT = 480,
        FULLSCREEN = false,
        RESIZABLE = false
    },
    FONT = {
        PATH = "assets/font/Minecraftia-Regular.ttf",
        BASE_SIZE = 12
    },
    DIALOG = {
        BOX_THICKNESS = 1,
        BOX_HEIGHT = 32,
        PADDING_X = 12,
        PADDING_Y = 6,
        LINE_SPACING = 30,
        TEXT_COLOR = {0.314, 0.235, 0.482},
        INITIAL_DELAY = 1
    },
    SPRITE = {
        WIDTH = 320,
        HEIGHT = 240,
        FRAME_COUNT = 24,
        FRAME_RATE = 12
    },
    COLORS = {
        SKY = {1.0, 0.858, 0.686},
        GROUND = {1.0, 0.612, 0.443}
    }
}

local Assets = {
    IMAGES = {
        CYBION = "assets/gfx/cybionImage.png",
        SPRITESHEET = "assets/gfx/backgroundSheet.png",
        CLOUDS = "assets/gfx/clouds.png"
    },
    SOUNDS = {
        TALK = "assets/sfx/typeSound.ogg",
        OPTION_SELECT = "assets/sfx/optionSelect.ogg",
        OPTION_SWITCH = "assets/sfx/optionSwitch.ogg",
        BACKGROUND = "assets/sfx/Eternity.ogg"
    }
}

-- Initialize global state
local GameState = {
    patchInProgress = false,
    showOutput = false,
    dialogShown = false,
    currentFrame = 1,
    timer = 0,
    animationTimer = 0,
    patchOutput = {},
    clouds = {},
    windowWidth = 0,
    windowHeight = 0,
    scale = 1
}

local Resources = {
    font = nil,
    cybion = nil,
    spritesheet = nil,
    cloudImage = nil,
    cloudQuads = {},
    messages = {},
    patchChannel = love.thread.getChannel("patch_output")
}

local Args = {
    patchScript = "patch_script.sh",
    gameName = "the game",
    patchTime = "5 minutes",
    messagesFile = "messages.lua"
}

-- Utility functions
local Utils = {
    parseArgs = function()
        if arg and #arg > 0 then
            for i = 1, #arg do
                if arg[i] == "-f" and arg[i + 1] and arg[i + 1] ~= "" then
                    Args.patchScript = arg[i + 1]
                    i = i + 1
                elseif arg[i] == "-g" and arg[i + 1] and arg[i + 1] ~= "" then
                    Args.gameName = arg[i + 1]
                    i = i + 1
                elseif arg[i] == "-t" and arg[i + 1] and arg[i + 1] ~= "" then
                    Args.patchTime = arg[i + 1]
                    i = i + 1
                elseif arg[i] == "-m" and arg[i + 1] and arg[i + 1] ~= "" then
                    Args.messagesFile = arg[i + 1]
                    i = i + 1
                end
            end
        end
    end,

    wrapText = function(text, limit)
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
    end,

    calculateScale = function()
        local scaleX = GameState.windowWidth / Config.SPRITE.WIDTH
        local scaleY = GameState.windowHeight / Config.SPRITE.HEIGHT
        GameState.scale = math.min(scaleX, scaleY)
        
        return {
            scale = GameState.scale,
            scaleX = scaleX,
            scaleY = scaleY,
            maxScale = math.min(scaleX, scaleY),
            boxThickness = math.floor(Config.DIALOG.BOX_THICKNESS * GameState.scale),
            boxHeight = math.floor(Config.DIALOG.BOX_HEIGHT * GameState.scale),
            fontSize = math.max(12, math.floor(Config.FONT.BASE_SIZE * GameState.scale))
        }
    end,
	
	loadMessages = function()
    -- Try to load custom messages first
    local function loadExternalMessages(filePath)
        local file = io.open(filePath, "r")
        if not file then
            print("Failed to load messages from:", filePath)
            return nil
        end

        local content = file:read("*a")
        file:close()

        local chunk, err = load(content, "messages", "t", {})
        if not chunk then
            print("Error loading messages:", err)
            return nil
        end

        return chunk()
    end

    -- Try to load custom messages, fall back to defaults if that fails
    local customMessages = loadExternalMessages(Args.messagesFile)
    if customMessages then
        print("Custom messages loaded from", Args.messagesFile)
        return customMessages
    else
        print("Using default messages")
        return {
            intro1 = "Hello! Welcome to the PortMaster patching shop. Today we will be patching " .. Args.gameName .. " for you.",
            intro2 = "The patch will take " .. Args.patchTime .. ". So grab some coffee while you wait. Press A to start the patching process.",
            complete = "Thank you for waiting, the patching process is complete! Press A to proceed to " .. Args.gameName .. ".",
            failed = "Patching failed! Please go to the PortMaster Discord for help."
        }
    end
end
	
}

-- Forward declare systems that need to reference each other
local CloudSystem
local DialogSystem
local PatchSystem
local SpriteSystem

-- Initialize systems after all dependencies are available
PatchSystem = {
    start = function()
        local thread = love.thread.newThread("patch_thread.lua")
        thread:start(Args.patchScript)
        GameState.patchInProgress = true
        GameState.showOutput = true
    end,

    readOutput = function()
        local line = Resources.patchChannel:pop()
        if line then
            local wrappedLines = Utils.wrapText(line, 62)
            for _, wrappedLine in ipairs(wrappedLines) do
                table.insert(GameState.patchOutput, wrappedLine)
                if #GameState.patchOutput > 3 then
                    table.remove(GameState.patchOutput, 1)
                end
            end

            if line:find("Patching completed successfully!") then
                GameState.patchInProgress = false
                GameState.showOutput = false
                DialogSystem.showComplete()
                return
            end
            
            if line:find("Patching process failed!") then
                GameState.patchInProgress = false
                GameState.showOutput = false
                DialogSystem.showFailed()
                return
            end
        end
    end
}

DialogSystem = {
    showInitial = function()
        Talkies.say("Cybion", Resources.messages.intro1, {
            image = Resources.cybion,
            oncomplete = function()
                Talkies.say("Cybion", Resources.messages.intro2, {
                    image = Resources.cybion,
                    oncomplete = PatchSystem.start
                })
            end
        })
    end,

    showComplete = function()
        Talkies.say("Cybion", Resources.messages.complete, {
            image = Resources.cybion,
            oncomplete = function()
                love.event.quit()
            end
        })
    end,

    showFailed = function()
        Talkies.say("Cybion", Resources.messages.failed, {
            image = Resources.cybion,
            oncomplete = function()
                love.event.quit()
            end
        })
    end
}

CloudSystem = {
    init = function()
        Resources.cloudImage = love.graphics.newImage(Assets.IMAGES.CLOUDS)
        
        -- Create cloud quads
        for i = 0, 5 do
            Resources.cloudQuads[i + 1] = love.graphics.newQuad(
                i * 64, 0, 64, 64,
                Resources.cloudImage:getDimensions()
            )
        end
        
        CloudSystem.generateClouds()
    end,

    generateClouds = function()
        local minCloudY = GameState.windowHeight * 0.4
        local numClouds = math.floor(100)
        
        for i = 1, numClouds do
            local yPos = math.random() ^ 2 * minCloudY - 50
            table.insert(GameState.clouds, {
                x = love.math.random(0, GameState.windowWidth * 1.5),
                y = yPos,
                quad = Resources.cloudQuads[love.math.random(1, 6)],
                speed = love.math.random(5, 20) * GameState.scale
            })
        end
    end,

    update = function(dt)
        for _, cloud in ipairs(GameState.clouds) do
            cloud.x = cloud.x - cloud.speed * dt
            if cloud.x < -64 * GameState.scale then
                cloud.x = love.math.random(GameState.windowWidth, GameState.windowWidth * 2)
                cloud.y = love.math.random(20, GameState.windowHeight / 3)
            end
        end
    end,

    draw = function()
        love.graphics.setColor(1, 1, 1)
        for _, cloud in ipairs(GameState.clouds) do
            love.graphics.draw(Resources.cloudImage, cloud.quad, 
                cloud.x, cloud.y, 0, GameState.scale, GameState.scale)
        end
    end
}

-- Add the SpriteSystem implementation
SpriteSystem = {
    init = function()
        Resources.spritesheet = love.graphics.newImage(Assets.IMAGES.SPRITESHEET)
    end,

    update = function(dt)
        -- Update animation
        GameState.animationTimer = GameState.animationTimer + dt
        if GameState.animationTimer >= 1 / Config.SPRITE.FRAME_RATE then
            GameState.animationTimer = GameState.animationTimer - 1 / Config.SPRITE.FRAME_RATE
            GameState.currentFrame = (GameState.currentFrame % Config.SPRITE.FRAME_COUNT) + 1
        end
    end,

    draw = function()
        love.graphics.setColor(1, 1, 1)
        local frameX = (GameState.currentFrame - 1) * Config.SPRITE.WIDTH
        local frameQuad = love.graphics.newQuad(
            frameX, 0,
            Config.SPRITE.WIDTH,
            Config.SPRITE.HEIGHT,
            Resources.spritesheet:getDimensions()
        )
        
        local offsetX = math.floor((GameState.windowWidth - Config.SPRITE.WIDTH * GameState.scale) / 2)
        local offsetY = GameState.windowHeight - (Config.SPRITE.HEIGHT * GameState.scale)
        
        love.graphics.draw(
            Resources.spritesheet,
            frameQuad,
            offsetX,
            offsetY,
            0,
            GameState.scale,
            GameState.scale
        )
    end,

    -- Helper function to get current frame info
    getCurrentFrame = function()
        return GameState.currentFrame
    end,

    -- Helper function to reset animation
    resetAnimation = function()
        GameState.currentFrame = 1
        GameState.animationTimer = 0
    end
}



-- LÖVE callbacks
function love.load()
    Utils.parseArgs()
    love.graphics.setDefaultFilter("nearest", "nearest")
    
    GameState.windowWidth, GameState.windowHeight = Config.WINDOW.DEFAULT_WIDTH, Config.WINDOW.DEFAULT_HEIGHT
    love.window.setMode(GameState.windowWidth, GameState.windowHeight, {
        fullscreen = Config.WINDOW.FULLSCREEN,
        resizable = Config.WINDOW.RESIZABLE
    })

    local scaling = Utils.calculateScale()
    
    -- Initialize resources
    Resources.font = love.graphics.newFont(Config.FONT.PATH, scaling.fontSize)
    Resources.cybion = love.graphics.newImage(Assets.IMAGES.CYBION)
    Resources.messages = Utils.loadMessages()  -- Load messages here
    
    -- Initialize systems
    SpriteSystem.init()
    CloudSystem.init()
    
    -- Configure Talkies
    Talkies.font = Resources.font
    Talkies.talkSound = love.audio.newSource(Assets.SOUNDS.TALK, "static")
    Talkies.optionOnSelectSound = love.audio.newSource(Assets.SOUNDS.OPTION_SELECT, "static")
    Talkies.optionSwitchSound = love.audio.newSource(Assets.SOUNDS.OPTION_SWITCH, "static")
    Talkies.characterImage = Resources.cybion
    Talkies.textSpeed = "fast"
    Talkies.inlineOptions = true
    Talkies.messageBackgroundColor = {1.000, 0.851, 0.910}
    Talkies.messageColor = Config.DIALOG.TEXT_COLOR
    Talkies.messageBorderColor = Config.DIALOG.TEXT_COLOR
    Talkies.titleColor = Config.DIALOG.TEXT_COLOR
    Talkies.height = scaling.boxHeight
    Talkies.thickness = scaling.boxThickness
end

-- Modify love.update() to use SpriteSystem
function love.update(dt)
    Talkies.update(dt)
    CloudSystem.update(dt)
    SpriteSystem.update(dt)  -- Update sprite animation
    
    -- Handle dialog
    GameState.timer = GameState.timer + dt
    if not GameState.dialogShown and GameState.timer >= Config.DIALOG.INITIAL_DELAY then
        DialogSystem.showInitial()
        GameState.dialogShown = true
    end

    -- Handle patch system
    if GameState.patchInProgress then
        PatchSystem.readOutput()
    end
end

-- Modify love.draw() to use SpriteSystem
function love.draw()
    -- Draw background
    love.graphics.setColor(Config.COLORS.SKY)
    love.graphics.rectangle("fill", 0, 0, GameState.windowWidth, GameState.windowHeight)
    
    love.graphics.setColor(Config.COLORS.GROUND)
    love.graphics.rectangle("fill", 0, GameState.windowHeight - (46 * GameState.scale),
        GameState.windowWidth, GameState.windowHeight)
    
    -- Draw game elements
    CloudSystem.draw()
    SpriteSystem.draw()  -- Draw sprite animation
    
    -- Draw UI elements
    Talkies.draw()
    
    -- Draw patch output if needed
    if GameState.showOutput then
        love.graphics.setFont(Resources.font)
        local lineSpacing = Config.DIALOG.LINE_SPACING / GameState.scale
        local outputHeight = #GameState.patchOutput * lineSpacing
        local outputY = math.max(GameState.windowHeight - outputHeight -
            (Config.DIALOG.PADDING_Y * GameState.scale), 0)
        
        for i, line in ipairs(GameState.patchOutput) do
            love.graphics.setColor(Config.DIALOG.TEXT_COLOR)
            love.graphics.print(line, Config.DIALOG.PADDING_X * GameState.scale,
                outputY + (i - 1) * lineSpacing)
        end
        
        love.graphics.setColor(1, 1, 1)
    end
end

function love.gamepadpressed(joystick, button)
    if button == "a" and not GameState.patchInProgress and GameState.dialogShown then
        Talkies.onAction()
    end
end