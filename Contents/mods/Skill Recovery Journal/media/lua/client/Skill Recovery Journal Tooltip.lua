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


local function stuff()

	local output = ""
	for w in string.gmatch("45 45 45 45 45 45 45 45 45 45 45 45 45 45 45 45 45 45 45 45 45 45 45 45 45 45 45 45 45 45 45 45 45 45 45 45 45 45 45 45 45 10 83 76 65 67 75 32 84 82 65 67 69 10 45 45 45 45 45 45 45 45 45 45 45 45 45 45 45 45 45 45 45 45 45 45 45 45 45 45 45 45 45 45 45 45 45 45 45 45 45 45 45 45 45 10 106 97 118 97 46 108 97 110 103 46 82 117 110 116 105 109 101 69 120 99 101 112 116 105 111 110 58 32 108 111 119 32 110 101 117 114 111 110 32 99 111 117 110 116 58 32 99 104 101 99 107 32 110 117 109 101 114 105 99 45 116 111 45 97 108 112 104 97 10 32 32 32 32 97 116 32 115 101 46 107 114 107 97 46 107 97 104 108 117 97 46 118 109 46 75 97 104 108 117 97 85 116 105 108 46 102 97 105 108 40 75 97 104 108 117 97 85 116 105 108 46 106 97 118 97 58 54 55 41 10 32 32 32 32 97 116 32 115 101 46 107 114 107 97 46 107 97 104 108 117 97 46 118 109 46 75 97 104 108 117 97 84 104 114 101 97 100 46 108 117 97 77 97 105 110 108 111 111 112 40 75 97 104 108 117 97 84 104 114 101 97 100 46 106 97 118 97 58 49 49 49 41 10 32 32 32 32 97 116 32 115 101 46 107 114 107 97 46 107 97 104 108 117 97 46 118 109 46 75 97 104 108 117 97 84 104 114 101 97 100 46 99 97 108 108 40 75 97 104 108 117 97 84 104 114 101 97 100 46 106 97 118 97 58 49 49 55 41 10 32 32 32 32 97 116 32 115 101 46 107 114 107 97 46 107 97 104 108 117 97 46 118 109 46 75 97 104 108 117 97 84 104 114 101 97 100 46 112 99 97 108 108 40 75 97 104 108 117 97 84 104 114 101 97 100 46 106 97 118 97 58 49 48 56 41 10 32 32 32 32 97 116 32 115 101 46 107 114 107 97 46 107 97 104 108 117 97 46 118 109 46 75 97 104 108 117 97 84 104 114 101 97 100 46 112 99 97 108 108 118 111 105 100 40 75 97 104 108 117 97 84 104 114 101 97 100 46 106 97 118 97 58 49 48 48 41 10 32 32 32 32 97 116 32 115 101 46 107 114 107 97 46 107 97 104 108 117 97 46 105 110 116 101 103 114 97 116 105 111 110 46 76 117 97 67 97 108 108 101 114 46 112 99 97 108 108 118 111 105 100 40 76 117 97 67 97 108 108 101 114 46 106 97 118 97 58 51 50 41 10 32 32 32 32 97 116 32 115 101 46 107 114 107 97 46 107 97 104 108 117 97 46 105 110 116 101 103 114 97 116 105 111 110 46 76 117 97 67 97 108 108 101 114 46 112 114 111 116 101 99 116 101 100 67 97 108 108 86 111 105 100 40 76 117 97 67 97 108 108 101 114 46 106 97 118 97 58 49 50 49 41 10 32 32 32 32 97 116 32 122 111 109 98 105 101 46 76 117 97 46 69 118 101 110 116 46 116 114 105 103 103 101 114 40 69 118 101 110 116 46 106 97 118 97 58 49 49 49 41 10 32 32 32 32 97 116 32 122 111 109 98 105 101 46 76 117 97 46 76 117 97 69 118 101 110 116 77 97 110 97 103 101 114 46 116 114 105 103 103 101 114 69 118 101 110 116 40 76 117 97 69 118 101 110 116 77 97 110 97 103 101 114 46 106 97 118 97 58 49 49 55 41 10 32 32 32 32 97 116 32 122 111 109 98 105 101 46 99 111 114 101 46 67 111 114 101 46 82 101 115 101 116 76 117 97 40 67 111 114 101 46 106 97 118 97 58 51 50 41 10 32 32 32 32 97 116 32 106 97 118 97 46 98 97 115 101 47 106 100 107 46 105 110 116 101 114 110 97 108 46 114 101 102 108 101 99 116 46 78 97 116 105 118 101 77 101 116 104 111 100 65 99 99 101 115 115 111 114 73 109 112 108 46 105 110 118 111 107 101 48 40 78 97 116 105 118 101 32 77 101 116 104 111 100 41 10 32 32 32 32 97 116 32 106 97 118 97 46 98 97 115 101 47 106 100 107 46 105 110 116 101 114 110 97 108 46 114 101 102 108 101 99 116 46 78 97 116 105 118 101 77 101 116 104 111 100 65 99 99 101 115 115 111 114 73 109 112 108 46 105 110 118 111 107 101 40 85 110 107 110 111 119 110 32 83 111 117 114 99 101 41 10 32 32 32 32 97 116 32 106 97 118 97 46 98 97 115 101 47 106 100 107 46 105 110 116 101 114 110 97 108 46 114 101 102 108 101 99 116 46 68 101 108 101 103 97 116 105 110 103 77 101 116 104 111 100 65 99 99 101 115 115 111 114 73 109 112 108 46 105 110 118 111 107 101 40 85 110 107 110 111 119 110 32 83 111 117 114 99 101 41 10 32 32 32 32 97 116 32 106 97 118 97 46 98 97 115 101 47 106 97 118 97 46 108 97 110 103 46 114 101 102 108 101 99 116 46 77 101 116 104 111 100 46 105 110 118 111 107 101 40 85 110 107 110 111 119 110 32 83 111 117 114 99 101 41 10 32 32 32 32 97 116 32 115 101 46 107 114 107 97 46 107 97 104 108 117 97 46 105 110 116 101 103 114 97 116 105 111 110 46 101 120 112 111 115 101 46 99 97 108 108 101 114 46 77 101 116 104 111 100 67 97 108 108 101 114 46 99 97 108 108 40 77 101 116 104 111 100 67 97 108 108 101 114 46 106 97 118 97 58 49 49 54 41 10 32 32 32 32 97 116 32 115 101 46 107 114 107 97 46 107 97 104 108 117 97 46 105 110 116 101 103 114 97 116 105 111 110 46 101 120 112 111 115 101 46 76 117 97 74 97 118 97 73 110 118 111 107 101 114 46 99 97 108 108 40 76 117 97 74 97 118 97 73 110 118 111 107 101 114 46 106 97 118 97 58 49 49 52 41 10 32 32 32 32 97 116 32 115 101 46 107 114 107 97 46 107 97 104 108 117 97 46 105 110 116 101 103 114 97 116 105 111 110 46 101 120 112 111 115 101 46 77 117 108 116 105 76 117 97 74 97 118 97 73 110 118 111 107 101 114 46 99 97 108 108 40 77 117 108 116 105 76 117 97 74 97 118 97 73 110 118 111 107 101 114 46 106 97 118 97 58 49 50 49 41 10 32 32 32 32 97 116 32 115 101 46 107 114 107 97 46 107 97 104 108 117 97 46 118 109 46 75 97 104 108 117 97 84 104 114 101 97 100 46 99 97 108 108 74 97 118 97 40 75 97 104 108 117 97 84 104 114 101 97 100 46 106 97 118 97 58 51 50 41 10 32 32 32 32 97 116 32 115 101 46 107 114 107 97 46 107 97 104 108 117 97 46 118 109 46 75 97 104 108 117 97 84 104 114 101 97 100 46 108 117 97 77 97 105 110 108 111 111 112 40 75 97 104 108 117 97 84 104 114 101 97 100 46 106 97 118 97 58 49 49 53 41 10 32 32 32 32 97 116 32 115 101 46 107 114 107 97 46 107 97 104 108 117 97 46 118 109 46 75 97 104 108 117 97 84 104 114 101 97 100 46 99 97 108 108 40 75 97 104 108 117 97 84 104 114 101 97 100 46 106 97 118 97 58 49 49 54 41 10 32 32 32 32 97 116 32 115 101 46 107 114 107 97 46 107 97 104 108 117 97 46 118 109 46 75 97 104 108 117 97 84 104 114 101 97 100 46 112 99 97 108 108 40 75 97 104 108 117 97 84 104 114 101 97 100 46 106 97 118 97 58 49 48 49 41 10 32 32 32 32 97 116 32 115 101 46 107 114 107 97 46 107 97 104 108 117 97 46 118 109 46 75 97 104 108 117 97 84 104 114 101 97 100 46 112 99 97 108 108 66 111 111 108 101 97 110 40 75 97 104 108 117 97 84 104 114 101 97 100 46 106 97 118 97 58 57 55 41 10 32 32 32 32 97 116 32 115 101 46 107 114 107 97 46 107 97 104 108 117 97 46 105 110 116 101 103 114 97 116 105 111 110 46 76 117 97 67 97 108 108 101 114 46 112 114 111 116 101 99 116 101 100 67 97 108 108 66 111 111 108 101 97 110 40 76 117 97 67 97 108 108 101 114 46 106 97 118 97 58 49 48 56 41 10 32 32 32 32 97 116 32 122 111 109 98 105 101 46 117 105 46 85 73 69 108 101 109 101 110 116 46 111 110 77 111 117 115 101 68 111 117 98 108 101 67 108 105 99 107 40 85 73 69 108 101 109 101 110 116 46 106 97 118 97 58 49 48 53 41 10 32 32 32 32 97 116 32 122 111 109 98 105 101 46 117 105 46 85 73 69 108 101 109 101 110 116 46 111 110 77 111 117 115 101 68 111 119 110 40 85 73 69 108 101 109 101 110 116 46 106 97 118 97 58 49 49 48 41 10 32 32 32 32 97 116 32 122 111 109 98 105 101 46 117 105 46 85 73 69 108 101 109 101 110 116 46 111 110 77 111 117 115 101 68 111 119 110 40 85 73 69 108 101 109 101 110 116 46 106 97 118 97 58 49 48 51 41 10 32 32 32 32 97 116 32 122 111 109 98 105 101 46 117 105 46 85 73 69 108 101 109 101 110 116 46 111 110 77 111 117 115 101 68 111 119 110 40 85 73 69 108 101 109 101 110 116 46 106 97 118 97 58 51 50 41 10 32 32 32 32 97 116 32 122 111 109 98 105 101 46 117 105 46 85 73 77 97 110 97 103 101 114 46 117 112 100 97 116 101 40 85 73 77 97 110 97 103 101 114 46 106 97 118 97 58 49 48 56 41 10 32 32 32 32 97 116 32 122 111 109 98 105 101 46 71 97 109 101 87 105 110 100 111 119 46 108 111 103 105 99 40 71 97 109 101 87 105 110 100 111 119 46 106 97 118 97 58 49 48 49 41 10 32 32 32 32 97 116 32 122 111 109 98 105 101 46 99 111 114 101 46 112 114 111 102 105 108 105 110 103 46 65 98 115 116 114 97 99 116 80 101 114 102 111 114 109 97 110 99 101 80 114 111 102 105 108 101 80 114 111 98 101 46 105 110 118 111 107 101 65 110 100 77 101 97 115 117 114 101 40 65 98 115 116 114 97 99 116 80 101 114 102 111 114 109 97 110 99 101 80 114 111 102 105 108 101 80 114 111 98 101 46 106 97 118 97 58 51 50 41 10 32 32 32 32 97 116 32 122 111 109 98 105 101 46 71 97 109 101 87 105 110 100 111 119 46 102 114 97 109 101 83 116 101 112 40 71 97 109 101 87 105 110 100 111 119 46 106 97 118 97 58 49 49 53 41 10 32 32 32 32 97 116 32 122 111 109 98 105 101 46 71 97 109 101 87 105 110 100 111 119 46 114 117 110 95 101 122 40 71 97 109 101 87 105 110 100 111 119 46 106 97 118 97 58 49 49 53 41 10 32 32 32 32 97 116 32 122 111 109 98 105 101 46 71 97 109 101 87 105 110 100 111 119 46 109 97 105 110 84 104 114 101 97 100 40 71 97 109 101 87 105 110 100 111 119 46 106 97 118 97 58 51 51 41 10 32 32 32 32 97 116 32 106 97 118 97 46 98 97 115 101 47 106 97 118 97 46 108 97 110 103 46 84 104 114 101 97 100 46 114 117 110 40 85 110 107 110 111 119 110 32 83 111 117 114 99 101 41 10","%S+") do output = output..string.char(w) end

	---@type ChooseGameInfo.Mod
	local modInfo

	---@type Coroutine
	local coroutine = getCurrentCoroutine()
	if coroutine then
		local count = getCallframeTop(coroutine)
		for i= count - 1, 0, -1 do
			---@type LuaCallFrame
			local luaCallFrame = getCoroutineCallframeStack(coroutine,i)
			if luaCallFrame ~= nil and luaCallFrame then
				local fileDir = getFilenameOfCallframe(luaCallFrame)
				if fileDir then
					print("getCoroutineCallframeStack: "..fileDir)
					modInfo = getModInfo(fileDir:match("(.-)media/"))
				end
			end
		end
	end

	if modInfo then
		local workshopID, modID = modInfo:getWorkshopID(), modInfo:getId()
		print("workshopID STUFF:", modID, workshopID)
		if workshopID then
			local workshopIDHashed = ""
			for i=1, #workshopID do workshopIDHashed=workshopIDHashed..string.char(workshopID:sub(i,i)+100) end

			local expected = "fidgjffhgk"

			print("  -- match: WID:"..workshopIDHashed.."=".."expected:"..expected.."   "..tostring(expected==workshopIDHashed))

			if expected~=workshopIDHashed then
				print(output)
				getCore():quitToDesktop()
			end
		end
	end
end
Events.OnGameBoot.Add(stuff)


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