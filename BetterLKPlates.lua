local addon = CreateFrame("Frame")
local overlay = CreateFrame("Frame", nil, WorldFrame)
overlay:SetWidth(1)
overlay:SetHeight(1)
overlay:Hide()

local config, attached, castStart, castEnd, channel
local preview, previewPoints, samplePlate, sampleBuff, sampleDebuff, sampleHealth
local dirty, elapsed = true, 0
local plates, points, auras, timers, expires = {}, {}, {}, {}, {}
local positions = {
    {"combo", "Combo points", 0, 17},
    {"buff", "Buffs (right edge)", 28, 0},
    {"debuff", "Debuffs", 0, 30},
    {"cast", "Cast bar", 0, -28},
}
local count, total = -1, 40

local combo = CreateFrame("Frame", nil, overlay)
combo:SetHeight(5)
combo:SetWidth(48)
combo:SetPoint("BOTTOM", overlay, "TOP", 0, 3)
local function createPoint(frame)
    local border = frame:CreateTexture(nil, "ARTWORK")
    border:SetTexture(0.08, 0.08, 0.08, 1)
    local fill = frame:CreateTexture(nil, "OVERLAY")
    fill:SetTexture(0.9, 0.12, 0.12, 1)
    fill:SetPoint("TOPLEFT", border, "TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMRIGHT", border, "BOTTOMRIGHT", -1, 1)
    return {border = border, fill = fill}
end

for i = 1, 5 do points[i] = createPoint(combo) end

local cast = CreateFrame("StatusBar", nil, overlay)
cast:SetWidth(110)
cast:SetHeight(10)
cast:SetPoint("TOP", overlay, "BOTTOM", 0, -10)
cast:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
cast:SetStatusBarColor(1, 0.66, 0.15)
local castText = cast:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
castText:SetPoint("CENTER")
cast:Hide()

for i = 1, total do
    local icon = overlay:CreateTexture(nil, "ARTWORK")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    auras[i] = icon
    local timer = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    timer:SetPoint("CENTER", icon, "CENTER")
    timers[i] = timer
end

local function detach()
    attached = nil
    castEnd = nil
    overlay:Hide()
end

local function sizePoints(frame, textures)
    local scale = config.comboScale / 100
    frame:SetWidth(48 * scale)
    frame:SetHeight(5 * scale)
    for i, block in ipairs(textures) do
        local point = block.border
        point:SetWidth(8 * scale)
        point:SetHeight(5 * scale)
        point:ClearAllPoints()
        point:SetPoint("LEFT", frame, "LEFT", (i - 1) * 10 * scale, 0)
    end
end

local function stylePoint(point, active)
    local alpha = active and 1 or config.inactiveOpacity / 100
    if active then
        point.fill:SetTexture(0.9, 0.12, 0.12, 1)
    else
        point.fill:SetTexture(0.5, 0.5, 0.5, 1)
    end
    point.fill:SetAlpha(alpha)
    point.border:SetAlpha(alpha)
end

local function updateCombo()
    sizePoints(combo, points)
    combo:ClearAllPoints()
    combo:SetPoint("BOTTOM", overlay, "CENTER", config.comboX, config.comboY)
    local n = GetComboPoints("player", "target")
    if n == 0 and UnitHasVehicleUI("player") then
        n = GetComboPoints("vehicle", "target")
    end
    if n > 0 then combo:Show() else combo:Hide() end
    for i, point in ipairs(points) do
        stylePoint(point, i <= n)
    end
end

local function placeAura(icon, anchor, key, index, count)
    if key == "buff" then
        icon:ClearAllPoints()
        icon:SetWidth(config.buffSize)
        icon:SetHeight(config.buffSize)
        icon:SetPoint("LEFT", anchor, "RIGHT",
            config.buffX + index * (config.buffSize + config.spacing), config.buffY)
        return
    end
    local step = config.size + config.spacing
    local row = math.floor(index / 10)
    local columns = math.min(10, count - row * 10)
    icon:ClearAllPoints()
    icon:SetWidth(config.size)
    icon:SetHeight(config.size)
    icon:SetPoint("BOTTOM", anchor, "CENTER",
        config[key .. "X"] + (index % 10 - (columns - 1) / 2) * step,
        config[key .. "Y"] + row * step)
end

local function updateTimers()
    local now = GetTime()
    for i, timer in ipairs(timers) do
        local remaining = expires[i] and expires[i] - now
        if remaining and remaining > 0 then
            timer:SetText(remaining >= 60 and math.ceil(remaining / 60) .. "m" or math.ceil(remaining))
        else
            timer:SetText("")
        end
    end
