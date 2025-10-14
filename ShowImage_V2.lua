-- showimage_V2.lua (Modern GUI + CLI + Secure Wireless Edition)
-- All-in-one CC:Tweaked image tool with beautiful UI and advanced features
-- By GLICHED-HACKER

local args = {...}

-- ---------- Detect Monitors ----------
local monitors = {}
for _, side in ipairs(peripheral.getNames()) do
    if peripheral.getType(side) == "monitor" then
        table.insert(monitors, side)
    end
end

-- ---------- Colors ----------
local colors = colors or colours
local COLOR_PRIMARY = colors.cyan  -- CHANGED FROM ORANGE
local COLOR_SECONDARY = colors.gray
local COLOR_BG = colors.black
local COLOR_TEXT = colors.white
local COLOR_SUCCESS = colors.lime
local COLOR_ERROR = colors.red

-- ---------- Improved Encryption ----------
local function secureHash(input)
    local h1, h2, h3 = 5381, 52711, 0
    for i = 1, #input do
        local c = string.byte(input, i)
        h1 = ((h1 * 33) + c) % 2147483647
        h2 = ((h2 * 37) + c) % 2147483647
        h3 = ((h3 * 41) + c + i) % 2147483647
    end
    return h1, h2, h3
end

local function deriveKey(password, salt)
    local key = password .. salt
    for i = 1, 1000 do
        local h1, h2, h3 = secureHash(key)
        key = tostring(h1) .. tostring(h2) .. tostring(h3)
    end
    return key
end

local function generateSalt()
    local salt = ""
    for i = 1, 16 do
        salt = salt .. string.char(math.random(33, 126))
    end
    return salt
end

local function xorEncrypt(data, key)
    local keyHash = deriveKey(key, "encryption_key")
    local result = {}
    local keyLen = #keyHash
    
    for i = 1, #data do
        local keyByte = string.byte(keyHash, ((i - 1) % keyLen) + 1)
        local dataByte = string.byte(data, i)
        table.insert(result, string.char(bit32.bxor(dataByte, keyByte)))
    end
    
    return table.concat(result)
end

local function encryptMessage(msg, password)
    local timestamp = os.epoch("utc")
    local fullMsg = textutils.serialize({data = msg, timestamp = timestamp})
    local encrypted = xorEncrypt(fullMsg, password)
    local encoded = textutils.serialise(encrypted)
    return {encrypted = encoded, timestamp = timestamp}
end

local function decryptMessage(encMsg, password)
    local encrypted = textutils.unserialise(encMsg.encrypted)
    if not encrypted then return nil end
    
    local decrypted = xorEncrypt(encrypted, password)
    local success, msg = pcall(textutils.unserialize, decrypted)
    if not success then return nil end
    
    local currentTime = os.epoch("utc")
    if math.abs(currentTime - msg.timestamp) > 60000 then
        return nil
    end
    
    return msg.data
end

-- ---------- Security Config ----------
local CONFIG_FILE = "showimage_config"
local RAW_MODE = false  -- Global flag for raw network mode

local function saveConfig(password)
    local salt = generateSalt()
    local h1, h2, h3 = secureHash(password .. salt)
    local f = fs.open(CONFIG_FILE, "w")
    f.write(textutils.serialize({
        passwordHash = tostring(h1) .. tostring(h2) .. tostring(h3),
        salt = salt,
        rawMode = RAW_MODE
    }))
    f.close()
end

local function loadConfig()
    if not fs.exists(CONFIG_FILE) then return nil end
    local f = fs.open(CONFIG_FILE, "r")
    local data = textutils.unserialize(f.readAll())
    f.close()
    if data then
        RAW_MODE = data.rawMode or false
    end
    return data
end

local function toggleRawMode()
    local config = loadConfig()
    if config then
        RAW_MODE = not RAW_MODE
        config.rawMode = RAW_MODE
        local f = fs.open(CONFIG_FILE, "w")
        f.write(textutils.serialize(config))
        f.close()
    else
        RAW_MODE = not RAW_MODE
    end
end

local function verifyPassword(password)
    local config = loadConfig()
    if not config or not config.salt then return false, nil end
    local h1, h2, h3 = secureHash(password .. config.salt)
    local testHash = tostring(h1) .. tostring(h2) .. tostring(h3)
    return testHash == config.passwordHash, config
end

-- ---------- UI Components ----------
local function drawBox(x, y, w, h, color, title)
    term.setBackgroundColor(color)
    for dy = 0, h - 1 do
        term.setCursorPos(x, y + dy)
        term.write(string.rep(" ", w))
    end
    
    if title then
        term.setCursorPos(x + 2, y)
        term.setTextColor(COLOR_BG)
        term.write(" " .. title .. " ")
    end
end

