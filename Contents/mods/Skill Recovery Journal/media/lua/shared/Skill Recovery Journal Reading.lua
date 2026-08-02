local SRJ = require "Skill Recovery Journal Main"
local modDataCapture = require "Skill Recovery Journal ModData"

require "TimedActions/ISBaseTimedAction"

---@class ReadSkillRecoveryJournal : ISBaseTimedAction
ReadSkillRecoveryJournal = ISBaseTimedAction:derive("ReadSkillRecoveryJournal")


function ReadSkillRecoveryJournal:isValid()
	local vehicle = self.character:getVehicle()
	if vehicle and vehicle:isDriver(self.character) then return not vehicle:isEngineRunning() or vehicle:getSpeed2D() == 0 end
	return self.character:getInventory():contains(self.item)
end


function ReadSkillRecoveryJournal:start()
	self.action:setTime(-1)
	self.item:setJobType(getText("ContextMenu_Read") ..' '.. self.item:getName())

	self:setAnimVariable("PerformingAction", "ReadBook")
	self:setOverrideHandModels(nil, self.item)

	local logText = ISLogSystem.getGenericLogText(self.character)
	sendClientCommand(self.character, 'ISLogSystem', 'writeLog', {loggerName = "PerkLog", logText = logText.."[SRJ START READING]"})
end


function ReadSkillRecoveryJournal:complete()
	if self.item then
		if self.markUsedOnComplete then
			local journalModData = self.item:getModData()
			journalModData["SRJ"] = journalModData["SRJ"] or {}
			journalModData["SRJ"].used = true
		end

		if self.item.transmitModData then
			self.item:transmitModData()
		end
	end
	return true
end


function ReadSkillRecoveryJournal:forceStop()
	if self.action then self.action:setLoopedAction(false) end
	self.item:setJobDelta(0.0)
	if self.changesWereMade then
		self:complete()
	end
	ISBaseTimedAction.forceStop(self)
end


function ReadSkillRecoveryJournal:stop()
	if self.changesWereMade then
		self:complete()
	end
	ISBaseTimedAction.stop(self)
end


function ReadSkillRecoveryJournal:perform()
	self.character:playSound("CloseBook")
	if self.changesWereMade then
		self:complete()
	end
	ISBaseTimedAction.perform(self)
end


