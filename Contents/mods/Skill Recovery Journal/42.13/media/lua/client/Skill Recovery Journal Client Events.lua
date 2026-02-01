local SRJ = require "Skill Recovery Journal Main"

local errorMagnifier = require "errorMagnifier_Main"
if not errorMagnifier then return end
if errorMagnifier.registerDebugReport then
    errorMagnifier.registerDebugReport("SkillRecoveryJournal", function()

        local character
        local journals

        local player = getPlayer()
        if player then
            character = {}
            local passiveSkillsInit = SRJ.modDataHandler.getPassiveLevels(player)
            local startingLevels = SRJ.modDataHandler.getFreeLevelsFromTraitsAndProfession(player)
            local deductibleXP = SRJ.modDataHandler.getDeductedXP(player)
            local multipliers = SRJ.xpHandler.getOrStoreXPMultipliers(player)
            local charReadXP = SRJ.modDataHandler.getReadXP(player)
            local allGainedXP = SRJ.calculateAllGainedSkills(player)

            for i=1, Perks.getMaxIndex()-1 do
                ---@type PerkFactory.Perk
                local perk = Perks.fromIndex(i)
                local perkID = perk and perk:getId()
                if perkID then
                    local currentXP = player:getXp():getXP(perk)
                    if currentXP > 0 then
                        character[perkID] = {
                            gainedXP = allGainedXP[perkID],
                            readXP = charReadXP and charReadXP[perkID],
                            currentXP = currentXP,
                            startingLevel = (passiveSkillsInit[perkID] or startingLevels[perkID]),
                            deductXP = deductibleXP[perkID],
                            multis = multipliers[perkID],
                        }
                    end
                end
            end

            local recipes = SRJ.getGainedRecipes(player)
            local recipeCount = 0
            for _ in pairs(recipes) do recipeCount = recipeCount + 1 end
            character.recipeCount = recipeCount

            character.survivorKills = player:getSurvivorKills()
            character.zombieKills = player:getZombieKills()

            local playerInv = player:getInventory()
            local js = playerInv:getItemsFromFullType("Base.SkillRecoveryBoundJournal")

            for i=0, js:size()-1 do
                local j = js:get(i)
                if j then
                    journals = journals or {}
                    journals[i] = SRJ.modDataHandler.getItemModData(j)
                end
            end
        end

        local sandboxVars = SandboxVars.SkillRecoveryJournal

        return {
            Version = getGameVersion(),
            Mode = (isClient() and "MULTIPLAYER" or "SINGLE PLAYER"),
            ["SANDBOX"] = sandboxVars,
            ["CHARACTER"] = character or "NONE",
            ["JOURNALS"] = journals or "NONE",
        }
    end, "Skill Recovery Journal")
end


local contextSRJ = require "Skill Recovery Journal Context"
if contextSRJ then
    Events.OnPreFillInventoryObjectContextMenu.Add(contextSRJ.doContextMenu)
    Events.OnFillInventoryObjectContextMenu.Add(contextSRJ.postContextMenu)
end

function OnServerWriteCommand(module, command, args)
    -- server sends changes for client to show
    if module == "SkillRecoveryJournal" then
        if command == "write_changes" then 
            SRJ.showHaloProgressText(getPlayer(), args.changesBeingMade, args.updateCount, args.maxUpdates, args.title)
        elseif command == "character_say" then
            SRJ.showCharacterFeedback(getPlayer(), args.text)
        elseif command == "zKills" then
            getPlayer():setZombieKills(args.kills)
        elseif command == "sKills" then
            getPlayer():setSurvivorKills(args.kills)
        end
    end
end

Events.OnServerCommand.Add(OnServerWriteCommand)