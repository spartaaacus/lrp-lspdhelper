script_name('LRP /jmembres Silent Overlay (COMPACT)')
script_author('_spartacus')

require 'lib.moonloader'

local encoding = require 'encoding'
encoding.default = 'CP1252'
local u8 = encoding.UTF8

local sampev = require 'samp.events'

local INI_PATH = getWorkingDirectory() .. '\\config\\jpanel.ini'

local PANEL_PADDING = 6
local LINE_SPACING_BASE = 13
local MAX_LINES = 18

local CAPTURE_TIMEOUT_SEC = 6.0
local CAPTURE_IDLE_END_SEC = 1.50

local KEY_MOD = VK_CONTROL
local KEY_TOGGLE = VK_J

local TITLE_COLOR = 0xFFFFFFFF
local SUB_COLOR = 0xFFE0E0E0
local TEXT_ON_COLOR = 0xFF7CFF7C
local TEXT_OFF_COLOR = 0xFFFF7C7C
local TEXT_NEUTRAL_COLOR = 0xFFEAEAEA
local SHADOW_COLOR = 0xC0000000

local BG_COLOR = 0xA0000000
local BORDER_COLOR = 0x55FFFFFF

local panelEnabled = true
local capturing = false
local suppress = false
local captureStart = 0
local lastServerLineAt = 0
local internalSend = false

local titleLine = 'LSPD Helper'
local lines = {}
local lastUpdateStr = '—'

local font = nil
local fontBold = nil

local cfg = {
    version = '1.0',
    x = 0.98,
    y = 0.20,
    z = 1.00,
    scale = 1.00,
    font = 'Verdana',
    max_width_ratio = 0.70,
    safeMargin = 8,
    status_max_chars = 80,
    auto_refresh = 0,
    auto_refresh_interval = 30,
    title_text = 'LSPD Helper',
    title_show_counts = 1
}

local function JPLOG(fmt, ...)
    local msg = (select('#', ...) > 0) and string.format(fmt, ...) or tostring(fmt)
    print(string.format('[JPANEL] %s', msg))
end

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
    return renderGetFontDrawTextLength(f, s)
end

local function estimateTextWidthPx(text, fontSize)
    local s = tostring(text or '')
    local n = #s
    if n <= 0 then return 0 end
    local avg = (tonumber(fontSize) or 8) * 0.58
    return math.floor(n * avg)
end

local function safeTextWidth(f, s, fontSize)
    local w = measureTextWidth(f, s)
    if w <= 0 then w = estimateTextWidthPx(s, fontSize) end
    return w
end

