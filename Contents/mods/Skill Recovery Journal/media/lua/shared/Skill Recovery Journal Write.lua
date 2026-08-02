local SRJ = require "Skill Recovery Journal Main"
local modDataCapture = require "Skill Recovery Journal ModData"

require "TimedActions/ISBaseTimedAction"

---@class WriteSkillRecoveryJournal : ISBaseTimedAction
WriteSkillRecoveryJournal = ISBaseTimedAction:derive("WriteSkillRecoveryJournal")


function WriteSkillRecoveryJournal:isValid()
	local vehicle = self.character:getVehicle()
	if vehicle and vehicle:isDriver(self.character) then return not vehicle:isEngineRunning() or vehicle:getSpeed2D() == 0 end
	return self.character:getInventory():contains(self.item) and self.character:getInventory():contains(self.writingTool)
end


function WriteSkillRecoveryJournal:start()
	self.action:setTime(-1)
	self.item:setJobType(getText("ContextMenu_Write") ..' '.. self.item:getName())
	self:setAnimVariable("PerformingAction", "TranscribeJournal")
	self:setOverrideHandModels(self.writingTool, self.item)
	local logText = ISLogSystem.getGenericLogText(self.character)
	sendClientCommand(self.character, 'ISLogSystem', 'writeLog', {loggerName = "PerkLog", logText = logText.."[SRJ START WRITING]"})
end


function WriteSkillRecoveryJournal:complete()
	if self.item and self.journalBuffer and self.changesWereMade then
		local journalModData = self.item:getModData()
		journalModData["SRJ"] = journalModData["SRJ"] or {}
		local JMD = journalModData["SRJ"]

		JMD.ID = copyTable(self.journalBuffer.ID or {})
		JMD.author = self.journalBuffer.author
		JMD.gainedXP = copyTable(self.journalBuffer.gainedXP or {})
		JMD.learnedRecipes = copyTable(self.journalBuffer.learnedRecipes or {})
		JMD.learnedTraits = copyTable(self.journalBuffer.learnedTraits or {})
		JMD.kills = copyTable(self.journalBuffer.kills or {})
		if self.journalBuffer.pModData then
			JMD.pModData = copyTable(self.journalBuffer.pModData)
		end
		if self.journalBuffer.used ~= nil then
			JMD.used = self.journalBuffer.used
		end

		if self.item.transmitModData then
			self.item:transmitModData()
		end

		-- Cache user journal data to server JSON file
		if self.character then
			sendClientCommand(self.character, 'SkillRecoveryJournal', 'savePlayerJournalJson', {
				username = self.character:getUsername(),
				steamID = self.character:getSteamID(),
				author = JMD.author,
				gainedXP = JMD.gainedXP,
				learnedRecipes = JMD.learnedRecipes,
				learnedTraits = JMD.learnedTraits,
				kills = JMD.kills,
				pModData = JMD.pModData
			})
		end
	end
	return true
end


function WriteSkillRecoveryJournal:forceStop()
	self.item:setJobDelta(0.0)
	if self.action then self.action:setLoopedAction(false) end
	self.character:playSound("CloseBook")
	local logText = ISLogSystem.getGenericLogText(self.character)
	sendClientCommand(self.character, 'ISLogSystem', 'writeLog', {loggerName = "PerkLog", logText = logText.."[SRJ STOP WRITING] (forceStop)"})
	if self.changesWereMade then
		self:complete()
	end
	ISBaseTimedAction.forceStop(self)
end


function WriteSkillRecoveryJournal:stop()
	local logText = ISLogSystem.getGenericLogText(self.character)
	sendClientCommand(self.character, 'ISLogSystem', 'writeLog', {loggerName = "PerkLog", logText = logText.."[SRJ STOP WRITING] (stop)"})
	if self.changesWereMade then
		self:complete()
	end
	ISBaseTimedAction.stop(self)
end


function WriteSkillRecoveryJournal:perform()
	self.item:getContainer():setDrawDirty(true)
	self.character:playSound("CloseBook")
	local logText = ISLogSystem.getGenericLogText(self.character)
	sendClientCommand(self.character, 'ISLogSystem', 'writeLog', {loggerName = "PerkLog", logText = logText.."[SRJ STOP READING] (perform)"})

	if self.changesWereMade then
		self:complete()
	end
	ISBaseTimedAction.perform(self)
end


