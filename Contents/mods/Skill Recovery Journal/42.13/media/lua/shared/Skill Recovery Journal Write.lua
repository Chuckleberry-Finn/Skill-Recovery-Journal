require "TimedActions/ISBaseTimedAction"

local SRJ = require "Skill Recovery Journal Main"

---@class WriteSkillRecoveryJournal : ISBaseTimedAction
WriteSkillRecoveryJournal = ISBaseTimedAction:derive("WriteSkillRecoveryJournal")


-- called on client on many occasions
function WriteSkillRecoveryJournal:isValid()
	if self.character:tooDarkToRead() then
		HaloTextHelper.addBadText(self.character, getText("ContextMenu_TooDark"));
		return false
	end
	local vehicle = self.character:getVehicle()
	if vehicle and vehicle:isDriver(self.character) then return not vehicle:isEngineRunning() or vehicle:getSpeed2D() == 0 end
	
	-- FIXME if :isValid (and :perform) is handled correctly, self.item will be null in :new on server and updateWriting will crash
	--if isClient() and self.item and self.writingTool then
    --    return self.character:getInventory():containsID(self.item:getID()) and self.character:getInventory():containsID(self.writingTool:getID())
    --else
	--	return self.character:getInventory():contains(self.item) and self.character:getInventory():contains(self.writingTool)
	--end
	return self.character:getInventory():contains(self.item) and self.character:getInventory():contains(self.writingTool)
end


-- called on client on client start
function WriteSkillRecoveryJournal:start()
	self.item:setJobDelta(0.0);
	self.item:setJobType(getText("ContextMenu_Write") ..' '.. self.item:getName())
	--self:setAnimVariable("PerformingAction", "TranscribeJournal") -- is not animating
	self:setAnimVariable("ReadType", "book")
	self:setActionAnim(CharacterActionAnims.Read)
	self:setOverrideHandModels(self.writingTool, self.item)
	
	self.character:setReading(true)
	self.character:reportEvent("EventRead")
	
	local logText = ISLogSystem.getGenericLogText(self.character)
	sendClientCommand(self.character, 'ISLogSystem', 'writeLog', {loggerName = "PerkLog", logText = logText.."[SRJ START WRITING]"})
end


-- called on client on client stop
function WriteSkillRecoveryJournal:stop()
	if getDebug() then print("WriteSkillRecoveryJournal stop with changes " .. tostring(self.wroteNewContent) .. " after " .. tostring((getTimestampMs() - self.startTime) * 3600)) end
	self.character:setReading(false);
	self.item:setJobDelta(0.0);
	self.character:playSound("CloseBook")

	local logText = ISLogSystem.getGenericLogText(self.character)
	sendClientCommand(self.character, 'ISLogSystem', 'writeLog', {loggerName = "PerkLog", logText = logText.."[SRJ STOP WRITING] (stop)"})

	ISBaseTimedAction.stop(self)
end


-- called on server on client start
function WriteSkillRecoveryJournal:serverStart()
	--if getDebug() then print("WriteSkillRecoveryJournal serverStart") end
	emulateAnimEvent(self.netAction, 10, "update", nil)
end


-- called on server on client stop
function WriteSkillRecoveryJournal:serverStop()
	if getDebug() then print("WriteSkillRecoveryJournal serverStop after " .. tostring((getTimestampMs() - self.startTime) * 3600)) end
	syncItemModData(self.character, self.item)
end


-- called on client on server complete
function WriteSkillRecoveryJournal:perform()
	print("WriteSkillRecoveryJournal perform")
    self.character:setReading(false);
    self.item:setJobDelta(0.0);
	self.character:playSound("CloseBook")
	local logText = ISLogSystem.getGenericLogText(self.character)
	sendClientCommand(self.character, 'ISLogSystem', 'writeLog', {loggerName = "PerkLog", logText = logText.."[SRJ STOP READING] (perform)"})

	ISBaseTimedAction.perform(self)
end


-- called on server on server complete
function WriteSkillRecoveryJournal:complete()
	if getDebug() then print("WriteSkillRecoveryJournal complete after " .. tostring((getTimestampMs() - self.startTime) * 3600)) end
    self.item:setJobDelta(0.0);
	syncItemModData(self.character, self.item)
	return true
end


-- infinite Timed Action
function WriteSkillRecoveryJournal:getDuration() 
	return -1
end


function WriteSkillRecoveryJournal:animEvent(event, parameter)
	if event == "update" and isServer() then
		-- only on server in MP
		self:updateWriting()
	end
end


-- only on client SP/MP
function WriteSkillRecoveryJournal:update()
	-- if updateTick was reached
	if self:updateWriting() then
		-- handle sound if changes made or MP
		if isClient() then
			-- play sound every 2-6 updates
			self.playSoundLater = self.playSoundLater or 0
			if self.playSoundLater > 0 then
				self.playSoundLater = self.playSoundLater-1
			else
				self.playSoundLater = (ZombRand(2,6) + SRJ.gameTime:getMultiplier())
				self.character:playSound(self.writingToolSound)
			end
		end
	end
end


