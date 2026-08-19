require "TimedActions/ISBaseTimedAction"

local SRJ = require "Skill Recovery Journal Main"

---@class SkillRecoveryJournalAction : ISBaseTimedAction
SkillRecoveryJournalAction = ISBaseTimedAction:derive("SkillRecoveryJournalAction")


-- VALIDATION
function SkillRecoveryJournalAction:isValid()
    if not self.isAllowed then return false end

	if self.character:tooDarkToRead() then
		HaloTextHelper.addBadText(self.character, getText("ContextMenu_TooDark"));
		return false
	end
	local vehicle = self.character:getVehicle()
	if vehicle and vehicle:isDriver(self.character) then return not vehicle:isEngineRunning() or vehicle:getSpeed2D() == 0 end
	
    return self.character:getInventory():contains(self.item) and (self.doReading or self.character:getInventory():contains(self.writingTool))
end


-- START (client)
function SkillRecoveryJournalAction:start()
    self.item:setJobDelta(0.0)
    local jobType = getText(((self.doReading and "ContextMenu_Read") or "ContextMenu_Write")) .. " " .. self.item:getName()
    self.item:setJobType(jobType)
    
    self:setAnimVariable("ReadType", "book")
    self:setActionAnim(CharacterActionAnims.Read)
    self:setOverrideHandModels(self.writingTool, self.item)

    self.character:setReading(true)
    self.character:reportEvent("EventRead")

    local logText = ISLogSystem.getGenericLogText(self.character)
    sendClientCommand(self.character, 'ISLogSystem', 'writeLog',
        { loggerName = "PerkLog", logText = logText .. "[" .. self.typeName .. " START]" })
end


-- STOP (client)
function SkillRecoveryJournalAction:stop()
    if getDebug() then
        print(self.typeName .. " stop after " ..
            tostring((getTimestampMs() - self.startTime) / 1000) ..
            " at " .. self.updates .. "/" .. self.durationData.intervals)
    end

    self.character:setReading(false)
    self.item:setJobDelta(0.0)
    self.character:playSound("CloseBook")

    local logText = ISLogSystem.getGenericLogText(self.character)
    sendClientCommand(self.character, 'ISLogSystem', 'writeLog',
        { loggerName = "PerkLog", logText = logText .. "[" .. self.typeName.. "  STOP] (stop)" })

    ISBaseTimedAction.stop(self)
end


-- SERVER START
function SkillRecoveryJournalAction:serverStart()
    if not self.isAllowed then
        if self.netAction then self.netAction:forceComplete() end
        return
    end
    emulateAnimEvent(self.netAction, 10, "update", nil)
end


-- SERVER STOP
function SkillRecoveryJournalAction:serverStop()
    print("SRJ TRACE: serverStop() called, updates=" .. tostring(self.updates))

    if not self.item then print("WARNING: SkillRecoveryJournalAction:serverStop - 'item' not found. ") return end
    if not self.character then print("WARNING: SkillRecoveryJournalAction:serverStop - 'character' not found. ") return end
    SRJ.ledger.syncDisplay(self.item, self.character)
    sendServerCommand(self.character, "SkillRecoveryJournal", "readXP", {data = self.readXP or SRJ.ledger.getReadXP(self.character)})
    self.character:flagForHotSave()
    SRJ.ledger.save(self.character)
    print("SRJ TRACE: serverStop() finished")
end


-- PERFORM (client)
function SkillRecoveryJournalAction:perform()
    self.character:setReading(false)
    self.item:setJobDelta(0.0)

    local logText = ISLogSystem.getGenericLogText(self.character)
    sendClientCommand(self.character, 'ISLogSystem', 'writeLog',
        { loggerName = "PerkLog", logText = logText .. "[" .. self.typeName.. " STOP] (perform)" })

    ISBaseTimedAction.perform(self)
end


-- COMPLETE (server)
function SkillRecoveryJournalAction:complete()
    print("SRJ TRACE: complete() called, updates=" .. tostring(self.updates))

    self.item:setJobDelta(0.0)
    SRJ.ledger.syncDisplay(self.item, self.character)
    sendServerCommand(self.character, "SkillRecoveryJournal", "readXP", {data = self.readXP or SRJ.ledger.getReadXP(self.character)})
    self.character:flagForHotSave()
    SRJ.ledger.save(self.character)
    print("SRJ TRACE: complete() finished")
    return true
end


-- INFINITE ACTION
function SkillRecoveryJournalAction:getDuration()
    return -1
end


-- ANIMATION EVENTS
function SkillRecoveryJournalAction:animEvent(event, parameter)
    if event == "PageFlip" then
        if getGameSpeed() == 1 then
            self.character:playSound("PageFlipBook")
        end
    elseif event == "update" and SRJ.isAuthoritative() then
        self:updateTick()
    end
