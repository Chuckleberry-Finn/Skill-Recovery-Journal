local SRJ_XPHandler = {}

SRJ_XPHandler.isSkillExcludedFrom = {}
---@param perk PerkFactory.Perk
function SRJ_XPHandler.isSkillExcludedFrom.SpeedReduction(perk) return (perk == Perks.Sprinting or perk == Perks.Fitness or perk == Perks.Strength) or false end
---@param perk PerkFactory.Perk
function SRJ_XPHandler.isSkillExcludedFrom.SpeedIncrease(perk) return (perk == Perks.Fitness or perk == Perks.Strength) or false end


---@param player IsoGameCharacter|IsoPlayer
---@param perk PerkFactory.Perk
function SRJ_XPHandler.unBoostXP(player,perk,XP)

    local debugPrint = ""
    if getDebug() then debugPrint = debugPrint.."unBoostXP: "..tostring(perk).." xp:"..XP end

    if perk == Perks.Fitness and (not player:getNutrition():canAddFitnessXp()) then return 0 end

    local exerciseMultiplier = 1
    if perk == Perks.Strength and instanceof(player,"IsoPlayer") then
        if player:getNutrition():getProteins() > 50 and player:getNutrition():getProteins() < 300 then exerciseMultiplier = 1.5
        elseif player:getNutrition():getProteins() < -300 then exerciseMultiplier = 0.7
        end
        if getDebug() then debugPrint = debugPrint.."\n   exerciseMultiplier: "..exerciseMultiplier.."*"..XP end
    end
    XP = XP*exerciseMultiplier
    if getDebug() then debugPrint = debugPrint.."= "..XP end

    ---@type IsoGameCharacter.XP
    local pXP = player:getXp()

    ---trait impacting XP gains
    local traitMultiplier = 1
    --if not SRJ_XPHandler.isSkillExcludedFrom.SpeedReduction(perk) then traitMultiplier = 0.25 end
    if player:HasTrait("FastLearner") and (not SRJ_XPHandler.isSkillExcludedFrom.SpeedIncrease(perk)) then traitMultiplier = 1.3 end
    if player:HasTrait("SlowLearner") and (not SRJ_XPHandler.isSkillExcludedFrom.SpeedReduction(perk)) then traitMultiplier = 0.7 end
    if player:HasTrait("Pacifist") and (perk:getParent()==Perks.Combat or perk==Perks.Aiming) then traitMultiplier = 0.75 end
    if getDebug() then debugPrint = debugPrint.."\n   traitMultiplier: "..traitMultiplier.."*"..XP end
    XP = XP*traitMultiplier
    if getDebug() then debugPrint = debugPrint.."= "..XP end

    ---sandbox multiplier
    local sandboxMultiplier = 1
    if (not perk:isPassiv()) then
        sandboxMultiplier = SandboxVars.XpMultiplier or 1
    elseif perk:isPassiv() and SandboxVars.XpMultiplierAffectsPassive==true then
        sandboxMultiplier = SandboxVars.XpMultiplier or 1
    end
    if getDebug() then debugPrint = debugPrint.."\n   sandboxMultiplier: "..sandboxMultiplier.."*"..XP end
    XP = XP*sandboxMultiplier
    if getDebug() then debugPrint = debugPrint.."= "..XP end

    --- perks boostMap based on career and starting traits - does not transfer starting skills - this is specifically about the bonus-XP earned.
    --- This checks if the sandboxOption is not false - so that true and nil return true (as they are not false)
    --- Reason being when sandbox options are added after the fact they will remain 'nil' and this was something occurring by default originally.
    local applyCareerAndTraits = SandboxVars.SkillRecoveryJournal.RecoverProfessionAndTraitsBonuses ~= false
    local xpBoostID = (applyCareerAndTraits and pXP:getPerkBoost(perk)) or 0
    local xpBoostMultiplier = 1

    if xpBoostID == 0 and (not SRJ_XPHandler.isSkillExcludedFrom.SpeedReduction(perk)) then xpBoostMultiplier = 0.25
    elseif xpBoostID == 1 and perk==Perks.Sprinting then xpBoostMultiplier = 1.25
    elseif xpBoostID == 1 then xpBoostMultiplier = 1
    elseif xpBoostID == 2 and (not SRJ_XPHandler.isSkillExcludedFrom.SpeedIncrease(perk)) then xpBoostMultiplier = 1.33
    elseif xpBoostID == 3 and (not SRJ_XPHandler.isSkillExcludedFrom.SpeedIncrease(perk)) then xpBoostMultiplier = 1.66
    end
    if getDebug() then debugPrint = debugPrint.."\n   xpBoostMultiplier: "..xpBoostMultiplier.."*"..XP end
    XP = XP*xpBoostMultiplier
    if getDebug() then debugPrint = debugPrint.."= "..XP end

    ---from reading skill books
    local skillBookMultiplier = math.max(1,pXP:getMultiplier(perk))
    if getDebug() then debugPrint = debugPrint.."\n   skillBookMultiplier: "..skillBookMultiplier.."*"..XP end
    XP = XP*skillBookMultiplier
    if getDebug() then debugPrint = debugPrint.."= "..XP end
    if getDebug() then print(debugPrint.."\n"..tostring(perk).." to be recorded: "..XP) end

    return XP
end


return SRJ_XPHandler