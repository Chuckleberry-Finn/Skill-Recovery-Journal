local SRJ_XPHandler = {}

SRJ_XPHandler.isSkillExcludedFrom = {}
---@param perk PerkFactory.Perk
function SRJ_XPHandler.isSkillExcludedFrom.SpeedReduction(perk) return (perk == Perks.Sprinting or perk == Perks.Fitness or perk == Perks.Strength) or false end
---@param perk PerkFactory.Perk
function SRJ_XPHandler.isSkillExcludedFrom.SpeedIncrease(perk) return (perk == Perks.Fitness or perk == Perks.Strength) or false end


SRJ_XPHandler.tmpStoredValues = {}

---@param player IsoGameCharacter|IsoPlayer
function SRJ_XPHandler.getOrStoreXPMultipliers(player)
    ---Need to check for stuff like dynamic traits edge cases
    ---@type TraitCollection
    local traitsSize = player:getCharacterTraits():size()
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


---Pass raw net XP 1:1 without distorting multipliers
---@param player IsoGameCharacter|IsoPlayer
---@param perk PerkFactory.Perk
function SRJ_XPHandler.reBoostXP(player,perk,XP)
    return XP
end

---Pass raw net XP 1:1 without distorting multipliers
---@param player IsoGameCharacter|IsoPlayer
---@param perk PerkFactory.Perk
function SRJ_XPHandler.unBoostXP(player,perk,XP)
    return XP
end


function SRJ_XPHandler.fetchMultipliers(player,perk)
    local SRJ = require "Skill Recovery Journal Main"
    local perkObj = (SRJ and SRJ.getPerk) and SRJ.getPerk(perk) or perk
    if not perkObj then return 1, 1 end

    ---trait impacting XP gains
    local traitMultiplier = 1
    --if not SRJ_XPHandler.isSkillExcludedFrom.SpeedReduction(perkObj) then traitMultiplier = 0.25 end
    if player:HasTrait("FastLearner") and (not SRJ_XPHandler.isSkillExcludedFrom.SpeedIncrease(perkObj)) then traitMultiplier = 1.3 end
    if player:HasTrait("SlowLearner") and (not SRJ_XPHandler.isSkillExcludedFrom.SpeedReduction(perkObj)) then traitMultiplier = 0.7 end
    if player:HasTrait("Pacifist") and (perkObj:getParent()==Perks.Combat or perkObj==Perks.Aiming) then traitMultiplier = 0.75 end

    --- perks boostMap based on career and starting traits - does not transfer starting skills - this is specifically about the bonus-XP earned.
    ---@type IsoGameCharacter.XP
    local pXP = player:getXp()
    local xpBoostID = pXP:getPerkBoost(perkObj)
    local xpBoostMultiplier = 1
    if xpBoostID == 0 and (not SRJ_XPHandler.isSkillExcludedFrom.SpeedReduction(perkObj)) then xpBoostMultiplier = 0.25
    elseif xpBoostID == 1 and perkObj==Perks.Sprinting then xpBoostMultiplier = 1.25
    elseif xpBoostID == 1 then xpBoostMultiplier = 1
    elseif xpBoostID == 2 and (not SRJ_XPHandler.isSkillExcludedFrom.SpeedIncrease(perkObj)) then xpBoostMultiplier = 1.33
    elseif xpBoostID == 3 and (not SRJ_XPHandler.isSkillExcludedFrom.SpeedIncrease(perkObj)) then xpBoostMultiplier = 1.66
    end

    return traitMultiplier, xpBoostMultiplier
end


return SRJ_XPHandler
