script_name('LRP - LSPD HELPER')
script_author('_spartacus')

require 'lib.moonloader'

local encoding = require 'encoding'
encoding.default = 'CP1252'
local u8 = encoding.UTF8

local sampev = require 'samp.events'

local INI_PATH = getWorkingDirectory() .. '\\config\\lspdhelper.ini'

local PANEL_PADDING = 6
local LINE_SPACING_BASE = 13

local TITLE_COLOR = 0xFFFFFFFF
local SUB_COLOR = 0xFFE0E0E0
local TEXT_ON_COLOR = 0xFF7CFF7C
local TEXT_OFF_COLOR = 0xFFFF7C7C
local TEXT_NEUTRAL_COLOR = 0xFFEAEAEA
local SHADOW_COLOR = 0xC0000000

local BG_COLOR = 0x90000000
local BORDER_COLOR = 0x55FFFFFF
local STATUS_PART_COLOR = 0xFFCFCFCF
local SEP_COLOR = 0xFFB0B0B0

local panelEnabled = true
local capturing = false
local suppress = false
local captureStart = 0
local lastServerLineAt = 0
local internalSend = false

local titleLine = 'LSPD Helper'
local lastUpdateStr = nil

local font = nil
local fontBold = nil

local cfg = {
    version = '1.1',
    x = 0.99,
    y = 0.80,
    z = 1.00,
    scale = 1.00,
    font = 'Arial Narrow',
    max_width_ratio = 0.95,
    safeMargin = 4,
    status_max_chars = 120,
    auto_refresh = 1,
    auto_refresh_interval = 30,
    title_show_counts = 1,
    title_template = 'LSPD Helper (ON:{ON} | OFF:{OFF} | TOTAL:{TOTAL})',
    hotkey_mod = 'CTRL',
    hotkey_key = 'J',
    capture_timeout = 10.0,
    capture_idle_end = 2.00,
    max_lines = 20,
    text_width_factor = 1.00,
    text_width_add = 0,
    text_right_padding = 6
}

local KEY_MOD = VK_CONTROL
local KEY_TOGGLE = VK_J

local entries = {}
local renderLeft = {}
local renderRight = {}
local renderColors = {}
local layoutDirty = true
local cachedBoxW, cachedBoxH = 0, 0
local seenKeys = {}

local function trim(s)
    return (tostring(s or ''):gsub('^%s+', ''):gsub('%s+$', ''))
end

local function stripColorCodes(s)
    s = tostring(s or '')
    s = s:gsub('{%x%x%x%x%x%x}', '')
    s = s:gsub('{%x%x%x%x%x%x%x%x}', '')
    return s
end

local function safeDecode(text)
    local raw = tostring(text or '')
    local decoded = raw
    local ok, res = pcall(function() return u8:decode(raw) end)
    if ok and type(res) == 'string' and res ~= '' then decoded = res end
    return decoded
end

local function nowTime()
    local t = os.date('*t')
    return string.format('%02d:%02d:%02d', t.hour, t.min, t.sec)
end

local function clamp(v, mn, mx)
    v = tonumber(v) or mn
    if v < mn then return mn end
    if v > mx then return mx end
    return v
end

local function clampInt(v, mn, mx)
    v = tonumber(v)
    if not v then return mn end
    v = math.floor(v + 0.5)
    if v < mn then return mn end
    if v > mx then return mx end
    return v
end

local function measureTextWidth(f, s)
    s = tostring(s or '')
    if s == '' then return 0 end
    local w = renderGetFontDrawTextLength(f, s)
    w = (w * (cfg.text_width_factor or 1.0)) + (cfg.text_width_add or 0)
    return w
end

