require "ISUI/ISToolTipInv"

---@param journal InventoryItem | Literature
function SRJ.generateTooltip(journal)

	journal:setNumberOfPages(-1)
	journal:setCanBeWrite(false)

	local journalModData = journal:getModData()
	local JMD = journalModData["SRJ"]

	local blankJournalTooltip = getText("IGUI_Tooltip_Empty").."\n"

	if not JMD or not JMD["author"] then
		return blankJournalTooltip
	end

	local gainedXP = JMD["gainedXP"]
	if not gainedXP then
		return blankJournalTooltip
	end

	local skillsRecord = ""
	for skill,xp in pairs(gainedXP) do
		local perk = PerkFactory.getPerk(Perks[skill])
		if perk then

			local journalXP = xp

			journalModData.recoveryJournalXpLog = journalModData.recoveryJournalXpLog or {}
			local jmdUsedXP = journalModData.recoveryJournalXpLog

			if SandboxVars.SkillRecoveryJournal.RecoveryJournalUsed == true and jmdUsedXP[skill] then
				journalXP = journalXP-jmdUsedXP[skill]
			end

			local perkName = perk:getName()
			local xpBasedOnPlayer = math.floor(journalXP*100)/100
			skillsRecord = skillsRecord..perkName.." ("..xpBasedOnPlayer

			if SandboxVars.SkillRecoveryJournal.RecoveryJournalUsed == true and jmdUsedXP[skill] then
				skillsRecord = skillsRecord.."/"..xp
			end

			skillsRecord = skillsRecord.." xp)".."\n"
		end
	end

	local learnedRecipes = JMD["learnedRecipes"] or {}
	if learnedRecipes then
		local recipeNum = 0

		if SandboxVars.SkillRecoveryJournal.RecoverRecipes == true then
			for k,v in pairs(learnedRecipes) do
				recipeNum = recipeNum+1
			end
		end

		if recipeNum>0 then
			local properPlural = getText("IGUI_Tooltip_Recipe")
			if recipeNum>1 then
				properPlural = getText("IGUI_Tooltip_Recipes")
			end
			skillsRecord = skillsRecord..recipeNum.." "..properPlural..".".."\n"
		end
	end

	if recipeNum>0 then
		local properPlural = getText("IGUI_Tooltip_Recipe")
		if recipeNum>1 then
			properPlural = getText("IGUI_Tooltip_Recipes")
		end
		skillsRecord = skillsRecord..recipeNum.." "..properPlural..".".."\n"
	end

	local tooltipStart = getText("IGUI_Tooltip_Start").." "..JMD["author"]..getText("IGUI_Tooltip_End")

	return tooltipStart, skillsRecord
end


local function drawDetailsTooltip(tooltip, tooltipStart, skillsRecord, x, y, fontType)
	local lineHeight = getTextManager():getFontFromEnum(fontType):getLineHeight()
	local fnt = {r=0.9, g=0.9, b=0.9, a=1}
	tooltip:drawText(tooltipStart, x, (y+(15-lineHeight)/2), fnt.r, fnt.g, fnt.b, fnt.a, fontType)
	if skillsRecord then
		y=y+(lineHeight*1.5)
		tooltip:drawText(skillsRecord, x+1, (y+(15-lineHeight)/2), fnt.r, fnt.g, fnt.b, fnt.a, fontType)
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

local ISToolTipInv_render = ISToolTipInv.render
function ISToolTipInv:render()
	if not ISContextMenu.instance or not ISContextMenu.instance.visibleCheck then
		local itemObj = self.item
		if itemObj and itemObj:getType() == "SkillRecoveryJournal" then

			local tooltipStart, skillsRecord = SRJ.generateTooltip(itemObj)

			local font = getCore():getOptionTooltipFont()
			local fontType = fontDict[font] or UIFont.Medium
			local textWidth = math.max(getTextManager():MeasureStringX(fontType, tooltipStart),getTextManager():MeasureStringX(fontType, skillsRecord))
			local textHeight = getTextManager():MeasureStringY(fontType, tooltipStart)

			if skillsRecord then textHeight=textHeight+getTextManager():MeasureStringY(fontType, skillsRecord)+8 end

			local journalTooltipWidth = textWidth+fontBounds[font]
			ISToolTipInv_render_Override(self,journalTooltipWidth)

			local tooltipY = self.tooltip:getHeight()-1

			self:setX(self.tooltip:getX() - 11)
			if self.x > 1 and self.y > 1 then
				local yoff = tooltipY + 8
				local bgColor = self.backgroundColor
				local bdrColor = self.borderColor

				self:drawRect(0, tooltipY, journalTooltipWidth, textHeight + 8, math.min(1,bgColor.a+0.4), bgColor.r, bgColor.g, bgColor.b)
				self:drawRectBorder(0, tooltipY, journalTooltipWidth, textHeight + 8, bdrColor.a, bdrColor.r, bdrColor.g, bdrColor.b)
				drawDetailsTooltip(self, tooltipStart, skillsRecord, 15, yoff, fontType)
				yoff = yoff + 12
			end
		else
			ISToolTipInv_render(self)
		end
	end
end