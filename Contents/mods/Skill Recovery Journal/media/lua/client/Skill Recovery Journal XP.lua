local SRJ = require "Skill Recovery Journal Main"


local isSkillExcludedFrom = {}
---@param perk PerkFactory.Perk
function isSkillExcludedFrom.SpeedReduction(perk) return (perk == Perks.Sprinting or perk == Perks.Fitness or perk == Perks.Strength) or false end
---@param perk PerkFactory.Perk
function isSkillExcludedFrom.SpeedIncrease(perk) return (perk == Perks.Fitness or perk == Perks.Strength) or false end


---@param player IsoGameCharacter|IsoPlayer
---@param perk PerkFactory.Perk
local function unBoostXP(player,perk,XP)

    local debugPrint = ""
    if getDebug() then debugPrint = debugPrint.."unBoostXP: "..tostring(perk).." xp:"..XP end

    if perk == Perks.Fitness and (not player:getNutrition():canAddFitnessXp()) then return 0 end

    local exerciseMultiplier = 1
    if perk == Perks.Strength and instanceof(player,"IsoPlayer") then
        if player:getNutrition():getProteins() > 50 and player:getNutrition():getProteins() < 300 then exerciseMultiplier = 1.5
        elseif player:getNutrition():getProteins() < -300 then exerciseMultiplier = 0.7
        end
    end
    if getDebug() then debugPrint = debugPrint.."\n   exerciseMultiplier: "..exerciseMultiplier.."*"..XP end
    XP = XP*exerciseMultiplier
    if getDebug() then debugPrint = debugPrint.."= "..XP end


    ---@type IsoGameCharacter.XP
    local pXP = player:getXp()

    ---trait impacting XP gains
    local traitMultiplier = 1
    --if not isSkillExcludedFrom.SpeedReduction(perk) then traitMultiplier = 0.25 end
    if player:HasTrait("FastLearner") and (not isSkillExcludedFrom.SpeedIncrease(perk)) then traitMultiplier = 1.3 end
    if player:HasTrait("SlowLearner") and (not isSkillExcludedFrom.SpeedReduction(perk)) then traitMultiplier = 0.7 end
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

    ---perks boostMap based on career and starting traits
    ---checking if it's 'not false' instead of 'true' because I want older saves before this sandbox option to get what they expect to occur
    local applyCareerAndTraits = SandboxVars.SkillRecoveryJournal.RecoverProfessionAndTraitsBonuses ~= false
    local xpBoostID = (applyCareerAndTraits and pXP:getPerkBoost(perk)) or 0
    local xpBoostMultiplier = 1

    if xpBoostID == 0 and (not isSkillExcludedFrom.SpeedReduction(perk)) then xpBoostMultiplier = 0.25
    elseif xpBoostID == 1 and perk==Perks.Sprinting then xpBoostMultiplier = 1.25
    elseif xpBoostID == 1 then xpBoostMultiplier = 1
    elseif xpBoostID == 2 and (not isSkillExcludedFrom.SpeedIncrease(perk)) then xpBoostMultiplier = 1.33
    elseif xpBoostID == 3 and (not isSkillExcludedFrom.SpeedIncrease(perk)) then xpBoostMultiplier = 1.66
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

--[[
---@param player IsoGameCharacter
---@param perk PerkFactory.Perk
---@param perkLevelAfter number
---@param addedLevel boolean
local function onLevelChangeViaDebug(player, perk, perkLevelAfter, addedLevel)

    --local pXp = player:getXp()
    local totalForLevel = perk:getXpForLevel(perkLevelAfter + ((not addedLevel and 1) or 0) )
    --print("perk: "..tostring(perk).."    totalForLevel: "..totalForLevel.."    -currentXP: "..currentXP)

    local remainder = totalForLevel
    if addedLevel==false then remainder = 0-remainder end

    print("addedLevel: "..tostring(addedLevel).."    perkLevelAfter: "..perkLevelAfter.."    remainder XP: "..remainder)

    local maxLevelXP = perk:getTotalXpForLevel(10)
    SRJ.recordXPGain(player, perk, remainder, {}, maxLevelXP)
end
Events.LevelPerk.Add(onLevelChangeViaDebug)
--]]

local ignoreNextCatchJavaAddXP = {}
local function catchJavaAddXP(player, perksType, XP)

    if ignoreNextCatchJavaAddXP[player] then
        ignoreNextCatchJavaAddXP[player] = nil
        return
    end

    ---@type IsoGameCharacter.XP
    local pXP = player:getXp()
    local currentXP = pXP:getXP(perksType)
    local maxLevelXP = perksType:getTotalXpForLevel(10)

    local debugPrint = "passUnBoostOnAddXP: "
    ---checking if it's 'not false' instead of 'true' because I want older saves before this sandbox option to get what they expect to occur
    if SandboxVars.SkillRecoveryJournal.RecoverProfessionAndTraitsBonuses == false then
        local xpBoostID = pXP:getPerkBoost(perksType)
        local xpBoostNumerator = 1

        if xpBoostID == 0 and (not isSkillExcludedFrom.SpeedReduction(perksType)) then xpBoostNumerator = 0.25
        elseif xpBoostID == 1 and perksType==Perks.Sprinting then xpBoostNumerator = 1.25
        elseif xpBoostID == 1 then xpBoostNumerator = 1
        elseif xpBoostID == 2 and (not isSkillExcludedFrom.SpeedIncrease(perksType)) then xpBoostNumerator = 1.33
        elseif xpBoostID == 3 and (not isSkillExcludedFrom.SpeedIncrease(perksType)) then xpBoostNumerator = 1.66
        end
        if getDebug() then debugPrint = debugPrint..XP.."/"..xpBoostNumerator end
        XP = XP/xpBoostNumerator
    end

    if currentXP <= maxLevelXP then
        if getDebug() then print(debugPrint.." "..tostring(perksType).." to be recorded: "..XP) end
        SRJ.recordXPGain(player, perksType, XP, {}, maxLevelXP)
    end
end


---Ideally this will be loaded in last
local function loadOnBoot() Events.AddXP.Add(catchJavaAddXP) end
Events.OnGameBoot.Add(loadOnBoot)


local patchClassMethod = {}
function patchClassMethod.create(original_function)
    return function(self, perksType, XP, passHook, applyXPBoosts, transmitMP)
        local info = {}

        ---@type Coroutine
        local coroutine = getCurrentCoroutine()
        if coroutine then
            local count = getCallframeTop(coroutine)
            for i= count - 1, 0, -1 do
                ---@type LuaCallFrame
                local luaCallFrame = getCoroutineCallframeStack(coroutine,i)
                if luaCallFrame ~= nil and luaCallFrame then
                    local fileDir = getFilenameOfCallframe(luaCallFrame)
                    if fileDir then
                        local index = fileDir:match('^.*()/')
                        if index then
                            local filename = fileDir:sub(index+1):gsub(".lua", "")
                            if filename then info[filename] = true end
                        end
                    end
                end
            end
        end

        ---@type IsoGameCharacter
        local player = getPlayer()
        ---@type IsoGameCharacter.XP
        local pXP = player:getXp()
        if pXP ~= self then return end

        if passHook==nil then passHook = true end

        local currentXP = pXP:getXP(perksType)
        local maxLevelXP = perksType:getTotalXpForLevel(10)
        if currentXP <= maxLevelXP then
            local unBoostedXP = (applyXPBoosts==false and XP) or unBoostXP(player, perksType, XP)
            SRJ.recordXPGain(player, perksType, unBoostedXP, info, maxLevelXP)
            if passHook==true then ignoreNextCatchJavaAddXP[player] = true end
        end

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
