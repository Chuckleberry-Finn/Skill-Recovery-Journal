require "TimedActions/ISBaseTimedAction"

local SRJ = require "Skill Recovery Journal Main"

---@class ReadSkillRecoveryJournal : ISBaseTimedAction
ReadSkillRecoveryJournal = ISBaseTimedAction:derive("ReadSkillRecoveryJournal")


function ReadSkillRecoveryJournal:isValid()
	if self.character:tooDarkToRead() then
		HaloTextHelper.addBadText(self.character, getText("ContextMenu_TooDark"));
		return false
	end
	local vehicle = self.character:getVehicle()
	if vehicle and vehicle:isDriver(self.character) then return not vehicle:isEngineRunning() or vehicle:getSpeed2D() == 0 end
	return self.character:getInventory():contains(self.item)
end


function ReadSkillRecoveryJournal:start()
	self.item:setJobDelta(0.0);
	self.item:setJobType(getText("ContextMenu_Read") ..' '.. self.item:getName())
	self:setAnimVariable("ReadType", "book")
	self:setActionAnim(CharacterActionAnims.Read)
	self:setOverrideHandModels(nil, self.item)

	self.character:setReading(true)
	self.character:reportEvent("EventRead")

	local logText = ISLogSystem.getGenericLogText(self.character)
	sendClientCommand(self.character, 'ISLogSystem', 'writeLog', {loggerName = "PerkLog", logText = logText.."[SRJ START READING]"})
end


function ReadSkillRecoveryJournal:stop()
	if getDebug() then print("ReadSkillRecoveryJournal stop after " .. tostring((SRJ.gameTime:getWorldAgeHours() - self.startTime) * 3600)) end
	self.character:setReading(false);
	self.item:setJobDelta(0.0);
	self.character:playSound("CloseBook")

	local logText = ISLogSystem.getGenericLogText(self.character)
	sendClientCommand(self.character, 'ISLogSystem', 'writeLog', {loggerName = "PerkLog", logText = logText.."[SRJ STOP READING] (stop)"})

	ISBaseTimedAction.stop(self)
end


-- called on server on client start
function ReadSkillRecoveryJournal:serverStart()
	--if getDebug() then print("ReadSkillRecoveryJournal serverStart") end
	emulateAnimEvent(self.netAction, 10, "update", nil)
end


function ReadSkillRecoveryJournal:serverStop()
	--if getDebug() then print("ReadSkillRecoveryJournal serverStop") end
	syncItemModData(self.character, self.item)
end


function ReadSkillRecoveryJournal:perform()
	self.character:setReading(false)
	self.item:setJobDelta(0.0);
	self.item:getContainer():setDrawDirty(true)
	
	local logText = ISLogSystem.getGenericLogText(self.character)
	sendClientCommand(self.character, 'ISLogSystem', 'writeLog', {loggerName = "PerkLog", logText = logText.."[SRJ STOP READING] (perform)"})
	
	ISBaseTimedAction.perform(self)
end


function ReadSkillRecoveryJournal:complete()
	if getDebug() then print("WriteSkillRecoveryJournal complete") end
	self.item:setJobDelta(0.0);
	syncItemModData(self.character, self.item)
	return true
end

-- infinite Timed Action
function ReadSkillRecoveryJournal:getDuration() 
	return -1
end


function ReadSkillRecoveryJournal:animEvent(event, parameter)
	if event == "PageFlip" then
		if getGameSpeed() ~= 1 then return end
		self.character:playSound("PageFlipBook")
	elseif event == "update" and isServer() then
		self:updateReading()
	end
end


