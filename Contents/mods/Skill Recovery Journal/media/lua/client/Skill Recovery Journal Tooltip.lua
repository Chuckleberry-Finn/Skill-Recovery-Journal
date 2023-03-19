require "ISUI/ISToolTipInv"

local SRJ = require "Skill Recovery Journal Main"


local function flagPlayerWithBoostedXP(id, player)
	if not player then return end

	local pMD = player:getModData()
	if pMD.bBoostedXP then return end

	local pXP = player:getXp()
	local boosted

	for i=1, Perks.getMaxIndex()-1 do
		---@type PerkFactory.Perk
		local perk = Perks.fromIndex(i)
		boosted = boosted or pXP:getPerkBoost(perk)>0
	end

	pMD.bBoostedXP = boosted
	return pMD.bBoostedXP
end
Events.OnCreatePlayer.Add(flagPlayerWithBoostedXP)
local function getBoostedXPFlag(player) return player:getModData().bBoostedXP or flagPlayerWithBoostedXP(player) end


---@param journal InventoryItem | Literature
local function SRJ_generateTooltip(journal, player)

	---fix old draft attempt at something------------------------
	journal:setNumberOfPages(-1)
	journal:setCanBeWrite(false)
	--TODO: Should have been removed like a year ago - 12/29/22
	-------------------------------------------------------------

	local journalModData = journal:getModData()
	local JMD = journalModData["SRJ"]

	local blankJournalTooltip = getText("IGUI_Tooltip_Empty").."\n"

	if not JMD or not JMD["author"] then return blankJournalTooltip end

	local storedJournalXP = JMD["gainedXP"]
	if not storedJournalXP then return blankJournalTooltip end

	local warning --= {}

	if (not JMD.usedRenameOption) then
		---checking if it's '== false' instead of '== true' because I want older saves before this sandbox option to get what they expect to occur
		if (SandboxVars.SkillRecoveryJournal.RecoverProfessionAndTraitsBonuses == false) and getBoostedXPFlag(player) then
			warning = warning or {}
			table.insert(warning, "IGUI_Bonus_XP_Warning")
		end

		if (SandboxVars.SkillRecoveryJournal.TranscribeTVXP == false) then
			warning = warning or {}
			table.insert(warning, "IGUI_TV_XP_Warning")
		end
	end

	local skillsRecord = ""
	local oneTimeUse = (SandboxVars.SkillRecoveryJournal.RecoveryJournalUsed == true)

	for perkID,xp in pairs(storedJournalXP) do
		local perk = Perks[perkID]
		if perk then
			local journalXP = xp

			local jmdUsedXP = journalModData.recoveryJournalXpLog
			if oneTimeUse and jmdUsedXP and jmdUsedXP[perkID] and jmdUsedXP[perkID] then
				journalXP = journalXP-jmdUsedXP[perkID]
			end

			local perkName = perk:getName()
			local xpBasedOnPlayer = math.floor(journalXP*100)/100

			skillsRecord = skillsRecord..perkName.." ("..xpBasedOnPlayer
			if oneTimeUse then skillsRecord = skillsRecord.."/"..xp end
			skillsRecord = skillsRecord.." xp)".."\n"
		end
	end

	local learnedRecipes = JMD["learnedRecipes"] or {}
	if learnedRecipes then
		local recipeNum = 0

		if SandboxVars.SkillRecoveryJournal.RecoverRecipes == true then for k,v in pairs(learnedRecipes) do recipeNum = recipeNum+1 end end

		if recipeNum>0 then
			local properPlural = getText("IGUI_Tooltip_Recipe")
			if recipeNum>1 then properPlural = getText("IGUI_Tooltip_Recipes") end
			skillsRecord = skillsRecord..recipeNum.." "..properPlural..".".."\n"
		end
	end

	local tooltipStart = getText("IGUI_Tooltip_Start").." "..JMD["author"]..getText("IGUI_Tooltip_End")

	return tooltipStart, skillsRecord, warning
	end


local function drawDetailsTooltip(tooltip, tooltipStart, skillsRecord, warning, x, y, fontType)
	local fontHeight = getTextManager():getFontHeight(fontType)
	local fnt = {r=0.9, g=0.9, b=0.9, a=1}
	tooltip:drawText(tooltipStart, x, y, fnt.r, fnt.g, fnt.b, fnt.a, fontType)
	if skillsRecord then
		y=y+(fontHeight*1.5)
		tooltip:drawText(skillsRecord, x+1, y, fnt.r, fnt.g, fnt.b, fnt.a, fontType)
	end
	if warning then
		y=y+getTextManager():MeasureStringY(fontType, skillsRecord)
		tooltip:drawText(warning, x+1, y, fnt.r, 0.3, 0.3, 0.5, fontType)
	end
end

local fontDict = { ["Small"] = UIFont.NewSmall, ["Medium"] = UIFont.NewMedium, ["Large"] = UIFont.NewLarge, }
local fontBounds = { ["Small"] = 28, ["Medium"] = 32, ["Large"] = 42, }