end

local function updateAuras()
    local slot = 1
    for row, filter in ipairs({"HELPFUL", config.mine and "HARMFUL|PLAYER" or "HARMFUL"}) do
        local first = slot
        for i = 1, 40 do
            local name, _, texture, _, _, _, expiration = UnitAura("target", i, filter)
            if not name or slot - first >= 20 then break end
            if texture then
                auras[slot]:SetTexture(texture)
                expires[slot] = expiration and expiration > 0 and expiration or nil
                auras[slot]:Show()
                slot = slot + 1
            end
        end
        for i = first, slot - 1 do
            placeAura(auras[i], row == 1 and plates[attached].health or overlay, row == 1 and "buff" or "debuff", i - first, slot - first)
        end
    end
    for i = slot, total do
        auras[i]:Hide()
        expires[i] = nil
    end
    updateTimers()
end

local function updateCast()
    castEnd = nil
    cast:Hide()
    if not config.cast then return end
    cast:ClearAllPoints()
    cast:SetPoint("TOP", overlay, "CENTER", config.castX, config.castY)
    local name, _, _, _, startMS, endMS = UnitCastingInfo("target")
    channel = not name
    if channel then name, _, _, _, startMS, endMS = UnitChannelInfo("target") end
    if not name or not startMS or not endMS or endMS <= startMS then return end
    castStart, castEnd = startMS / 1000, endMS / 1000
    cast:SetMinMaxValues(0, castEnd - castStart)
    castText:SetText(name)
    cast:SetValue(channel and castEnd - GetTime() or GetTime() - castStart)
    cast:Show()
end

local function plateHidden(frame)
    if attached == frame then detach() end
    dirty = true
end

local function discover(...)
    for i = 1, select("#", ...) do
        local frame = select(i, ...)
        if not plates[frame] and not frame:GetName() then
            local first, second = frame:GetRegions()
            local signature = first and first:GetObjectType() == "Texture" and first:GetTexture()
            local name
            if signature == "Interface\\TargetingFrame\\UI-TargetingFrame-Flash" then
                name = select(7, frame:GetRegions())
            elseif signature == "Interface\\Tooltips\\Nameplate-Border" then
                name = select(5, frame:GetRegions())
            elseif second and second:GetObjectType() == "Texture"
                and second:GetTexture() == "Interface\\Tooltips\\Nameplate-Border" then
                name = select(7, frame:GetRegions())
            end
            local health = frame:GetChildren()
            if name and name:GetObjectType() == "FontString"
                and health and health:GetObjectType() == "StatusBar" then
                plates[frame] = {name = name, health = health}
                frame:HookScript("OnHide", plateHidden)
                frame:HookScript("OnShow", function() dirty = true end)
            end
        end
    end
end

local function match()
    local target = UnitName("target")
    local children = WorldFrame:GetNumChildren()
    if children ~= count then
        count = children
        discover(WorldFrame:GetChildren())
    end
    local candidate, opaque, names = nil, 0, 0
    for frame, plate in pairs(plates) do
        if frame:IsVisible() then
            local same = target and plate.name:GetText() == target
            if same then names = names + 1 end
            if frame:GetAlpha() >= 0.99 then
                opaque = opaque + 1
                if same and plate.health:IsVisible() then candidate = frame end
            end
        end
    end
    -- Wrath highlights the selected plate by dimming other visible plates.
    -- A same-name plate that is still opaque makes the match ambiguous.
    if opaque == 1 and candidate then return candidate end
    return nil, names, opaque
end

local function refresh()
    local frame = match()
    if not frame then detach(); return end
    if attached == frame then return end
    attached = frame
    local health = plates[frame].health
    overlay:ClearAllPoints()
    overlay:SetPoint("CENTER", health, "TOP")
    overlay:SetFrameLevel(health:GetFrameLevel() + 2)
    updateCombo()
    updateAuras()
    updateCast()
    overlay:Show()
end

local function onUpdate(_, dt)
    elapsed = elapsed + dt
    if dirty or elapsed >= 0.12 then
        elapsed, dirty = 0, false
        refresh()
        if attached then updateTimers() end
    end
    if attached and (not UnitExists("target") or not attached:IsVisible()
        or attached:GetAlpha() < 0.99
        or plates[attached].name:GetText() ~= UnitName("target")) then
        detach()
    end
    if castEnd then
        local now = GetTime()
        if now >= castEnd then castEnd = nil; cast:Hide()
        else cast:SetValue(channel and castEnd - now or now - castStart) end
    end
