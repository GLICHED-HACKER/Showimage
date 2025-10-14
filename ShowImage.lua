-- showimage.lua (GUI Edition)
-- All-in-one CC:Tweaked image tool with GUI for local/wireless monitor control.
-- By GLICHED-HACKER

-- ---------- Detect Monitors ----------
local monitors = {}
for _, side in ipairs(peripheral.getNames()) do
    if peripheral.getType(side) == "monitor" then
        table.insert(monitors, side)
    end
end

-- ---------- Helpers ----------
local function centerText(y, text, w)
    local scrW, _ = term.getSize()
    scrW = w or scrW
    term.setCursorPos(math.floor((scrW - #text) / 2) + 1, y)
    term.write(text)
end

local function drawBox(x, y, w, h, title)
    paintutils.drawFilledBox(x, y, x+w-1, y+h-1, colors.gray)
    paintutils.drawBox(x, y, x+w-1, y+h-1, colors.black)
    if title then
        term.setCursorPos(x+1, y)
        term.write("["..title.."]")
    end
end

local function bottomPrompt(text)
    local _, h = term.getSize()
    term.setCursorPos(1, h)
    term.clearLine()
    term.write(text .. ": ")
    return read()
end

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

-- ---------- Wireless ----------
local function openModem()
    for _, p in ipairs(peripheral.getNames()) do
        if peripheral.getType(p) == "modem" then
            rednet.open(p)
            return true
        end
    end
    return false
end

local function listenWireless()
    if not openModem() then
        print("No modem found!")
        sleep(2)
        return
    end
    print("Listening for wireless image commands...")
    while true do
        local _, msg = rednet.receive()
        if msg and msg.cmd == "draw" then
            drawOnMonitor(msg.side, msg.mode, msg.file, msg.scale)
        end
    end
end

local function sendWireless()
    local id = tonumber(bottomPrompt("Target computer ID"))
    local side = bottomPrompt("Monitor side")
    local mode = bottomPrompt("Mode (fit/center/fill)")
    local file = bottomPrompt("File (.nfp)")
    local scale = 1
    if mode == "center" then
        scale = tonumber(bottomPrompt("Scale")) or 1
    end

    if not openModem() then
        print("No modem found!")
        sleep(2)
        return
    end

    rednet.send(id, {cmd="draw", side=side, mode=mode, file=file, scale=scale})
    print("Sent image to "..id)
    sleep(2)
end

-- ---------- GUI ----------
local function gui()
    term.clear()
    centerText(1, "SHOWIMAGE GUI", 51)
    drawBox(2, 3, 47, 12, "Monitors")
    for i, side in ipairs(monitors) do
        term.setCursorPos(4, 3+i)
        term.write(i .. ") " .. side)
    end

    drawBox(2, 14, 47, 4, "Actions")
    term.setCursorPos(4, 15) term.write("1) Display on monitor(s)")
    term.setCursorPos(4, 16) term.write("2) Wireless Send")
    term.setCursorPos(4, 17) term.write("3) Wireless Listen")
    term.setCursorPos(4, 18) term.write("4) Exit")
end

-- ---------- Main Loop ----------
while true do
    gui()
    local choice = bottomPrompt("Select option (1-4)")

    if choice == "1" then
        local side = bottomPrompt("Monitor side (or 'all')")
        local mode = bottomPrompt("Mode (fit/center/fill)")
        local file = bottomPrompt("File (.nfp)")
        local scale = 1
        if mode == "center" then
            scale = tonumber(bottomPrompt("Scale (e.g. 1, 2)")) or 1
        end

        if side == "all" then
            for _, s in ipairs(monitors) do
                drawOnMonitor(s, mode, file, scale)
            end
        else
            drawOnMonitor(side, mode, file, scale)
        end
        sleep(2)

    elseif choice == "2" then
        sendWireless()

    elseif choice == "3" then
        listenWireless()

    elseif choice == "4" then
        term.clear()
        term.setCursorPos(1,1)
        break

    else
        bottomPrompt("Invalid option, press Enter to continue")
    end
end
