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
	
	-- FIXME#4 if :isValid (and :perform) is handled correctly, self.item will be null in :new on server and updateWriting will crash
	--if isClient() and self.item and self.writingTool then
    --    return self.character:getInventory():containsID(self.item:getID()) and self.character:getInventory():containsID(self.writingTool:getID())
    --else
	--	return self.character:getInventory():contains(self.item) and self.character:getInventory():contains(self.writingTool)
	--end
	return self.character:getInventory():contains(self.item) and self.character:getInventory():contains(self.writingTool)
end


-- called on client on client start
function WriteSkillRecoveryJournal:start()
	self.action:setUseProgressBar(false) --TODO: Config
	self.action:setTime(-1)
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
	print("WriteSkillRecoveryJournal stop with changes " .. tostring(self.wroteNewContent) .. " after " .. tostring(SRJ.gameTime:getWorldAgeHours() - self.startTime))
	self.character:setReading(false);
	self.character:playSound("CloseBook")
	local logText = ISLogSystem.getGenericLogText(self.character)
	sendClientCommand(self.character, 'ISLogSystem', 'writeLog', {loggerName = "PerkLog", logText = logText.."[SRJ STOP WRITING] (stop)"})

	ISBaseTimedAction.stop(self)
end


-- called on server on client start
function WriteSkillRecoveryJournal:serverStart()
	--if getDebug() then print("WriteSkillRecoveryJournal serverStart") end
	print("WriteSkillRecoveryJournal serverStart")
	emulateAnimEvent(self.netAction, 10, "update", nil)
end


-- called on server on client stop
function WriteSkillRecoveryJournal:serverStop()
    --self.character:setReading(false);

	--if getDebug() then print("WriteSkillRecoveryJournal serverStop") end
	print("WriteSkillRecoveryJournal serverStop after " .. tostring(SRJ.gameTime:getWorldAgeHours() - self.startTime))
	syncItemModData(self.character, self.item)
end


-- called on client on server complete
function WriteSkillRecoveryJournal:perform()
	print("WriteSkillRecoveryJournal perform")

    self.character:setReading(false);
	self.character:playSound("CloseBook")
	local logText = ISLogSystem.getGenericLogText(self.character)
	sendClientCommand(self.character, 'ISLogSystem', 'writeLog', {loggerName = "PerkLog", logText = logText.."[SRJ STOP READING] (perform)"})

	ISBaseTimedAction.perform(self)
end


-- called on server on server complete
function WriteSkillRecoveryJournal:complete()
	print("WriteSkillRecoveryJournal complete after " .. tostring(SRJ.gameTime:getWorldAgeHours() - self.startTime))
	syncItemModData(self.character, self.item)
	return true
end


-- infinite Timed Action
function WriteSkillRecoveryJournal:getDuration() 
	return -1
end


function WriteSkillRecoveryJournal:animEvent(event, parameter)
	if event == "update" then
		-- only on server in MP
		if isServer() then
			self:updateWriting()
		end
	end
end


function WriteSkillRecoveryJournal:finish()
	if isServer() then
		self.netAction:forceComplete()
	else
		-- FIXME#5: feedback only visible when called on client
		if self.wroteNewContent or isClient() then -- FIXME#3: client does not know if we actually wrote stuff...
			self.character:Say(getText("IGUI_PlayerText_AllDoneWithJournal"), 0.55, 0.55, 0.55, UIFont.Dialogue, 0, "default")
		else
			self.character:Say(getText("IGUI_PlayerText_NothingToAddToJournal"), 0.55, 0.55, 0.55, UIFont.Dialogue, 0, "default")
		end

		self:forceStop()
	end
end


