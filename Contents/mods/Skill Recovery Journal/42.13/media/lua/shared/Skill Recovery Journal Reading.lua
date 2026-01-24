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

		self.updates = self.updates + 1

		---@type IsoGameCharacter | IsoPlayer | IsoMovingObject | IsoObject
		local player = self.character

		local JMD = SRJ.modDataHandler.getItemModData(journal)
		local changesMade = false
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

		local oneTimeUse = (SandboxVars.SkillRecoveryJournal.RecoveryJournalUsed == true)
		if not delayedStop then

			-- apply read recipes
			if (#self.learnedRecipes > 0) then
				changesMade = true

				local recipeChunk = self.durationData.recipeChunk
				if recipeChunk > 0 and self.updates % self.durationData.recipeInterval == 0 then

					for i=1, recipeChunk do
						if #self.learnedRecipes > 0 then
							local recipeID = self.learnedRecipes[#self.learnedRecipes]
							if recipeID then player:learnRecipe(recipeID) end
							table.remove(self.learnedRecipes,#self.learnedRecipes)
							self.changesBeingMadeIndex["recipes"] = (self.changesBeingMadeIndex["recipes"] or 0) + 1
						end
					end
				end
			end

			-- apply read xp
			local XpStoredInJournal = JMD["gainedXP"]
			local greatestXp = 0

			local validSkills = {}

			local readXP = SRJ.modDataHandler.getReadXP(player)
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


				JMD.recoveryJournalXpLog = JMD.recoveryJournalXpLog or {}
				local jmdUsedXP = JMD.recoveryJournalXpLog

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
								local skill_name = getTextOrNull("IGUI_perks_"..perkID) or perkID
								if not self.changesBeingMadeIndex[skill_name] then
									self.changesBeingMadeIndex[skill_name] = true
									table.insert(self.changesBeingMade, skill_name)
								end
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
						table.insert(self.changesBeingMade, dataID)
					end
					changesMade = true
				end
			end

			-- read kills if journal contains more kills than previously read
			local readKills = self.durationData.kills.Zombie > 0 or self.durationData.kills.Survivor > 0
			if readKills and (((JMD.kills.Zombie or 0) > (readXP.kills.Zombie or 0)) or ((JMD.kills.Survivor or 0) > (readXP.kills.Survivor or 0))) then
				local zombies, survivor = SRJ.handleKills(self.durationData, player, JMD, true)
				if survivor and not self.changesBeingMadeIndex["survivorKills"] then
					table.insert(self.changesBeingMade, getText("IGUI_char_Survivor_Killed"))
					self.changesBeingMadeIndex["survivorKills"] = true
					changesMade = true
				end
				if zombies and not self.changesBeingMadeIndex["zombieKills"] then
					table.insert(self.changesBeingMade, getText("IGUI_char_Zombies_Killed"))
					self.changesBeingMadeIndex["zombieKills"] = true
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
			if self.updates % 4 == 0 then -- show halo text every 4th update
				-- summarize recipes
				local properPlural = getTextOrNull("IGUI_Tooltip_Recipe") or "Recipe" -- FIXME: Server can not retrieve translation
				local recipeChunk = self.changesBeingMadeIndex["recipes"]
					if recipeChunk and recipeChunk > 0 then
					if recipeChunk>1 then properPlural = getTextOrNull("IGUI_Tooltip_Recipes") or "Recipes" end
					table.insert(self.changesBeingMade, recipeChunk.." "..properPlural)
				end

				SRJ.showHaloProgressText(player, self.changesBeingMade, self.updates, self.durationData.intervals, "IGUI_Tooltip_Learning")

				-- reset pending changes
				self.changesBeingMade = {}
				self.changesBeingMadeIndex = {}
			end

			-- sync modData to show journal decay tooltip
			if oneTimeUse and isServer() then
				syncItemModData(player, journal)
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
	if getDebug() then print("ReadSkillRecoveryJournal:new - at " .. tostring(now) .. " isServer "..tostring(isServer()) .. " isClient " .. tostring(isClient())) end 

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
	o.timeFactor = (o.updateInterval / o.defaultUpdateInterval)
	o.updateTime = now + o.updateInterval -- do first update after one interval
	
	o.updates = -1 -- update counter

	-- for debug
	o.lastUpdateTime = now
	o.startTime = now
	
	o.durationData = SRJ.xpHandler.calculateReadWriteXpRates(SRJ, character, item, o.timeFactor, o.learnedRecipes, nil, true, o.updateInterval)

	o.changesBeingMade = {}
	o.changesBeingMadeIndex = {}

	return o
end