local function truncateToWidth(f, s, maxPx)
    s = tostring(s or '')
    if s == '' then return '' end
    if maxPx <= 0 then return '' end
    if measureTextWidth(f, s) <= maxPx then return s end
    local ell = '...'
    local cut = s
    while #cut > 1 and measureTextWidth(f, cut .. ell) > maxPx do
        cut = cut:sub(1, #cut - 1)
    end
    return cut .. ell
end

local function isDecorLine(s)
    s = stripColorCodes(s)
    if s == '' then return false end
    if s:find('^[%p%s]+$') and #s > 8 then return true end
    local cleaned = s:gsub('%w', '')
    if #s >= 20 and (#cleaned / #s) > 0.85 then return true end
    return false
end

local function isHeaderLine(s)
    s = stripColorCodes(s):lower()
    s = s:gsub('[^%w%s_]', '')
    return (s:find('membres') and (s:find('connect') or s:find('connecte')))
end

local function isListLine(s)
    s = tostring(s or '')
    return (s:find('_') and s:find('R%d+'))
end

local function lineStatusColor(entry)
    if not entry then return TEXT_NEUTRAL_COLOR end
    if entry.onDuty == true then return TEXT_ON_COLOR end
    if entry.onDuty == false then return TEXT_OFF_COLOR end
    return TEXT_NEUTRAL_COLOR
end

local function drawTextShadow(f, txt, x, y, color)
    renderFontDrawText(f, txt, x + 1, y + 1, SHADOW_COLOR)
    renderFontDrawText(f, txt, x, y, color)
end

local function ensureIniExists()
    local f = io.open(INI_PATH, 'r')
    if f then f:close() return end
    os.execute('mkdir "' .. getWorkingDirectory() .. '\\config"')
    local w = io.open(INI_PATH, 'w+')
    if not w then return end
    w:write('[jpanel]\n')
    w:write('version=1.0\n\n')
    w:write('x=0.99\n')
    w:write('y=0.80\n')
    w:write('z=1.0\n')
    w:write('scale=1.0\n')
    w:write('font=Arial Narrow\n\n')
    w:write('max_width_ratio=0.80\n')
    w:write('safeMargin=4\n')
    w:write('status_max_chars=120\n\n')
    w:write('auto_refresh=1\n')
    w:write('auto_refresh_interval=30\n\n')
    w:write('title_text=LSPD Helper\n')
    w:write('title_show_counts=1\n')
    w:close()
end

local function loadIni()
    ensureIniExists()

    local t = {
        version = cfg.version,
        x = cfg.x,
        y = cfg.y,
        z = cfg.z,
        scale = cfg.scale,
        font = cfg.font,
        max_width_ratio = cfg.max_width_ratio,
        safemargin = cfg.safeMargin,
        status_max_chars = cfg.status_max_chars,
        auto_refresh = cfg.auto_refresh,
        auto_refresh_interval = cfg.auto_refresh_interval,
        title_text = cfg.title_text,
        title_show_counts = cfg.title_show_counts
    }

    local file = io.open(INI_PATH, 'r')
    if not file then
        JPLOG('Impossible de lire %s', INI_PATH)
        return
    end

    local section = nil
    for line in file:lines() do
        local s = trim(line)
        if s ~= '' and not s:match('^;') and not s:match('^#') then
            local sec = s:match('^%[(.-)%]$')
            if sec then
                section = sec:lower()
            elseif section == 'jpanel' then
                local k, v = s:match('^(.-)=(.*)$')
                if k and v then
                    k = trim(k):lower()
                    v = trim(v)
                    if k == 'version' then t.version = v ~= '' and v or t.version end
                    if k == 'x' then t.x = tonumber(v) or t.x end
                    if k == 'y' then t.y = tonumber(v) or t.y end
                    if k == 'z' then t.z = tonumber(v) or t.z end
                    if k == 'scale' then t.scale = tonumber(v) or t.scale end
                    if k == 'font' and v ~= '' then t.font = v end
                    if k == 'max_width_ratio' then t.max_width_ratio = tonumber(v) or t.max_width_ratio end
                    if k == 'safemargin' then t.safemargin = tonumber(v) or t.safemargin end
                    if k == 'status_max_chars' then t.status_max_chars = tonumber(v) or t.status_max_chars end
                    if k == 'auto_refresh' then t.auto_refresh = tonumber(v) or t.auto_refresh end
                    if k == 'auto_refresh_interval' then t.auto_refresh_interval = tonumber(v) or t.auto_refresh_interval end
                    if k == 'title_text' and v ~= '' then t.title_text = v end
                    if k == 'title_show_counts' then t.title_show_counts = tonumber(v) or t.title_show_counts end
                end
            end
        end
    end
    file:close()

    cfg.version = (t.version ~= '' and t.version) or cfg.version
    cfg.x = clamp(t.x, 0.0, 1.0)
    cfg.y = clamp(t.y, 0.0, 1.0)
    cfg.z = clamp(t.z, 0.0, 1.0)
    cfg.scale = clamp(t.scale, 0.5, 3.0)
    cfg.font = t.font
    cfg.max_width_ratio = clamp(t.max_width_ratio, 0.25, 0.95)
    cfg.safeMargin = clampInt(t.safemargin, 0, 80)
    cfg.status_max_chars = clampInt(t.status_max_chars, 0, 300)
    cfg.auto_refresh = clampInt(t.auto_refresh, 0, 1)
    cfg.auto_refresh_interval = clampInt(t.auto_refresh_interval, 5, 3600)
    cfg.title_text = t.title_text
    cfg.title_show_counts = clampInt(t.title_show_counts, 0, 1)

    if font then renderReleaseFont(font) end
    if fontBold then renderReleaseFont(fontBold) end

    local size = math.floor(8 * cfg.scale + 0.5)
    if size < 7 then size = 7 end

    font = renderCreateFont(cfg.font, size, 5)
    fontBold = renderCreateFont(cfg.font, size, 7)

    JPLOG('INI loaded v%s: x=%.2f y=%.2f z=%.2f scale=%.2f font=%s max_width_ratio=%.2f safeMargin=%d status_max_chars=%d auto_refresh=%d interval=%d title_show_counts=%d',
        cfg.version, cfg.x, cfg.y, cfg.z, cfg.scale, cfg.font, cfg.max_width_ratio, cfg.safeMargin, cfg.status_max_chars,
        cfg.auto_refresh, cfg.auto_refresh_interval, cfg.title_show_counts)
end

local function shortenGrade(grade)
    local g = trim(grade)
    g = g:gsub('Chef de la police', 'Chef')
    g = g:gsub('Recrue', 'REC.')
    g = g:gsub('Officier', 'OFF.')
    g = g:gsub('Sergent', 'SGT.')
    g = g:gsub('Lieutenant', 'LTN.')
    g = g:gsub('Capitaine', 'CPT.')
    g = g:gsub('Commandant', 'CMDT.')
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
    if s == '' or s == 'N/A' then return 'N/A' end
    local firstToken = s:match('^(%S+)') or 'N/A'
    if firstToken:match('^[A-Za-z]+%d+$') then
        return firstToken:upper()
    end
    return 'N/A'
end

local function parseOfficerLine(msg)
    local raw = trim(stripColorCodes(msg))
    raw = raw:gsub('%s+', ' ')

    local first, last, rankCode, rest = raw:match('^([%w]+)_([%w]+)%s+(R%d+)%s+(.+)$')
    if not first then return nil end

    local grade = rest:match('^(.-)%s*%(%d%d%d%-%d%d%d%d%)')
    if not grade then
        grade = rest:match('^(.-)%s*%((ON)%)') or rest:match('^(.-)%s*%((OFF)%)')
    end
    grade = trim(grade or 'Grade inconnu')

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

    if cfg.status_max_chars and cfg.status_max_chars > 0 and #statusText > cfg.status_max_chars then
        statusText = statusText:sub(1, cfg.status_max_chars)
    end

    local initial = first:sub(1, 1):upper()
    local lastname = last:upper()

    local gradeShort = shortenGrade(grade)
    gradeShort = removeRankCodePrefix(rankCode, gradeShort)

    local unitKey = extractUnitKey(statusText)

    local display = string.format('%s.%s (%s) | %s', initial, lastname, gradeShort, statusText)

    return {
        first = first,
        last = last,
        onDuty = onDuty,
        grade = grade,
        gradeShort = gradeShort,
        statusText = statusText,
        unitKey = unitKey,
        display = display
    }
end

local function buildGroupedSorted(list)
    local buckets = {}
    for i = 1, #list do
        local e = list[i]
        local key = (e and e.unitKey) or 'N/A'
        if not buckets[key] then buckets[key] = {} end
        buckets[key][#buckets[key] + 1] = e
    end

    local keys = {}
    for k in pairs(buckets) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
        if a == 'N/A' and b ~= 'N/A' then return false end
        if b == 'N/A' and a ~= 'N/A' then return true end
        return a < b
    end)

    local function alphaSort(a, b)
        local af = (a.first or ''):lower()
        local bf = (b.first or ''):lower()
        if af == bf then
            return (a.last or ''):lower() < (b.last or ''):lower()
        end
        return af < bf
    end

    local out = {}
    for i = 1, #keys do
        local arr = buckets[keys[i]]
        table.sort(arr, alphaSort)
        for j = 1, #arr do out[#out + 1] = arr[j] end
    end
    return out
end

local function sortAndGroupEntries()
    local onList, offList = {}, {}
    for i = 1, #lines do
        local e = lines[i]
        if e and e.onDuty == true then
            onList[#onList + 1] = e
        else
            offList[#offList + 1] = e
        end
    end

    local onSorted = buildGroupedSorted(onList)
    local offSorted = buildGroupedSorted(offList)

    local merged = {}
    for i = 1, #onSorted do merged[#merged + 1] = onSorted[i] end
    if #onSorted > 0 and #offSorted > 0 then
        merged[#merged + 1] = { isSeparator = true }
    end
    for i = 1, #offSorted do merged[#merged + 1] = offSorted[i] end

    lines = merged
    return #onList, #offList
end

local function startCapture()
    capturing = true
    suppress = true
    captureStart = os.clock()
    lastServerLineAt = os.clock()

    titleLine = cfg.title_text or 'LSPD Helper'
    lines = {}
    lastUpdateStr = nowTime()

    JPLOG('CAPTURE START (/jmembres)')
end

local function stopCapture(reason)
    capturing = false
    suppress = false
    local onCount, offCount = sortAndGroupEntries()

    if cfg.title_show_counts == 1 then
        titleLine = string.format('%s (ON:%d | OFF:%d)', cfg.title_text or 'LSPD Helper', onCount, offCount)
    else
        titleLine = cfg.title_text or 'LSPD Helper'
    end

    JPLOG('CAPTURE STOP (%s). lines=%d', tostring(reason), #lines)
end

local function triggerRefresh()
    if capturing then
        JPLOG('Refresh ignore: capture deja en cours')
        return
    end

    startCapture()
    lua_thread.create(function()
        wait(0)
        internalSend = true
        sampSendChat('/jmembres')
        JPLOG('Sent /jmembres (internal)')
    end)
end

local function drawBox(x, y, w, h, color)
    renderDrawBox(x, y, w, h, color)
end

local function drawPanel()
    if not panelEnabled then return end
    if not font or not fontBold then return end

    local sx, sy = getScreenResolution()
    local scale = cfg.scale
    local fontSize = math.floor(8 * cfg.scale + 0.5)
    if fontSize < 7 then fontSize = 7 end

    local safeMargin = cfg.safeMargin or 8
    local pad = math.floor(PANEL_PADDING * scale + 0.5)
    local lineH = math.floor(LINE_SPACING_BASE * scale + 0.5)
    if lineH < 11 then lineH = 11 end

    local header = titleLine or (cfg.title_text or 'LSPD Helper')
    local stamp = 'Maj: ' .. (lastUpdateStr or '—')
    local contentCount = math.min(#lines, MAX_LINES)

    local maxW = 0
    maxW = math.max(maxW, safeTextWidth(fontBold, header, fontSize))
    maxW = math.max(maxW, safeTextWidth(font, stamp, fontSize))

    if contentCount == 0 then
        maxW = math.max(maxW, safeTextWidth(font, 'Tapez /jmembres', fontSize))
    else
        for i = 1, contentCount do
            local e = lines[i]
            if e and e.isSeparator then
                maxW = math.max(maxW, safeTextWidth(font, '----------------', fontSize))
            else
                maxW = math.max(maxW, safeTextWidth(font, (e and e.display) or '', fontSize))
            end
        end
    end

    local boxW = math.floor(maxW + pad * 2)
    local minW = 220
    if boxW < minW then boxW = minW end

    local maxWcap = math.floor(sx * (cfg.max_width_ratio or 0.70)) - (safeMargin * 2)
    if maxWcap > (sx - safeMargin * 2) then maxWcap = (sx - safeMargin * 2) end
    if maxWcap < 160 then maxWcap = (sx - safeMargin * 2) end
    if boxW > maxWcap then boxW = maxWcap end

    local boxH = math.floor(pad * 2 + lineH * (2 + (contentCount > 0 and contentCount or 1)))

    local anchorX = math.floor(sx * cfg.x + 0.5)
    local anchorY = math.floor(sy * cfg.y + 0.5)

    local x = math.floor(anchorX - (boxW * cfg.z) + 0.5)
    local y = anchorY

    if x < safeMargin then x = safeMargin end
    if y < safeMargin then y = safeMargin end
    if x + boxW > sx - safeMargin then x = sx - boxW - safeMargin end
    if y + boxH > sy - safeMargin then y = sy - boxH - safeMargin end

    drawBox(x, y, boxW, boxH, BG_COLOR)
    drawBox(x, y, boxW, 1, BORDER_COLOR)
    drawBox(x, y + boxH - 1, boxW, 1, BORDER_COLOR)
    drawBox(x, y, 1, boxH, BORDER_COLOR)
    drawBox(x + boxW - 1, y, 1, boxH, BORDER_COLOR)

    local tx = x + pad
    local ty = y + pad
    local usableW = boxW - (pad * 2)

    drawTextShadow(fontBold, truncateToWidth(fontBold, header, usableW), tx, ty, TITLE_COLOR)
    ty = ty + lineH

    drawTextShadow(font, truncateToWidth(font, stamp, usableW), tx, ty, SUB_COLOR)
    ty = ty + lineH

    if contentCount == 0 then
        drawTextShadow(font, 'Tapez /jmembres', tx, ty, SUB_COLOR)
        return
    end

    for i = 1, contentCount do
        local entry = lines[i]
        if entry and entry.isSeparator then
            drawTextShadow(font, truncateToWidth(font, '----------------', usableW), tx, ty, SUB_COLOR)
        else
            local lineText = truncateToWidth(font, (entry and entry.display) or '', usableW)
            drawTextShadow(font, lineText, tx, ty, lineStatusColor(entry))
        end
        ty = ty + lineH
    end
end

function main()
    while not isSampAvailable() do wait(100) end

    loadIni()

    sampRegisterChatCommand('jpanelreload', function()
        loadIni()
        sampAddChatMessage('[JPANEL] INI recharge.', 0xFFFFFFFF)
    end)

    sampRegisterChatCommand('jpanelrefresh', function()
        triggerRefresh()
        sampAddChatMessage('[JPANEL] Refresh /jmembres lance.', 0xFFFFFFFF)
    end)

    if cfg.auto_refresh == 1 then
        lua_thread.create(function()
            while true do
                wait((cfg.auto_refresh_interval or 30) * 1000)
                if panelEnabled and not capturing then
                    triggerRefresh()
                end
            end
        end)
    end

    JPLOG('Ready v%s. CTRL+J toggle | /jpanelreload | /jpanelrefresh', cfg.version)

    while true do
        wait(0)

        if isKeyDown(KEY_MOD) and wasKeyPressed(KEY_TOGGLE) then
            panelEnabled = not panelEnabled
            JPLOG('panelEnabled=%s', tostring(panelEnabled))
        end

        if capturing then
            local now = os.clock()
            if (now - captureStart) > CAPTURE_TIMEOUT_SEC then
                stopCapture('timeout')
            elseif #lines > 0 and (now - lastServerLineAt) > CAPTURE_IDLE_END_SEC then
                stopCapture('idle_end')
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

    local isJm =
        (low == 'jmembres') or (low == '/jmembres') or
        low:find('^jmembres%s') or low:find('^/jmembres%s')

    if isJm then
        triggerRefresh()
        return false
    end
end

function sampev.onServerMessage(color, text)
    if not suppress then return end

    local decoded = safeDecode(text)
    local msg = trim(stripColorCodes(decoded))

    if isHeaderLine(msg) then
        lastServerLineAt = os.clock()
        return false
    end

    if isDecorLine(msg) then
        lastServerLineAt = os.clock()
        return false
    end

    if isListLine(msg) then
        local entry = parseOfficerLine(msg)
        if entry then
            if #lines < 300 then
                lines[#lines + 1] = entry
            end
            lastServerLineAt = os.clock()
        end
        return false
    end

    return false
end
