-- 牧场物语：矿石镇的伙伴（男孩版 / A4NJ）矿场透视
-- 
-- 适用：mGBA 0.10.5 及以后版本
-- 功能：只读取游戏内存，不会改写 ROM、存档或游戏数据。
--   * mGBA 0.10.x：在 Scripting 窗口显示 28x28 实时网格与完整中文物品名称。
--   * 一键启动版：把只读到的矿格写入临时状态文件，交给 Windows 高清透明浮层显示。

local CONFIG = {
    refreshFrames = 8, -- 文字网格与矿格数据的刷新间隔（帧）
    overlayRefreshFrames = 6, -- 镜头移动时最多每 6 帧重画一次，避免快进拖死界面
    showJunkOre = true,
    showMoney = true,
    showTileLabels = true, -- mGBA 0.11 开发版：在游戏画面的格子上直接显示短名称
    overlayFontSize = 8,   -- 每个 16x16 格中央显示较小标签，方便判断所属格子
    labelBackgroundColor = 0x28000000, -- 约 16% 黑底，尽量不挡住路面
    headerBackgroundColor = 0x70000000, -- 楼层标题稍深，仍可透出游戏画面
    useExternalHdOverlay = true, -- 使用 Windows 桌面分辨率浮层，关闭 mGBA 原生像素叠加
}

local tempDirectory = "."
if os ~= nil and os.getenv ~= nil and os.getenv("TEMP") ~= nil then
    tempDirectory = os.getenv("TEMP"):gsub("\\", "/")
end
local EXTERNAL_OVERLAY_PATH = tempDirectory .. "/mgba_mine_xray_state.txt"

-- 已对用户的 A4NJ 汉化 ROM 与 5 个 VBA 即时存档验证。
local ADDR = {
    tileData = 0x02007C68,     -- 28 * 28 个 u16，按行存放
    mineLocation = 0x02039064, -- 地图 ID；可由它区分泉矿/湖矿与层数
    stamina = 0x02006A29,
    fatigue = 0x02006A2A,
    cameraX = 0x030077BC,
    cameraY = 0x030077BE,
}

local TILE_CHAR = {
    [0x0] = ".", -- 未挖地面
    [0x1] = "=", -- 已挖地面
    [0x2] = "v", -- 已显示的下层楼梯
    [0x3] = "^", -- 上层楼梯
    [0x4] = "#", -- 空石头（石中无物）
}

-- code 是网格第 1 个字符；color 是新版 mGBA 画面叠加颜色（ARGB）。
local ROCK = {
    [0x00] = { code = "#", label = "",   name = "空石头",       color = 0x00000000 },
    [0x0A] = { code = "@", label = "转", name = "转移石",       color = 0xFFFF40FF, important = true },
    [0x0C] = { code = "x", label = "废", name = "废矿石",       color = 0xFFB0B0B0 },
    [0x0D] = { code = "C", label = "铜", name = "铜",             color = 0xFFFFA050 },
    [0x0E] = { code = "S", label = "银", name = "银",             color = 0xFFFFFFFF },
    [0x0F] = { code = "G", label = "金", name = "金",             color = 0xFFFFD700 },
    [0x10] = { code = "M", label = "秘", name = "秘银",           color = 0xFF70A0FF },
    [0x11] = { code = "O", label = "奥", name = "奥利哈钢",       color = 0xFFFFFFFF },
    [0x12] = { code = "A", label = "刚", name = "金刚石",         color = 0xFF40FFFF },
    [0x13] = { code = "N", label = "月", name = "月亮石",         color = 0xFFD0D8FF },
    [0x14] = { code = "R", label = "玫", name = "沙漠玫瑰石",     color = 0xFFFFB0C8 },
    [0x15] = { code = "P", label = "粉", name = "粉红钻石",       color = 0xFFFF50A8, important = true },
    [0x16] = { code = "L", label = "亚", name = "亚历山大石",     color = 0xFF40FF70, important = true },
    [0x17] = { code = "Y", label = "贤", name = "贤者之石",       color = 0xFFFFFFFF, important = true },
    [0x18] = { code = "D", label = "钻", name = "钻石",           color = 0xFFC8FFFF },
    [0x19] = { code = "E", label = "绿", name = "祖母绿",         color = 0xFF40FF70 },
    [0x1A] = { code = "U", label = "红", name = "红宝石",         color = 0xFFFF5050 },
    [0x1B] = { code = "T", label = "黄", name = "黄玉",           color = 0xFFFFFF40 },
    [0x1C] = { code = "I", label = "橄", name = "橄榄石",         color = 0xFFA0FF50 },
    [0x1D] = { code = "F", label = "萤", name = "萤石",           color = 0xFF30F0A0 },
    [0x1E] = { code = "Q", label = "玛", name = "玛瑙",           color = 0xFFFFA040 },
    [0x1F] = { code = "H", label = "紫", name = "紫水晶",         color = 0xFFD080FF },
    [0x20] = { code = "V", label = "女", name = "女神之玉",       color = 0xFFFFFFFF, important = true },
    [0x21] = { code = "K", label = "河", name = "河童之玉",       color = 0xFF40FF40, important = true },
}