end

local function number(value, default, low, high)
    value = tonumber(value)
    if not value or value ~= value then return default end
    return math.min(high, math.max(low, math.floor(value)))
end

local function targetChanged()
    detach()
    dirty = true
    addon:SetScript("OnUpdate", UnitExists("target") and onUpdate or nil)
end

local panel

local function refreshVisuals()
    sizePoints(preview, previewPoints)
    for i, point in ipairs(previewPoints) do
        stylePoint(point, i <= 3)
    end
    preview:ClearAllPoints()
    preview:SetPoint("BOTTOM", samplePlate, "CENTER", config.comboX, config.comboY)
    placeAura(sampleBuff, sampleHealth, "buff", 0, 1)
    placeAura(sampleDebuff, samplePlate, "debuff", 0, 1)
    if attached then
        updateCombo()
        updateAuras()
        updateCast()
    end
end

local function setupOptions()
    panel = CreateFrame("Frame")
    panel.name = "BetterLKPlates"
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(panel.name)
    local help = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    help:SetPoint("TOPLEFT", 16, -42)
    help:SetText("Offsets and aura size adjustments are relative to the baseline. Positive Y moves up.")

    local controls, displayValue = {}, {}
    local function field(key, label, x, y, low, high, baseline, factor)
        baseline, factor = baseline or 0, factor or 1
        displayValue[key] = function() return tostring((config[key] - baseline) / factor) end
        local caption = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        caption:SetPoint("TOPLEFT", x, y)
        caption:SetText(label)
        local box = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
        box:SetAutoFocus(false)
        box:SetWidth(58)
        box:SetHeight(22)
        box:SetMaxLetters(5)
        box:SetPoint("TOPLEFT", caption, "BOTTOMLEFT", 4, -3)
        local function save(self)
            local value = tonumber(self:GetText())
            if value then config[key] = number(value * factor + baseline, config[key], low, high) end
            self:SetText(displayValue[key]())
            refreshVisuals()
        end
        box:SetScript("OnEditFocusLost", save)
        box:SetScript("OnEnterPressed", box.ClearFocus)
        box:SetScript("OnEscapePressed", function(self)
            self:SetText(displayValue[key]())
            self:ClearFocus()
        end)
        controls[key] = box
    end

    for i, position in ipairs(positions) do
        local key, label = position[1], position[2]
        local y = -73 - (i - 1) * 48
        field(key .. "X", label .. " X", 16, y, -200, 200, position[3])
        field(key .. "Y", label .. " Y", 180, y, -200, 200, position[4])
    end
    field("size", "Debuff size adjustment", 16, -265, 8, 32, 28)
    field("spacing", "Aura icon spacing", 180, -265, 0, 12)

    field("buffSize", "Buff size adjustment", 16, -311, 8, 32, 20)


    local checks = {}
    local function checkbox(key, label, y)
        local check = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
        check:SetPoint("TOPLEFT", 12, y)
        local caption = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        caption:SetPoint("LEFT", check, "RIGHT", 2, 0)
        caption:SetText(label)
        check:SetScript("OnClick", function(self)
            config[key] = not not self:GetChecked()
            refreshVisuals()
        end)
        checks[key] = check
    end
    checkbox("mine", "Show only my debuffs", -350)
    checkbox("cast", "Show addon cast bar", -380)

    field("comboScale", "Combo point scale (%)", 16, -414, 50, 300, 0, 2)
    field("inactiveOpacity", "Inactive point opacity (%)", 180, -414, 0, 100)
    local sampleLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    sampleLabel:SetPoint("TOP", panel, "TOP", 155, -95)
    sampleLabel:SetText("Nameplate layout preview")
    preview = CreateFrame("Frame", nil, panel)
    samplePlate = CreateFrame("Frame", nil, panel)
    samplePlate:SetWidth(1)
    samplePlate:SetHeight(1)
    samplePlate:SetPoint("TOP", sampleLabel, "BOTTOM", 0, -150)
    local bar = samplePlate:CreateTexture(nil, "ARTWORK")
    sampleHealth = bar
    bar:SetTexture(0.2, 0.65, 0.24)
    bar:SetWidth(110)
    bar:SetHeight(9)
    bar:SetPoint("TOP", samplePlate, "CENTER")
    local name = samplePlate:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    name:SetText("Sample target")
    name:SetPoint("BOTTOM", samplePlate, "CENTER", 0, 2)
    sampleBuff = samplePlate:CreateTexture(nil, "ARTWORK")
    sampleBuff:SetTexture("Interface\\Icons\\Spell_Nature_Rejuvenation")
    sampleDebuff = samplePlate:CreateTexture(nil, "ARTWORK")
    sampleDebuff:SetTexture("Interface\\Icons\\Spell_Shadow_ShadowWordPain")
    local timer = samplePlate:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    timer:SetPoint("CENTER", sampleDebuff, "CENTER")
    timer:SetText("12")
    local align = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    align:SetWidth(142)
    align:SetHeight(23)
    align:SetPoint("TOP", samplePlate, "CENTER", 0, -50)
    align:SetText("Reset aura positions")
    align:SetScript("OnClick", function()
        for _, position in ipairs(positions) do
            local key = position[1]
            if key == "buff" or key == "debuff" then
                config[key .. "X"], config[key .. "Y"] = position[3], position[4]
                controls[key .. "X"]:SetText(displayValue[key .. "X"]())
                controls[key .. "Y"]:SetText(displayValue[key .. "Y"]())
            end
        end
        refreshVisuals()
    end)
    previewPoints = {}
    for i = 1, 5 do previewPoints[i] = createPoint(preview) end
    refreshVisuals()

    panel:SetScript("OnShow", function()
        for key, box in pairs(controls) do box:SetText(displayValue[key]()) end
        for key, check in pairs(checks) do check:SetChecked(config[key]) end
    end)
    InterfaceOptions_AddCategory(panel)