function ReadSkillRecoveryJournal:update()

	if not self.loopedAction then return end

	local player = self.character
	local JMD = self.journalData
	if not JMD then return end

	local changesMade = false
	local delayedStop = false

	local changesBeingMade = {}
	local totalRecoverableXP = 1
	local totalRedXP = 1

	local sayText, sayTextChoices
	local bJournalUsedUp = false

	local pSteamID = player:getSteamID()
	local pUsername = player:getUsername()

	local journalID = JMD["ID"]
	local protections = SandboxVars.SkillRecoveryJournal.SecurityFeatures or 1

	if (protections<=2) and pSteamID ~= 0 and journalID and journalID["steamID"] and (journalID["steamID"] ~= pSteamID) then
		delayedStop = true
		sayText = getText("IGUI_PlayerText_DoesntFeelRightToRead")
	end

	if (protections==1) and journalID and journalID["username"] and (journalID["username"] ~= pUsername) then
		delayedStop = true
		sayText = getText("IGUI_PlayerText_DoesntFeelRightToRead")
	end

	if not delayedStop then

		local readTimeMulti = SandboxVars.SkillRecoveryJournal.ReadTimeSpeed or 1

		if (#self.learnedRecipes > 0) then

			self.recipeIntervals = self.recipeIntervals+1
			changesMade = true

			if self.recipeIntervals > 5 then
				local recipeChunk = math.min(#self.learnedRecipes, math.floor(1.09^math.sqrt(#self.learnedRecipes))) * readTimeMulti
				local properPlural = getText("IGUI_Tooltip_Recipe")
				if recipeChunk>1 then properPlural = getText("IGUI_Tooltip_Recipes") end
				table.insert(changesBeingMade, recipeChunk.." "..properPlural)

				for i=0, recipeChunk do
					local recipeID = self.learnedRecipes[#self.learnedRecipes]
					if recipeID then player:learnRecipe(recipeID) end
					table.remove(self.learnedRecipes,#self.learnedRecipes)
				end
				self.recipeIntervals = 0
			end
		end

		if self.learnedTraits and (#self.learnedTraits > 0) then

			self.traitIntervals = (self.traitIntervals or 0) + 1
			changesMade = true

			if self.traitIntervals > 5 then
				local traitChunk = math.min(#self.learnedTraits, math.floor(1.09^math.sqrt(#self.learnedTraits))) * readTimeMulti
				for i=0, traitChunk do
					local traitID = self.learnedTraits[#self.learnedTraits]
					if traitID then
						if not player:HasTrait(traitID) and not SRJ.isTraitExcluded(traitID, player) then
							player:getTraits():add(traitID)
						end
						local traitObj = TraitFactory.getTrait(traitID)
						local traitName = traitObj and traitObj:getLabel() or traitID
						table.insert(changesBeingMade, traitName)
					end
					table.remove(self.learnedTraits, #self.learnedTraits)
				end
				self.traitIntervals = 0
			end
		end

		local XpStoredInJournal = JMD["gainedXP"]
		local greatestXp = 0

		local validSkills = {}

		if XpStoredInJournal then
			for skill,xp in pairs(XpStoredInJournal) do
				local perk = SRJ.getPerk(skill)
				if perk then
					local valid, percent = SRJ.bSkillValid(perk)
					if valid then
						validSkills[skill] = true
						if skill=="NONE" or skill=="MAX" then
							XpStoredInJournal[skill] = nil
						else
							if xp > greatestXp then greatestXp = xp end
						end
					end
				end
			end

			local xpRate = math.sqrt(greatestXp)/25
			local readXP = SRJ.getReadXP(player)

			local playerModData = player:getModData()
			playerModData.recoveryJournalXpLog = playerModData.recoveryJournalXpLog or {}
			local jmdUsedXP = playerModData.recoveryJournalXpLog

			local oneTimeUse = (SandboxVars.SkillRecoveryJournal.RecoveryJournalUsed == true)

			for skill,xp in pairs(XpStoredInJournal) do
				totalRecoverableXP = totalRecoverableXP + xp
				local perk = SRJ.getPerk(skill)
				if perk and validSkills[skill] then

					readXP[skill] = readXP[skill] or 0
					local currentlyReadXP = readXP[skill]
					totalRedXP = totalRedXP + currentlyReadXP
					local journalXP = xp

					if oneTimeUse and jmdUsedXP[skill] then
						if jmdUsedXP[skill] >= journalXP then bJournalUsedUp = true end
						currentlyReadXP = math.max(currentlyReadXP, jmdUsedXP[skill])
					end

					if currentlyReadXP < journalXP then

						local differential = SRJ.getMaxXPDifferential(perk)

						local perkLevelPlusOne = player:getPerkLevel(perk)+1
						local perPerkXpRate = round(((xpRate*math.sqrt(perkLevelPlusOne))*1000)/1000 * readTimeMulti / differential, 2)
						if perkLevelPlusOne == 11 then perPerkXpRate=false end

						if skill=="Fitness" then
							local cannotGain, message = SRJ.checkFitnessCanAddXp(player)
							if cannotGain then
								if message then sayText = getText(message) end
								perPerkXpRate = false
							end
						end

						if perPerkXpRate~=false then

							if perPerkXpRate <= 0 then perPerkXpRate = 0.01 end
							if currentlyReadXP+perPerkXpRate > journalXP then perPerkXpRate = math.max(journalXP-currentlyReadXP, 0.001) end

							readXP[skill] = readXP[skill]+perPerkXpRate
							jmdUsedXP[skill] = (jmdUsedXP[skill] or 0)+perPerkXpRate

							if perPerkXpRate > 0 then
								local addedXP = SRJ.xpHandler.reBoostXP(player,perk,perPerkXpRate)
								player:getXp():AddXP(perk, addedXP, false, false, true)
							end

							changesMade = true
							self.changesWereMade = true

							local skill_name = getText("IGUI_perks_"..skill)
							if skill_name == ("IGUI_perks_"..skill) then skill_name = skill end
							table.insert(changesBeingMade, skill_name)
						end
					end
				end
			end
		end

		if not self.modDataReadComplete then
			self.modDataReadComplete = true
			local modDataStored = modDataCapture.copyDataToPlayer(player, JMD)
			if modDataStored then
				for _,dataID in pairs(modDataStored) do
					table.insert(changesBeingMade, dataID)
				end
				changesMade = true
				self.changesWereMade = true
			end
		end

		SRJ.correctSandBoxOptions("KillsTrack")
		if JMD and (SandboxVars.SkillRecoveryJournal.KillsTrack or 0) > 0 then

			local readXP = SRJ.getReadXP(player)

			local readZKills = readXP and readXP.kills and readXP.kills.Zombie or 0
			local readSKills = readXP and readXP.kills and readXP.kills.Survivor or 0

			local zKills = player:getZombieKills()
			local sKills = player:getSurvivorKills()

			local jmdZKills = JMD.kills and JMD.kills.Zombie or 0
			local jmdSKills = JMD.kills and JMD.kills.Survivor or 0

			if (jmdZKills > readZKills) or (jmdSKills > readSKills) then
				readXP.kills = readXP.kills or {}
				if jmdZKills > readZKills then
					table.insert(changesBeingMade, getText("IGUI_char_Zombies_Killed"))
					player:setZombieKills(math.max(zKills, jmdZKills))
					readXP.kills.Zombie = jmdZKills
				end
				if jmdSKills > readSKills then
					table.insert(changesBeingMade, getText("IGUI_char_Survivor_Killed"))
					player:setSurvivorKills(math.max(sKills, jmdSKills))
					readXP.kills.Survivor = jmdSKills
				end
				changesMade = true
				self.changesWereMade = true
			end
		end
	end


	if JMD and (not changesMade) then
		delayedStop = true

		if (SandboxVars.SkillRecoveryJournal.RecoveryJournalUsed == true) and SRJ.isJournalFullyDrained(JMD, player) then
			JMD.used = true
			self.markUsedOnComplete = true
		end

		if bJournalUsedUp or JMD.used then
			sayText = getText("IGUI_JournalXPUsedUp")
		elseif (not sayText) then
			sayTextChoices = {"IGUI_PlayerText_KnowSkill","IGUI_PlayerText_BookObsolete"}
			sayText = getText(sayTextChoices[ZombRand(#sayTextChoices)+1])
		end

	end 

	if self.haloTextDelay <= 0 and #changesBeingMade > 0 then
		self.haloTextDelay = 100
		local progressText = math.floor(((totalRedXP - self.oldCharacterXP) / (totalRecoverableXP - self.oldCharacterXP)) * 100 + 0.5) .. "%" 
		local changesBeingMadeText = getText("IGUI_Tooltip_Learning") .." (" .. progressText .. "): "
		for k,v in pairs(changesBeingMade) do
			changesBeingMadeText = changesBeingMadeText.." "..v
			if k~=#changesBeingMade then
				changesBeingMadeText = changesBeingMadeText..", "
			end
		end

		HaloTextHelper:update()
		HaloTextHelper.addText(self.character, changesBeingMadeText, HaloTextHelper.getColorWhite())
	end

	if sayText and not self.spoke then
		self.spoke = true
		player:Say(sayText, 0.55, 0.55, 0.55, UIFont.Dialogue, 0, "default")
	end
	if delayedStop then self:forceStop() end
end


function ReadSkillRecoveryJournal:new(character, item)
	local o = {}
	setmetatable(o, self)
	self.__index = self

	o.character = character
	o.oldCharacterXP = 0
	local charSkills = SRJ.calculateGainedSkills(character) or {}
	for perkID, xp in pairs(charSkills) do
		o.oldCharacterXP = o.oldCharacterXP + xp
	end
	o.item = item

	local journalModData = item:getModData()
	local rawJMD = journalModData["SRJ"] or {}

	-- Snapshot journal data into client-local table
	o.journalData = copyTable(rawJMD)
	o.markUsedOnComplete = false

	o.stopOnWalk = false
	o.stopOnRun = true
	o.loopedAction = true
	o.ignoreHandsWounds = true
	o.caloriesModifier = 0.5
	o.readTimer = -30
	o.forceProgressBar = true
	o.learnedRecipes = {}
	o.learnedTraits = {}
	o.recipeIntervals = 0
	o.traitIntervals = 0
	o.maxTime = -1
	o.haloTextDelay = 0

	local JMD = o.journalData
	if JMD then
		if SandboxVars.SkillRecoveryJournal.RecoverRecipes == true then
			local learnedRecipes = JMD["learnedRecipes"]
			if learnedRecipes then
				for recipeID,_ in pairs(learnedRecipes) do
					if not character:isRecipeKnown(recipeID) then
						table.insert(o.learnedRecipes, recipeID)
					end
				end
			end
		end

		if SandboxVars.SkillRecoveryJournal.RecoverTraits ~= false then
			local learnedTraits = JMD["learnedTraits"]
			if learnedTraits then
				for traitID,_ in pairs(learnedTraits) do
					if not character:HasTrait(traitID) then
						table.insert(o.learnedTraits, traitID)
					end
				end
			end
		end
	end

	return o
end
