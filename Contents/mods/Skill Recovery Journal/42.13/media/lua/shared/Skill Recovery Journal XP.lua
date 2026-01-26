local SRJ_XPHandler = {}

SRJ_XPHandler.isSkillExcludedFrom = {}
---@param perk PerkFactory.Perk
function SRJ_XPHandler.isSkillExcludedFrom.SpeedReduction(perk) return (perk == Perks.Sprinting or perk == Perks.Fitness or perk == Perks.Strength) or false end
---@param perk PerkFactory.Perk
function SRJ_XPHandler.isSkillExcludedFrom.SpeedIncrease(perk) return (perk == Perks.Fitness or perk == Perks.Strength) or false end


SRJ_XPHandler.tmpStoredValues = {}
SRJ_XPHandler.perkXpTable = {}
SRJ_XPHandler.maxXPDifferential = {}


function SRJ_XPHandler.getMaxXPDifferential(perk)
	if SRJ_XPHandler.maxXPDifferential[perk] then return SRJ_XPHandler.maxXPDifferential[perk] end
	local maxXPDefault = Perks.PhysicalCategory:getTotalXpForLevel(10)
	local maxXPPerk = Perks[perk]:getTotalXpForLevel(10)

	SRJ_XPHandler.maxXPDifferential[perk] = maxXPDefault/maxXPPerk
	return SRJ_XPHandler.maxXPDifferential[perk]
end

---@param player IsoGameCharacter|IsoPlayer
function SRJ_XPHandler.getOrStoreXPMultipliers(player)
    ---Need to check for stuff like dynamic traits edge cases
    ---@type TraitCollection
    local traitsSize = player:getCharacterTraits():getKnownTraits():size()
    local previouslyStored = SRJ_XPHandler.tmpStoredValues[player]

    if not previouslyStored or previouslyStored.size ~= traitsSize then
        SRJ_XPHandler.tmpStoredValues[player] = {}
        previouslyStored = SRJ_XPHandler.tmpStoredValues[player]
        previouslyStored.size = traitsSize
        previouslyStored.multipliers = {}
        for i=1, Perks.getMaxIndex()-1 do
            ---@type PerkFactory.Perk
            local perk = Perks.fromIndex(i)
            if perk and perk:getParent():getId()~="None" then
                local traitMultiplier, xpBoostMultiplier = SRJ_XPHandler.fetchMultipliers(player,perk)
                local perkID = perk:getId()
                previouslyStored.multipliers[perkID] = (traitMultiplier*xpBoostMultiplier)
            end
        end
    end
    return previouslyStored.multipliers
end


---This process "boosts" flat XP to that of the `provided` player as well as the `current` sandbox-XP-Multi
---@param player IsoGameCharacter|IsoPlayer
---@param perk PerkFactory.Perk
function SRJ_XPHandler.reBoostXP(player,perk,XP)
    local traitMultiplier, xpBoostMultiplier = SRJ_XPHandler.fetchMultipliers(player,perk,XP)

    local debugPrint = ""
    if getDebug() then debugPrint = debugPrint.."unBoostXP: "..tostring(perk).." xp:"..XP end

    XP = XP*traitMultiplier
    if getDebug() then debugPrint = debugPrint.."\n   traitMultiplier: "..traitMultiplier.." -> "..XP end

    XP = XP*xpBoostMultiplier
    if getDebug() then debugPrint = debugPrint.."\n   xpBoostMultiplier: "..xpBoostMultiplier.." -> "..XP end

    --if getDebug() then print(debugPrint.."\n"..tostring(perk).." to be recorded: "..XP) end

    return XP
end

---This process "flattens" the XP to that of unemployed/traitless as well as sandbox-XP-Multi=1
---@param player IsoGameCharacter|IsoPlayer
---@param perk PerkFactory.Perk
function SRJ_XPHandler.unBoostXP(player,perk,XP)

    local traitMultiplier, xpBoostMultiplier = SRJ_XPHandler.fetchMultipliers(player,perk,XP)

    local debugPrint = ""
    if getDebug() then debugPrint = debugPrint.."unBoostXP: "..tostring(perk).." xp:"..XP end

    XP = XP/traitMultiplier
    if getDebug() then debugPrint = debugPrint.."\n   traitMultiplier: "..traitMultiplier.." -> "..XP end

    XP = XP/xpBoostMultiplier
    if getDebug() then debugPrint = debugPrint.."\n   xpBoostMultiplier: "..xpBoostMultiplier.." -> "..XP end

    --if getDebug() then print(debugPrint.."\n"..tostring(perk).." to be recorded: "..XP) end

    return XP
end