function WriteSkillRecoveryJournal:update()

	if not self.loopedAction then return end

	local JMD = self.journalBuffer
	if not JMD then return end

	local bOwner = true
	local pSteamID = self.character:getSteamID()
	local pUsername = self.character:getUsername()
	local journalID = JMD["ID"]
	local protections = SandboxVars.SkillRecoveryJournal.SecurityFeatures or 1

	if (protections<=2) and pSteamID ~= 0 and journalID and journalID["steamID"] and (journalID["steamID"] ~= pSteamID) then bOwner = false end
	if (protections==1) and pUsername and journalID and journalID["username"] and (journalID["username"] ~= pUsername) then bOwner = false end

	local transcribeTimeMulti = SandboxVars.SkillRecoveryJournal.TranscribeSpeed or 1

	local changesBeingMade = {}
	local changesBeingMadeIndex = {}

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
				if recipeID then
					JMD["learnedRecipes"][recipeID] = true
				end
				table.remove(self.gainedRecipes,#self.gainedRecipes)
			end
			self.recipeIntervals = 0
		end
	end

	if bOwner and self.gainedTraits and (#self.gainedTraits > 0) then
		self.traitIntervals = (self.traitIntervals or 0) + 1
		self.changesMade = true

		if self.traitIntervals > 5 then
			local traitChunk = math.min(#self.gainedTraits, math.floor(1.09^math.sqrt(#self.gainedTraits))) * transcribeTimeMulti
			for i=0, traitChunk do
				local traitID = self.gainedTraits[#self.gainedTraits]
				if traitID then
					JMD["learnedTraits"][traitID] = true
					local traitObj = TraitFactory.getTrait(traitID)
					local traitName = traitObj and traitObj:getLabel() or traitID
					table.insert(changesBeingMade, traitName)
				end
				table.remove(self.gainedTraits, #self.gainedTraits)
			end
			self.traitIntervals = 0
		end
	end

	local storedJournalXP = JMD["gainedXP"]
	local readXp = SRJ.getReadXP(self.character)
	local totalRecoverableXP = 1
	local totalStoredXP = 1

	if bOwner and storedJournalXP and self.gainedSkills then
		for perkID,xp in pairs(self.gainedSkills) do
			if xp > 0 then
				totalRecoverableXP = totalRecoverableXP + xp

				storedJournalXP[perkID] = storedJournalXP[perkID] or 0
				if xp > storedJournalXP[perkID] then

					local perkObj = SRJ.getPerk(perkID)
					local perkLevelPlusOne = perkObj and (self.character:getPerkLevel(perkObj) + 1) or 1

					local differential = SRJ.getMaxXPDifferential(perkObj or perkID)

					local xpRate = math.sqrt(xp)/25

					xpRate = round(((xpRate*math.sqrt(perkLevelPlusOne))*1000)/1000 * transcribeTimeMulti / differential, 2)

					if xpRate>0 then
						self.changesMade = true

						local skill_name = getTextOrNull("IGUI_perks_"..perkID) or perkID

						if not changesBeingMadeIndex[skill_name] then
							changesBeingMadeIndex[skill_name] = true
							table.insert(changesBeingMade, skill_name)
						end

						local resultingXp = math.min(xp, storedJournalXP[perkID]+xpRate)
						storedJournalXP[perkID] = resultingXp
						readXp[perkID] = math.max(resultingXp,(readXp[perkID] or 0))
					end
				end
			end
			totalStoredXP = totalStoredXP + (storedJournalXP[perkID] or 0)
		end
	end

	SRJ.correctSandBoxOptions("KillsTrack")
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

	if not self.modDataStoredComplete then
		self.modDataStoredComplete = true
		local modDataStored = modDataCapture.copyDataToJournal(self.character, JMD)
		if modDataStored then
			for _,dataID in pairs(modDataStored) do
				table.insert(changesBeingMade, dataID)
			end
			self.changesMade = true
		end
	end

	if self.haloTextDelay <= 0 and #changesBeingMade > 0 then
		self.haloTextDelay = 100
		local progressText = math.floor(((totalStoredXP - self.oldJournalTotalXP) / (totalRecoverableXP - self.oldJournalTotalXP)) * 100 + 0.5) .. "%"
		local changesBeingMadeText = getText("IGUI_Tooltip_Transcribing") .. " (" .. progressText ..") :"
		for k,v in pairs(changesBeingMade) do changesBeingMadeText = changesBeingMadeText.." "..v..((k~=#changesBeingMade and ", ") or "") end
		HaloTextHelper.addText(self.character, changesBeingMadeText, "", HaloTextHelper.getColorWhite())
	end

	if self.changesMade==true then

		self.changesWereMade = true

		self.playSoundLater = self.playSoundLater or 0
		if self.playSoundLater > 0 then
			self.playSoundLater = self.playSoundLater-1
		else
			self.playSoundLater = (ZombRand(2,6) + getGameTime():getMultiplier())
			self.character:playSound(self.writingToolSound)
		end
	else

		if self.changesWereMade then
			self.character:Say(getText("IGUI_PlayerText_AllDoneWithJournal"), 0.55, 0.55, 0.55, UIFont.Dialogue, 0, "default")
		else
			self.character:Say(getText("IGUI_PlayerText_NothingToAddToJournal"), 0.55, 0.55, 0.55, UIFont.Dialogue, 0, "default")
		end

		self:forceStop()
	end
end


---@param character IsoGameCharacter
function WriteSkillRecoveryJournal:new(character, item, writingTool)

	local o = {}
	setmetatable(o, self)
	self.__index = self

	o.character = character
	o.item = item
	o.writingTool = writingTool

	local journalModData = o.item:getModData()
	local rawJMD = journalModData["SRJ"] or {}

	-- Client-local table buffer for server-authoritative state management
	o.journalBuffer = {
		ID = copyTable(rawJMD.ID or {}),
		author = rawJMD.author,
		gainedXP = copyTable(rawJMD.gainedXP or {}),
		learnedRecipes = copyTable(rawJMD.learnedRecipes or {}),
		learnedTraits = copyTable(rawJMD.learnedTraits or {}),
		kills = copyTable(rawJMD.kills or {}),
		pModData = copyTable(rawJMD.pModData or {}),
		used = rawJMD.used
	}
	local JMD = o.journalBuffer

	o.writingToolSound = "PenWriteSounds"
	if character:getInventory():contains("Pencil") then
		o.writingToolSound = "PencilWriteSounds"
	end

	local learnedRecipes = JMD["learnedRecipes"]
	local learnedTraits = JMD["learnedTraits"]

	local gainedRecipes = SRJ.getGainedRecipes(character)
	o.gainedRecipes = {}
	if SandboxVars.SkillRecoveryJournal.RecoverRecipes == true then
		for _,recipeID in pairs(gainedRecipes) do
			if learnedRecipes[recipeID] ~= true then
				table.insert(o.gainedRecipes,recipeID)
			end
		end
	end

	local gainedTraits = SRJ.getGainedTraits(character)
	o.gainedTraits = {}
	if SandboxVars.SkillRecoveryJournal.RecoverTraits ~= false then
		for _,traitID in pairs(gainedTraits) do
			if learnedTraits[traitID] ~= true then
				table.insert(o.gainedTraits, traitID)
			end
		end
	end

	o.gainedSkills = SRJ.calculateGainedSkills(character) or false
	o.oldJournalTotalXP = 0
	for perkID, xp in pairs(JMD["gainedXP"]) do
		o.oldJournalTotalXP = o.oldJournalTotalXP + xp
	end
	o.willWrite = true
	local sayText

	if not o.gainedSkills and (#o.gainedRecipes <= 0) and (#o.gainedTraits <= 0) then
		sayText=getText("IGUI_PlayerText_DontHaveAnyXP"), 0.55, 0.55, 0.55, UIFont.Dialogue, 0, "default"
		o.willWrite = false
	else
		local journalID = JMD["ID"]
		local pSteamID = character:getSteamID()
		local pUsername = character:getUsername()

		local protections = SandboxVars.SkillRecoveryJournal.SecurityFeatures or 1

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

	if character:HasTrait("Illiterate") then
		local sayTextChoices = {"IGUI_PlayerText_DontUnderstand", "IGUI_PlayerText_TooComplicated", "IGUI_PlayerText_DontGet"}
		sayText=getText(sayTextChoices[ZombRand(#sayTextChoices)+1]).." ("..getText("UI_trait_Illiterate")..")"
		o.willWrite = false
	end

	if sayText then character:Say(sayText) end
	if o.willWrite then JMD["author"] = character:getFullName() end

	o.writeTimer = 0
	o.stopOnWalk = false
	o.stopOnRun = true
	o.loopedAction = true
	o.ignoreHandsWounds = true
	o.caloriesModifier = 0.5
	o.learnedRecipes = {}
	o.recipeIntervals = 0
	o.maxTime = -1
	o.haloTextDelay = 0

	return o
end