end

addon:RegisterEvent("PLAYER_LOGIN")
addon:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_LOGIN" then
        config = type(BetterLKPlatesDB) == "table" and BetterLKPlatesDB or {}
        BetterLKPlatesDB = config
        config.size = number(config.size, 28, 8, 32)
        config.buffSize = number(config.buffSize, 20, 8, 32)
        if not config.buffRightAnchor then
            config.buffX, config.buffY = 28, 0
            config.buffRightAnchor = true
        end
        config.spacing = number(config.spacing, 3, 0, 12)
        config.inactiveOpacity = number(config.inactiveOpacity, 50, 0, 100)
        config.comboScale = number(config.comboScale, 200, 50, 300)
        config.cast = config.cast == true
        config.mine = config.mine ~= false
        for _, name in ipairs({
            "PLAYER_TARGET_CHANGED", "PLAYER_ENTERING_WORLD", "UNIT_AURA", "UNIT_COMBO_POINTS",
            "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
            "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_START",
            "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_CHANNEL_STOP",
        }) do addon:RegisterEvent(name) end
        for _, position in ipairs(positions) do
            local key = position[1]
            config[key .. "X"] = number(config[key .. "X"], position[3], -200, 200)
            config[key .. "Y"] = number(config[key .. "Y"], position[4], -200, 200)
        end
        setupOptions()
        targetChanged()
    elseif event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
        targetChanged()
    elseif attached then
        if event == "UNIT_COMBO_POINTS" and (unit == "player" or unit == "vehicle") then
            updateCombo()
        elseif unit == "target" then
            if event == "UNIT_AURA" then updateAuras() else updateCast() end
        end
    end
end)

SLASH_BETTERLKTARGETPLATES1 = "/blkp"
SlashCmdList.BETTERLKTARGETPLATES = function(input)
    local command, value = input:lower():match("^%s*(%S*)%s*(.-)%s*$")
    if command == "" or command == "options" then
        InterfaceOptionsFrame_OpenToCategory(panel)
        InterfaceOptionsFrame_OpenToCategory(panel)
        return
    elseif command == "status" then
        local frame, names, opaque = match()
        print("BetterLKPlates: " .. (frame and "matched target plate" or
            ("no match; same-name plates=" .. tostring(names or 0) .. ", opaque plates=" .. tostring(opaque or 0))))
        return
    elseif command == "size" and tonumber(value) then
        config.size = number(value, config.size, 8, 32)
    elseif command == "spacing" and tonumber(value) then
        config.spacing = number(value, config.spacing, 0, 12)
    elseif (command == "mine" or command == "cast") and (value == "on" or value == "off") then
        config[command] = value == "on"
    else
        print("BetterLKPlates: /blkp size 8–32 | spacing 0–12 | mine on/off | cast on/off | status")
        return
    end
    if attached then updateAuras(); updateCast() end
    print("BetterLKPlates: " .. command .. " = " .. tostring(config[command]))
end