-- Updates the write journal action if the last update has been longer ago than updateInterval
-- returns true if time for next writing step was reached false otherwise
function WriteSkillRecoveryJournal:updateWriting()
	local now = SRJ.gameTime:getWorldAgeHours()

	-- if time has progressed over planned update time, do update
	if now >= self.updateTime then

		-- plan next update one interval later
		self.updateTime = self.updateTime + self.updateInterval

		self.updates = self.updates + 1

		-- all updating is done by server
		if isClient() then return true end

		---@type IsoGameCharacter | IsoPlayer | IsoMovingObject | IsoObject
		local player = self.character

		local JMD = SRJ.modDataHandler.getItemModData(self.item)
		local changesMade = false

		local journalID = JMD["ID"]
		local pSteamID = player:getSteamID()
		local pUsername = player:getUsername()

		local bOwner = true
		if pSteamID ~= 0 and journalID and journalID["steamID"] and (journalID["steamID"] ~= pSteamID) then bOwner = false end
		if pUsername and journalID and journalID["username"] and (journalID["username"] ~= pUsername) then bOwner = false end
		
		-- write gained recipes
		if bOwner and (#self.gainedRecipes > 0) then
			changesMade = true

			local recipeChunk = self.durationData.recipeChunk
			if recipeChunk and self.updates % self.durationData.recipeInterval == 0 then

				for i=1, recipeChunk do
					local recipeID = self.gainedRecipes[#self.gainedRecipes]
					JMD["learnedRecipes"][recipeID] = true
					table.remove(self.gainedRecipes,#self.gainedRecipes)
					self.changesBeingMadeIndex["recipes"] = (self.changesBeingMadeIndex["recipes"] or 0) + 1
				end
			end
		end

		-- write gained xp
		local storedJournalXP = JMD["gainedXP"]
		local readXP = SRJ.modDataHandler.getReadXP(player)
		local totalRecoverableXP = 1
		local totalStoredXP = 1

		if bOwner and storedJournalXP and self.gainedSkills then
			for perkID,xp in pairs(self.gainedSkills) do
				if xp > 0 then
					totalRecoverableXP = totalRecoverableXP + xp

					storedJournalXP[perkID] = storedJournalXP[perkID] or 0
					if xp > storedJournalXP[perkID] then

						local xpRate = self.durationData.rates[perkID] or 0
						if xpRate>0 then

							changesMade = true

							local skill_name = getTextOrNull("IGUI_perks_"..perkID) or perkID
							if not self.changesBeingMadeIndex[skill_name] then
								self.changesBeingMadeIndex[skill_name] = true
								table.insert(self.changesBeingMade, skill_name)
							end

							local resultingXp = math.min(xp, storedJournalXP[perkID]+xpRate)
							--print("TESTING: "..perkID.." recoverable:"..xp.." gained:"..storedJournalXP[perkID].." +"..xpRate)
							storedJournalXP[perkID] = resultingXp

							-- store amount as already read in player data, so it cant be gained again
							readXP[perkID] = math.max(resultingXp,(readXP[perkID] or 0))
						end
					end
				end
				totalStoredXP = totalStoredXP + (storedJournalXP[perkID] or 0)
			end
		end

		-- write kills if player has more kills than stored
		local writeKills = self.durationData.kills.Zombie > 0 or self.durationData.kills.Survivor > 0
		if writeKills and ((player:getZombieKills() or 0) > (JMD.kills.Zombie or 0)) or ((player:getSurvivorKills() or 0) > (JMD.kills.Survivor or 0)) then
			local zombies, survivor = SRJ.handleKills(self.durationData, player, JMD, false)
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

		-- copy custom mod data to journal
		if not self.modDataStoredComplete then
			self.modDataStoredComplete = true
			local modDataStored = SRJ.modDataHandler.copyDataToJournal(player, self.item)
			if modDataStored then
				for _,dataID in pairs(modDataStored) do
					table.insert(self.changesBeingMade, dataID)
				end
				changesMade = true
			end
		end

		-- end if nothing gained
		if changesMade == false then
			-- give feedback why we stop
			local feedback ="IGUI_PlayerText_NothingToAddToJournal"
			if self.wroteNewContent then
				feedback = "IGUI_PlayerText_AllDoneWithJournal"
			end

			SRJ.showCharacterFeedback(player, feedback)

			-- invoke stop
			if isServer() then
				self.netAction:forceComplete()
			else
				self:forceStop()
			end
		else
			-- we wrote xp
			self.wroteNewContent = true

			if isServer() then
				syncItemModData(player, self.item) -- syncs item tooltip
			end

			-- show transcript progress as halo text every 2 real-time seconds
			local rtNow = getTimestampMs()
			if (rtNow - self.lastUpdateTime) > 2000 then
				-- summarize recipes
				local properPlural = getTextOrNull("IGUI_Tooltip_Recipe") or "Recipe" -- FIXME: Server can not retrieve translation
				local recipeChunk = self.changesBeingMadeIndex["recipes"]
					if recipeChunk and recipeChunk > 0 then
					if recipeChunk>1 then properPlural = getTextOrNull("IGUI_Tooltip_Recipes") or "Recipes" end
					table.insert(self.changesBeingMade, recipeChunk.." "..properPlural)
				end

				SRJ.showHaloProgressText(player, self.changesBeingMade, self.updates, self.durationData.intervals, "IGUI_Tooltip_Transcribing")

				-- reset pending changes
				self.changesBeingMade = {}
				self.changesBeingMadeIndex = {}

				self.lastUpdateTime = rtNow
			end
		end

		return true
	end
	-- return false if tick was skipped
	return false
end


---@param character IsoGameCharacter
function WriteSkillRecoveryJournal:new(character, item, writingTool) --time, recipe, container, containers)
	local now = SRJ.gameTime:getWorldAgeHours()
	if getDebug() then print("WriteSkillRecoveryJournal:new - at " .. tostring(now) .. " isServer "..tostring(isServer()) .. " isClient " .. tostring(isClient())) end 

	local o = ISBaseTimedAction.new(self, character)

	-- vanilla fields
	o.useProgressBar = false
	o.stopOnWalk = false
	o.stopOnRun = true
	o.ignoreHandsWounds = true
	o.caloriesModifier = 0.5

	-- params
	o.character = character
	o.item = item
	o.writingTool = writingTool

	-- SRJ
	o.writingToolSound = "PenWriteSounds"
	if character:getInventory():contains("Pencil") then
		o.writingToolSound = "PencilWriteSounds"
	end

	local JMD = SRJ.modDataHandler.getItemModData(o.item)
	o.gainedRecipes = {}
	if SandboxVars.SkillRecoveryJournal.RecoverRecipes == true then
		local learnedRecipes = JMD["learnedRecipes"]
		local gainedRecipes = SRJ.getGainedRecipes(character, learnedRecipes)
		o.gainedRecipes = gainedRecipes
	end

	o.gainedSkills = SRJ.calculateAllGainedSkills(character) or false
	o.oldJournalTotalXP = 0
	for perkID, xp in pairs(JMD["gainedXP"]) do o.oldJournalTotalXP = o.oldJournalTotalXP + xp end

	o.willWrite = true
	local sayText

	--if getDebug() then print("gainedSkills: "..tostring(#o.gainedSkills)) end

	if not o.gainedSkills and (#o.gainedRecipes <= 0) then
		sayText=getText("IGUI_PlayerText_DontHaveAnyXP"), 0.55, 0.55, 0.55, UIFont.Dialogue, 0, "default"
		o.willWrite = false
	else
		JMD["ID"] = JMD["ID"] or {}
		local journalID = JMD["ID"]
		local pSteamID = character:getSteamID()
		local pUsername = character:getUsername()

		local protections = SandboxVars.SkillRecoveryJournal.SecurityFeatures or 1
		---1 = "Prevent Username/SteamID Mismatch"
		---2 = "Only Prevent SteamID Mismatch",
		---3 = "Don't Prevent Mismatches",

		if (protections<=2) and pSteamID ~= 0 then
			if journalID["steamID"] and (journalID["steamID"] ~= pSteamID) then
				sayText=getText("IGUI_PlayerText_DoesntFeelRightToWrite"), 0.55, 0.55, 0.55, UIFont.Dialogue, 0, "default"
				o.willWrite = false
			end
			if o.willWrite and pSteamID then
				journalID["steamID"] = pSteamID
			end
		end

		if (protections==1) then
			if pUsername and journalID["username"] and (journalID["username"] ~= pUsername) then
				sayText=getText("IGUI_PlayerText_DoesntFeelRightToWrite"), 0.55, 0.55, 0.55, UIFont.Dialogue, 0, "default"
				o.willWrite = false
			end

			if o.willWrite and pUsername and (not journalID["username"]) then
				journalID["username"] = pUsername
			end
		end
	end

	if character:hasTrait(CharacterTrait.ILLITERATE) then
		local sayTextChoices = {"IGUI_PlayerText_DontUnderstand", "IGUI_PlayerText_TooComplicated", "IGUI_PlayerText_DontGet"}
		sayText=getText(sayTextChoices[ZombRand(#sayTextChoices)+1]).." ("..getText("UI_trait_Illiterate")..")"
		o.willWrite = false
	end

	if sayText then character:Say(sayText) end
	if o.willWrite then JMD["author"] = character:getFullName() end

	-- timings, update intervals between updates in in-game hours
	o.updateInterval = 10 / 3600 -- every in-game 10 seconds
	o.defaultUpdateInterval = 3.48 / 3600 -- legacy ~ 3.48 sec to maintain old duration
	o.timeFactor = (o.updateInterval / o.defaultUpdateInterval)
	o.updateTime = now + o.updateInterval -- do first update after one interval
	
	o.updates = -1 -- update counter

	o.lastUpdateTime = 0
	o.startTime = getTimestampMs()

	o.durationData = SRJ.xpHandler.calculateReadWriteXpRates(SRJ, character, item, o.timeFactor, o.gainedRecipes, o.gainedSkills, false, o.updateInterval)

	o.changesBeingMade = {}
	o.changesBeingMadeIndex = {}

	return o
end