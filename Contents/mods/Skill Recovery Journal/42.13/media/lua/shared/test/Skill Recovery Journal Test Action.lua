require "TimedActions/ISBaseTimedAction"

TestSkillRecoveryJournal = ISBaseTimedAction:derive("TestSkillRecoveryJournal")

function TestSkillRecoveryJournal:isValid()
    return true
end

function TestSkillRecoveryJournal:waitToStart()
	--local sq = self.character:getSquare()
	--self.character:faceLocation(sq:getX(), sq:getY())
	--return self.character:shouldBeTurning()
    return false
end

function TestSkillRecoveryJournal:start()
    print("TestSkillRecoveryJournal start")
	--self:setActionAnim("Loot")
	--self.character:SetVariable("LootPosition", "Low")

	print("SRJ TEST START - PLAYER AND MOD DATA WILL BE CLEARED")

	local player = self.character
	SRJ:resetModData(player, self.item)
	player:setPerkLevelDebug(Perks.Cooking, 1)
	player:setZombieKills(13)
	player:setSurvivorKills(37)
	-- TODO learn recipes

	ISTimedActionQueue.add(SkillRecoveryJournalAction:new(player, self.item, false, self.writingTool))
	--TODO: 
	-- Queue check if written cook xp, kills, recipes
	-- Queue clear player mod data, skills
	-- Queue read journal
	-- Queue check if read cook xp, kills, recipes
	
	--TODO: check different multipliers
end

function TestSkillRecoveryJournal:update()
    self.updates = self.updates + 1
    --if self.updates > 10 then
	--    self:setJobDelta(0.1); 
    --end
    --print("TestSkillRecoveryJournal update #", self.updates)
end

function TestSkillRecoveryJournal:stop()
    print("TestSkillRecoveryJournal stop")
	ISBaseTimedAction.stop(self)
end

function TestSkillRecoveryJournal:serverStart()
    print("TestSkillRecoveryJournal serverStart")
    --emulateAnimEvent(self.netAction, 10, "update", nil)
end

--function TestSkillRecoveryJournal:animEvent(event, parameter)
--	if event == "update" then
--		-- only on server in MP
--		if isServer() then
--            self.updates = self.updates + 1
--            print("Server update #", self.updates)
--		end
--	end
--end

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
	return -1
end

function TestSkillRecoveryJournal:new(character, item, writingTool)
	local o = ISBaseTimedAction.new(self, character)
	o.character = character
	o.item = item
	o.maxTime = o:getDuration()
	o.writingTool = writingTool
    o.updates = 0

	if (not character or not item or not writingTool) then
		print("SRJ TEST INIT FAIL! SOMETHING WAS NULL!")	
		return o
	end

	return o
end

--function OnServerWriteCommand(module, command, args)
--    --print("Received Message! Module ", module, " | Command ", command)
--end
--
--Events.OnServerCommand.Add(OnServerWriteCommand)