end


-- UPDATE (client)
function SkillRecoveryJournalAction:update()
    if self:updateTick() and not self.doReading then
        -- writing sound every few ticks FIXME: breaks sound
        --self.playSoundLater = self.playSoundLater or 0
        --if self.playSoundLater > 0 then
        --    self.playSoundLater = self.playSoundLater - 1
        --elseif self.writingToolSound then
        --    self.playSoundLater = (ZombRand(4,8) + SRJ.gameTime:getMultiplier())
        --    self.character:playSound(self.writingToolSound) 
        --end
    end
end


-- SHARED TICK LOGIC (server + client)
function SkillRecoveryJournalAction:updateTick()
    -- should not be called if not isValid()
    if not self.isAllowed then
        if getDebug() then print("SRJ ERROR: Action is not valid! Forcing stop.") end
        if self.netAction then
            self.netAction:forceComplete()
        else
            self:forceStop()
        end
        return false
    end


    local now = SRJ.gameTime:getWorldAgeHours()
    if now < self.updateTime then
        return false
    end

    -- Advance timers
    self.updateTime = self.updateTime + self.updateInterval
    self.updates = self.updates + 1

    self.item:setJobDelta(math.min(self.updates / math.max(self.durationData.intervals, 1), 0.99))

    if isClient() then return true end -- update is handled by server

    -- Shared references
    local player = self.character
    local JMD = SRJ.ledger.getJournalRecord(self.item, player)

    -- Mode-specific processing
    local changesMade, sayText = SRJ.processJournalTick(self, player, JMD, self.doReading)

    if not changesMade then
        if sayText and not self.spoke then
            self.spoke = true
            SRJ.showCharacterFeedback(player, sayText)
        end
    else
        -- Halo text not before X in game time
        if (now - self.lastUpdateTime) * 3600 > 45 then

            -- summarize recipe chunk
            local recipeChunk = self.changesBeingMadeIndex.recipes
            if recipeChunk and recipeChunk > 0 then
                local recipes = (recipeChunk > 1 and "IGUI_Tooltip_Recipes") or "IGUI_Tooltip_Recipe"
                table.insert(self.changesBeingMade, recipeChunk)
                table.insert(self.changesBeingMade, recipes)
            end

            -- summarize zombies chunk
            local zombiesChunk = self.changesBeingMadeIndex.zombies
            if zombiesChunk and zombiesChunk > 0 then
                table.insert(self.changesBeingMade, zombiesChunk)
                table.insert(self.changesBeingMade, "IGUI_char_Zombies_Killed")
            end

            -- summarize survivor chunk
            local survivorChunk = self.changesBeingMadeIndex.survivors
            if survivorChunk and survivorChunk > 0 then
                table.insert(self.changesBeingMade, survivorChunk)
                table.insert(self.changesBeingMade, "IGUI_char_Survivor_Killed")
            end


            local haloKey = self.doReading
                and "IGUI_Tooltip_Learning"
                or  "IGUI_Tooltip_Transcribing"

            SRJ.showHaloProgressText(
                player,
                self.changesBeingMade,
                self.updates,
                self.durationData.intervals,
                haloKey
            )

            sendServerCommand(player, "SkillRecoveryJournal", "readXP", {data = self.readXP or SRJ.ledger.getReadXP(player)})

            self.changesBeingMade = {}
            self.changesBeingMadeIndex = {}
            self.lastUpdateTime = now
        end
    end

    local hardCap = math.max(self.durationData.intervals * 3, 100)
    if self.updates > hardCap then
        print("SRJ ERROR: action exceeded " .. hardCap .. " updates, forcing stop")
        changesMade = false
    end

    -- If nothing changed, we stop
    if not changesMade then
        print("SRJ TRACE: updateTick stopping, isAuthoritative=" .. tostring(SRJ.isAuthoritative()) .. " isClient=" .. tostring(isClient()) .. " hasNetAction=" .. tostring(self.netAction ~= nil))
        if self.netAction then
            self.netAction:forceComplete()
        else
            self:forceStop()
        end
    end

    return changesMade
end