-- only on client SP/MP
function WriteSkillRecoveryJournal:update()
	if not self.loopedAction then return end

	-- if updateTick was reached
	if self:updateWriting() then
		-- handle sound if changes made or MP
		if self.changesMade==true or isClient() then
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

	-- on client, handle halotext FIXME#2: timing is off, should not use getMultipier in MP
	self.haloTextDelay = self.haloTextDelay - (SRJ.gameTime:getMultiplier() or 0)
	-- debug things - remove later
	self.lastUpdateTime = now or 0
	self.writeTimer = 0

	self.writeTimer = (now - (self.lastUpdateTime or 0))
	--self.writeTimer = self.writeTimer + (SRJ.gameTime:getMultiplier() or 0)

	--print("WriteSkillRecoveryJournal updateWriting")
	--print("write timer: ".. tostring(self.writeTimer))

	-- if time has progressed over planned update time, do update
	if now >= self.updateTime then
		--print("update after " ..  tostring(self.writeTimer * 60 * 60) .. " in-game seconds -> " .. tostring(self.writeTimer))

		-- plan next update one interval later
		self.updateTime = self.updateTime + self.updateInterval

		-- all updating is done by server
		if isClient() then
			return true
		end

		self.changesMade = false

		local changesBeingMade, changesBeingMadeIndex = {}, {}

		local JMD = SRJ.modDataHandler.getItemModData(self.item)
		local journalID = JMD["ID"]
		local pSteamID = self.character:getSteamID()
		local pUsername = self.character:getUsername()

		local bOwner = true
		if pSteamID ~= 0 and journalID and journalID["steamID"] and (journalID["steamID"] ~= pSteamID) then bOwner = false end
		if pUsername and journalID and journalID["username"] and (journalID["username"] ~= pUsername) then bOwner = false end

		local transcribeTimeMulti = SandboxVars.SkillRecoveryJournal.TranscribeSpeed or 1

		-- write gained recipes
		if bOwner and (#self.gainedRecipes > 0) then
			self.recipeIntervals = self.recipeIntervals+1
			self.changesMade = true

			if self.recipeIntervals > 5 then
				local recipeChunk = math.min(#self.gainedRecipes, math.floor(1.09^math.sqrt(#self.gainedRecipes))) * transcribeTimeMulti

				local properPlural = getText("IGUI_Tooltip_Recipe")
				if recipeChunk>1 then
					properPlural = getText("IGUI_Tooltip_Recipes")
				end
				table.insert(changesBeingMade, recipeChunk.." "..properPlural)

				for i=0, recipeChunk do
					local recipeID = self.gainedRecipes[#self.gainedRecipes]
					JMD["learnedRecipes"][recipeID] = true
					table.remove(self.gainedRecipes,#self.gainedRecipes)
				end
				self.recipeIntervals = 0
			end
		end

		-- write gained xp
		local storedJournalXP = JMD["gainedXP"]
		local readXp = SRJ.modDataHandler.getReadXP(self.character)
		local totalRecoverableXP = 1
		local totalStoredXP = 1

		if bOwner and storedJournalXP and self.gainedSkills then
			for perkID,xp in pairs(self.gainedSkills) do
				if xp > 0 then
					totalRecoverableXP = totalRecoverableXP + xp

					storedJournalXP[perkID] = storedJournalXP[perkID] or 0
					if xp > storedJournalXP[perkID] then

						local perkLevelPlusOne = self.character:getPerkLevel(Perks[perkID])+1

						local differential = SRJ.getMaxXPDifferential(perkID) or 1

						local xpRate = math.sqrt(xp)/25

						local timeFactor = (self.updateInterval / self.defaultUpdateInterval)

						--print("xpRate: ", xpRate, "  perkLevelPlusOne: ", perkLevelPlusOne, "  differential: ", differential, " timeFactor: ", timeFactor)

						xpRate = round(((xpRate*math.sqrt(perkLevelPlusOne))*1000)/1000 * transcribeTimeMulti * timeFactor / differential, 2)

						if xpRate>0 then
							self.changesMade = true

							local skill_name = getTextOrNull("IGUI_perks_"..perkID) or perkID

							if not changesBeingMadeIndex[skill_name] then
								changesBeingMadeIndex[skill_name] = true
								table.insert(changesBeingMade, skill_name)
							end

							local resultingXp = math.min(xp, storedJournalXP[perkID]+xpRate)
							--print("TESTING: "..perkID.." recoverable:"..xp.." gained:"..storedJournalXP[perkID].." +"..xpRate)
							storedJournalXP[perkID] = resultingXp

							-- store amount as already red in player data, so it cant be gained again
							readXp[perkID] = math.max(resultingXp,(readXp[perkID] or 0))
						end
					end
				end
				totalStoredXP = totalStoredXP + (storedJournalXP[perkID] or 0)
			end
		end

		-- store player kills
		local killsRecoveryPercentage = SandboxVars.SkillRecoveryJournal.KillsTrack or 0
		if JMD and killsRecoveryPercentage > 0 then

			local zKills = math.floor(self.character:getZombieKills() * (killsRecoveryPercentage/100) )
			local sKills = math.floor(self.character:getSurvivorKills() * (killsRecoveryPercentage/100) )

			JMD.kills = JMD.kills or {}
			readXp.kills = readXp.kills or {}

			local zombieKills = (JMD.kills.Zombie or 0)
			local survivorKills = (JMD.kills.Survivor or 0)

			local unaccountedZKills = (zKills > zombieKills) and zKills-zombieKills
			local unaccountedSKills = (sKills > survivorKills) and sKills-survivorKills

			if unaccountedZKills or unaccountedSKills then
				if unaccountedZKills then
					table.insert(changesBeingMade, getText("IGUI_char_Zombies_Killed"))
					JMD.kills.Zombie = (JMD.kills.Zombie or 0) + unaccountedZKills
					readXp.kills.Zombie = (readXp.kills.Zombie or 0) + unaccountedZKills
				end
				if unaccountedSKills then
					table.insert(changesBeingMade, getText("IGUI_char_Survivor_Killed"))
					JMD.kills.Survivor = (JMD.kills.Survivor or 0) + unaccountedSKills
					readXp.kills.Survivor = (readXp.kills.Survivor or 0) + unaccountedSKills
				end
				self.changesMade = true
			end
		end

		-- copy custom mod data to journal
		if not self.modDataStoredComplete then
			self.modDataStoredComplete = true
			local modDataStored = SRJ.modDataHandler.copyDataToJournal(self.character, self.item)
			if modDataStored then
				for _,dataID in pairs(modDataStored) do
					table.insert(changesBeingMade, dataID)
				end
				self.changesMade = true
			end
		end

		-- end if nothing gained
		if self.changesMade == false then
			self:finish()
		else
			self.wroteNewContent = true

			-- show transcript progress as halo text, prevent overlapping addTexts
			if self.haloTextDelay <= 0 and #changesBeingMade > 0 then
				self.haloTextDelay = 100
				if not isServer() then
					SRJ.handleHaloText(self.character, changesBeingMade, totalStoredXP, totalRecoverableXP, self.oldJournalTotalXP, "IGUI_Tooltip_Transcribing")
				else
					local args = {}
					args.changesBeingMade = changesBeingMade
					args.totalStoredXP = totalStoredXP
					args.totalRecoverableXP = totalRecoverableXP
					args.oldJournalTotalXP = self.oldJournalTotalXP
					sendServerCommand(self.character, "SkillRecoveryJournal", "write_changes", args)
					syncItemModData(self.character, self.item)
				end
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
	print("WriteSkillRecoveryJournal:new - at " .. tostring(now) .. " isServer "..tostring(isServer()) .. " isClient " .. tostring(isClient()))

	local o = ISBaseTimedAction.new(self, character);
	setmetatable(o, self)
	self.__index = self

	o.character = character
	o.item = item
	o.writingTool = writingTool

	local JMD = SRJ.modDataHandler.getItemModData(o.item)

	o.writingToolSound = "PenWriteSounds"
	if character:getInventory():contains("Pencil") then
		o.writingToolSound = "PencilWriteSounds"
	end

	o.gainedRecipes = {}
	if SandboxVars.SkillRecoveryJournal.RecoverRecipes == true then
		local learnedRecipes = JMD["learnedRecipes"]
		local gainedRecipes = SRJ.getGainedRecipes(character, learnedRecipes)
		o.gainedRecipes = gainedRecipes
	end


	o.gainedSkills = SRJ.calculateAllGainedSkills(character) or false
	o.oldJournalTotalXP = 0
	for perkID, xp in pairs(JMD["gainedXP"]) do
		o.oldJournalTotalXP = o.oldJournalTotalXP + xp
	end
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

		if (protections==1) and isClient() then
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

	o.writeTimer = 0
	o.stopOnWalk = false
	o.stopOnRun = true
	o.loopedAction = false
	o.ignoreHandsWounds = true
	o.caloriesModifier = 0.5
	o.forceProgressBar = true
	o.recipeIntervals = 0
	o.maxTime = -1
	o.haloTextDelay = 0

	-- interval between updates in in-game seconds
	local updateIntervalSeconds = SandboxVars.SkillRecoveryJournal.UpdateIntervalSeconds or 10
	o.updateInterval = updateIntervalSeconds / 3600 -- in hours
	o.defaultUpdateInterval = 3.48 / 3600 -- legacy ~ 3.48 sec to maintain old duration
	o.updateTime = now + o.updateInterval

	-- for debug
	o.lastUpdateTime = now
	o.startTime = now

	return o
end

function OnServerWriteCommand(module, command, args)
    -- server sends changes for client to show
	if module == "SkillRecoveryJournal" and command == "write_changes" then
		SRJ.handleHaloText(getPlayer(), args.changesBeingMade, args.totalStoredXP, args.totalRecoverableXP, args.oldJournalTotalXP, "IGUI_Tooltip_Transcribing")
	end
end

Events.OnServerCommand.Add(OnServerWriteCommand)