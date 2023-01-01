local SRJ = require "Skill Recovery Journal Main"


local isSkillExcludedFrom = {}
---@param perk PerkFactory.Perk
function isSkillExcludedFrom.SpeedReduction(perk) return (perk == Perks.Sprinting or perk == Perks.Fitness or perk == Perks.Strength) end
---@param perk PerkFactory.Perk
function isSkillExcludedFrom.SpeedIncrease(perk) return (perk == Perks.Fitness or perk == Perks.Strength) end


---@param player IsoGameCharacter|IsoPlayer
---@param perk PerkFactory.Perk
local function unBoostXP(player,perk,XP)

    if perk == Perks.Fitness and (not player:getNutrition():canAddFitnessXp()) then return 0 end

    local exerciseMultiplier = 1
    if perk == Perks.Strength and instanceof(player,"IsoPlayer") then
        if player:getNutrition():getProteins() > 50 and player:getNutrition():getProteins() < 300 then exerciseMultiplier = 1.5
        elseif player:getNutrition():getProteins() < 300 then exerciseMultiplier = 0.7
        end
    end
    XP = XP*exerciseMultiplier

    ---@type IsoGameCharacter.XP
    local pXP = player:getXp()

    ---trait impacting XP gains
    local traitMultiplier = 1
    --if not isSkillExcludedFrom.SpeedReduction(perk) then traitMultiplier = 0.25 end
    if player:HasTrait("FastLearner") and (not isSkillExcludedFrom.SpeedIncrease(perk)) then traitMultiplier = 1.3 end
    if player:HasTrait("SlowLearner") and (not isSkillExcludedFrom.SpeedReduction(perk)) then traitMultiplier = 0.7 end
    if player:HasTrait("Pacifist") and (perk:getParent()==Perks.Combat or perk==Perks.Aiming) then traitMultiplier = 0.75 end
    XP = XP*traitMultiplier

    ---sandbox multiplier
    local sandboxMultiplier = 1
    if (not perk:isPassiv()) then
        sandboxMultiplier = SandboxVars.XpMultiplier or 1
    elseif perk:isPassiv() and SandboxVars.XpMultiplierAffectsPassive==true then
        sandboxMultiplier = SandboxVars.XpMultiplier or 1
    end
    XP = XP*sandboxMultiplier

    ---perks boostMap based on career and starting traits
    local applyCareerAndTraits = SandboxVars.SkillRecoveryJournal.RecoverProfessionAndTraitsBonuses == true
    local xpBoostID = (applyCareerAndTraits and pXP:getPerkBoost(perk)) or 0
    local xpBoostMultiplier = 1

    if xpBoostID == 0 and (not isSkillExcludedFrom.SpeedReduction(perk)) then xpBoostMultiplier = 0.25
    elseif xpBoostID == 1 and perk==Perks.Sprinting then xpBoostMultiplier = 1.25
    elseif xpBoostID == 1 then xpBoostMultiplier = 1
    elseif xpBoostID == 2 and (not isSkillExcludedFrom.SpeedIncrease(perk)) then xpBoostMultiplier = 1.33
    elseif xpBoostID == 3 and (not isSkillExcludedFrom.SpeedIncrease(perk)) then xpBoostMultiplier = 1.66
    end
    XP = XP*xpBoostMultiplier

    ---from reading skill books
    local skillBookMultiplier = math.max(1,pXP:getMultiplier(perk))
    XP = XP*skillBookMultiplier

    return XP
end


local patchClassMethod = {}
function patchClassMethod.create(original_function)
    return function(self, perksType, XP, passHook, applyXPBoosts, transmitMP)
        local info = {}
        local coroutine = getCurrentCoroutine()
        local count = getCallframeTop(coroutine)

        for i= count - 1, 0, -1 do
            local luaCallFrame = getCoroutineCallframeStack(coroutine,i)
            if luaCallFrame ~= nil then
                local functionFileLine = KahluaUtil.rawTostring2(luaCallFrame)
                if functionFileLine then
                    local func = functionFileLine:match("function: (.*) %-%- file: ")
                    local file = functionFileLine:match(" %-%- file: (.*).lua line # ")
                    if func and file then
                        info[func..","..file] = true
                    end
                end
            end
        end

        ---@type IsoGameCharacter
        local player = getPlayer()
        ---@type IsoGameCharacter.XP
        local pXP = player:getXp()
        if pXP ~= self then return end

        local currentXP = pXP:getXP(perksType)
        local maxLevelXP = perksType:getTotalXpForLevel(10)

        if currentXP <= maxLevelXP then
            local unBoostedXP = (applyXPBoosts==false and XP) or unBoostXP(player, perksType, XP)
            SRJ.recordXPGain(player, perksType, unBoostedXP, info, maxLevelXP)
        end

        if passHook==nil then passHook = true end
        if applyXPBoosts==nil then applyXPBoosts = true end
        if transmitMP==nil then transmitMP = false end

        --print("SkillRecoveryJournal: --"addXP: "..tostring(perksType).." +"..XP.."("..unBoostedXP..")   hook:"..tostring(passHook)..", boost:"..tostring(applyXPBoosts)..", mp:"..tostring(transmitMP))
        --local infoText for k,v in pairs(info) do infoText = (infoText or "").."; "..k end print(" -- --info: "..infoText)
        return original_function(self, perksType, XP, passHook, applyXPBoosts, transmitMP)
    end
end

function patchClassMethod.apply()
    print("SkillRecoveryJournal: accessing class:`zombie.characters.IsoGameCharacter$XP.class` method:`AddXP`")
    local class, methodName = XP.class, "AddXP"
    local metatable = __classmetatables[class]
    local metatable__index = metatable.__index
    local originalMethod = metatable__index[methodName]
    metatable__index[methodName] = patchClassMethod.create(originalMethod)
end
patchClassMethod.apply()