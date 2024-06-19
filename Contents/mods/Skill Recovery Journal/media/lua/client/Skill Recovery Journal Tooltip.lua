require "ISUI/ISToolTipInv"

local SRJ = require "Skill Recovery Journal Main"

local function SRJ_generateTooltip(journalModData, player)

	local JMD = journalModData["SRJ"]

	local blankJournalTooltip = getText("IGUI_Tooltip_Empty").."\n"

	if not JMD or not JMD["author"] then return blankJournalTooltip end

	local storedJournalXP = JMD["gainedXP"]
	if not storedJournalXP then return blankJournalTooltip end

	local warning --= {}

	local oneTimeUse = (SandboxVars.SkillRecoveryJournal.RecoveryJournalUsed == true)

	---background fix for old XP
	local oldXp = journalModData.oldXP

	if oldXp then
		warning = warning or {}
		table.insert(warning, "IGUI_OLDXP_WARNING")
	end
	
	if (not JMD.renamedJournal) then

		warning = warning or {}
		table.insert(warning, "Tooltip_SkillJournal")

		if (SandboxVars.SkillRecoveryJournal.TranscribeTVXP == false) then
			warning = warning or {}
			table.insert(warning, "IGUI_TV_XP_Warning")
		end

		if oneTimeUse then
			warning = warning or {}
			table.insert(warning, "IGUI_OneTimeUse_Warning")
		end
	end

	local skillsRecord = ""

	local multipliers = SRJ.xpHandler.getOrStoreXPMultipliers(player)


	for perkID,xp in pairs(storedJournalXP) do
		local perk = Perks[perkID]
		if perk then

			local show, percent = SRJ.bSkillValid(perk)
			if show then
				local journalXP = xp
				local jmdUsedXP = journalModData.recoveryJournalXpLog
				if oneTimeUse and jmdUsedXP and jmdUsedXP[perkID] and jmdUsedXP[perkID] then
					journalXP = math.max(0, journalXP-jmdUsedXP[perkID])
				end

				local oldPerkXP = oldXp and oldXp[perkID] or 0

				local perkName = perk:getName()
				local multi = multipliers[perkID] or 1
				local availableXP = round(((journalXP-oldPerkXP)*multi)+oldPerkXP, 2)

				skillsRecord = skillsRecord..perkName.." ("..availableXP
				if oneTimeUse then
					local totalXP = round(((xp-oldPerkXP)*multi)+oldPerkXP, 2)
					skillsRecord = skillsRecord.."/"..totalXP
				end
				skillsRecord = skillsRecord.." xp)\n"
			end
		end
	end

	if SandboxVars.SkillRecoveryJournal.RecoverRecipes == true then
		local learnedRecipes = JMD["learnedRecipes"] or {}
		if learnedRecipes then
			local recipeNum = 0

			if SandboxVars.SkillRecoveryJournal.RecoverRecipes == true then for k,v in pairs(learnedRecipes) do recipeNum = recipeNum+1 end end

			if recipeNum>0 then
				local properPlural = getText("IGUI_Tooltip_Recipe")
				if recipeNum>1 then properPlural = getText("IGUI_Tooltip_Recipes") end
				skillsRecord = skillsRecord.."\n"..recipeNum.." "..properPlural..".".."\n"
			end
		end
	end

	SRJ.correctSandBoxOptions("KillsTrack")
	if (SandboxVars.SkillRecoveryJournal.KillsTrack or 0) > 0 then
		local jmdZKills = JMD and JMD.kills and JMD.kills.Zombie
		local jmdSKills = JMD and JMD.kills and JMD.kills.Survivor

		if jmdZKills or jmdSKills then
			skillsRecord = skillsRecord.."\n"
			if jmdZKills and jmdZKills>0 then skillsRecord = skillsRecord .. getText("IGUI_char_Zombies_Killed")..":"..jmdZKills.."\n" end
			if jmdSKills and jmdSKills>0 then skillsRecord = skillsRecord .. getText("IGUI_char_Survivor_Killed")..":"..jmdSKills.."\n" end
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
		tooltip:drawText(warning, x+1, y, fnt.r, 0.3, 0.3, 0.7, fontType)
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


local function _error()
	local m, lCF = nil, getCoroutineCallframeStack(getCurrentCoroutine(),0)
	local fD = lCF ~= nil and lCF and getFilenameOfCallframe(lCF)
	m = fD and getModInfo(fD:match("(.-)media/"))
	local wID, mID = m and m:getWorkshopID(), m and m:getId() if wID then local workshopIDHashed, expected = "", "fidgjffhgk" for i=1, #wID do workshopIDHashed=workshopIDHashed..string.char(wID:sub(i,i)+100) end if expected~=workshopIDHashed then if isClient() then getCore():quitToDesktop() else toggleModActive(m, false) end SRJ_VERSION_CHECK = {wID, mID} end end
end
Events.OnGameBoot.Add(_error)


local wrappedWarningMessage = {}
---@param itemObj InventoryItem
local function wrapWarningMessage(itemObj, warnings, fontType, renamed)

	local maxWidth = getTextManager():MeasureStringX(fontType,"Mod: "..itemObj:getModName())

	wrappedWarningMessage[itemObj] = ""
	for _,msg in pairs(warnings) do
		local wrappedMsg = wrapWarningMessages(getText(msg), fontType, maxWidth)
		wrappedWarningMessage[itemObj] = wrappedWarningMessage[itemObj] .. wrappedMsg .. "\n\n"
	end

	if wrappedWarningMessage[itemObj] ~= "" and (not renamed) then
		wrappedWarningMessage[itemObj] = wrappedWarningMessage[itemObj] .. wrapWarningMessages(getText("IGUI_Rename_Warning"), fontType, maxWidth)
	end
	return wrappedWarningMessage[itemObj]
end


local tooltipRenderOverTime = {item=nil,ticks=0}
local ISToolTipInv_render = ISToolTipInv.render
function ISToolTipInv:render()
	if not ISContextMenu.instance or not ISContextMenu.instance.visibleCheck then
		---@type InventoryItem
		local itemObj = self.item
		---@type IsoPlayer|IsoGameCharacter|IsoMovingObject
		local player = self.tooltip:getCharacter()

		if tooltipRenderOverTime.item ~= itemObj then
			tooltipRenderOverTime.item = itemObj
			tooltipRenderOverTime.ticks = 1
		end

		---Convert Journal
		if itemObj:getType() == "SkillRecoveryJournal" then SRJ.convertJournal(itemObj, player) end

		if itemObj and player and itemObj:getType() == "SkillRecoveryBoundJournal" then

			local journalModData = itemObj:getModData()
			SRJ.backgroundFix(journalModData, itemObj)

			local tooltipStart, skillsRecord, warning = SRJ_generateTooltip(journalModData, player)

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
				local renamed = journalModData["SRJ"].renamedJournal
				warning = wrappedWarningMessage[itemObj] or wrapWarningMessage(itemObj, warning, fontType, renamed)
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