function SRJ_XPHandler.fetchMultipliers(player,perk)

    --[[
    local exerciseMultiplier = 1
    --if perk == Perks.Fitness and (not player:getNutrition():canAddFitnessXp()) then exerciseMultiplier 0 end
    --]]

    --[[
    if perk == Perks.Strength and instanceof(player,"IsoPlayer") then
        if player:getNutrition():getProteins() > 50 and player:getNutrition():getProteins() < 300 then exerciseMultiplier = 1.5
        elseif player:getNutrition():getProteins() < -300 then exerciseMultiplier = 0.7
        end
    end
    --]]

    ---trait impacting XP gains
    local traitMultiplier = 1
    --if not SRJ_XPHandler.isSkillExcludedFrom.SpeedReduction(perk) then traitMultiplier = 0.25 end
    if player:hasTrait(CharacterTrait.FAST_LEARNER) and (not SRJ_XPHandler.isSkillExcludedFrom.SpeedIncrease(perk)) then traitMultiplier = 1.3 end
    if player:hasTrait(CharacterTrait.SLOW_LEARNER) and (not SRJ_XPHandler.isSkillExcludedFrom.SpeedReduction(perk)) then traitMultiplier = 0.7 end
    if player:hasTrait(CharacterTrait.PACIFIST) and (perk:getParent()==Perks.Combat or perk==Perks.Aiming) then traitMultiplier = 0.75 end
    if player:hasTrait(CharacterTrait.CRAFTY) and (perk:getParent()==Perks.Crafting) then traitMultiplier = 1.3 end
    --[[
    local sandboxMultiplier = 1
    if (not perk:isPassiv()) then
        sandboxMultiplier = SandboxVars.XpMultiplier or 1
    elseif perk:isPassiv() and SandboxVars.XpMultiplierAffectsPassive==true then
        sandboxMultiplier = SandboxVars.XpMultiplier or 1
    end
    --]]

    --- perks boostMap based on career and starting traits - does not transfer starting skills - this is specifically about the bonus-XP earned.
    ---@type IsoGameCharacter.XP
    local pXP = player:getXp()
    local xpBoostID = pXP:getPerkBoost(perk)
    local xpBoostMultiplier = 1
    if xpBoostID == 0 and (not SRJ_XPHandler.isSkillExcludedFrom.SpeedReduction(perk)) then xpBoostMultiplier = 0.25
    elseif xpBoostID == 1 and perk==Perks.Sprinting then xpBoostMultiplier = 1.25
    elseif xpBoostID == 1 then xpBoostMultiplier = 1
    elseif xpBoostID == 2 and (not SRJ_XPHandler.isSkillExcludedFrom.SpeedIncrease(perk)) then xpBoostMultiplier = 1.33
    elseif xpBoostID == 3 and (not SRJ_XPHandler.isSkillExcludedFrom.SpeedIncrease(perk)) then xpBoostMultiplier = 1.66
    end

    ---Something to consider later I guess?
    --[[
    ---from reading skill books
    local skillBookMultiplier = math.max(1,pXP:getMultiplier(perk))
    if getDebug() then debugPrint = debugPrint.."\n   skillBookMultiplier: "..skillBookMultiplier.."*"..XP end
    XP = XP*skillBookMultiplier
    if getDebug() then debugPrint = debugPrint.."= "..XP end
    --]]

    return traitMultiplier, xpBoostMultiplier
end


-- Cache XP thresholds for levels
function SRJ_XPHandler.initXPTable()
    local perkXpTable = SRJ_XPHandler.perkXpTable or {}
    for i = 0, Perks.getMaxIndex() - 1 do
        local perk = Perks.fromIndex(i)
        if perk then
            local perkID = perk:getId()
            perkXpTable[perkID] = {}

            for level = 1, 10 do
                perkXpTable[perkID][level] = perk:getTotalXpForLevel(level)
            end
        end
    end
    SRJ_XPHandler.perkXpTable = perkXpTable
    return SRJ_XPHandler.perkXpTable
end


-- Get level from XP amount
function SRJ_XPHandler.getPerkLevelFromXP(perkID, xp)
    local xpTable = SRJ_XPHandler.perkXpTable[perkID] or SRJ_XPHandler.initXPTable()[perkID]
    if xpTable then
        for level = 10, 1, -1 do
            local required = xpTable[level]
            if xp >= required then
                return level
            end
        end
    end
    return 0
end


function SRJ_XPHandler.getPerkLevelAfterJournalRead(SRJ, player, perkID, multi, journalXP)
    local readXP = SRJ.modDataHandler.getReadXP(player)
	local playerXP = player:getXp():getXP(Perks[perkID]) / multi
	--print("Player ", playerXP, " JournalXP ", journalXP, " Read ", readXP[perkID], " Multi ", multi)
	local playerXPAfterFullRead = playerXP + math.max(0, journalXP - (readXP[perkID] or 0))
	local level = SRJ_XPHandler.getPerkLevelFromXP(perkID, math.ceil(playerXPAfterFullRead * multi))

    return level
end



return SRJ_XPHandler