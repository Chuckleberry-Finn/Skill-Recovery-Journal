if not getDebug() then return end

print("INIT SRJ TESTS")
SRJ = require "Skill Recovery Journal Main"

local character = getPlayer()
local item

-- run automated tests (resets all mod data!)
function SRJ:doTest()
	print("--- DO SRJ FULL TEST SETUP --")

	local result = false

	local items = character:getInventory():getItemsFromFullType("Base.SkillRecoveryBoundJournal", true)
	item = items:get(0)

	if item then
		-- reset modData and run all tests
		SRJ:resetModData(character, item)
		result = test_getPerkLevelFromXP() and test_calculateReadWriteXpRates()
	else
		print("Journal not found.")
	end

	print("--- FINISHED SRJ FULL TEST SETUP", (not result and "UN") or " ", "SUCCESSFULLY ---")
	return result
end

function SRJ:resetModData(character, item)
	print("resetModData")
	character:getModData()["SRJ"] = nil
	item:getModData()["SRJ"] = nil

	return true
end

function test()
	print("TEST")
end

-- Automated tests

-- test if rates for lvl 1 are still consistent for read and write
function test_calculateReadWriteXpRates()
	print("test_calculateReadWriteXpRates")
	local success = true
	local timeFactor = 10 / 3.48
	
	getPlayer():setPerkLevelDebug(Perks.Cooking, 0)
	if getPlayer():getPerkLevel(Perks.Cooking) == 0 then
		-- FIXME: TEST WITH A JOURNAL LVL 1
		local durationData = SRJ.calculateReadWriteRates(character, item, timeFactor, {}, nil, true, 10)
		success = durationData.intervals == 107

		if not success then
			print("test_calculateReadWriteXpRates reading with cooking == 0 failed! Intervals ", durationData.intervals)
		end
	end

	getPlayer():setPerkLevelDebug(Perks.Cooking, 1)
	if getPlayer():getPerkLevel(Perks.Cooking) == 1 then
		local journalXP = {}
		journalXP["Cooking"] = 75 * 4 -- 75xp at 0.25 multi
		local durationData = SRJ.calculateReadWriteRates(character, item, timeFactor, {}, journalXP, false, 10)
		success = durationData.intervals == 107

		if not success then
			print("test_calculateReadWriteXpRates writing with cooking == 1 failed! Intervals ", durationData.intervals)
		end
	end
	return success
end


-- test if perk level from xp is calculated correctly
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