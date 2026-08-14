require "XpSystem/ISUI/ISSkillProgressBar"

local totalXPText = getText("IGUI_Total").." "..getText("IGUI_XP_xp")
local gainedXPText = getText("IGUI_GainedXPText")
local startingLevelText = getText("IGUI_StartingLevelText")
local deductedXPText = getText("IGUI_DeductedXP")
local untranscribedXPText = getText("IGUI_UntranscribedXP")

local SRJ = require "Skill Recovery Journal Main"


local SRJ_GREEN = { 0.4, 1.0, 0.4 }
local SRJ_ORANGE = { 1.0, 0.7, 0.4 }
local SRJ_RED = { 1.0, 0.4, 0.4 }
local SRJ_GREY = { 0.4, 0.4, 0.4 }

local function SRJ_rgbTag(color)
    return "<RGB:"..color[1]..","..color[2]..","..color[3]..">"
end

local function SRJ_getProgressAmounts(char, perk)
    local perkID = perk:getId()
    local totalXP = char:getXp():getXP(perk)

    local charDeductedXP = SRJ.modDataHandler.getDeductedXP(char)
    local deductedXP = (charDeductedXP and charDeductedXP[perkID]) or 0

    local traitLevels = SRJ.modDataHandler.getFreeLevelsFromTraitsAndProfession(char)
    local startingLevel = traitLevels[perkID] or 0
    local settledXP = (startingLevel > 0) and perk:getTotalXpForLevel(startingLevel) or 0

    local charReadXP = SRJ.ledger.getReadXPAny(char)
    local readXP = (charReadXP and charReadXP[perkID]) or 0

    local remaining = math.max(totalXP - settledXP - deductedXP, 0)
    local greenXP = math.min(readXP, remaining)
    local deficitXP = remaining - greenXP

    return {
        totalXP = totalXP,
        startingLevel = startingLevel,
        settledXP = settledXP,
        deductedXP = deductedXP,
        greenXP = greenXP,
        deficitXP = deficitXP,
    }
end


local ISSkillProgressBar_updateTooltip = ISSkillProgressBar.updateTooltip
function ISSkillProgressBar:updateTooltip(lvlSelected)
    ISSkillProgressBar_updateTooltip(self, lvlSelected)

    local xpForLvl = ISSkillProgressBar.getXpForLvl(self.perk, lvlSelected)
    if self.level ~= lvlSelected then

        local state = xpSystemText.locked
        local xp = 0

        if (lvlSelected < self.level) then
            state = xpSystemText.unlocked
            xp = xpForLvl
        end

        local xpText = getText("IGUI_XP_tooltipxp", round(xp, 2), xpForLvl)
        self.message = self.message:gsub(" <LINE> "..state, " <LINE> "..state.." ("..xpText..")")
    end

    if lvlSelected <= self.level and instanceof(self.char,"IsoPlayer") then
        local amounts = SRJ_getProgressAmounts(self.char, self.perk)

        self.message = self.message.." <LINE><LINE> "..SRJ_rgbTag(SRJ_GREY).." Skill Recovery Journal"
        self.message = self.message.." <LINE> <RGB:0.8,0.8,0.8> "..startingLevelText..": "..amounts.startingLevel
        self.message = self.message .. " <LINE> <RGB:1,1,1> "..totalXPText..": "..round(amounts.totalXP, 2)

        if amounts.deductedXP > 0 then
            self.message = self.message .. " <LINE> "..SRJ_rgbTag(SRJ_ORANGE).." "..deductedXPText..": "..round(amounts.deductedXP, 2)
        end

        if amounts.greenXP > 0 then
            self.message = self.message.." <LINE> "..SRJ_rgbTag(SRJ_GREEN).." "..gainedXPText..": "..round(amounts.greenXP, 2)
        end

        if amounts.deficitXP > 0 then
            self.message = self.message .. " <LINE> "..SRJ_rgbTag(SRJ_RED).." "..untranscribedXPText..": "..round(amounts.deficitXP, 2)
        end
    end
end


local SRJ_FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local SRJ_SKILL_POINT_HGT = math.floor((SRJ_FONT_HGT_SMALL + 6)/2)
local SRJ_SKILL_POINT_SPACING = getCore():getOptionFontSizeReal()

local SRJ_STRIP_GAP = 1
local SRJ_STRIP_HEIGHT = 2

local SRJ_skillValidCache = {}

local function SRJ_isSkillRecordable(perk)
    local perkID = perk:getId()
    local cached = SRJ_skillValidCache[perkID]
    if cached == nil then
        cached = SRJ.bSkillValid(perk)
        SRJ_skillValidCache[perkID] = cached
    end
    return cached
end


local function SRJ_buildProgressSegments(filledWidth, amounts)
    local totalXP = amounts.totalXP
    if totalXP <= 0 then
        return { { width = filledWidth, color = SRJ_GREY } }
    end

    local segments = {}

    local function addSegment(amount, color)
        if amount > 0 then
            local width = math.max(filledWidth * (amount / totalXP), 1)
            table.insert(segments, { width = width, color = color })
        end
    end

    addSegment(amounts.settledXP, SRJ_GREY)
    addSegment(amounts.deductedXP, SRJ_ORANGE)
    addSegment(amounts.greenXP, SRJ_GREEN)
    addSegment(amounts.deficitXP, SRJ_RED)

    return segments
end


local ISSkillProgressBar_render = ISSkillProgressBar.render
function ISSkillProgressBar:render()
    ISSkillProgressBar_render(self)

    if not SRJ_isSkillRecordable(self.perk) then return end

    local totalFilledWidth = self.level * (SRJ_SKILL_POINT_HGT + SRJ_SKILL_POINT_SPACING)

    if self.level < 10 then
        if not self.xp or not self.xpForLvl or self.xpForLvl <= 0 then return end
        local sliceWidth = SRJ_SKILL_POINT_HGT / 100
        local percentProgress = (self.xp / self.xpForLvl) * 100
        if percentProgress < 0 then percentProgress = 0 end
        if percentProgress > 100 then percentProgress = 100 end
        totalFilledWidth = totalFilledWidth + sliceWidth * percentProgress
    end

    if totalFilledWidth <= 0 then return end

    local y = SRJ_SKILL_POINT_HGT + SRJ_STRIP_GAP
    local amounts = SRJ_getProgressAmounts(self.char, self.perk)
    local segments = SRJ_buildProgressSegments(totalFilledWidth, amounts)

    local segX = 0
    for _, segment in ipairs(segments) do
        self:drawRect(segX, y, segment.width, SRJ_STRIP_HEIGHT, 1, segment.color[1], segment.color[2], segment.color[3])
        segX = segX + segment.width
    end
end
