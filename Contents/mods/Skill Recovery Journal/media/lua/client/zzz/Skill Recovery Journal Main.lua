SRJ = {}


function SRJ.CleanseFalseSkills(gainedXP)
	for skill,xp in pairs(gainedXP) do

		local perkList = PerkFactory.PerkList
		local junk = true

		if xp>1 then
			for i=0, perkList:size()-1 do
				---@type PerkFactory.Perk
				local perk = perkList:get(i)
				if perk and tostring(perk:getType()) == skill then
					junk = false
				end
			end
		end

		if junk then
			gainedXP[skill] = nil
		end
	end
end


---@param journal InventoryItem | Literature
---@param player IsoGameCharacter | IsoPlayer
function SRJ.generateTooltip(journal, player)

	local journalModData = journal:getModData()
	local JMD = journalModData["SRJ"]

	local blankJournalTooltip = "An empty journal ready to be recorded into."

	if not JMD then
		return blankJournalTooltip
	end

	local gainedXP = JMD["gainedXP"]
	if not gainedXP then
		return blankJournalTooltip
	else
		SRJ.CleanseFalseSkills(JMD["gainedXP"])
	end

	local skillsRecord = ""
	for skill,xp in pairs(gainedXP) do
		local perk = PerkFactory.getPerk(Perks[skill])
		local perkName = perk:getName()
		local xpBasedOnPlayer = xp
		skillsRecord = skillsRecord..perkName.." ("..xpBasedOnPlayer.." xp)".."\n"
	end

	local learnedRecipes = JMD["learnedRecipes"] or {}
	local recipeNum = 0
	for k,v in pairs(learnedRecipes) do
		recipeNum = recipeNum+1
	end
	if recipeNum>0 then
		local properPlural = "recipe"
		if recipeNum>1 then
			properPlural = "recipes"
		end
		skillsRecord = skillsRecord..recipeNum.." "..properPlural..".".."\n"
	end

	skillsRecord = "\nA record of "..JMD["author"].."'s life.\n"..skillsRecord

	return skillsRecord
end


ISToolTipInv_setItem = ISToolTipInv.setItem
function ISToolTipInv:setItem(item)
	if item:getType() == "SkillRecoveryJournal" then
		item:setTooltip(SRJ.generateTooltip(item, self.tooltip:getCharacter()))
	end
	ISToolTipInv_setItem(self, item)
end