-- code 是网格第 2 个字符。同一层可能有很多个楼梯候选格；挖出其中一个后其余会消失。
local DIRT = {
    [0x00] = { code = ".", label = "",   name = "无",         color = 0x00000000 },
    [0x01] = { code = "v", label = "梯", name = "下层楼梯候选", color = 0xFFFF9000, important = true },
    [0x02] = { code = "$", label = "钱", name = "钱袋",       color = 0xFFFFFF00 },
    [0x03] = { code = "P", label = "果", name = "力之果实",     color = 0xFFFF3030, important = true },
    [0x04] = { code = "s", label = "镰", name = "诅咒镰刀",     color = 0xFFFF60D0, important = true },
    [0x05] = { code = "h", label = "锄", name = "诅咒锄头",     color = 0xFFFF60D0, important = true },
    [0x06] = { code = "a", label = "斧", name = "诅咒斧头",     color = 0xFFFF60D0, important = true },
    [0x07] = { code = "m", label = "锤", name = "诅咒锤子",     color = 0xFFFF60D0, important = true },
    [0x08] = { code = "w", label = "水", name = "诅咒洒水器",   color = 0xFFFF60D0, important = true },
    [0x09] = { code = "f", label = "竿", name = "诅咒钓竿",     color = 0xFFFF60D0, important = true },
    [0x0B] = { code = "b", label = "草", name = "黑色草",       color = 0xFFB0FF80 },
    [0x22] = { code = "r", label = "谱", name = "菜谱",         color = 0xFFFFFFFF, important = true },
}

local ROCK_ORDER = {
    0x0A, 0x0C, 0x0D, 0x0E, 0x0F, 0x10, 0x11, 0x12,
    0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19, 0x1A,
    0x1B, 0x1C, 0x1D, 0x1E, 0x1F, 0x20, 0x21,
}

local DIRT_ORDER = {
    0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
    0x08, 0x09, 0x0B, 0x22,
}

-- 这些稀有物即使当层没有，也会在“物品名称”页明确显示“本层没有”。
local SPECIAL_TARGETS = {
    { kind = "rock", id = 0x15 }, -- 粉红钻石
    { kind = "rock", id = 0x16 }, -- 亚历山大石
    { kind = "rock", id = 0x17 }, -- 贤者之石
    { kind = "rock", id = 0x20 }, -- 女神之玉
    { kind = "rock", id = 0x21 }, -- 河童之玉
    { kind = "rock", id = 0x0A }, -- 转移石
    { kind = "dirt", id = 0x03 }, -- 力之果实
    { kind = "dirt", id = 0x04 }, -- 诅咒镰刀
    { kind = "dirt", id = 0x05 }, -- 诅咒锄头
    { kind = "dirt", id = 0x06 }, -- 诅咒斧头
    { kind = "dirt", id = 0x07 }, -- 诅咒锤子
    { kind = "dirt", id = 0x08 }, -- 诅咒洒水器
    { kind = "dirt", id = 0x09 }, -- 诅咒钓竿
    { kind = "dirt", id = 0x22 }, -- 菜谱
}

