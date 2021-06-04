SRJ = {}

--TODO:
--[[ Read: Ideal: Timed actions as a means to increase/decrease time needed to relearn skills. 
	Alternative: Use recipe to have each skill level require a reading session - problem: which skill first? - repetitive and not ideal. ]]
--[[ Write time: Ideal: Used timed action so that writing time reflects the number of skills involved. 
	Additional: Writing time should reduce time for adding to journals as opposed to writing from scratch. 
	Alternative: Each level requires a pass wit hthe recipe - repetitive and not ideal. ]]

function SRJ.writingItems(scriptItems)
	scriptItems:addAll(getScriptManager():getItemsTag("Write"))
end


if ISToolTipInv then
	function ISToolTipInv:setItem(item)
		if item:getType() == "SkillRecoveryJournal" then
			local modData = item:getModData()
			if modData and modData["ToolTip"] then
				item:setTooltip(modData["ToolTip"])
			end
		end
		self.item = item
	end
end


---@param recipe InventoryItem | Literature
---@param player IsoGameCharacter | IsoPlayer
function SRJ.writeJournal(recipe, result, player)

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

	if not player then
		return
	end

	local skillsRecord = ""

	local recoverableSkills, skillNames = SRJ.calculateGainedSkills(player)
	if recoverableSkills == nil then
		player:Say("I don't have anything experiences to record.",0.75,0.75,0.75)
		print("INFO: SkillRecoveryJournal: No recoverable skills to be saved.")
		return
	end

	---@type InventoryItem | Literature
	local journal = oldJournal or player:getInventory():AddItem("Base.SkillRecoveryJournal")
	local journalModData = journal:getModData()
	journalModData["SRJ"] = journalModData["SRJ"] or {}
	local JMD = journalModData["SRJ"]

	if oldJournal then
		if JMD then
			if JMD["ID"] then
				print("old journal found: JMD: "..JMD["ID"]["steamID"].."=  "..JMD["ID"]["userName"])
			else
				print("old journal found: JMD: ERR: no ID stored.")
			end
		end
	end

	local JMDSkills = JMD["SRJ_RecoverableSkills"] or {}
	JMD["ID"] = {["steamID"]=player:getSteamID(),["userName"]=player:getUsername()}

	for skill,level in pairs(recoverableSkills) do
		level = math.max(level,(JMDSkills[skill] or 0))
		if level > 0 then
			skillsRecord = skillsRecord..skillNames[skill].."("..level..")\n"
		end
	end

	print("INFO: SkillRecoveryJournal: "..tostring(JMD["ID"]["steamID"]).." = "..tostring(JMD["ID"]["userName"]).." = "..player:getFullName())

	local author = "\nA record of "..player:getFullName().."'s life.\n"

	JMD["ToolTip"] = author..skillsRecord
	journal:setTooltip(author..skillsRecord)
end


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
		--print("-"..perky)
	end

	local gainedLevels = {}
	local skillNames = {}

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
				local perkName = perk:getName()
				local bonusFromTrait = bonusLevels[perkType] or 0
				local recoverableLevels = math.max(perkLevel-bonusFromTrait, 0)

				if recoverableLevels > 0 then
					gainedLevels[perkType] = recoverableLevels
					skillNames[perkType] = perkName
					storingSkills = true
					print("  "..i.." "..perkType.."/"..perkName.." = "..perkLevel.."(-"..tostring(bonusFromTrait)..")".." : "..tostring(recoverableLevels))
				end
			end
		end
	end

	if not storingSkills then
		return nil, nil
	end

	return gainedLevels, skillNames
end