SRJOVERWRITE_ISReadABook_update = ISReadABook.update
function ISReadABook:update()
	SRJOVERWRITE_ISReadABook_update(self)

	---@type Literature
	local journal = self.item

	if journal:getType() == "SkillRecoveryJournal" then
		---@type IsoGameCharacter | IsoPlayer
		local player = self.character

		local journalModData = journal:getModData()
		local JMD = journalModData["SRJ"]
		local gainedXp = false

		local delayedStop = false
		local sayText
		local sayTextChoices = {"IGUI_PlayerText_DontUnderstand", "IGUI_PlayerText_TooComplicated", "IGUI_PlayerText_DontGet"}

		local pSteamID = player:getSteamID()

		if (not JMD) then
			delayedStop = true
			sayText = "There's nothing written here."

		elseif self.character:HasTrait("Illiterate") then
			delayedStop = true
			sayText = sayTextChoices[ZombRand(#sayTextChoices)+1]

		elseif pSteamID ~= 0 then
			local journalID = JMD["ID"]
			if journalID["steamID"] and (journalID["steamID"] ~= pSteamID) then
				delayedStop = true
				sayText = sayTextChoices[ZombRand(#sayTextChoices)+1]
			end
		end

		if not delayedStop then

			local learnedRecipes = JMD["learnedRecipes"] or {}
			for recipeID,_ in pairs(learnedRecipes) do
				if not player:isRecipeKnown(recipeID) then
					player:learnRecipe(recipeID)
					gainedXp = true
				end
			end

			local gainedXP = JMD["gainedXP"]

			local maxXP = 0

			for skill,xp in pairs(gainedXP) do
				if skill and skill~="NONE" or skill~="MAX" then
					if xp > maxXP then
						maxXP = xp
					end
				else
					gainedXP[skill] = nil
				end
			end

			local XpMultiplier = SandboxVars.XpMultiplier or 1
			local xpRate = ((maxXP/self.maxTime)/XpMultiplier)/5


			for skill,xp in pairs(gainedXP) do
				local currentXP = player:getXp():getXP(Perks[skill])

				if (currentXP) < xp then
					--print ("TESTING:  xpRate:"..xpRate.."  xpStored:"..xp.."  currentXP:"..currentXP)
					if currentXP+xpRate > xp then
						xpRate = xpRate-(currentXP-xp)
						--print(" --xp overflow: xpRate:"..xpRate)
					end

					if xpRate>0 then
						player:getXp():AddXP(Perks[skill], xpRate)
						gainedXp = true
						self:resetJobDelta()
					end
				end
			end

			if not gainedXp then
				delayedStop = true
				sayTextChoices = {"IGUI_PlayerText_KnowSkill","IGUI_PlayerText_BookObsolete"}
				sayText = sayTextChoices[ZombRand(#sayTextChoices)+1]
			--else
			--	self:resetJobDelta()
			end
		end

		if delayedStop then
			if self.pageTimer >= self.maxTime then
				self.pageTimer = 0
				self.maxTime = 0
				if sayText then
					player:Say(getText(sayText), 0.55, 0.55, 0.55, UIFont.Dialogue, 0, "default")
				end
				self:forceStop()
			end
		end
	end
end


SRJOVERWRITE_ISCraftAction_new = ISCraftAction.new
function ISCraftAction:new(character, item, time, recipe, container, containers)
	local o = SRJOVERWRITE_ISCraftAction_new(self, character, item, time, recipe, container, containers)

	if recipe and recipe:getName() == "Transcribe Journal" then

		local levelCount = 1
		for i=1, Perks.getMaxIndex()-1 do
			---@type PerkFactory.Perks
			local perks = Perks.fromIndex(i)

			if perks ~= Perks.Strength and perks ~= Perks.Fitness then
				local perkLevel = character:getPerkLevel(perks)
			end
		end
		o.maxTime = o.maxTime*levelCount
	end

	return o
end


SRJOVERWRITE_ISReadABook_new = ISReadABook.new
function ISReadABook:new(player, item, time)
	local o = SRJOVERWRITE_ISReadABook_new(self, player, item, time)

	if o and item:getType() == "SkillRecoveryJournal" then
		o.loopedAction = false
		o.useProgressBar = false
		o.maxTime = 100

		local journalModData = item:getModData()
		local JMD = journalModData["SRJ"]
		local gainedXP = JMD["gainedXP"]
		if gainedXP then
			SRJ.CleanseFalseSkills(JMD["gainedXP"])
		end

	end

	return o
end


---@param recipe InventoryItem | Literature
---@param player IsoGameCharacter | IsoPlayer
function SRJ.writeJournal(recipe, result, player)

	if not player then
		return
	end

	---@type InventoryItem | Literature
	local oldJournal
	local writingToolSound = "PenWriteSounds"

	if recipe then
		for i=0, recipe:size()-1 do
			local item = recipe:get(i)
			if (item:getType() == "SkillRecoveryJournal") then
				oldJournal = recipe:get(i)
			elseif (item:getType() == "Pencil") then
				writingToolSound = "PencilWriteSounds"
			end
		end
	end

	local recoverableXP = SRJ.calculateGainedSkills(player)
	if recoverableXP == nil then
		player:Say("I don't have any experiences to record.", 0.55, 0.55, 0.55, UIFont.Dialogue, 0, "default")
		--print("INFO: SkillRecoveryJournal: No recoverable skills to be saved.")
		ISTimedActionQueue.clear(player)
		return
	end

	---@type InventoryItem | Literature
	local journal = oldJournal or player:getInventory():AddItem("Base.SkillRecoveryJournal")
	local journalModData = journal:getModData()
	journalModData["SRJ"] = journalModData["SRJ"] or {}
	local JMD = journalModData["SRJ"]

	JMD["gainedXP"] = JMD["gainedXP"] or {}
	local gainedXP = JMD["gainedXP"]

	JMD["ID"] = JMD["ID"] or {}
	local journalID = JMD["ID"]

	JMD["author"] = player:getFullName()
	local pSteamID = player:getSteamID()
	local pOnlineID = player:getOnlineID()
	print("-- SRJ INFO:".." pSteamID: "..pSteamID.." pOnlineID: "..pOnlineID.." --")

	if pSteamID ~= 0 then
		if journalID["steamID"] and (journalID["steamID"] ~= pSteamID) then
			player:Say("Doesn't feel right to write in someone else's journal.", 0.55, 0.55, 0.55, UIFont.Dialogue, 0, "default")
			ISTimedActionQueue.clear(player)
			return
		end
		journalID["steamID"] = pSteamID
	end
	journalID["onlineID"] = pOnlineID

	for skill,xp in pairs(recoverableXP) do
		if xp > 0 then
			if gainedXP[skill] and gainedXP[skill] > xp then
				xp = gainedXP[skill]
			end
			gainedXP[skill] = xp
		end
	end

	JMD["learnedRecipes"] = JMD["learnedRecipes"] or {}
	local learnedRecipes = JMD["learnedRecipes"]
	---@type ArrayList
	local knownRecipes = player:getKnownRecipes()

	for i=0, knownRecipes:size()-1 do
		local recipeID = knownRecipes:get(i)
		learnedRecipes[recipeID] = true
	end

	player:playSound(writingToolSound)
	ISTimedActionQueue.clear(player)
end


function SRJ.calculateGainedSkills(player)

	local bonusLevels = {}
	local traitXpMap = transformIntoKahluaTable(player:getDescriptor():getXPBoostMap())
	for perk,level in pairs(traitXpMap) do
		local perky = tostring(perk)
		local levely = tonumber(tostring(level))
		bonusLevels[perky] = levely
	end

	local gainedXP = {}
	local storingSkills = false

	print("INFO: SkillRecoveryJournal: calculating gained skills:  total skills: "..Perks.getMaxIndex())
	for i=1, Perks.getMaxIndex()-1 do
		---@type PerkFactory.Perks
		local perks = Perks.fromIndex(i)

		if perks then
			---@type PerkFactory.Perk
			local perk = PerkFactory.getPerk(perks)

			if perk then
				---@type IsoGameCharacter.PerkInfo
				local perkInfo = player:getPerkInfo(perks)
				if perkInfo then

					local perkLevel = perkInfo:getLevel()
					local perkType = tostring(perk:getType())
					local bonusLevelsFromTrait = bonusLevels[perkType] or 0

					local recoverableXPFactor = (SandboxVars.SkillRecoveryJournal.RecoveryPercentage/100) or 1

					local recoverableLevels = perkLevel*recoverableXPFactor
					local recoverableXP = perk:getTotalXpForLevel(recoverableLevels)

					local remainder = recoverableLevels-math.floor(recoverableLevels)
					if remainder then
						recoverableXP = recoverableXP+(perk:getXpForLevel(recoverableLevels+1)*remainder)
					end

					recoverableXP = recoverableXP-perk:getXpForLevel(bonusLevelsFromTrait)

					if perkType == "Strength" or perkType == "Fitness" then
						recoverableXP = 0
					end

					print("  "..i.." "..perkType.." = ("..perkLevel.."-"..tostring(bonusLevelsFromTrait)..") = "..recoverableLevels.." : "..tostring(recoverableXP))

					if recoverableXP > 0 then
						gainedXP[perkType] = recoverableXP
						storingSkills = true
					end
				end
			end
		end
	end

	if not storingSkills then
		return
	end

	return gainedXP
end