function ReadSkillRecoveryJournal:determineDuration(journalModData)
	local durationData = {
		rates = {},
		intervals = 0,
		recipeChunk = 0,
		kills = {},
	}

	local storedJournalXP = journalModData["gainedXP"]

	local readTimeMulti = SandboxVars.SkillRecoveryJournal.ReadTimeSpeed or 1
	local timeFactor = (self.updateInterval / self.defaultUpdateInterval)

	--recipes
	if (#self.learnedRecipes > 0) then
		durationData.recipeChunk = math.min(#self.learnedRecipes, math.floor(1.09^math.sqrt(#self.learnedRecipes))) * readTimeMulti
		local intervalsNeeded = math.ceil((durationData.recipeChunk * 5))
		durationData.intervals = math.max(intervalsNeeded,durationData.intervals)
	end

	--kills
	local readXP = SRJ.modDataHandler.getReadXP(self.character)

	local readZKills = readXP and readXP.kills and readXP.kills.Zombie or 0
	local readSKills = readXP and readXP.kills and readXP.kills.Survivor or 0

	local jmdZKills = journalModData.kills and journalModData.kills.Zombie
	local jmdSKills = journalModData.kills and journalModData.kills.Survivor

	local unaccountedZKills = jmdZKills and (jmdZKills > readZKills) and jmdZKills-readZKills
	if unaccountedZKills and unaccountedZKills > 0 then durationData.zombies = unaccountedZKills end

	local unaccountedSKills = jmdSKills and (jmdSKills > readSKills) and jmdSKills-readSKills
	if unaccountedSKills and unaccountedSKills > 0 then durationData.survivors = unaccountedSKills end

	if (unaccountedZKills and unaccountedZKills > 0) or (unaccountedSKills and unaccountedSKills > 0) then
		durationData.intervals = durationData.intervals+1
	end

	--modData
	--- the CopyData function actually does the copying - we need a function to JUST check if the data exists for this step
	local modDataStored = SRJ.modDataHandler.copyDataToPlayer(self.character, self.item)
	if modDataStored then durationData.intervals = durationData.intervals+1 end

	--xp
	if storedJournalXP then

		local greatestXp = 0
		--local totalRecoverableXP = 0
		--local totalReadXP = 0
		---need to spend more time pulling calculations that don't need to occur every tick to here and storing it in the duration-data
		local validSkills = {}
		local bJournalUsedUp = false

		for skill,xp in pairs(storedJournalXP) do
			local perk = Perks[skill]
			if perk then
				local valid, percent = SRJ.bSkillValid(perk)
				if valid then
					validSkills[skill] = true
					if skill=="NONE" or skill=="MAX" then
						storedJournalXP[skill] = nil
					else
						if xp > greatestXp then greatestXp = xp end
					end
				end
			end
		end

		journalModData.recoveryJournalXpLog = journalModData.recoveryJournalXpLog or {}
		local jmdUsedXP = journalModData.recoveryJournalXpLog

		local oneTimeUse = (SandboxVars.SkillRecoveryJournal.RecoveryJournalUsed == true)

		for perkID,xp in pairs(storedJournalXP) do
			--totalRecoverableXP = totalRecoverableXP + xp
			if Perks[perkID] and validSkills[perkID] then

				readXP[perkID] = readXP[perkID] or 0
				local currentlyReadXP = readXP[perkID]
				--totalReadXP = totalReadXP + currentlyReadXP
				local journalXP = xp

				if oneTimeUse and jmdUsedXP[perkID] and jmdUsedXP[perkID] then
					if jmdUsedXP[perkID] >= currentlyReadXP then bJournalUsedUp = true end
					currentlyReadXP = math.max(currentlyReadXP, jmdUsedXP[perkID])
				end

				if currentlyReadXP < journalXP then

					local perkLevelPlusOne = self.character:getPerkLevel(Perks[perkID])+1
					local differential = SRJ.getMaxXPDifferential(perkID) or 1
					local xpRate = round((((math.sqrt(xp) / 25) * math.sqrt(perkLevelPlusOne)) * 1000) / 1000 * readTimeMulti * timeFactor / differential, 2)
					if perkLevelPlusOne == 11 then xpRate=false end

					if perkID=="Fitness" then
						local cannotGain, message = SRJ.checkFitnessCanAddXp(self.character)
						if cannotGain then
							xpRate = false
						end
					end

					if xpRate and xpRate>0 then
						local recoverableXpForPerk = journalXP-currentlyReadXP
						durationData.rates[perkID] = xpRate
						local intervalsNeeded = math.ceil((recoverableXpForPerk/xpRate))
						print(" - ",perkID, "- xprate = ",xpRate,", ",recoverableXpForPerk, " (",intervalsNeeded,")")
						durationData.intervals = math.max(intervalsNeeded, durationData.intervals)
					end
				end
			end
		end
	end

	durationData.durationTime = durationData.intervals * self.updateInterval * 60 * 60 * 3

	if getDebug() then print("SRJ DEBUG DURATION (in ticks) ", durationData.intervals, " (in in-game time) ", durationData.durationTime) for k,v in pairs(durationData.rates) do print(" - ",k," = ",v) end end

	return durationData
end


function ReadSkillRecoveryJournal:update()
	-- in MP, all updating is done by server
	if not isClient() then 
		self:updateReading()
	end
end


function ReadSkillRecoveryJournal:updateReading()
	local now = SRJ.gameTime:getWorldAgeHours()

	---@type Literature
	local journal = self.item

	local bJournalUsedUp = false

	-- normalize update time via in game time. Adjust updateInterval as needed
	if now >= self.updateTime then
		--print("update after " ..  tostring((now - self.lastUpdateTime) * 60 * 60) .. " in-game seconds -> lastUpdate " .. tostring(self.lastUpdateTime))
		self.lastUpdateTime = now or 0 -- for debug

		-- plan next update one interval later
		self.updateTime = self.updateTime + self.updateInterval

		---@type IsoGameCharacter | IsoPlayer | IsoMovingObject | IsoObject
		local player = self.character

		local JMD = SRJ.modDataHandler.getItemModData(journal)
		local changesMade = false
		local changesBeingMade = {}
		local delayedStop = false
		local sayText
		local sayTextChoices = {"IGUI_PlayerText_DontUnderstand", "IGUI_PlayerText_TooComplicated", "IGUI_PlayerText_DontGet"}
		local totalRecoverableXP = 0
		local totalReadXP = 0

		local pSteamID = player:getSteamID()
		local pUsername = player:getUsername()

		-- check permissions
		if (not JMD) or (not JMD["ID"]) then
			delayedStop = true
			sayText = getText("IGUI_PlayerText_NothingWritten")

		elseif self.character:hasTrait(CharacterTrait.ILLITERATE) then
			delayedStop = true
			sayText = getText("IGUI_PlayerText_IGUI_PlayerText_Illiterate"..ZombRand(2)+1)-- 0,1 + 1

		else
			local journalID = JMD["ID"]

			local protections = SandboxVars.SkillRecoveryJournal.SecurityFeatures or 1
			---1 = "Prevent Username/SteamID Mismatch"
			---2 = "Only Prevent SteamID Mismatch",
			---3 = "Don't Prevent Mismatches",

			if (protections<=2) and journalID["steamID"] and (journalID["steamID"] ~= pSteamID) then
				delayedStop = true
				sayText = getText("IGUI_PlayerText_DoesntFeelRightToRead")
			end

			if (protections==1) and journalID["username"] and (journalID["username"] ~= pUsername) then
				delayedStop = true
				sayText = getText("IGUI_PlayerText_DoesntFeelRightToRead")
			end
		end

		if not delayedStop then

			-- apply read recipes
			if (#self.learnedRecipes > 0) then

				self.recipeIntervals = self.recipeIntervals+1
				changesMade = true

				if self.recipeIntervals > 5 then
					local recipeChunk = self.durationData.recipeChunk
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

			-- apply read xp
			local XpStoredInJournal = JMD["gainedXP"]
			local greatestXp = 0

			local validSkills = {}

			if XpStoredInJournal then
				for skill,xp in pairs(XpStoredInJournal) do
					local perk = Perks[skill]
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

				local readXP = SRJ.modDataHandler.getReadXP(player)

				JMD.recoveryJournalXpLog = JMD.recoveryJournalXpLog or {}
				local jmdUsedXP = JMD.recoveryJournalXpLog

				local oneTimeUse = (SandboxVars.SkillRecoveryJournal.RecoveryJournalUsed == true)

				for perkID,xp in pairs(XpStoredInJournal) do
					totalRecoverableXP = totalRecoverableXP + xp
					if Perks[perkID] and validSkills[perkID] then

						readXP[perkID] = readXP[perkID] or 0
						local currentlyReadXP = readXP[perkID]
						totalReadXP = totalReadXP + currentlyReadXP
						local journalXP = xp

						if oneTimeUse and jmdUsedXP[perkID] and jmdUsedXP[perkID] then
							if jmdUsedXP[perkID] >= currentlyReadXP then bJournalUsedUp = true end
							currentlyReadXP = math.max(currentlyReadXP, jmdUsedXP[perkID])
						end

						if currentlyReadXP < journalXP then

							local perkLevelPlusOne = player:getPerkLevel(Perks[perkID])+1
							local perPerkXpRate = self.durationData.rates[perkID] or 0
							if perkLevelPlusOne == 11 then perPerkXpRate=false end

							if perkID=="Fitness" then
								local cannotGain, message = SRJ.checkFitnessCanAddXp(player)
								if cannotGain then
									if message then sayText = getText(message) end
									perPerkXpRate = false
								end
							end

							--print("TESTING:  perPerkXpRate:"..perPerkXpRate.."  perkLevel:"..(perkLevelPlusOne-1).."  xpStored:"..xp.."  currentXP:"..currentlyReadXP)

							if perPerkXpRate~=false and perPerkXpRate > 0 then
								-- normalize perPerkXpRate
								if currentlyReadXP+perPerkXpRate > journalXP then perPerkXpRate = math.max(journalXP-currentlyReadXP, 0.001) end

								-- store amount already red in player data
								readXP[perkID] = readXP[perkID]+perPerkXpRate
								-- and in journal for decay
								jmdUsedXP[perkID] = (jmdUsedXP[perkID] or 0)+perPerkXpRate

								-- send add xp to server
								local addedXP = SRJ.xpHandler.reBoostXP(player,Perks[perkID],perPerkXpRate)
								addXpNoMultiplier(player, Perks[perkID], addedXP)

								changesMade = true

								-- build halo text
								local skill_name = getText("IGUI_perks_"..perkID)
								if skill_name == ("IGUI_perks_"..perkID) then skill_name = perkID end
								table.insert(changesBeingMade, skill_name)
							end
						end
					end
				end
			end

			-- apply stored custom mod data
			if not self.modDataReadComplete then
				self.modDataReadComplete = true
				local modDataStored = SRJ.modDataHandler.copyDataToPlayer(player, journal)
				if modDataStored then
					for _,dataID in pairs(modDataStored) do
						table.insert(changesBeingMade, dataID)
					end
					changesMade = true
				end
			end

			-- apply stored player kills
			if JMD and (SandboxVars.SkillRecoveryJournal.KillsTrack or 0) > 0 then

				--JMD.kills = {}
				local readXP = SRJ.modDataHandler.getReadXP(player)

				local zKills = player:getZombieKills()
				local sKills = player:getSurvivorKills()

				local unaccountedZKills = self.durationData.kills and self.durationData.kills.zombie
				local unaccountedSKills = self.durationData.kills and self.durationData.kills.survivor

				if unaccountedZKills or unaccountedSKills then
					readXP.kills = readXP.kills or {}
					if unaccountedZKills then
						table.insert(changesBeingMade, getText("IGUI_char_Zombies_Killed"))
						player:setZombieKills(zKills + unaccountedZKills)
						readXP.kills.Zombie = (readXP.kills.Zombie or 0) + unaccountedZKills
					end
					if unaccountedSKills then
						table.insert(changesBeingMade, getText("IGUI_char_Survivor_Killed"))
						player:setSurvivorKills(sKills + unaccountedSKills)
						readXP.kills.Survivor = (readXP.kills.Survivor or 0) + unaccountedSKills
					end
					changesMade = true
				end
			end
		end

		-- handle no changes made
		if JMD and (not changesMade) then
			delayedStop = true

			if bJournalUsedUp then
				sayText = getText("IGUI_JournalXPUsedUp")
			elseif (not sayText) then
				sayTextChoices = {"IGUI_PlayerText_KnowSkill"}
				sayText = getText(sayTextChoices[ZombRand(#sayTextChoices)+1])
			end
		end 

		-- show player text
		if sayText and not self.spoke then
			self.spoke = true
			SRJ.showCharacterFeedback(player, sayText)
		else
			-- show halo text
			self.haloTextIntervals = self.haloTextIntervals + 1
				if self.haloTextIntervals < 1 or self.haloTextIntervals > 3 then
				self.haloTextIntervals = 0

				SRJ.showHaloProgressText(self.character, changesBeingMade, totalReadXP, totalRecoverableXP, self.oldCharacterXP, "IGUI_Tooltip_Learning")
			end
		end

		-- invoke stop
		if delayedStop then 
			if isServer() then
				self.netAction:forceComplete()
			else
				self:forceStop()
			end
		end
	end
end


function ReadSkillRecoveryJournal:new(character, item)
	local now = SRJ.gameTime:getWorldAgeHours()
	local o = ISBaseTimedAction.new(self, character)

	o.character = character
	o.item = item

	o.stopOnWalk = false
	o.stopOnRun = true
	o.loopedAction = false
	o.ignoreHandsWounds = true
	o.forceProgressBar = true
	o.caloriesModifier = 0.5

	o.readTimer = -30
	o.forceProgressBar = true
	o.learnedRecipes = {}
	o.recipeIntervals = 0
	--o.maxTime = -1
	o.haloTextDelay = 0

	o.oldCharacterXP = 0 -- used for progress percentage
	local charSkills = SRJ.calculateAllGainedSkills(character) or {}
	for perkID, xp in pairs(charSkills) do
		o.oldCharacterXP = o.oldCharacterXP + xp
	end

	o.learnedRecipes = {}
	local JMD = SRJ.modDataHandler.getItemModData(item)
	if JMD then
		if SandboxVars.SkillRecoveryJournal.RecoverRecipes == true then
			local learnedRecipes = JMD["learnedRecipes"]
			if learnedRecipes then
				for recipeID,_ in pairs(learnedRecipes) do
					if not character:isRecipeActuallyKnown(recipeID) then
						table.insert(o.learnedRecipes, recipeID)
					end
				end
			end
		end
	end

	-- timings,  update intervals between updates in in-game hours
	o.updateInterval = 10 / 3600 -- every in-game 10 seconds
	o.defaultUpdateInterval = 3.48 / 3600 -- legacy ~ 3.48 sec to maintain old duration
	o.updateTime = now + o.updateInterval -- do first update after one interval
	
	o.recipeIntervals = 0 -- counter for recipe ticks
	o.haloTextIntervals = -1

	-- for debug
	o.lastUpdateTime = now
	o.startTime = now
	
	o.durationData = o:determineDuration(JMD)

	return o
end