-- CONSTRUCTOR
function SkillRecoveryJournalAction:new(character, item, doReading, writingTool)
    local now = SRJ.gameTime:getWorldAgeHours()

    if getDebug() then
        print((doReading and "Read" or "Write") ..
            "SkillRecoveryJournal:new - at " .. tostring(now) ..
            " isServer " .. tostring(isServer()) ..
            " isClient " .. tostring(isClient()) ..
            " isAuthoritative " .. tostring(SRJ.isAuthoritative()))
    end

    local o = ISBaseTimedAction.new(self, character)

    -- vanilla fields
    o.stopOnWalk        = false
    o.stopOnRun         = true
    o.ignoreHandsWounds = true
    o.caloriesModifier  = 0.5
    o.forceProgressBar  = false
    o.useProgressBar = false

    -- timings, update intervals between updates in in-game hours
    o.updateInterval        = 10 / 3600 -- every in-game 10 seconds
    o.defaultUpdateInterval = 3.48 / 3600 -- legacy ~3.48 sec to maintain old duration
    o.timeFactor            = o.updateInterval / o.defaultUpdateInterval
    o.updateTime            = now + o.updateInterval -- do first update after one interval
    o.lastUpdateTime        = 0
    o.startTime             = getTimestampMs()

    o.updates = -1 -- update counter

    -- params
    o.character = character
    o.item      = item

    o.doReading = doReading
    o.typeName  = doReading and "ReadSkillRecoveryJournal" or "WriteSkillRecoveryJournal"

    -- check if we are able to proceed (gainedXP, illiterate, permissions)
    if not item then
        print(o.typeName .. " ERROR: ITEM WAS NULL!!") 
        return o 
    end

    -- server: authoritative ledger record (also handles legacy migration).
    -- client: read-only display mirror, preview only, never authoritative.
    local JMD = SRJ.isAuthoritative()
        and SRJ.ledger.getJournalRecord(item, character)
        or SRJ.modDataHandler.getDisplayData(item)

    local isAllowed, sayText = SRJ.checkStaticConditions(character, JMD, doReading)

    if isAllowed and doReading and SRJ.isAuthoritative() then
        local canRead, readSayText = SRJ.ledger.canRead(item, character)
        if not canRead then
            isAllowed = false
            sayText = readSayText
        end
    end

	o.isAllowed = isAllowed

    -- if not allowed, give feedback and stop here
	if not o.isAllowed then 
        if sayText then character:Say(getText(sayText)) end
        -- safe stub so any later debug print / access to durationData.intervals can't crash on nil
        o.durationData = { intervals = 0 }
        o.changesBeingMade = {}
        o.changesBeingMadeIndex = {}
        return o
    end

    if SRJ.isAuthoritative() then SRJ.ledger.touchInteraction(item, character) end
    o.readXP = SRJ.isAuthoritative() and SRJ.ledger.getReadXP(character) or nil

    -- ACTION SETUP
    o.gainedRecipes = {}

    -- READING MODE
    if doReading then
        -- collect recipes from journal not yet known by the player
        if JMD and SandboxVars.SkillRecoveryJournal.RecoverRecipes == true then
            if SRJ.isAuthoritative() then
                local learnedRecipes = JMD.learnedRecipes
                if learnedRecipes then
                    for recipeID,_ in pairs(learnedRecipes) do
                        if not character:isRecipeActuallyKnown(recipeID) then
                            table.insert(o.gainedRecipes, recipeID)
                        end
                    end
                end
            else
                for i = 1, (JMD.learnedRecipeCount or 0) do
                    table.insert(o.gainedRecipes, i)
                end
            end
        end

    -- WRITING MODE
    else
        -- gained recipes since last write
        if SandboxVars.SkillRecoveryJournal.RecoverRecipes == true then
            local learnedRecipes = JMD.learnedRecipes
            o.gainedRecipes = SRJ.getGainedRecipes(character, learnedRecipes)
        end

        o.gainedSkills, o.flatGainedSkills = SRJ.calculateAllGainedSkills(character)
        o.gainedSkills = o.gainedSkills or false
        o.flatGainedSkills = o.flatGainedSkills or false

        
        -- fields specific to writing
        o.writingTool    = writingTool
        o.writingToolSound = "PenWriteSounds"
        if character:getInventory():contains("Pencil") then
            o.writingToolSound = "PencilWriteSounds"
        end
        
        -- determine if writing is allowed
        o.willWrite = true

        local gainedZKills, gainedSKills = SRJ.calculateGainedKills(JMD, character, false)
        local hasPendingKills = gainedZKills > 0 or gainedSKills > 0

        if not o.gainedSkills and not o.flatGainedSkills and (#o.gainedRecipes <= 0) and not hasPendingKills then
            sayText = "IGUI_PlayerText_DontHaveAnyXP"

            o.willWrite = false
        end
        
        if sayText then
            character:Say(getText(sayText))
            o.spoke = true
        end

        if o.willWrite then
            -- store author name in journal, init identity for security
            JMD["identity"] = JMD["identity"] or {}
            JMD.author = character:getFullName()
        end
    end
    
    -- durationData: XP rates, recipe chunking, kill rates, etc.
    o.durationData = SRJ.calculateReadWriteRates(
        character,
        item,
        o.timeFactor,
        o.gainedRecipes,
        o.gainedSkills,
        o.flatGainedSkills,
        doReading,
        o.updateInterval
    )

    o.changesBeingMade = {}
    o.changesBeingMadeIndex = {}
    o.killsComplete = false

    return o
end