local state = {
    buffer = nil,
    itemsBuffer = nil,
    map = nil,
    mapSignature = nil,
    location = nil,
    mineName = nil,
    floor = nil,
    lastRefreshFrame = -100000,
    overlay = nil,
    painter = nil,
    overlayReady = false,
    overlayWasVisible = false,
    lastOverlayFrame = -100000,
    lastOverlayCameraX = nil,
    lastOverlayCameraY = nil,
    externalOverlaySignature = nil,
    externalOverlayDisabled = false,
    externalOverlayErrorShown = false,
}

local function mineInfo(location)
    -- 泉矿 0..255 层：0x0034..0x0133
    if location >= 0x0034 and location <= 0x0133 then
        return "泉边矿场", location - 0x0034
    end
    -- 湖矿 0..255 层：0x0134..0x0233
    if location >= 0x0134 and location <= 0x0233 then
        return "湖中矿场", location - 0x0134
    end
    return nil, nil
end

local function readRomGameCode()
    -- mGBA 0.10.x 的 getGameCode() 对部分汉化 ROM 会返回非预期字符串。
    -- 直接读取 GBA ROM 头 0xAC..0xAF，可避免误报。
    local chars = {}
    for offset = 0, 3 do
        chars[#chars + 1] = string.char(emu:read8(0x080000AC + offset))
    end
    return table.concat(chars)
end

local function decodeTile(raw)
    return {
        raw = raw,
        tileType = raw % 0x10,
        rock = math.floor(raw / 0x10) % 0x40,
        dirt = math.floor(raw / 0x400) % 0x40,
    }
end

local function readMineMap()
    local result = {}
    local signature = {}
    for row = 0, 27 do
        result[row] = {}
        for col = 0, 27 do
            local address = ADDR.tileData + (row * 28 + col) * 2
            local raw = emu:read16(address)
            result[row][col] = decodeTile(raw)
            -- 用原始 1568 字节作为签名。签名不变就不重画文字，滚动条不会跳回顶部。
            signature[#signature + 1] = string.char(raw % 0x100, math.floor(raw / 0x100))
        end
    end
    return result, table.concat(signature)
end

local function writeExternalOverlayFile(lines)
    if not CONFIG.useExternalHdOverlay or state.externalOverlayDisabled then
        return false
    end
    if io == nil or io.open == nil then
        if not state.externalOverlayErrorShown then
            console:warn("矿场透视：当前 Lua 环境没有文件接口，Windows 高清浮层无法接收数据。")
            state.externalOverlayErrorShown = true
        end
        state.externalOverlayDisabled = true
        return false
    end

    local file, err = io.open(EXTERNAL_OVERLAY_PATH, "wb")
    if not file then
        if not state.externalOverlayErrorShown then
            console:warn("矿场透视：无法写入高清浮层临时状态：" .. tostring(err))
            state.externalOverlayErrorShown = true
        end
        return false
    end
    file:write(table.concat(lines, "\n"), "\n")
    file:flush()
    file:close()
    state.externalOverlayErrorShown = false
    return true
end

local function writeExternalOverlayInactive(force)
    if not CONFIG.useExternalHdOverlay then
        return
    end
    if not force and state.externalOverlaySignature == "inactive" then
        return
    end
    local frame = 0
    if emu ~= nil then
        local ok, value = pcall(function() return emu:currentFrame() end)
        if ok then
            frame = value
        end
    end
    if writeExternalOverlayFile({
        "B\t" .. tostring(frame),
        "A\t0",
        "E\t" .. tostring(frame),
    }) then
        state.externalOverlaySignature = "inactive"
    end
end

local function updateExternalOverlay(force)
    if not CONFIG.useExternalHdOverlay or not state.map or not state.mineName then
        return
    end

    local cameraX = emu:read16(ADDR.cameraX)
    local cameraY = emu:read16(ADDR.cameraY)
    local signature = tostring(state.location) .. ":" .. tostring(cameraX) .. ":" .. tostring(cameraY)
        .. ":" .. tostring(state.mapSignature)
    if not force and signature == state.externalOverlaySignature then
        return
    end

    local frame = emu:currentFrame()
    local mineShort = state.mineName == "湖中矿场" and "湖" or "泉"
    local lines = {
        "B\t" .. tostring(frame),
        "A\t1",
        string.format("M\t%s\t%d", mineShort, state.floor),
        string.format("C\t%d\t%d", cameraX, cameraY),
    }
    for row = 0, 27 do
        for col = 0, 27 do
            local cell = state.map[row][col]
            local hasRock = cell.tileType == 0x4 and cell.rock ~= 0 and ROCK[cell.rock] ~= nil
            local hasDirt = cell.dirt ~= 0 and DIRT[cell.dirt] ~= nil
            if hasRock or hasDirt then
                lines[#lines + 1] = string.format(
                    "T\t%d\t%d\t%d\t%d\t%d",
                    col, row, cell.tileType, cell.rock, cell.dirt
                )
            end
        end
    end
    lines[#lines + 1] = "E\t" .. tostring(frame)
    if writeExternalOverlayFile(lines) then
        state.externalOverlaySignature = signature
    end
end

local function cellCode(cell)
    local first
    if cell.tileType == 0x4 then
        local item = ROCK[cell.rock]
        first = item and item.code or "?"
    else
        first = TILE_CHAR[cell.tileType] or "?"
    end
    local ground = DIRT[cell.dirt]
    local second = ground and ground.code or "?"
    return first .. second
end

local function appendCoord(groups, name, x, y)
    if not groups[name] then
        groups[name] = {}
    end
    table.insert(groups[name], string.format("(%02d,%02d)", x, y))
end

local function coordSummary(coords, maxShown)
    maxShown = maxShown or 16
    local shown = {}
    for i = 1, math.min(#coords, maxShown) do
        shown[#shown + 1] = coords[i]
    end
    local text = table.concat(shown, " ")
    if #coords > maxShown then
        text = text .. string.format(" ... +%d", #coords - maxShown)
    end
    return text
end

local function printAllCoords(buffer, coords)
    -- 每行 8 个坐标，避免中文字体与横向滚动条导致难以阅读。
    local perLine = 8
    for first = 1, #coords, perLine do
        local line = {}
        for index = first, math.min(first + perLine - 1, #coords) do
            line[#line + 1] = coords[index]
        end
        buffer:print("    " .. table.concat(line, " ") .. "\n")
    end
end

local function collectItemCoords()
    local rocks = {}
    local dirt = {}
    for row = 0, 27 do
        for col = 0, 27 do
            local cell = state.map[row][col]
            if cell.tileType == 0x4 and cell.rock ~= 0 and ROCK[cell.rock] then
                appendCoord(rocks, cell.rock, col, row)
            end
            if cell.dirt ~= 0 and DIRT[cell.dirt] then
                appendCoord(dirt, cell.dirt, col, row)
            end
        end
    end
    return rocks, dirt
end

local function renderItemNames()
    if not state.itemsBuffer then
        return
    end

    state.itemsBuffer:clear()
    if not state.map or not state.mineName then
        state.itemsBuffer:print("当前不在矿场。进入泉边矿场或湖中矿场后，这里会显示完整物品名称。\n")
        return
    end

    local rocks, dirt = collectItemCoords()
    state.itemsBuffer:print(string.format(
        "%s  第 %d 层   体力=%d   疲劳=%d\n",
        state.mineName,
        state.floor,
        emu:read8(ADDR.stamina),
        emu:read8(ADDR.fatigue) % 0x80
    ))
    state.itemsBuffer:print("坐标格式为 (X,Y)；先在 Mine Map 页找坐标，再到游戏中对应格子。\n\n")

    state.itemsBuffer:print("【稀有物品与诅咒道具】\n")
    for _, target in ipairs(SPECIAL_TARGETS) do
        local item = target.kind == "rock" and ROCK[target.id] or DIRT[target.id]
        local coords = target.kind == "rock" and rocks[target.id] or dirt[target.id]
        local place = target.kind == "rock" and "石头内" or "地下"
        if coords and #coords > 0 then
            state.itemsBuffer:print(string.format("● %s（%s）：%d 个\n", item.name, place, #coords))
            printAllCoords(state.itemsBuffer, coords)
        else
            state.itemsBuffer:print(string.format("○ %s（%s）：本层没有\n", item.name, place))
        end
    end

    state.itemsBuffer:print("\n【本层所有矿石】\n")
    local anyRock = false
    for _, id in ipairs(ROCK_ORDER) do
        local coords = rocks[id]
        if coords and #coords > 0 then
            anyRock = true
            state.itemsBuffer:print(string.format("%s：%d 个\n", ROCK[id].name, #coords))
            printAllCoords(state.itemsBuffer, coords)
        end
    end
    if not anyRock then
        state.itemsBuffer:print("本层没有含物品的石头。\n")
    end

    state.itemsBuffer:print("\n【本层所有地下物】\n")
    local anyDirt = false
    for _, id in ipairs(DIRT_ORDER) do
        local coords = dirt[id]
        if coords and #coords > 0 then
            anyDirt = true
            state.itemsBuffer:print(string.format("%s：%d 个\n", DIRT[id].name, #coords))
            printAllCoords(state.itemsBuffer, coords)
        end
    end
    if not anyDirt then
        state.itemsBuffer:print("本层没有地下物。\n")
    end

    state.itemsBuffer:print("\n说明：同层可有很多“下层楼梯候选”。挖出一个后，其他候选会消失。\n")
end

local function renderNotInMine(location, extra)
    state.buffer:clear()
    state.buffer:print("矿场透视（只读内存）\n\n")
    if extra then
        state.buffer:print(extra .. "\n\n")
    end
    state.buffer:print(string.format("当前地图 ID: 0x%04X\n", location or 0))
    state.buffer:print("进入泉边矿场或冬季湖中矿场后，28x28 网格会自动出现。\n")
    state.buffer:print("每格两个字符：第 1 个=石头/格子状态，第 2 个=地下内容。\n")
    if state.itemsBuffer then
        state.itemsBuffer:clear()
        state.itemsBuffer:print("当前不在矿场。进入矿场后，这里会按完整中文名称显示物品与坐标。\n")
    end
end

local function renderText()
    local groups = {}
    local unknown = {}
    local stairCount = 0

    state.buffer:clear()
    state.buffer:print(string.format(
        "%s  第%d层   地图=0x%04X   体力=%d   疲劳=%d\n",
        state.mineName,
        state.floor,
        state.location,
        emu:read8(ADDR.stamina),
        emu:read8(ADDR.fatigue) % 0x80
    ))
    state.buffer:print("这里是坐标地图；完整物品名称请点左侧【Item Names 物品名称】。\n")
    state.buffer:print("每格=RD：R 是石头/格子，D 是地下物。坐标顺序为 (X,Y)。\n\n")

    state.buffer:print("    ")
    for col = 0, 27 do
        state.buffer:print(string.format("%02d ", col))
    end
    state.buffer:print("\n")

    for row = 0, 27 do
        local rowText = {}
        for col = 0, 27 do
            local cell = state.map[row][col]
            rowText[#rowText + 1] = cellCode(cell)

            local rockItem = ROCK[cell.rock]
            if cell.tileType == 0x4 and cell.rock ~= 0 then
                if rockItem then
                    if rockItem.important then
                        appendCoord(groups, rockItem.name, col, row)
                    end
                else
                    unknown[string.format("rock=0x%02X", cell.rock)] = true
                end
            end

            local dirtItem = DIRT[cell.dirt]
            if cell.dirt == 0x01 then
                stairCount = stairCount + 1
            elseif cell.dirt ~= 0 then
                if dirtItem then
                    if dirtItem.important then
                        appendCoord(groups, dirtItem.name, col, row)
                    end
                else
                    unknown[string.format("dirt=0x%02X", cell.dirt)] = true
                end
            end

            if TILE_CHAR[cell.tileType] == nil then
                unknown[string.format("type=0x%X", cell.tileType)] = true
            end
        end
        state.buffer:print(string.format("%02d  %s\n", row, table.concat(rowText, " ")))
    end

    state.buffer:print(string.format("\n下层楼梯候选格(v): %d 个（挖出任意一个后，其余候选会消失）\n", stairCount))
    local names = {}
    for name, _ in pairs(groups) do
        names[#names + 1] = name
    end
    table.sort(names)
    if #names > 0 then
        state.buffer:print("重要物品坐标：\n")
        for _, name in ipairs(names) do
            state.buffer:print("  " .. name .. ": " .. coordSummary(groups[name]) .. "\n")
        end
    end

    local unknownNames = {}
    for name, _ in pairs(unknown) do
        unknownNames[#unknownNames + 1] = name
    end
    table.sort(unknownNames)
    if #unknownNames > 0 then
        state.buffer:print("未识别编号: " .. table.concat(unknownNames, ", ") .. "\n")
    end

    state.buffer:print("\nR(第1字): #空石 x废矿 C铜 S银 G金 M秘银 O奥利哈钢 A金刚石\n")
    state.buffer:print("          N月亮 R沙漠玫瑰 P粉红钻 L亚历山大 Y贤者 D钻石 E祖母绿\n")
    state.buffer:print("          U红宝石 T黄玉 I橄榄 F萤石 Q玛瑙 H紫水晶 V女神玉 K河童玉 @转移石\n")
    state.buffer:print("D(第2字): v下层楼梯 $钱袋 P力之果实 s镰刀 h锄头 a斧头 m锤子 w洒水器 f钓竿 b黑草 r菜谱\n")
    state.buffer:print("格子状态: ..未挖 =.已挖 v.已显示下楼 ^.上楼；例如 Cv=铜矿石+楼梯候选。\n")
end

local function tryCreateOverlay()
    if canvas == nil or image == nil then
        return false
    end
    local ok, err = pcall(function()
        state.overlay = canvas:newLayer(canvas:screenWidth(), canvas:screenHeight())
        state.overlay:setPosition(0, 0)
        state.painter = image.newPainter(state.overlay.image)
        state.painter:setFill(true)
        state.painter:setStrokeWidth(0)
        state.painter:setBlend(true)
        -- 粗体微软雅黑在 GBA 的 240x160 小画布上比 7 号黑体更清楚。
        local fontOk, fontError = pcall(function()
            state.painter:loadFont("C:/Windows/Fonts/msyhbd.ttc")
        end)
        if not fontOk then
            local fallbackOk = pcall(function()
                state.painter:loadFont("C:/Windows/Fonts/simhei.ttf")
            end)
            if not fallbackOk then
                console:warn("矿场透视：中文字体载入失败，将使用 mGBA 默认字体：" .. tostring(fontError))
            end
        end
        state.painter:setFontSize(CONFIG.overlayFontSize)
    end)
    if not ok then
        console:warn("矿场透视：Canvas 叠加启用失败，已改用文字网格：" .. tostring(err))
        state.overlay = nil
        state.painter = nil
        return false
    end
    return true
end

local function drawTileMarker(item, x, y)
    if CONFIG.showTileLabels and item.label and item.label ~= "" then
        -- 标签缩在 16x16 游戏格中央，四周留空，方便判断它属于哪一格。
        state.painter:setStrokeWidth(0)
        state.painter:setFillColor(CONFIG.labelBackgroundColor)
        state.painter:drawRectangle(x + 2, y + 2, 12, 12)
        state.painter:setStrokeColor(0xFF000000)
        state.painter:setStrokeWidth(1)
        state.painter:setFillColor(item.color)
        state.painter:drawText(item.label, x + 2, y - 1, 17)
        state.painter:setStrokeWidth(0)
    else
        state.painter:setFillColor(item.color)
        state.painter:drawRectangle(x + 6, y + 6, 4, 4)
    end
end

local function drawGroundCue(item, id, x, y)
    -- 主标签被矿石占用时，用格子右下角提示地下物；橙色 L 角就是楼梯候选。
    state.painter:setStrokeWidth(0)
    state.painter:setFillColor(item.color)
    if id == 0x01 then
        state.painter:drawRectangle(x + 10, y + 13, 5, 2)
        state.painter:drawRectangle(x + 13, y + 10, 2, 5)
    else
        state.painter:drawRectangle(x + 11, y + 11, 4, 4)
    end
end

local function drawRockCue(item, x, y)
    -- 诅咒道具等重要地下物作为主标签时，左上角小色块保留“此格还有矿石”的提示。
    state.painter:setStrokeWidth(0)
    state.painter:setFillColor(item.color)
    state.painter:drawRectangle(x, y, 4, 4)
end

local function clearOverlay()
    if not state.overlayReady then
        return
    end
    state.painter:setBlend(false)
    state.painter:setStrokeWidth(0)
    state.painter:setFillColor(0x00000000)
    state.painter:drawRectangle(0, 0, canvas:screenWidth(), canvas:screenHeight())
    state.painter:setBlend(true)
    state.overlay:update()
    state.overlayWasVisible = false
    state.lastOverlayCameraX = nil
    state.lastOverlayCameraY = nil
end

local function drawOverlay(force)
    if not state.overlayReady or not state.map then
        return
    end

    local cameraX = emu:read16(ADDR.cameraX)
    local cameraY = emu:read16(ADDR.cameraY)
    local frame = emu:currentFrame()
    local cameraChanged = cameraX ~= state.lastOverlayCameraX or cameraY ~= state.lastOverlayCameraY
    if not force and not cameraChanged then
        return
    end
    if not force and frame >= state.lastOverlayFrame
        and frame - state.lastOverlayFrame < CONFIG.overlayRefreshFrames then
        return
    end
    state.lastOverlayFrame = frame
    state.lastOverlayCameraX = cameraX
    state.lastOverlayCameraY = cameraY

    state.painter:setBlend(false)
    state.painter:setFillColor(0x00000000)
    state.painter:drawRectangle(0, 0, canvas:screenWidth(), canvas:screenHeight())
    state.painter:setBlend(true)

    -- 右上角直接显示当前矿场与层数。
    state.painter:setStrokeWidth(0)
    state.painter:setFillColor(CONFIG.headerBackgroundColor)
    state.painter:drawRectangle(181, 0, 59, 15)
    state.painter:setStrokeColor(0xFF000000)
    state.painter:setStrokeWidth(1)
    state.painter:setFillColor(0xFFFFFFFF)
    state.painter:setFontSize(10)
    local mineShort = state.mineName == "湖中矿场" and "湖" or "泉"
    state.painter:drawText(mineShort .. tostring(state.floor) .. "层", 184, -3, 17)
    state.painter:setStrokeWidth(0)
    state.painter:setFontSize(CONFIG.overlayFontSize)

    local screenWidth = canvas:screenWidth()
    local screenHeight = canvas:screenHeight()
    for row = 0, 27 do
        for col = 0, 27 do
            local cell = state.map[row][col]
            local x = 24 + col * 16 - cameraX
            local y = 55 + row * 16 - cameraY
            -- 只绘制当前屏幕可见的格子；屏幕外的 600 多格不再生成文字。
            local isVisible = x > -15 and x < screenWidth and y > -15 and y < screenHeight
            local rockItem = ROCK[cell.rock]
            local showRock = cell.tileType == 0x4 and rockItem and rockItem.color ~= 0
                and (CONFIG.showJunkOre or cell.rock ~= 0x0C)
            local dirtItem = DIRT[cell.dirt]
            local showDirt = dirtItem and dirtItem.color ~= 0
                and (CONFIG.showMoney or cell.dirt ~= 0x02)

            -- 诅咒工具、力之果实和菜谱优先；普通楼梯/钱袋只做角标，不盖住矿石名称。
            if isVisible then
                local dirtIsMain = showDirt and (not showRock or (dirtItem.important and cell.dirt ~= 0x01))
                if dirtIsMain then
                    drawTileMarker(dirtItem, x, y)
                    if showRock then
                        drawRockCue(rockItem, x, y)
                    end
                elseif showRock then
                    drawTileMarker(rockItem, x, y)
                    if showDirt then
                        drawGroundCue(dirtItem, cell.dirt, x, y)
                    end
                elseif showDirt then
                    drawTileMarker(dirtItem, x, y)
                end
            end
        end
    end

    state.overlay:update()
    state.overlayWasVisible = true
end

local function refresh(force)
    if emu == nil then
        return
    end

    local frame = emu:currentFrame()
    if not force and frame >= state.lastRefreshFrame and frame - state.lastRefreshFrame < CONFIG.refreshFrames then
        updateExternalOverlay(false)
        drawOverlay(false)
        return
    end
    state.lastRefreshFrame = frame

    local location = emu:read16(ADDR.mineLocation)
    local locationChanged = location ~= state.location
    local name, floor = mineInfo(location)
    state.location = location
    state.mineName = name
    state.floor = floor

    if not name then
        local wasInMine = state.map ~= nil
        state.map = nil
        state.mapSignature = nil
        if force or locationChanged or wasInMine then
            renderNotInMine(location)
        end
        if state.overlayWasVisible then
            clearOverlay()
        end
        if force or locationChanged or wasInMine then
            writeExternalOverlayInactive(true)
        end
        return
    end

    local newMap, newSignature = readMineMap()
    local mapChanged = newSignature ~= state.mapSignature
    state.map = newMap
    state.mapSignature = newSignature

    -- 只有换层或格子内容真正变化时才清空、重画文字。
    -- 普通帧只更新画面叠加（如果 mGBA 版本支持），不会影响文字滚动位置。
    if force or locationChanged or mapChanged then
        renderText()
        renderItemNames()
    end
    updateExternalOverlay(force or locationChanged or mapChanged)
    drawOverlay(force or locationChanged or mapChanged)
end

local function initialize()
    state.buffer = console:createBuffer("Mine Map 坐标地图")
    state.buffer:setSize(92, 64)
    state.itemsBuffer = console:createBuffer("Item Names 物品名称")
    state.itemsBuffer:setSize(72, 800)

    if emu == nil then
        renderNotInMine(0, "请先载入游戏 ROM，再重新载入此脚本。")
        return
    end

    local gameCode = readRomGameCode()
    if gameCode ~= "A4NJ" then
        renderNotInMine(emu:read16(ADDR.mineLocation),
            string.format("警告：当前 ROM 代码是 %s，此脚本已验证的版本是 A4NJ 男孩版。", tostring(gameCode)))
        console:warn(string.format("矿场透视：ROM 代码是 %s，不是 A4NJ，内存地址可能不适用。", tostring(gameCode)))
    end

    if CONFIG.useExternalHdOverlay then
        state.overlayReady = false
        console:log("矿场透视：已启用 Windows 高清透明浮层数据桥接；mGBA 像素叠加已关闭。")
    else
        state.overlayReady = tryCreateOverlay()
    end
    if state.overlayReady then
        console:log("矿场透视：已启用文字网格与游戏画面彩色点叠加。")
    elseif not CONFIG.useExternalHdOverlay then
        console:log("矿场透视：已启用文字网格。mGBA 0.10.x 无 Canvas，这是正常情况。")
    end

    writeExternalOverlayInactive(true)
    refresh(true)
    callbacks:add("frame", refresh)
    callbacks:add("shutdown", function() writeExternalOverlayInactive(true) end)
end

initialize()