local function ISToolTipInv_render_Override(self,hardSetWidth)
	if not ISContextMenu.instance or not ISContextMenu.instance.visibleCheck then
		local mx = getMouseX() + 24
		local my = getMouseY() + 24
		if not self.followMouse then
			mx = self:getX()
			my = self:getY()
			if self.anchorBottomLeft then
				mx = self.anchorBottomLeft.x
				my = self.anchorBottomLeft.y
			end
		end

		self.tooltip:setX(mx+11)
		self.tooltip:setY(my)
		self.tooltip:setWidth(50)
		self.tooltip:setMeasureOnly(true)
		self.item:DoTooltip(self.tooltip)
		self.tooltip:setMeasureOnly(false)

		local myCore = getCore()
		local maxX = myCore:getScreenWidth()
		local maxY = myCore:getScreenHeight()
		local tw = self.tooltip:getWidth()
		local th = self.tooltip:getHeight()

		self.tooltip:setX(math.max(0, math.min(mx + 11, maxX - tw - 1)))
		if not self.followMouse and self.anchorBottomLeft then
			self.tooltip:setY(math.max(0, math.min(my - th, maxY - th - 1)))
		else
			self.tooltip:setY(math.max(0, math.min(my, maxY - th - 1)))
		end

		self:setX(self.tooltip:getX() - 11)
		self:setY(self.tooltip:getY())
		self:setWidth(hardSetWidth or (tw + 11))
		self:setHeight(th)

		if self.followMouse then
			self:adjustPositionToAvoidOverlap({ x = mx - 24 * 2, y = my - 24 * 2, width = 24 * 2, height = 24 * 2 })
		end

		self:drawRect(0, 0, self.width, self.height, self.backgroundColor.a, self.backgroundColor.r, self.backgroundColor.g, self.backgroundColor.b)
		self:drawRectBorder(0, 0, self.width, self.height, self.borderColor.a, self.borderColor.r, self.borderColor.g, self.borderColor.b)
		self.item:DoTooltip(self.tooltip)
	end
end


local function wrapWarningMessages(warningMessage, fontType, maxWidth)
	local warningWidth = getTextManager():MeasureStringX(fontType, warningMessage)
	if warningWidth > maxWidth then
		local words = warningMessage:gmatch("%S+")
		local rebuilt, currentLine = "", ""
		for word in words do
			local currentLineWidth = getTextManager():MeasureStringX(fontType, currentLine)
			local wordWidth = getTextManager():MeasureStringX(fontType, word)
			local inBetween = ((wordWidth+currentLineWidth > maxWidth) and "\n") or (currentLineWidth>0 and " ") or ""
			currentLine = currentLine..inBetween..word
			rebuilt = rebuilt..inBetween..word
			if inBetween == "\n" then currentLine = word end
		end
		warningMessage = rebuilt
	end
	return warningMessage
end


local wrappedWarningMessage
---@param itemObj InventoryItem
local function wrapWarningMessage(itemObj, warnings, fontType)

	local maxWidth = getTextManager():MeasureStringX(fontType,"Mod: "..itemObj:getModName())

	wrappedWarningMessage = ""
	for _,msg in pairs(warnings) do
		local wrappedMsg = wrapWarningMessages(getText(msg), fontType, maxWidth)
		wrappedWarningMessage = wrappedWarningMessage .. wrappedMsg .. "\n\n"
	end

	wrappedWarningMessage = wrappedWarningMessage .. wrapWarningMessages(getText("IGUI_Rename_Warning"), fontType, maxWidth)
	return wrappedWarningMessage
end


local tooltipRenderOverTime = {item=nil,ticks=0}
local ISToolTipInv_render = ISToolTipInv.render
function ISToolTipInv:render()
	if not ISContextMenu.instance or not ISContextMenu.instance.visibleCheck then
		---@type InventoryItem
		local itemObj = self.item
		local player = self.tooltip:getCharacter()

		if tooltipRenderOverTime.item ~= itemObj then
			tooltipRenderOverTime.item = itemObj
			tooltipRenderOverTime.ticks = 1
		end

		if itemObj and player and itemObj:getType() == "SkillRecoveryJournal" then

			local tooltipStart, skillsRecord, warning = SRJ_generateTooltip(itemObj, player)

			local font = getCore():getOptionTooltipFont()
			local fontType = fontDict[font] or UIFont.Medium
			local fontHeight = getTextManager():getFontHeight(fontType)
			local textWidth = math.max(getTextManager():MeasureStringX(fontType, tooltipStart),getTextManager():MeasureStringX(fontType, skillsRecord))
			local textHeight = fontHeight

			if skillsRecord then
				textHeight=(textHeight*0.5)+getTextManager():MeasureStringY(fontType, skillsRecord)
			end

			if tooltipRenderOverTime.item == itemObj then
				tooltipRenderOverTime.ticks = tooltipRenderOverTime.ticks+1
				if tooltipRenderOverTime.ticks < 15 then warning = false end
			end

			if warning then
				warning = wrappedWarningMessage or wrapWarningMessage(itemObj, warning, fontType)
				textHeight = textHeight+fontHeight+getTextManager():MeasureStringY(fontType, warning)
			end

			textHeight=textHeight+(fontHeight*1.5)

			local journalTooltipWidth = textWidth+fontBounds[font]
			ISToolTipInv_render_Override(self,journalTooltipWidth)

			local tooltipY = self.tooltip:getHeight()-1

			self:setX(self.tooltip:getX() - 11)
			if self.x > 1 and self.y > 1 then
				local yoff = tooltipY + 8
				local bgColor = self.backgroundColor
				local bdrColor = self.borderColor

				self:drawRect(0, tooltipY, journalTooltipWidth, textHeight, math.min(1,bgColor.a+0.4), bgColor.r, bgColor.g, bgColor.b)
				self:drawRectBorder(0, tooltipY, journalTooltipWidth, textHeight, bdrColor.a, bdrColor.r, bdrColor.g, bdrColor.b)
				drawDetailsTooltip(self, tooltipStart, skillsRecord, warning, 15, yoff, fontType)
				yoff = yoff + 12
			end
		else
			ISToolTipInv_render(self)
		end
	end
end