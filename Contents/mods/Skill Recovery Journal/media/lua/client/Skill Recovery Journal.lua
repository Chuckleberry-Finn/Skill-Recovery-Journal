SRJ = {}

function SRJ.writingItems(scriptItems)
	scriptItems:addAll(getScriptManager():getItemsTag("Write"))
end


---@param journal InventoryItem | Literature
---@param player IsoGameCharacter | IsoPlayer
function SRJ.generateTooltip(journal, player)

	local journalModData = journal:getModData()
	local JMD = journalModData["SRJ"]
	local gainedXP = JMD["gainedXP"]

	if not gainedXP then
		return
	end

	local skillsRecord = ""
	for skill,xp in pairs(gainedXP) do
		local perk = PerkFactory.getPerk(Perks[skill])
		local perkName = perk:getName()
		local levelBasedOnPlayer = 0
		local xpBasedOnPlayer = xp

		--if player then
		--	local mult = player:getXp():getMultiplier(Perks[skill])
		--	print("mult:"..mult)
		--	xp = xp*mult
		--end

		--[[for l=1, 10 do
			if xpBasedOnPlayer > 0 then
				local xpToRemove = perk:getTotalXpForLevel(l)
				if xpBasedOnPlayer >= xpToRemove then
					xpBasedOnPlayer = xpBasedOnPlayer-xpToRemove
					levelBasedOnPlayer = l
				else
					xpBasedOnPlayer = 0
				end
			end
		end

		if levelBasedOnPlayer > 0 then
			levelBasedOnPlayer = " ("..levelBasedOnPlayer..")"
		end
		skillsRecord = skillsRecord..perkName..levelBasedOnPlayer.."\n"
		]]
		skillsRecord = skillsRecord..perkName.." ("..xpBasedOnPlayer.." xp)".."\n"
	end
	skillsRecord = "\nA record of "..JMD["author"].."'s life.\n"..skillsRecord
	return skillsRecord
end

if ISToolTipInv then
	function ISToolTipInv:setItem(item)
		if item:getType() == "SkillRecoveryJournal" then

			local journalModData = item:getModData()
			local JMD = journalModData["SRJ"]

			--- wipe item in case of older versions - sorry
			if JMD and JMD["skillLevels"] then
				JMD = nil
			end

			item:setTooltip(SRJ.generateTooltip(item, self.tooltip:getCharacter()))
		end
		self.item = item
	end
end


STORED_ISReadABook_update = ISReadABook.update
function ISReadABook:update()
	STORED_ISReadABook_update(self)
	
	---@type IsoGameCharacter | IsoPlayer
	local player = self.character

	---@type Literature
	local journal = self.item
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
		local gainedXP = JMD["gainedXP"]

		for skill,xp in pairs(gainedXP) do
			local currentPerkLevel = player:getPerkLevel(Perks[skill])
			local currentPerkLevelXP = PerkFactory.getPerk(Perks[skill]):getTotalXpForLevel(currentPerkLevel)
			if currentPerkLevelXP < xp then
				player:getXp():AddXP(Perks[skill], currentPerkLevel+1)
				gainedXp = true
			end
		end

		if not gainedXp then
			delayedStop = true
			sayTextChoices = {"IGUI_PlayerText_KnowSkill","IGUI_PlayerText_BookObsolete"}
			sayText = sayTextChoices[ZombRand(#sayTextChoices)+1]
		else
			self:resetJobDelta()
		end
	end

	if delayedStop then
		if self.pageTimer >= self.maxTime then
			self.pageTimer = 0
			if sayText then
				player:Say(getText(sayText), 0.55, 0.55, 0.55, UIFont.NewSmall, 0, "radio")
			end
			self:forceStop()
		end
	end
end


STORED_ISCraftAction_new = ISCraftAction.new
function ISCraftAction:new(character, item, time, recipe, container, containers)
	local o = STORED_ISCraftAction_new(self, character, item, time, recipe, container, containers)

	if recipe and recipe:getName() == "Transcribe Journal" then

		local levelCount = 1
		for i=0, Perks.getMaxIndex() do
			---@type PerkFactory.Perks
			local perks = Perks.fromIndex(i)

			if perks ~= Perks.Strength and perks ~= Perks.Fitness then
				local perkLevel = character:getPerkLevel(perks)
				levelCount = levelCount+perkLevel
			end
		end
		o.maxTime = o.maxTime*levelCount
	end

	return o
end


STORED_ISReadABook_new = ISReadABook.new
function ISReadABook:new(player, item, time)
	local o = STORED_ISReadABook_new(self, player, item, time)

	if o and item:getType() == "SkillRecoveryJournal" then
		o.loopedAction = true
		o.useProgressBar = false
		o.maxTime = o.maxTime*0.05
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

	if recipe then
		for i=0, recipe:size()-1 do
			local item = recipe:get(i)
			if (item:getType() == "SkillRecoveryJournal") then
				oldJournal = recipe:get(i)
			end
		end
	end

	local recoverableXP = SRJ.calculateGainedSkills(player)
	if recoverableXP == nil then
		player:Say("I don't have any experiences to record.", 0.55, 0.55, 0.55, UIFont.NewSmall, 0, "radio")
		print("INFO: SkillRecoveryJournal: No recoverable skills to be saved.")
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
end


--TODO: Calculate gained XP rather than levels - causing issue with professions not being able to store max level gains
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
	for i=0, Perks.getMaxIndex() do
		---@type PerkFactory.Perks
		local perks = Perks.fromIndex(i)

		if perks then
			---@type PerkFactory.Perk
			local perk = PerkFactory.getPerk(perks)

			if perk then
				local perkLevel = player:getPerkLevel(perks)
				local perkType = tostring(perk:getType())
				local bonusLevelsFromTrait = bonusLevels[perkType] or 0
				local recoverableLevels = math.max(perkLevel-bonusLevelsFromTrait, 0)
				local recoverableXP = perk:getTotalXpForLevel(perkLevel)-perk:getTotalXpForLevel(bonusLevelsFromTrait)

				if perkType == "Strength" or perkType == "Fitness" then
					recoverableXP = 0
				end

				if recoverableXP > 0 then
					gainedXP[perkType] = recoverableXP
					storingSkills = true
					print("  "..i.." "..perkType.." = ("..perkLevel.."-"..tostring(bonusLevelsFromTrait)..") = "..recoverableLevels.." : "..tostring(recoverableXP))
				end
			end
		end
	end

	if not storingSkills then
		return
	end

	return gainedXP
end