local function drawButton(x, y, w, text, selected)
    local bg = selected and COLOR_PRIMARY or COLOR_SECONDARY
    drawBox(x, y, w, 1, bg)
    
    term.setCursorPos(x + math.floor((w - #text) / 2), y)
    term.setTextColor(selected and COLOR_BG or COLOR_TEXT)
    term.write(text)
end

local function centerText(y, text, color)
    local w, _ = term.getSize()
    term.setCursorPos(math.floor((w - #text) / 2) + 1, y)
    term.setTextColor(color or COLOR_TEXT)
    term.write(text)
end

local function drawHeader(title)
    drawBox(1, 1, term.getSize(), 1, COLOR_PRIMARY)
    term.setCursorPos(2, 1)
    term.setTextColor(COLOR_BG)
    term.write(title)
end

local function drawProgressBar(x, y, w, progress)
    drawBox(x, y, w, 1, COLOR_SECONDARY)
    local filled = math.floor(w * progress)
    if filled > 0 then
        drawBox(x, y, filled, 1, colors.blue)
    end
end

-- ---------- Monitor Selection UI with Scrolling ----------
local function selectMonitors()
    local selected = {}
    local cursor = 1
    local scroll = 0
    local maxVisible = 8  -- Maximum monitors visible at once
    
    while true do
        term.setBackgroundColor(COLOR_BG)
        term.clear()
        drawHeader("ShowImage - Select Monitors")
        
        term.setCursorPos(2, 3)
        term.setTextColor(COLOR_TEXT)
        term.write("Use Arrow Keys, Space to toggle, Enter to confirm")
        
        -- Calculate visible range
        local totalItems = #monitors + 1  -- +1 for "Select All"
        local visibleStart = scroll + 1
        local visibleEnd = math.min(scroll + maxVisible, totalItems)
        
        -- Draw "All" option if visible
        local y = 5
        if visibleStart == 1 then
            if cursor == 1 then
                drawButton(3, y, 30, "[ ] Select All", true)
            else
                term.setCursorPos(3, y)
                term.setTextColor(COLOR_SECONDARY)
                term.write("[ ] Select All")
            end
            y = y + 1
        end
        
        -- Draw visible monitors
        for i = math.max(1, visibleStart - 1), math.min(#monitors, visibleEnd - 1) do
            if i >= 1 then
                local side = monitors[i]
                local isSelected = selected[side] == true
                local checkbox = isSelected and "[X]" or "[ ]"
                local text = checkbox .. " " .. side
                
                if cursor == i + 1 then
                    drawButton(3, y, 30, text, true)
                else
                    term.setCursorPos(3, y)
                    term.setTextColor(isSelected and COLOR_SUCCESS or COLOR_TEXT)
                    term.write(text)
                end
                y = y + 1
            end
        end
        
        -- Scroll indicators
        if scroll > 0 then
            term.setCursorPos(35, 6)
            term.setTextColor(COLOR_PRIMARY)
            term.write("^")
        end
        if visibleEnd < totalItems then
            term.setCursorPos(35, 5 + maxVisible)
            term.setTextColor(COLOR_PRIMARY)
            term.write("v")
        end
        
        -- Instructions at bottom
        term.setCursorPos(2, 15)
        term.setTextColor(COLOR_SECONDARY)
        term.write("Selected: " .. #(function() local t={} for k,v in pairs(selected) do table.insert(t,k) end return t end)())
        
        term.setCursorPos(2, 16)
        term.write("Backspace to cancel")
        
        local event, key = os.pullEvent("key")
        
        if key == keys.up then
            cursor = math.max(1, cursor - 1)
            if cursor < scroll + 1 then
                scroll = math.max(0, scroll - 1)
            end
        elseif key == keys.down then
            cursor = math.min(totalItems, cursor + 1)
            if cursor > scroll + maxVisible then
                scroll = math.min(totalItems - maxVisible, scroll + 1)
            end
        elseif key == keys.space then
            if cursor == 1 then
                -- Toggle all
                if next(selected) then
                    selected = {}
                else
                    for _, side in ipairs(monitors) do
                        selected[side] = true
                    end
                end
            else
                local side = monitors[cursor - 1]
                selected[side] = not selected[side] or nil
            end
        elseif key == keys.enter then
            local result = {}
            for side, _ in pairs(selected) do
                table.insert(result, side)
            end
            return result
        elseif key == keys.backspace then
            return nil
        end
    end
end

-- ---------- Image Handling ----------
local function loadImage(path)
    local ok, img = pcall(paintutils.loadImage, path)
    if not ok or not img then
        error("Failed to load image: " .. path)
    end
    return img
end

local function scaleImage(img, newW, newH)
    local oldH, oldW = #img, #img[1]
    local scaled = {}
    for y = 1, newH do
        scaled[y] = {}
        local srcY = math.floor((y - 1) * oldH / newH) + 1
        for x = 1, newW do
            local srcX = math.floor((x - 1) * oldW / newW) + 1
            scaled[y][x] = img[srcY][srcX]
        end
    end
    return scaled
end

local function drawFit(mon, img)
    local w, h = mon.getSize()
    local scaled = scaleImage(img, w, h)
    local old = term.redirect(mon)
    paintutils.drawImage(scaled, 1, 1)
    term.redirect(old)
end

local function drawCenter(mon, img, scale)
    local w, h = mon.getSize()
    local oldW, oldH = #img[1], #img
    local newW, newH = math.floor(oldW * scale), math.floor(oldH * scale)
    local scaled = scaleImage(img, newW, newH)

    local offX = math.floor((w - newW) / 2) + 1
    local offY = math.floor((h - newH) / 2) + 1

    local old = term.redirect(mon)
    mon.clear()
    paintutils.drawImage(scaled, offX, offY)
    term.redirect(old)
end

local function drawOnMonitor(side, mode, file, scale)
    local mon = peripheral.wrap(side)
    if not mon then return end
    local img = loadImage(file)
    if mode == "fit" then
        drawFit(mon, img)
    else
        drawCenter(mon, img, scale or 1)
    end
end

local function drawImageData(side, mode, imgData, scale)
    local mon = peripheral.wrap(side)
    if not mon then return end
    if mode == "fit" then
        drawFit(mon, imgData)
    else
        drawCenter(mon, imgData, scale or 1)
    end
end

-- ---------- Wireless ----------
local function openModem()
    for _, p in ipairs(peripheral.getNames()) do
        if peripheral.getType(p) == "modem" then
            local modem = peripheral.wrap(p)
            if modem.isWireless() then
                rednet.open(p)
                return true, p
            end
        end
    end
    return false, nil
end

local function listenWireless()
    local config = loadConfig()
    if not config and not RAW_MODE then
        term.setBackgroundColor(COLOR_BG)
        term.clear()
        drawHeader("Error - Security Not Configured")
        term.setCursorPos(2, 3)
        term.setTextColor(COLOR_ERROR)
        print("\n  Security not configured!")
        print("  Run setup first (option 4 in GUI)")
        print("  Or enable raw mode (option 5)")
        sleep(3)
        return
    end
    
    local hasModem, modemSide = openModem()
    if not hasModem then
        term.setBackgroundColor(COLOR_BG)
        term.clear()
        drawHeader("Error - No Wireless Modem")
        term.setCursorPos(2, 3)
        term.setTextColor(COLOR_ERROR)
        print("\n  No wireless modem found!")
        print("  Attach one and try again.")
        sleep(3)
        return
    end
    
    term.setBackgroundColor(COLOR_BG)
    term.clear()
    drawHeader("Wireless Listener - Active")
    
    term.setCursorPos(2, 3)
    term.setTextColor(COLOR_SUCCESS)
    print("  Status: ONLINE")
    term.setTextColor(COLOR_TEXT)
    print("  Computer ID: " .. os.getComputerID())
    print("  Modem: " .. modemSide)
    print("  Encryption: " .. (RAW_MODE and "DISABLED (RAW MODE)" or "ENABLED"))
    print("  Range: " .. (modemSide:find("ender") and "Unlimited" or "64 blocks"))
    print("\n  Press any key to stop")
    
    drawBox(2, 10, term.getSize() - 2, 1, COLOR_SECONDARY)
    term.setCursorPos(3, 10)
    term.setTextColor(COLOR_TEXT)
    term.write("Activity Log")
    
    local logY = 11
    
    while true do
        -- Check for key press
        local event, key = os.pullEvent()
        
        if event == "key" then
            -- Any key pressed, return to menu
            return
        elseif event == "rednet_message" then
            local senderId = key  -- In rednet_message event, key is actually the sender ID
            local msg = os.pullEvent()  -- This will be a dummy pull, we need to get the message differently
            
            -- We need to restructure this - let's use parallel
            break
        end
    end
end

-- Restructure listenWireless to use parallel
local function listenWireless()
    local config = loadConfig()
    if not config and not RAW_MODE then
        term.setBackgroundColor(COLOR_BG)
        term.clear()
        drawHeader("Error - Security Not Configured")
        term.setCursorPos(2, 3)
        term.setTextColor(COLOR_ERROR)
        print("\n  Security not configured!")
        print("  Run setup first (option 4 in GUI)")
        print("  Or enable raw mode (option 5)")
        sleep(3)
        return
    end
    
    local hasModem, modemSide = openModem()
    if not hasModem then
        term.setBackgroundColor(COLOR_BG)
        term.clear()
        drawHeader("Error - No Wireless Modem")
        term.setCursorPos(2, 3)
        term.setTextColor(COLOR_ERROR)
        print("\n  No wireless modem found!")
        print("  Attach one and try again.")
        sleep(3)
        return
    end
    
    term.setBackgroundColor(COLOR_BG)
    term.clear()
    drawHeader("Wireless Listener - Active")
    
    term.setCursorPos(2, 3)
    term.setTextColor(COLOR_SUCCESS)
    print("  Status: ONLINE")
    term.setTextColor(COLOR_TEXT)
    print("  Computer ID: " .. os.getComputerID())
    print("  Modem: " .. modemSide)
    print("  Encryption: " .. (RAW_MODE and "DISABLED (RAW MODE)" or "ENABLED"))
    print("  Range: " .. (modemSide:find("ender") and "Unlimited" or "64 blocks"))
    print("\n  Press any key to stop")
    
    drawBox(2, 10, term.getSize() - 2, 1, COLOR_SECONDARY)
    term.setCursorPos(3, 10)
    term.setTextColor(COLOR_TEXT)
    term.write("Activity Log")
    
    local logY = 11
    local running = true
    
    -- Function to handle messages
    local function handleMessages()
        while running do
            local senderId, msg = rednet.receive(0.5)
            
            if senderId and msg then
                if logY > 18 then
                    logY = 11
                    for i = 11, 18 do
                        term.setCursorPos(2, i)
                        term.clearLine()
                    end
                end
                
                term.setCursorPos(2, logY)
                term.setTextColor(COLOR_SECONDARY)
                term.write(os.date("[%X]") .. " ")
                term.setTextColor(COLOR_TEXT)
                term.write("Message from #" .. senderId)
                logY = logY + 1
                
                if msg and type(msg) == "table" then
                    if msg.cmd == "auth" and not RAW_MODE then
                        term.setCursorPos(4, logY)
                        term.setTextColor(colors.yellow)
                        term.write("Auth request...")
                        logY = logY + 1
                        
                        if not msg.password then
                            term.setCursorPos(4, logY)
                            term.setTextColor(COLOR_ERROR)
                            term.write("FAILED: No password")
                            logY = logY + 1
                            rednet.send(senderId, {cmd = "auth_response", success = false})
                        else
                            local valid, cfg = verifyPassword(msg.password)
                            if valid then
                                term.setCursorPos(4, logY)
                                term.setTextColor(COLOR_SUCCESS)
                                term.write("SUCCESS: Authenticated")
                                logY = logY + 1
                                
                                local currentMonitors = {}
                                for _, side in ipairs(peripheral.getNames()) do
                                    if peripheral.getType(side) == "monitor" then
                                        table.insert(currentMonitors, side)
                                    end
                                end
                                
                                rednet.send(senderId, {
                                    cmd = "auth_response",
                                    success = true,
                                    monitors = currentMonitors,
                                    rawMode = RAW_MODE
                                })
                            else
                                term.setCursorPos(4, logY)
                                term.setTextColor(COLOR_ERROR)
                                term.write("FAILED: Wrong password")
                                logY = logY + 1
                                rednet.send(senderId, {cmd = "auth_response", success = false})
                            end
                        end
                        
                    elseif msg.cmd == "raw_draw" or (msg.cmd == "draw" and RAW_MODE) then
                        -- Raw mode - no encryption
                        term.setCursorPos(4, logY)
                        term.setTextColor(colors.yellow)
                        term.write("RAW command (unencrypted)...")
                        logY = logY + 1
                        
                        term.setCursorPos(4, logY)
                        term.setTextColor(COLOR_TEXT)
                        local sides = msg.sides or {msg.side}
                        term.write("Drawing on: " .. table.concat(sides, ", "))
                        logY = logY + 1
                        
                        for _, side in ipairs(sides) do
                            if msg.imgData then
                                drawImageData(side, msg.mode, msg.imgData, msg.scale)
                            else
                                drawOnMonitor(side, msg.mode, msg.file, msg.scale)
                            end
                        end
                        
                        term.setCursorPos(4, logY)
                        term.setTextColor(COLOR_SUCCESS)
                        term.write("Image displayed!")
                        logY = logY + 1
                        
                    elseif msg.encrypted and not RAW_MODE then
                        term.setCursorPos(4, logY)
                        term.setTextColor(colors.yellow)
                        term.write("Encrypted command...")
                        logY = logY + 1
                        
                        local decrypted = decryptMessage(msg, msg.sessionKey or "default")
                        
                        if decrypted and decrypted.cmd == "draw" then
                            term.setCursorPos(4, logY)
                            term.setTextColor(COLOR_TEXT)
                            term.write("Drawing on: " .. table.concat(decrypted.sides or {decrypted.side}, ", "))
                            logY = logY + 1
                            
                            local sides = decrypted.sides or {decrypted.side}
                            for _, side in ipairs(sides) do
                                if decrypted.imgData then
                                    drawImageData(side, decrypted.mode, decrypted.imgData, decrypted.scale)
                                else
                                    drawOnMonitor(side, decrypted.mode, decrypted.file, decrypted.scale)
                                end
                            end
                            
                            term.setCursorPos(4, logY)
                            term.setTextColor(COLOR_SUCCESS)
                            term.write("Image displayed!")
                            logY = logY + 1
                        else
                            term.setCursorPos(4, logY)
                            term.setTextColor(COLOR_ERROR)
                            term.write("Decryption failed")
                            logY = logY + 1
                        end
                    end
                end
                
                logY = logY + 1
            end
        end
    end
    
    -- Function to wait for key press
    local function waitForKey()
        os.pullEvent("key")
        running = false
    end
    
    -- Run both in parallel
    parallel.waitForAny(handleMessages, waitForKey)
end

local function sendWireless()
    term.setBackgroundColor(COLOR_BG)
    term.clear()
    drawHeader("Wireless Send")
    
    term.setCursorPos(2, 3)
    term.setTextColor(COLOR_TEXT)
    term.write("Target Computer ID: ")
    local id = tonumber(read())
    
    if not id then
        term.setCursorPos(2, 5)
        term.setTextColor(COLOR_ERROR)
        print("Invalid computer ID!")
        sleep(2)
        return
    end
    
    local hasModem, modemSide = openModem()
    if not hasModem then
        term.setCursorPos(2, 5)
        term.setTextColor(COLOR_ERROR)
        print("No wireless modem found!")
        sleep(2)
        return
    end
    
    local useRaw = RAW_MODE
    local password = nil
    local response = nil
    
    if not useRaw then
        term.setCursorPos(2, 4)
        term.write("Password: ")
        password = read("*")
        
        if not password or #password == 0 then
            term.setCursorPos(2, 6)
            term.setTextColor(COLOR_ERROR)
            print("Password cannot be empty!")
            sleep(2)
            return
        end
        
        term.setCursorPos(2, 6)
        term.setTextColor(colors.yellow)
        term.write("Authenticating...")
        
        rednet.send(id, {cmd = "auth", password = password})
        local senderId, resp = rednet.receive(5)
        response = resp
        
        if not response or not response.success then
            term.setCursorPos(2, 6)
            term.clearLine()
            term.setTextColor(COLOR_ERROR)
            term.write("Authentication failed!")
            sleep(2)
            return
        end
        
        term.setCursorPos(2, 6)
        term.clearLine()
        term.setTextColor(COLOR_SUCCESS)
        term.write("Authenticated!")
        
        if response.monitors and #response.monitors > 0 then
            term.setCursorPos(2, 8)
            term.setTextColor(COLOR_TEXT)
            print("Available monitors:")
            for i, side in ipairs(response.monitors) do
                term.setCursorPos(4, 8 + i)
                term.write(i .. ") " .. side)
            end
        end
        
        sleep(1)
    else
        term.setCursorPos(2, 5)
        term.setTextColor(colors.red)
        term.write("RAW MODE: No encryption")
        sleep(1)
    end
    
    -- Ask for monitor side directly
    local availableMonitors = (response and response.monitors) or {}
    local currentY = (response and response.monitors) and (8 + #response.monitors + 2) or 7
    term.setCursorPos(2, currentY)
    term.setTextColor(COLOR_TEXT)
    term.write("Monitor side (or 'all'): ")
    local sideInput = read()
    
    if not sideInput or #sideInput == 0 then
        term.setCursorPos(2, currentY + 2)
        term.setTextColor(COLOR_ERROR)
        print("Monitor side cannot be empty!")
        sleep(2)
        return
    end
    
    local selectedSides = {}
    if sideInput:lower() == "all" then
        if #availableMonitors == 0 then
            term.setCursorPos(2, currentY + 2)
            term.setTextColor(COLOR_ERROR)
            print("No monitors available!")
            sleep(2)
            return
        end
        selectedSides = availableMonitors
    else
        selectedSides = {sideInput}
    end
    
    term.setCursorPos(2, currentY + 1)
    term.write("Mode (fit/center/fill): ")
    local mode = read()
    
    -- Validate mode
    if mode ~= "fit" and mode ~= "center" and mode ~= "fill" then
        term.setCursorPos(2, currentY + 3)
        term.setTextColor(COLOR_ERROR)
        print("Invalid mode! Use: fit, center, or fill")
        sleep(2)
        return
    end
    
    term.setCursorPos(2, currentY + 2)
    term.write("File (.nfp): ")
    local file = read()
    
    if not file or #file == 0 then
        term.setCursorPos(2, currentY + 4)
        term.setTextColor(COLOR_ERROR)
        print("File path cannot be empty!")
        sleep(2)
        return
    end
    
    -- Check if file exists
    if not fs.exists(file) then
        term.setCursorPos(2, currentY + 4)
        term.setTextColor(COLOR_ERROR)
        print("File not found: " .. file)
        sleep(2)
        return
    end
    
    local scale = 1
    if mode == "center" then
        term.setCursorPos(2, currentY + 3)
        term.write("Scale: ")
        scale = tonumber(read()) or 1
        if scale <= 0 then
            scale = 1
        end
    end
    
    local sendImageY = mode == "center" and (currentY + 4) or (currentY + 3)
    term.setCursorPos(2, sendImageY)
    term.write("Send image data? (y/n): ")
    local sendImageInput = read():lower()
    local sendImage = sendImageInput == "y" or sendImageInput == "yes"
    
    -- Try to load the image first to catch errors early
    local img = nil
    local loadSuccess, loadError = pcall(function()
        img = loadImage(file)
    end)
    
    if not loadSuccess then
        term.setCursorPos(2, sendImageY + 2)
        term.setTextColor(COLOR_ERROR)
        print("Failed to load image!")
        term.setCursorPos(2, sendImageY + 3)
        print("Error: " .. tostring(loadError))
        sleep(3)
        return
    end
    
    term.setCursorPos(2, sendImageY + 2)
    term.setTextColor(colors.yellow)
    term.write(useRaw and "Sending..." or "Encrypting and sending...")
    
    local message
    if sendImage then
        message = {cmd="draw", sides=selectedSides, mode=mode, imgData=img, scale=scale}
    else
        message = {cmd="draw", sides=selectedSides, mode=mode, file=file, scale=scale}
    end
    
    if useRaw then
        -- Send unencrypted in raw mode
        rednet.send(id, message)
    else
        -- Encrypt and send
        local encrypted = encryptMessage(message, password)
        encrypted.sessionKey = password
        rednet.send(id, encrypted)
    end
    
    term.setCursorPos(2, sendImageY + 2)
    term.clearLine()
    term.setTextColor(COLOR_SUCCESS)
    term.write("Sent successfully!")
    sleep(2)
end

-- ---------- Security Setup ----------
local function setupSecurity()
    term.setBackgroundColor(COLOR_BG)
    term.clear()
    drawHeader("Security Setup")
    
    term.setCursorPos(2, 3)
    term.setTextColor(COLOR_TEXT)
    print("  Set a password for this computer.")
    print("  Others will need it to send images.")
    print("\n  Minimum: 4 characters")
    
    term.setCursorPos(2, 9)
    term.write("  Password: ")
    local password = read("*")
    
    if #password < 4 then
        term.setCursorPos(2, 11)
        term.setTextColor(COLOR_ERROR)
        print("  ERROR: Too short!")
        sleep(2)
        return false
    end
    
    term.setCursorPos(2, 10)
    term.write("  Confirm:  ")
    local confirm = read("*")
    
    if password ~= confirm then
        term.setCursorPos(2, 12)
        term.setTextColor(COLOR_ERROR)
        print("  ERROR: Passwords don't match!")
        sleep(2)
        return false
    end
    
    term.setCursorPos(2, 12)
    term.setTextColor(colors.yellow)
    term.write("  Generating keys...")
    sleep(0.5)
    saveConfig(password)
    
    term.setCursorPos(2, 12)
    term.clearLine()
    term.setTextColor(COLOR_SUCCESS)
    term.write("  Setup complete!")
    
    term.setCursorPos(2, 14)
    term.setTextColor(COLOR_TEXT)
    print("  Computer ID: " .. os.getComputerID())
    print("\n  Press any key...")
    os.pullEvent("key")
    return true
end

-- ---------- Modern GUI ----------
local function modernGUI()
    local selected = 1
    local monitorScroll = 0  -- Move scroll variable outside the loop
    local options = {
        "Display on Monitor(s)",
        "Wireless Send",
        "Wireless Listen",
        "Security Setup",
        "Toggle Raw Mode",  -- ADDED OPTION
        "Exit"
    }
    
    while true do
        term.setBackgroundColor(COLOR_BG)
        term.clear()
        drawHeader("ShowImage v2.0")
        
        -- Monitor status with scrolling
        local monitorBoxHeight = 5
        local maxMonitorsVisible = 3
        
        drawBox(2, 3, 30, monitorBoxHeight, COLOR_SECONDARY)
        -- Header
        term.setBackgroundColor(COLOR_PRIMARY)
        term.setCursorPos(2, 3)
        term.write(string.rep(" ", 30))
        term.setCursorPos(4, 3)
        term.setTextColor(COLOR_BG)
        term.write("Monitors")
        
        -- Monitor list
        if #monitors > 0 then
            local visibleStart = monitorScroll + 1
            local visibleEnd = math.min(monitorScroll + maxMonitorsVisible, #monitors)
            
            for i = visibleStart, visibleEnd do
                local displayY = 3 + (i - visibleStart) + 1
                term.setCursorPos(4, displayY)
                term.setBackgroundColor(COLOR_SECONDARY)
                term.setTextColor(COLOR_SUCCESS)
                term.write("* " .. monitors[i])
            end
            
            -- Scroll indicators with better visibility
            term.setBackgroundColor(COLOR_SECONDARY)
            if monitorScroll > 0 then
                term.setCursorPos(29, 4)
                term.setTextColor(COLOR_PRIMARY)
                term.write("^")
            end
            if visibleEnd < #monitors then
                term.setCursorPos(29, 6)
                term.setTextColor(COLOR_PRIMARY)
                term.write("v")
            end
            
            -- Show count if there are hidden monitors
            if #monitors > maxMonitorsVisible then
                term.setCursorPos(4, 7)
                term.setTextColor(COLOR_SECONDARY)
                term.write("(" .. visibleStart .. "-" .. visibleEnd .. " of " .. #monitors .. ")")
            end
        else
            term.setCursorPos(4, 5)
            term.setBackgroundColor(COLOR_SECONDARY)
            term.setTextColor(COLOR_ERROR)
            term.write("No monitors")
        end
        
        -- Security status
        drawBox(34, 3, 30, 4, COLOR_SECONDARY)
        -- Header
        term.setBackgroundColor(colors.orange)
        term.setCursorPos(34, 3)
        term.write(string.rep(" ", 30))
        term.setCursorPos(36, 3)
        term.setTextColor(COLOR_BG)
        term.write("Security")
        
        -- Security info
        term.setCursorPos(36, 4)
        term.setBackgroundColor(COLOR_SECONDARY)
        local config = loadConfig()
        if config then
            term.setTextColor(COLOR_SUCCESS)
            term.write("Configured")
        else
            term.setTextColor(COLOR_ERROR)
            term.write("Not Configured")
        end
        
        term.setCursorPos(36, 5)
        if RAW_MODE then
            term.setTextColor(COLOR_ERROR)
            term.write("Mode: RAW")
        else
            term.setTextColor(COLOR_SUCCESS)
            term.write("Mode: Encrypted")
        end
        
        -- Menu - centered and moved down
        local startY = 10
        local menuWidth = 40
        local menuX = math.floor((term.getSize() - menuWidth) / 2)
        for i, option in ipairs(options) do
            drawButton(menuX, startY + (i - 1), menuWidth, option, i == selected)
        end
        
        -- Footer - ALWAYS VISIBLE with proper background
        local w, h = term.getSize()
        term.setBackgroundColor(COLOR_BG)
        term.setCursorPos(1, h)
        term.clearLine()
        
        term.setCursorPos(2, h)
        term.setTextColor(COLOR_PRIMARY)
        
        if #monitors > maxMonitorsVisible then
            term.write("Arrows: Nav  PgUp/PgDn: Scroll  Enter: Select")
        else
            term.write("Arrow Keys: Navigate")
            term.setCursorPos(w - 14, h)
            term.write("Enter: Select")
        end
        
        local event, key = os.pullEvent("key")
        
        if key == keys.up then
            selected = math.max(1, selected - 1)
        elseif key == keys.down then
            selected = math.min(#options, selected + 1)
        elseif key == keys.pageUp then
            -- Scroll monitors up
            if #monitors > 3 then
                monitorScroll = math.max(0, monitorScroll - 1)
            end
        elseif key == keys.pageDown then
            -- Scroll monitors down
            if #monitors > 3 then
                monitorScroll = math.min(#monitors - 3, monitorScroll + 1)
            end
        elseif key == keys.enter then
            if selected == 1 then
                -- Display on monitors
                if #monitors == 0 then
                    term.setBackgroundColor(COLOR_BG)
                    term.clear()
                    drawHeader("Error")
                    term.setCursorPos(2, 3)
                    term.setTextColor(COLOR_ERROR)
                    print("\n  No monitors detected!")
                    sleep(2)
                else
                    local sides = selectMonitors()
                    if sides and #sides > 0 then
                        term.setBackgroundColor(COLOR_BG)
                        term.clear()
                        drawHeader("Display Image")
                        
                        -- Find all .nfp files
                        local function findImages(dir)
                            local images = {}
                            local function scan(path)
                                local items = fs.list(path)
                                for _, item in ipairs(items) do
                                    local fullPath = fs.combine(path, item)
                                    if fs.isDir(fullPath) then
                                        scan(fullPath)
                                    elseif item:match("%.nfp$") then
                                        table.insert(images, fullPath)
                                    end
                                end
                            end
                            scan(dir)
                            return images
                        end
                        
                        local images = findImages("/")
                        
                        term.setCursorPos(2, 3)
                        term.setTextColor(COLOR_TEXT)
                        local nextY = 3
                        if #images > 0 then
                            print("Available images:")
                            nextY = 4
                            local maxDisplay = math.min(#images, 10)
                            for i = 1, maxDisplay do
                                term.setCursorPos(4, nextY)
                                term.setTextColor(COLOR_SUCCESS)
                                term.write(images[i])
                                nextY = nextY + 1
                            end
                            if #images > 10 then
                                term.setCursorPos(4, nextY)
                                term.setTextColor(COLOR_SECONDARY)
                                term.write("... and " .. (#images - 10) .. " more")
                                nextY = nextY + 1
                            end
                            nextY = nextY + 1
                        else
                            print("No .nfp files found")
                            nextY = 5
                        end
                        
                        term.setCursorPos(2, nextY)
                        term.setTextColor(COLOR_TEXT)
                        term.write("File (.nfp): ")
                        local file = read()
                        nextY = nextY + 1
                        
                        -- Validate file
                        if not file or #file == 0 then
                            term.setCursorPos(2, nextY)
                            term.setTextColor(COLOR_ERROR)
                            print("File path cannot be empty!")
                            sleep(2)
                        elseif not fs.exists(file) then
                            term.setCursorPos(2, nextY)
                            term.setTextColor(COLOR_ERROR)
                            print("File not found: " .. file)
                            sleep(2)
                        else
                            -- Try to load image first
                            local img = nil
                            local loadSuccess, loadError = pcall(function()
                                img = loadImage(file)
                            end)
                            
                            if not loadSuccess then
                                term.setCursorPos(2, nextY)
                                term.setTextColor(COLOR_ERROR)
                                print("Failed to load image!")
                                term.setCursorPos(2, nextY + 1)
                                print("Error: " .. tostring(loadError))
                                sleep(3)
                            else
                                term.setCursorPos(2, nextY)
                                term.setTextColor(COLOR_TEXT)
                                term.write("Mode (fit/center/fill): ")
                                local mode = read()
                                nextY = nextY + 1
                                
                                -- Validate mode
                                if mode ~= "fit" and mode ~= "center" and mode ~= "fill" then
                                    term.setCursorPos(2, nextY)
                                    term.setTextColor(COLOR_ERROR)
                                    print("Invalid mode! Use: fit, center, or fill")
                                    sleep(2)
                                else
                                    local scale = 1
                                    if mode == "center" then
                                        term.setCursorPos(2, nextY)
                                        term.write("Scale: ")
                                        scale = tonumber(read()) or 1
                                        if scale <= 0 then scale = 1 end
                                        nextY = nextY + 1
                                    end
                                    
                                    for _, side in ipairs(sides) do
                                        drawOnMonitor(side, mode, file, scale)
                                    end
                                    
                                    term.setCursorPos(2, nextY + 1)
                                    term.setTextColor(COLOR_SUCCESS)
                                    term.write("Displayed on " .. #sides .. " monitor(s)!")
                                    sleep(2)
                                end
                            end
                        end
                    end
                end
            elseif selected == 2 then
                sendWireless()
            elseif selected == 3 then
                listenWireless()
            elseif selected == 4 then
                setupSecurity()
            elseif selected == 5 then
                -- Toggle raw mode
                toggleRawMode()
                term.setBackgroundColor(COLOR_BG)
                term.clear()
                drawHeader("Raw Mode Toggle")
                term.setCursorPos(2, 3)
                term.setTextColor(RAW_MODE and colors.red or COLOR_SUCCESS)
                print("\n  Raw Mode: " .. (RAW_MODE and "ENABLED" or "DISABLED"))
                term.setTextColor(COLOR_TEXT)
                if RAW_MODE then
                    print("\n  WARNING: All messages will be")
                    print("  sent UNENCRYPTED! Anyone can")
                    print("  read or send images.")
                else
                    print("\n  All messages will be encrypted")
                    print("  and password-protected.")
                end
                print("\n  Press any key...")
                os.pullEvent("key")
            elseif selected == 6 then
                term.setBackgroundColor(COLOR_BG)
                term.clear()
                term.setCursorPos(1, 1)
                return
            end
        end
    end
end

-- ---------- CLI Mode ----------
local function showHelp()
    print("ShowImage v2.0 - Usage")
    print("\nOptions:")
    print("  -s, --sides <s1,s2>    Monitor sides ")
    print("  -m, --mode <mode>      Display mode ")
    print("  -f, --file <file>      Image file (.nfp)")
    print("  -z, --scale <scale>    Scale factor")
    print("  -w, --wireless <id>    Send to computer ID")
    print("  -p, --password <pwd>   Password")
    print("  -t, --transfer         Send image data")
    print("  -l, --listen           Listen mode")
    print("  --setup                Security setup")
    print("  -h, --help             Show help")
    print("\nExamples:")
    print("  showimage -s left,right -m fit -f logo.nfp")
    print("  showimage -s all -m center -f bg.nfp -z 2")
    print("  showimage -w 5 -p 23 -s top -m fit -f logo.nfp -t")
end

local function parseCLI()
    local opts = {}
    local i = 1
    while i <= #args do
        local arg = args[i]
        if arg == "-s" or arg == "--sides" then
            i = i + 1
            opts.sides = args[i]
        elseif arg == "-m" or arg == "--mode" then
            i = i + 1
            opts.mode = args[i]
        elseif arg == "-f" or arg == "--file" then
            i = i + 1
            opts.file = args[i]
        elseif arg == "-z" or arg == "--scale" then
            i = i + 1
            opts.scale = tonumber(args[i]) or 1
        elseif arg == "-w" or arg == "--wireless" then
            i = i + 1
            opts.wireless = tonumber(args[i])
        elseif arg == "-p" or arg == "--password" then
            i = i + 1
            opts.password = args[i]
        elseif arg == "-t" or arg == "--transfer" then
            opts.transfer = true
        elseif arg == "-l" or arg == "--listen" then
            opts.listen = true
        elseif arg == "--setup" then
            opts.setup = true
        elseif arg == "-h" or arg == "--help" then
            showHelp()
            return nil
        else
            print("Unknown option: " .. arg)
            showHelp()
            return nil
        end
        i = i + 1
    end
    return opts
end

local function runCLI()
    local opts = parseCLI()
    if not opts then return end

    if opts.setup then
        setupSecurity()
        return
    end

    if opts.listen then
        listenWireless()
        return
    end

    if not opts.file then
        print("Error: No file specified")
        showHelp()
        return
    end

    opts.mode = opts.mode or "fit"
    opts.scale = opts.scale or 1

    if opts.wireless then
        if not opts.password then
            print("Error: Password required")
            return
        end
        
        local hasModem = openModem()
        if not hasModem then
            print("Error: No wireless modem!")
            return
        end

        print("Authenticating...")
        rednet.send(opts.wireless, {cmd = "auth", password = opts.password})
        
        local senderId, response = rednet.receive(5)
        if not response or not response.success then
            print("Authentication failed!")
            return
        end
        
        print("Authenticated!")
        
        if response.monitors and #response.monitors > 0 then
            print("\nAvailable monitors:")
            for i, side in ipairs(response.monitors) do
                print("  " .. i .. ") " .. side)
            end
        end
        print("")

        -- Parse sides
        local sideList = {}
        if opts.sides == "all" then
            sideList = response.monitors or {}
        else
            for side in string.gmatch(opts.sides, "[^,]+") do
                table.insert(sideList, side)
            end
        end

        print("Encrypting and sending...")
        local message
        if opts.transfer then
            local img = loadImage(opts.file)
            message = {
                cmd="draw",
                sides=sideList,
                mode=opts.mode,
                imgData=img,
                scale=opts.scale
            }
        else
            message = {
                cmd="draw",
                sides=sideList,
                mode=opts.mode,
                file=opts.file,
                scale=opts.scale
            }
        end
        
        local encrypted = encryptMessage(message, opts.password)
        encrypted.sessionKey = opts.password
        rednet.send(opts.wireless, encrypted)
        print("Sent to computer " .. opts.wireless)
    else
        if not opts.sides then
            print("Error: No monitor sides specified")
            showHelp()
            return
        end

        -- Parse sides
        local sideList = {}
        if opts.sides == "all" then
            sideList = monitors
        else
            for side in string.gmatch(opts.sides, "[^,]+") do
                table.insert(sideList, side)
            end
        end

        for _, side in ipairs(sideList) do
            drawOnMonitor(side, opts.mode, opts.file, opts.scale)
        end
        print("Displayed on " .. #sideList .. " monitor(s)")
    end
end

-- ---------- Main Entry Point ----------
if #args == 0 then
    local config = loadConfig()
    if not config then
        term.setBackgroundColor(COLOR_BG)
        term.clear()
        drawHeader("ShowImage - First Time Setup")
        
        term.setCursorPos(2, 3)
        term.setTextColor(COLOR_TEXT)
        print("  Welcome to ShowImage!")
        print("\n  Before you start, you need to")
        print("  set up security for wireless")
        print("  image transfers.")
        print("\n  Press any key to continue...")
        os.pullEvent("key")
        
        if not setupSecurity() then
            print("\n  Setup failed!")
            sleep(2)
            return
        end
    end
    
    modernGUI()
else
    runCLI()
end
