require "TimedActions/ISBaseTimedAction"

local SRJ = require "Skill Recovery Journal Main"

TestSkillRecoveryJournal = ISBaseTimedAction:derive("TestSkillRecoveryJournal")

function TestSkillRecoveryJournal:isValid()
    return false
end

function TestSkillRecoveryJournal:waitToStart()
	--local sq = self.character:getSquare()
	--self.character:faceLocation(sq:getX(), sq:getY())
	--return self.character:shouldBeTurning()
    return false
end

function TestSkillRecoveryJournal:start()
    print("TestSkillRecoveryJournal start")
	self:setActionAnim("Loot")
	self.character:SetVariable("LootPosition", "Low")
end

function TestSkillRecoveryJournal:update()
    self.updates = self.updates + 1
    if self.updates > 10 then
	    self:setJobDelta(0.1); 
    end
    print("TestSkillRecoveryJournal update #", self.updates)
end

function TestSkillRecoveryJournal:stop()
    print("TestSkillRecoveryJournal stop")
	ISBaseTimedAction.stop(self)
end

function TestSkillRecoveryJournal:serverStart()
    print("TestSkillRecoveryJournal serverStart")
    emulateAnimEvent(self.netAction, 10, "update", nil)
end

function TestSkillRecoveryJournal:animEvent(event, parameter)
	if event == "update" then
		-- only on server in MP
		if isServer() then
            self.updates = self.updates + 1
            print("Server update #", self.updates)
		end
	end
end

function TestSkillRecoveryJournal:serverStop()
    print("TestSkillRecoveryJournal serverStop")
end

function TestSkillRecoveryJournal:perform()
    print("TestSkillRecoveryJournal perform")
	-- needed to remove from queue / start next.
	ISBaseTimedAction.perform(self)
end

function TestSkillRecoveryJournal:complete()
    print("TestSkillRecoveryJournal complete")
	return true
end

function TestSkillRecoveryJournal:getDuration()
	if self.character:isTimedActionInstant() then
		return 1
	end
	return 1
end

-- Automated tests
function TestSkillRecoveryJournal:test_calculateReadWriteXpRates()
	local success = true
	local timeFactor = 10 / 3.48
	if getPlayer():getPerkLevel(Perks.Cooking) == 1 then
		print("Test write")

		self.item:getModData()["SRJ"] = nil
		local journalXP = {}
		journalXP["Cooking"] = 75 * 4 --?
		local durationData = SRJ.xpHandler.calculateReadWriteXpRates(SRJ, self.character, self.item, timeFactor, {}, journalXP, false, 10)
		success = durationData.intervals == 107

		if not success then
			print("test_calculateReadWriteXpRates failed! Intervals ", durationData.intervals)
		end
	elseif getPlayer():getPerkLevel(Perks.Cooking) == 0 then
		print("Test read")
		
		self.character:getModData()["SRJ"] = nil
		local durationData = SRJ.xpHandler.calculateReadWriteXpRates(SRJ, self.character, self.item, timeFactor, {}, nil, true, 10)
		success = durationData.intervals == 107

		if not success then
			print("test_calculateReadWriteXpRates failed! Intervals ", durationData.intervals)
		end
	end
		return success
end


function test_getPerkLevelFromXP()
	local success = true
	print("test_getPerkLevelFromXP with Fitness")
	for level = 1, 10 do
		local xpForLevel = Perks.Fitness:getTotalXpForLevel(level)
		local levelForXP = SRJ.xpHandler.getPerkLevelFromXP("Fitness", level)
		if not levelForXP == level then
			success = false
			print("getPerkLevelFromXP for Fitness failed in level ",level, "! xpForLevel " ,xpForLevel , " levelForXP " ,levelForXP)
			break
		end
	end
	
	print("test_getPerkLevelFromXP with Cooking")
	for level = 1, 10 do
		local xpForLevel = Perks.Cooking:getTotalXpForLevel(level)
		local levelForXP = SRJ.xpHandler.getPerkLevelFromXP("Cooking", level)
		if not levelForXP == level then
			success = false
			print("getPerkLevelFromXP for Cooking failed in level ",level, "! xpForLevel " ,xpForLevel , " levelForXP " ,levelForXP)
			break
		end
	end

	local level = getPlayer():getPerkLevel(Perks.Fishing)
	print("test_getPerkLevelFromXP with Player Fishing ", level)
	local xpForLevel = getPlayer():getXp():getXP(Perks.Fishing)
	local levelForXP = SRJ.xpHandler.getPerkLevelFromXP("Fishing", level)
	if not levelForXP == level then
		success = false
		print("getPerkLevelFromXP for Fishing failed in level ",level, "! xpForLevel " ,xpForLevel , " levelForXP " ,levelForXP)
	end

	local level = getPlayer():getPerkLevel(Perks.Fitness)
	print("test_getPerkLevelFromXP with Player Fitness ", level)
	local xpForLevel = getPlayer():getXp():getXP(Perks.Fitness)
	local levelForXP = SRJ.xpHandler.getPerkLevelFromXP("Fitness", level)
	if not levelForXP == level then
		success = false
		print("getPerkLevelFromXP for Fitness failed in level ",level, "! xpForLevel " ,xpForLevel , " levelForXP " ,levelForXP)
	end

	return success
end

function TestSkillRecoveryJournal:new(character, item, writingTool)
	local o = ISBaseTimedAction.new(self, character)
	o.character = character
	o.item = item
	o.maxTime = o:getDuration()
	o.writingTool = writingTool
    o.updates = 0

	print("NEW SRJ TEST - PLAYER MOD DATA WILL BE CLEARED")
	if o:test_calculateReadWriteXpRates() and test_getPerkLevelFromXP() then
		print("All good.")
	end

	return o
end

function OnServerWriteCommand(module, command, args)
    --print("Received Message! Module ", module, " | Command ", command)
end

Events.OnServerCommand.Add(OnServerWriteCommand)