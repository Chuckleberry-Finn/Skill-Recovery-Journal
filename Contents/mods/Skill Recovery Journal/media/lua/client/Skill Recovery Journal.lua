SRJ = {}

function SRJ.writingItems(scriptItems)
	scriptItems:addAll(getScriptManager():getItemsTag("Write"))
end


if ISToolTipInv then
	function ISToolTipInv:setItem(item)
		if item:getType() == "SkillRecoveryJournal" then

			local journalModData = item:getModData()
			local JMD = journalModData["SRJ"]

			if JMD and JMD["ToolTip"] then
				item:setTooltip(JMD["ToolTip"])
			end
		end
		self.item = item
	end
end


STORED_ISReadABook_update = ISReadABook.update
function ISReadABook:update()
	STORED_ISReadABook_update(self)

	--local jobDeltaBy10 = math.floor(self:getJobDelta()*10)
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

	if self.character:HasTrait("Illiterate") then
		delayedStop = true
		sayText = sayTextChoices[ZombRand(#sayTextChoices)+1]
	end

	if (not JMD) then
		delayedStop = true
		sayText = "There's nothing written here."
	end

	if not delayedStop then
		local skillLevels = JMD["skillLevels"]

		for skill,level in pairs(skillLevels) do
			local currentPerkLevel = player:getPerkLevel(Perks[skill])
			if currentPerkLevel < level then
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

	local skillsRecord = ""

	local recoverableSkills = SRJ.calculateGainedSkills(player)
	if recoverableSkills == nil then
		player:Say("I don't have any experiences to record.", 0.55, 0.55, 0.55, UIFont.NewSmall, 0, "radio")
		print("INFO: SkillRecoveryJournal: No recoverable skills to be saved.")
		return
	end

	---@type InventoryItem | Literature
	local journal = oldJournal or player:getInventory():AddItem("Base.SkillRecoveryJournal")
	local journalModData = journal:getModData()
	journalModData["SRJ"] = journalModData["SRJ"] or {}
	local JMD = journalModData["SRJ"]

	JMD["skillLevels"] = JMD["skillLevels"] or {}
	local storedSkills = JMD["skillLevels"]

	JMD["ID"] = JMD["ID"] or {}
	local journalID = JMD["ID"]

	local pSteamID = player:getSteamID()
	local pOnlineID = player:getOnlineID()
	print("-- SRJ INFO:".." pSteamID: "..pSteamID.." pOnlineID: "..pOnlineID.." --")

	if pSteamID ~= 0 then
		journalID["steamID"] = pSteamID
	end
	journalID["onlineID"] = pOnlineID

	for skill,level in pairs(recoverableSkills) do
		if level > 0 then
			if storedSkills[skill] and storedSkills[skill] > level then
				level = storedSkills[skill]
			end
			storedSkills[skill] = level
		end
	end

	for skill,level in pairs(storedSkills) do
		local perk = PerkFactory.getPerk(Perks[skill])
		local perkName = perk:getName()
		skillsRecord = skillsRecord..perkName.."("..level..")\n"
	end

	JMD["author"] = player:getFullName()
	JMD["ToolTip"] = "\nA record of "..JMD["author"].."'s life.\n"..skillsRecord
	journal:setTooltip(JMD["ToolTip"])
end


--TODO: Calculate gained XP rather than levels - causing issue with professions not being able to store max level gains
function SRJ.calculateGainedSkills(player)

	local bonusLevels = {}
	local traitXpMap = transformIntoKahluaTable(player:getDescriptor():getXPBoostMap())
	for perk,level in pairs(traitXpMap) do
		local perky = tostring(perk)
		local levely = tonumber(tostring(level))
		if perky=="Strength" or perky=="Fitness" then
			levely = levely+2
		end
		bonusLevels[perky] = levely
	end

	local gainedLevels = {}
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
				local bonusFromTrait = bonusLevels[perkType] or 0
				local recoverableLevels = math.max(perkLevel-bonusFromTrait, 0)

				if recoverableLevels > 0 then
					gainedLevels[perkType] = recoverableLevels
					storingSkills = true
					print("  "..i.." "..perkType.." = "..perkLevel.."(-"..tostring(bonusFromTrait)..")".." : "..tostring(recoverableLevels))
				end
			end
		end
	end

	if not storingSkills then
		return
	end

	return gainedLevels
end