local function truncateToWidthNoDots(f, s, maxPx)
    s = tostring(s or '')
    if s == '' then return '' end
    if maxPx <= 0 then return '' end
    if measureTextWidth(f, s) <= maxPx then return s end
    local cut = s
    while #cut > 1 and measureTextWidth(f, cut) > maxPx do
        cut = cut:sub(1, #cut - 1)
    end
    return cut
end

local function drawTextShadow(f, txt, x, y, color)
    renderFontDrawText(f, txt, x + 1, y + 1, SHADOW_COLOR)
    renderFontDrawText(f, txt, x, y, color)
end

local function drawRect(x, y, w, h, color)
    renderDrawBox(x, y, w, h, color)
end

local function ensureIniExists()
    local f = io.open(INI_PATH, 'r')
    if f then f:close() return end

    os.execute('mkdir "' .. getWorkingDirectory() .. '\\config"')
    local w = io.open(INI_PATH, 'w+')
    if not w then return end

    w:write('[jpanel]\n\n')
    w:write('VERSION=1.1\n\n')
    w:write('X=0.99\nY=0.80\nZ=1.0\nSCALE=1.0\nFONT=Arial Narrow\n\n')
    w:write('MAX_WIDTH_RATIO=0.95\nSAFE_MARGIN=4\nSTATUS_MAX_CHARS=120\n\n')
    w:write('AUTO_REFRESH=1\nAUTO_REFRESH_INTERVAL=30\n\n')
    w:write('TITLE_SHOW_COUNTS=1\nTITLE_TEMPLATE=LSPD Helper (ON:{ON} | OFF:{OFF} | TOTAL:{TOTAL})\n\n')
    w:write('HOTKEY_MOD=CTRL\nHOTKEY_KEY=J\n\n')
    w:write('CAPTURE_TIMEOUT=10.0\nCAPTURE_IDLE_END=2.00\n\n')
    w:write('MAX_LINES=20\n\n')
    w:write('TEXT_WIDTH_FACTOR=1.00\n')
    w:write('TEXT_WIDTH_ADD=0\n')
    w:write('TEXT_RIGHT_PADDING=6\n')

    w:close()
end

local function vkFromKeyName(v)
    v = trim(v)
    if v == '' then return nil end
    local n = tonumber(v)
    if n then return n end
    local up = v:upper()
    if #up == 1 then return _G['VK_' .. up] end
    return _G['VK_' .. up]
end

local function resolveHotkey()
    local m = (cfg.hotkey_mod or 'CTRL'):upper()
    if m == 'NONE' then
        KEY_MOD = 0
    elseif m == 'ALT' then
        KEY_MOD = VK_MENU
    elseif m == 'SHIFT' then
        KEY_MOD = VK_SHIFT
    else
        KEY_MOD = VK_CONTROL
    end
    KEY_TOGGLE = vkFromKeyName(cfg.hotkey_key or 'J') or VK_J
end

local function getHotkeyLabel()
    local m = (cfg.hotkey_mod or 'CTRL'):upper()
    local k = (cfg.hotkey_key or 'J'):upper()
    if m == 'NONE' then return k end
    return m .. ' + ' .. k
end

local function loadIni()
    ensureIniExists()

    local t = {
        version = cfg.version,
        x = cfg.x, y = cfg.y, z = cfg.z, scale = cfg.scale,
        font = cfg.font,
        max_width_ratio = cfg.max_width_ratio,
        safe_margin = cfg.safeMargin,
        status_max_chars = cfg.status_max_chars,
        auto_refresh = cfg.auto_refresh,
        auto_refresh_interval = cfg.auto_refresh_interval,
        title_show_counts = cfg.title_show_counts,
        title_template = cfg.title_template,
        hotkey_mod = cfg.hotkey_mod,
        hotkey_key = cfg.hotkey_key,
        capture_timeout = cfg.capture_timeout,
        capture_idle_end = cfg.capture_idle_end,
        max_lines = cfg.max_lines,
        text_width_factor = cfg.text_width_factor,
        text_width_add = cfg.text_width_add,
        text_right_padding = cfg.text_right_padding
    }

    local file = io.open(INI_PATH, 'r')
    if not file then return end

    local section = nil
    for line in file:lines() do
        local s = trim(line)
        if s ~= '' and not s:match('^;') and not s:match('^#') then
            local sec = s:match('^%[(.-)%]$')
            if sec then
                section = sec:lower()
            else
                local k, v = s:match('^(.-)=(.*)$')
                if k and v then
                    local allow = (section == nil) or (section == 'lspdhelper') or (section == 'jpanel')
                    if allow then
                        k = trim(k):upper()
                        v = trim(v)
                        if k == 'VERSION' then t.version = v end
                        if k == 'X' then t.x = tonumber(v) or t.x end
                        if k == 'Y' then t.y = tonumber(v) or t.y end
                        if k == 'Z' then t.z = tonumber(v) or t.z end
                        if k == 'SCALE' then t.scale = tonumber(v) or t.scale end
                        if k == 'FONT' and v ~= '' then t.font = v end
                        if k == 'MAX_WIDTH_RATIO' then t.max_width_ratio = tonumber(v) or t.max_width_ratio end
                        if k == 'SAFE_MARGIN' then t.safe_margin = tonumber(v) or t.safe_margin end
                        if k == 'STATUS_MAX_CHARS' then t.status_max_chars = tonumber(v) or t.status_max_chars end
                        if k == 'AUTO_REFRESH' then t.auto_refresh = tonumber(v) or t.auto_refresh end
                        if k == 'AUTO_REFRESH_INTERVAL' then t.auto_refresh_interval = tonumber(v) or t.auto_refresh_interval end
                        if k == 'TITLE_SHOW_COUNTS' then t.title_show_counts = tonumber(v) or t.title_show_counts end
                        if k == 'TITLE_TEMPLATE' and v ~= '' then t.title_template = v end
                        if k == 'HOTKEY_MOD' and v ~= '' then t.hotkey_mod = v end
                        if k == 'HOTKEY_KEY' and v ~= '' then t.hotkey_key = v end
                        if k == 'CAPTURE_TIMEOUT' then t.capture_timeout = tonumber(v) or t.capture_timeout end
                        if k == 'CAPTURE_IDLE_END' then t.capture_idle_end = tonumber(v) or t.capture_idle_end end
                        if k == 'MAX_LINES' then t.max_lines = tonumber(v) or t.max_lines end
                        if k == 'TEXT_WIDTH_FACTOR' then t.text_width_factor = tonumber(v) or t.text_width_factor end
                        if k == 'TEXT_WIDTH_ADD' then t.text_width_add = tonumber(v) or t.text_width_add end
                        if k == 'TEXT_RIGHT_PADDING' then t.text_right_padding = tonumber(v) or t.text_right_padding end
                    end
                end
            end
        end
    end
    file:close()

    cfg.version = (t.version ~= '' and t.version) or '1.1'
    cfg.x = clamp(t.x, 0.0, 1.0)
    cfg.y = clamp(t.y, 0.0, 1.0)
    cfg.z = clamp(t.z, 0.0, 1.0)
    cfg.scale = clamp(t.scale, 0.5, 3.0)
    cfg.font = t.font
    cfg.max_width_ratio = clamp(t.max_width_ratio, 0.25, 0.99)
    cfg.safeMargin = clampInt(t.safe_margin, 0, 80)
    cfg.status_max_chars = clampInt(t.status_max_chars, 0, 300)
    cfg.auto_refresh = clampInt(t.auto_refresh, 0, 1)
    cfg.auto_refresh_interval = clampInt(t.auto_refresh_interval, 5, 600)
    cfg.title_show_counts = clampInt(t.title_show_counts, 0, 1)
    cfg.title_template = t.title_template or cfg.title_template
    cfg.hotkey_mod = t.hotkey_mod or cfg.hotkey_mod
    cfg.hotkey_key = t.hotkey_key or cfg.hotkey_key
    cfg.capture_timeout = clamp(t.capture_timeout, 2.0, 30.0)
    cfg.capture_idle_end = clamp(t.capture_idle_end, 0.3, 10.0)
    cfg.max_lines = clampInt(t.max_lines, 5, 80)
    cfg.text_width_factor = clamp(t.text_width_factor, 0.80, 1.30)
    cfg.text_width_add = clampInt(t.text_width_add, -50, 50)
    cfg.text_right_padding = clampInt(t.text_right_padding, 0, 40)

    resolveHotkey()

    if font then renderReleaseFont(font) end
    if fontBold then renderReleaseFont(fontBold) end

    local size = math.floor(8 * cfg.scale + 0.5)
    if size < 7 then size = 7 end

    font = renderCreateFont(cfg.font, size, 5)
    fontBold = renderCreateFont(cfg.font, size, 7)

    layoutDirty = true
end

local function shortenGrade(grade)
    local g = trim(grade)
    g = g:gsub('Chef de la police', 'Chef')
    g = g:gsub('Commandant', 'CMDT.')
    g = g:gsub('Capitaine', 'CPT.')
    g = g:gsub('Lieutenant', 'LTN.')
    g = g:gsub('Sergent', 'SGT.')
    g = g:gsub('Officier', 'OFF.')
    g = g:gsub('Recrue', 'REC.')
    g = g:gsub('%s+', ' ')
    return g
end

local function removeRankCodePrefix(rankCode, gradeShort)
    local rnum = tostring(rankCode or ''):match('^R(%d+)$')
    if not rnum then return gradeShort end
    local g = trim(gradeShort)
    local prefix = 'R' .. rnum .. ' '
    if g:sub(1, #prefix):upper() == prefix:upper() then
        g = trim(g:sub(#prefix + 1))
    end
    return g
end

local function extractUnitKey(statusText)
    local s = trim(statusText or '')
    if s == '' or s == 'N/A' then return '' end
    local key = s:match('^([A-Za-z]+%d+)')
    if key then return key:upper() end
    return ''
end

local function parseOfficerLine(msg)
    local raw = trim(stripColorCodes(msg))
    raw = raw:gsub('%s+', ' ')

    local first, last, rankCode, rest = raw:match('^([%w]+)_([%w]+)%s+(R%d+)%s+(.+)$')
    if not first then return nil end

    local phone = rest:match('%((%d%d%d%-%d%d%d%d)%)')
    if not phone then return nil end

    local grade = rest:match('^(.-)%s*%(%d%d%d%-%d%d%d%d%)')
    grade = trim(grade or '')
    if grade == '' then return nil end

    local onDutyStr = rest:match('%((ON)%)') or rest:match('%((OFF)%)') or ''
    local onDuty = nil
    if onDutyStr == 'ON' then onDuty = true end
    if onDutyStr == 'OFF' then onDuty = false end

    local statusText = rest
    statusText = statusText:gsub('%(%d%d%d%-%d%d%d%d%)', '')
    statusText = statusText:gsub('%(ON%)', '')
    statusText = statusText:gsub('%(OFF%)', '')
    statusText = trim(statusText)

    local escapedGrade = grade:gsub('([^%w])', '%%%1')
    statusText = statusText:gsub('^' .. escapedGrade, '')
    statusText = trim(statusText)
    if statusText == '' then statusText = 'N/A' end

    if cfg.status_max_chars > 0 and #statusText > cfg.status_max_chars then
        statusText = statusText:sub(1, cfg.status_max_chars)
    end

    local initial = first:sub(1, 1):upper()
    local lastname = last:upper()

    local gradeShort = shortenGrade(grade)
    gradeShort = removeRankCodePrefix(rankCode, gradeShort)

    local unitKey = extractUnitKey(statusText)

    return {
        first = first,
        last = last,
        onDuty = onDuty,
        unitKey = unitKey,
        left = string.format('%s.%s (%s)', initial, lastname, gradeShort),
        right = statusText
    }
end

local function applyTitleCounts(onCount, offCount)
    if cfg.title_show_counts ~= 1 then
        titleLine = 'LSPD Helper'
        return
    end
    local tpl = cfg.title_template or 'LSPD Helper (ON:{ON} | OFF:{OFF} | TOTAL:{TOTAL})'
    tpl = tpl:gsub('{ON}', tostring(onCount))
    tpl = tpl:gsub('{OFF}', tostring(offCount))
    tpl = tpl:gsub('{TOTAL}', tostring(onCount + offCount))
    titleLine = tpl
end

local function sortAndBuildRender()
    local onList, offList = {}, {}
    for i = 1, #entries do
        local e = entries[i]
        if e and e.onDuty == true then
            onList[#onList + 1] = e
        else
            offList[#offList + 1] = e
        end
    end

    local function cmp(a, b)
    local au = (a.unitKey or '')
    local bu = (b.unitKey or '')

    local aEmpty = (au == '') and 1 or 0
    local bEmpty = (bu == '') and 1 or 0
    if aEmpty ~= bEmpty then return aEmpty < bEmpty end

    if au ~= bu then return au < bu end

    local al = (a.last or ''):lower()
    local bl = (b.last or ''):lower()
    if al ~= bl then return al < bl end

    return (a.first or ''):lower() < (b.first or ''):lower()
    end

    table.sort(onList, cmp)
    table.sort(offList, cmp)

    renderLeft, renderRight, renderColors = {}, {}, {}

    for i = 1, #onList do
        renderLeft[#renderLeft + 1] = onList[i].left
        renderRight[#renderRight + 1] = onList[i].right
        renderColors[#renderColors + 1] = TEXT_ON_COLOR
    end

    if #onList > 0 and #offList > 0 then
        renderLeft[#renderLeft + 1] = '----------------'
        renderRight[#renderRight + 1] = ''
        renderColors[#renderColors + 1] = SUB_COLOR
    end

    for i = 1, #offList do
        renderLeft[#renderLeft + 1] = offList[i].left
        renderRight[#renderRight + 1] = offList[i].right
        renderColors[#renderColors + 1] = TEXT_OFF_COLOR
    end

    return #onList, #offList
end

local function startCapture()
    capturing = true
    suppress = true
    captureStart = os.clock()
    lastServerLineAt = os.clock()
    entries = {}
    renderLeft, renderRight, renderColors = {}, {}, {}
    seenKeys = {}
    lastUpdateStr = nowTime()
    layoutDirty = true
end

local function stopCapture()
    capturing = false
    suppress = false
    local onCount, offCount = sortAndBuildRender()
    applyTitleCounts(onCount, offCount)
    lastUpdateStr = nowTime()
    layoutDirty = true
end

local function triggerRefresh()
    if capturing then return end
    startCapture()
    lua_thread.create(function()
        wait(0)
        internalSend = true
        sampSendChat('/jmembres')
    end)
end

local function computeLayout(sx, sy, pad, lineH)
    local header = titleLine or 'LSPD Helper'
    local stampTime = lastUpdateStr
    if not stampTime or stampTime == '' or stampTime == '--' then stampTime = 'N/A' end
    local stamp = 'Upd: ' .. stampTime .. '  v' .. tostring(cfg.version or '1.1')

    local sepW = measureTextWidth(font, ' | ')

    local maxW = 0
    maxW = math.max(maxW, measureTextWidth(fontBold, header))
    maxW = math.max(maxW, measureTextWidth(font, stamp))

    local contentCount = math.min(#renderLeft, cfg.max_lines)
    if contentCount == 0 then
        maxW = math.max(maxW, measureTextWidth(font, 'Tapez /jmembres'))
    else
        for i = 1, contentCount do
            local l = renderLeft[i] or ''
            local r = renderRight[i] or ''
            local w = measureTextWidth(font, l)
            if r ~= '' and l ~= '----------------' then
                w = w + sepW + measureTextWidth(font, r)
            end
            if w > maxW then maxW = w end
        end
    end

    local boxW = math.floor(maxW + pad * 2)
    local minW = 220
    if boxW < minW then boxW = minW end

    local safeMargin = cfg.safeMargin or 8
    local maxWcap = math.floor(sx * (cfg.max_width_ratio or 0.95)) - (safeMargin * 2)
    if maxWcap > (sx - safeMargin * 2) then maxWcap = (sx - safeMargin * 2) end
    if maxWcap < 160 then maxWcap = (sx - safeMargin * 2) end
    if boxW > maxWcap then boxW = maxWcap end

    local rows = 2 + (contentCount > 0 and contentCount or 1)
    local boxH = math.floor(pad * 2 + lineH * rows)

    cachedBoxW, cachedBoxH = boxW, boxH
end

local function drawPanel()
    if not panelEnabled then return end
    if not font or not fontBold then return end

    local sx, sy = getScreenResolution()
    local scale = cfg.scale

    local safeMargin = cfg.safeMargin or 8
    local pad = math.floor(PANEL_PADDING * scale + 0.5)
    local lineH = math.floor(LINE_SPACING_BASE * scale + 0.5)
    if lineH < 11 then lineH = 11 end

    if layoutDirty then
        computeLayout(sx, sy, pad, lineH)
        layoutDirty = false
    end

    local boxW, boxH = cachedBoxW, cachedBoxH

    local anchorX = math.floor(sx * cfg.x + 0.5)
    local anchorY = math.floor(sy * cfg.y + 0.5)

    local x = math.floor(anchorX - (boxW * cfg.z) + 0.5)
    local y = anchorY

    if x < safeMargin then x = safeMargin end
    if y < safeMargin then y = safeMargin end
    if x + boxW > sx - safeMargin then x = sx - boxW - safeMargin end
    if y + boxH > sy - safeMargin then y = sy - boxH - safeMargin end

    drawRect(x, y, boxW, boxH, BG_COLOR)
    drawRect(x, y, boxW, 1, BORDER_COLOR)
    drawRect(x, y + boxH - 1, boxW, 1, BORDER_COLOR)
    drawRect(x, y, 1, boxH, BORDER_COLOR)
    drawRect(x + boxW - 1, y, 1, boxH, BORDER_COLOR)

    local header = titleLine or 'LSPD Helper'
    local stampTime = lastUpdateStr
    if not stampTime or stampTime == '' or stampTime == '--' then stampTime = 'N/A' end
    local stamp = 'Upd: ' .. stampTime .. '  v' .. tostring(cfg.version or '1.1')
    local contentCount = math.min(#renderLeft, cfg.max_lines)

    local tx = x + pad
    local ty = y + pad
    local usableW = boxW - (pad * 2) - (cfg.text_right_padding or 0)
    if usableW < 40 then usableW = 40 end

    drawTextShadow(fontBold, truncateToWidthNoDots(fontBold, header, usableW), tx, ty, TITLE_COLOR)
    ty = ty + lineH

    drawTextShadow(font, truncateToWidthNoDots(font, stamp, usableW), tx, ty, SUB_COLOR)
    ty = ty + lineH

    if contentCount == 0 then
        drawTextShadow(font, 'Tapez /jmembres', tx, ty, SUB_COLOR)
        return
    end

    for i = 1, contentCount do
        local left = renderLeft[i] or ''
        local right = renderRight[i] or ''
        local col = renderColors[i] or TEXT_NEUTRAL_COLOR

        if left == '----------------' then
            drawTextShadow(font, truncateToWidthNoDots(font, left, usableW), tx, ty, SUB_COLOR)
        elseif right == '' then
            drawTextShadow(font, truncateToWidthNoDots(font, left, usableW), tx, ty, col)
        else
            local sep = ' | '
            local sepW = measureTextWidth(font, sep)
            local rightW = measureTextWidth(font, right)

            local leftMax
            local rightMax
            if rightW + sepW < usableW then
                leftMax = usableW - (rightW + sepW)
                rightMax = rightW
            else
                leftMax = math.floor(usableW * 0.55)
                rightMax = usableW - (leftMax + sepW)
                if rightMax < 40 then rightMax = 40 end
            end

            local leftDraw = truncateToWidthNoDots(font, left, leftMax)
            drawTextShadow(font, leftDraw, tx, ty, col)

            local lx = tx + measureTextWidth(font, leftDraw)
            drawTextShadow(font, sep, lx, ty, SEP_COLOR)

            local rx = lx + sepW
            local rightDraw = truncateToWidthNoDots(font, right, rightMax)
            drawTextShadow(font, rightDraw, rx, ty, STATUS_PART_COLOR)
        end

        ty = ty + lineH
    end
end

function main()
    while not isSampAvailable() do wait(100) end

    loadIni()

    sampAddChatMessage('{335ea3}[LSPD Helper]{FFFFFF} /lspdhelper pour connaitre les commandes.', 0xFFFFFFFF)

    sampRegisterChatCommand('lspdhelper', function()
        sampAddChatMessage('{335ea3}[LSPD Helper]{FFFFFF} /lspdreload {335ea3}recharge la config .ini', 0xFFFFFFFF)
        sampAddChatMessage('{335ea3}[LSPD Helper]{FFFFFF} /lspdrefresh {335ea3}relance /jmembres', 0xFFFFFFFF)
        sampAddChatMessage(string.format('{335ea3}[LSPD Helper]{FFFFFF} %s pour activer/desactiver le panel.', getHotkeyLabel()), 0xFFFFFFFF)
    end)

    sampRegisterChatCommand('lspdreload', function()
        loadIni()
        sampAddChatMessage('{335ea3}[LSPD Helper]{FFFFFF} Config rechargee.', 0xFFFFFFFF)
        sampAddChatMessage(string.format('{335ea3}[LSPD Helper]{FFFFFF} Hotkey: %s', getHotkeyLabel()), 0xFFFFFFFF)
    end)

    sampRegisterChatCommand('lspdrefresh', function()
        triggerRefresh()
        sampAddChatMessage('{335ea3}[LSPD Helper]{FFFFFF} Refresh lance.', 0xFFFFFFFF)
    end)

    sampAddChatMessage(string.format('{335ea3}[LSPD Helper]{FFFFFF} Hotkey: %s', getHotkeyLabel()), 0xFFFFFFFF)

    local lastAuto = os.clock()

    while true do
        wait(0)

        if (KEY_MOD == 0 and wasKeyPressed(KEY_TOGGLE)) or (KEY_MOD ~= 0 and isKeyDown(KEY_MOD) and wasKeyPressed(KEY_TOGGLE)) then
            panelEnabled = not panelEnabled
            layoutDirty = true
        end

        if cfg.auto_refresh == 1 then
            local now = os.clock()
            if (now - lastAuto) >= (cfg.auto_refresh_interval or 30) then
                lastAuto = now
                triggerRefresh()
            end
        end

        if capturing then
            local now = os.clock()
            if (now - captureStart) > cfg.capture_timeout then
                stopCapture()
            elseif #entries > 0 and (now - lastServerLineAt) > cfg.capture_idle_end then
                stopCapture()
            end
        end

        drawPanel()
    end
end

function sampev.onSendCommand(cmd)
    cmd = tostring(cmd or '')
    local low = cmd:lower()

    if internalSend then
        internalSend = false
        return
    end

    return
end

function sampev.onServerMessage(color, text)
    if not suppress then return end

    local decoded = safeDecode(text)
    local msg = trim(stripColorCodes(decoded))
    if msg == '' then return false end

    local low = msg:lower()
    if low:find('membres') and (low:find('connect') or low:find('connecte')) then
        if #entries > 0 then
            entries = {}
            seenKeys = {}
            renderLeft, renderRight, renderColors = {}, {}, {}
            layoutDirty = true
        end
        lastServerLineAt = os.clock()
        return false
    end

    if msg:find('^[%p%s]+$') and #msg > 8 then
        lastServerLineAt = os.clock()
        return false
    end

    if msg:find('_') and msg:find('R%d+') then
        local entry = parseOfficerLine(msg)
        if entry then
            local k = (entry.first or '') .. '_' .. (entry.last or '')
            if not seenKeys[k] then
                seenKeys[k] = true
                if #entries < 300 then
                    entries[#entries + 1] = entry
                end
                layoutDirty = true
            end
            lastServerLineAt = os.clock()
        end
        return false
    end

    return false
end
