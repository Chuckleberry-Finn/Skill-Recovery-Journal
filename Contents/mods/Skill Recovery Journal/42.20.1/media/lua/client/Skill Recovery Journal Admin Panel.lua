require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"
require "ISUI/ISTextEntryBox"
require "ISUI/ISScrollingListBox"
require "ISUI/ISTickBox"
require "ISUI/ISLabel"

local adminEvents = require "Skill Recovery Journal Admin Events"

SRJAdminPanel = ISCollapsableWindow:derive("SRJAdminPanel")

local ROW_H = 22
local PAD = 8

function SRJAdminPanel:initialise()
    ISCollapsableWindow.initialise(self)
end

function SRJAdminPanel:createChildren()
    ISCollapsableWindow.createChildren(self)

    self.usernameEntry = ISTextEntryBox:new("", PAD, 32, 220, ROW_H)
    self.usernameEntry:initialise()
    self.usernameEntry:instantiate()
    self:addChild(self.usernameEntry)

    self.lookupButton = ISButton:new(PAD + 228, 32, 80, ROW_H, "Lookup", self, SRJAdminPanel.onLookup)
    self.lookupButton:initialise()
    self:addChild(self.lookupButton)

    local onlineX = PAD + 228 + 80 + 12
    local onlineListH = 74

    self.onlinePlayersLabel = ISLabel:new(onlineX, 32, 16, "Online (click to look up):", 1, 1, 1, 1, UIFont.Small, true)
    self:addChild(self.onlinePlayersLabel)

    self.onlinePlayersList = ISScrollingListBox:new(onlineX, 32 + ROW_H, self.width - onlineX - PAD, onlineListH)
    self.onlinePlayersList:initialise()
    self.onlinePlayersList.itemheight = ROW_H
    self.onlinePlayersList.doDrawItem = SRJAdminPanel.drawOnlinePlayerItem
    self.onlinePlayersList.onMouseDown = function(listSelf, x, y)
        ISScrollingListBox.onMouseDown(listSelf, x, y)
        local row = listSelf:rowAt(x, y)
        if row and listSelf.items[row] then
            self:onClickOnlinePlayer(listSelf.items[row].item)
        end
    end
    self:addChild(self.onlinePlayersList)

    self.refreshOnlineButton = ISButton:new(onlineX, 32 + ROW_H + onlineListH + 2, 90, ROW_H, "Refresh Online", self, function() self:refreshOnlinePlayers() end)
    self.refreshOnlineButton:initialise()
    self:addChild(self.refreshOnlineButton)

    local afterOnlineListY = 32 + ROW_H + onlineListH + ROW_H + 4

    self.statusLabel = ISLabel:new(PAD, afterOnlineListY + 6, 20, "", 1, 1, 1, 1, UIFont.Small, true)
    self:addChild(self.statusLabel)

    local listTop = afterOnlineListY + 30
    self.journalList = ISScrollingListBox:new(PAD, listTop, 240, self.height - listTop - PAD)
    self.journalList:initialise()
    self.journalList.itemheight = ROW_H
    self.journalList.doDrawItem = SRJAdminPanel.drawJournalListItem
    self.journalList.onMouseDown = function(listSelf, x, y)
        ISScrollingListBox.onMouseDown(listSelf, x, y)
        local row = listSelf:rowAt(x, y)
        if row and listSelf.items[row] then
            self:selectJournal(listSelf.items[row].item.ledgerID)
        end
    end
    self:addChild(self.journalList)

    local editX = PAD + 240 + PAD
    local editW = self.width - editX - PAD
    self.editTop = listTop
    self.editX = editX
    self.editW = editW

    self.fieldList = ISScrollingListBox:new(editX, listTop, editW, self.height - listTop - PAD - 40)
    self.fieldList:initialise()
    self.fieldList.itemheight = ROW_H
    self.fieldList.doDrawItem = SRJAdminPanel.drawFieldRow
    self:addChild(self.fieldList)

    local btnY = self.height - PAD - 40
    self.saveButton = ISButton:new(editX, btnY, 70, ROW_H, "Save", self, SRJAdminPanel.onSave)
    self.saveButton:initialise()
    self:addChild(self.saveButton)

    self.deleteButton = ISButton:new(editX + 78, btnY, 70, ROW_H, "Delete", self, SRJAdminPanel.onDelete)
    self.deleteButton:initialise()
    self:addChild(self.deleteButton)

    self.spawnButton = ISButton:new(editX + 156, btnY, 130, ROW_H, "Spawn Linked Journal", self, SRJAdminPanel.onSpawn)
    self.spawnButton:initialise()
    self:addChild(self.spawnButton)
end


function SRJAdminPanel.drawOnlinePlayerItem(listSelf, y, item, alt)
    listSelf:drawText(item.item, 4, y + 2, 1, 1, 1, 1, UIFont.Small)
    return y + listSelf.itemheight
end


function SRJAdminPanel:onClickOnlinePlayer(username)
    self.usernameEntry:setText(username)
    self:onLookup()
end


function SRJAdminPanel:refreshOnlinePlayers()
    self.onlinePlayersList:clear()

    local players = (isClient() or isServer()) and getOnlinePlayers() or IsoPlayer.getPlayers()
    if not players then return end

    local seen = {}
    for i = 0, players:size() - 1 do
        local p = players:get(i)
        if p then
            local username
            if isClient() or isServer() then
                username = p.getUsername and p:getUsername()
            else
                -- SP always routes to the literal "SinglePlayer" ledger regardless
                -- of character name - listing the character's own name here would
                -- produce a lookup that can never match the real ledger file
                username = "SinglePlayer"
            end
            if username and username ~= "" and not seen[username] then
                seen[username] = true
                self.onlinePlayersList:addItem(username, username)
            end
        end
    end
end


function SRJAdminPanel:setStatus(text)
    if self.statusLabel then self.statusLabel:setName(text or "") end
end


function SRJAdminPanel:onLookup()
    local username = self.usernameEntry:getText()
    if not username or username == "" then
        self:setStatus("Enter a username first.")
        return
    end
    -- guard against accidentally typing the filename instead of just the username
    local stripped = username:gsub("%.json$", ""):gsub("%.txt$", "")
    if stripped ~= username then
        username = stripped
        self.usernameEntry:setText(username)
    end
    self:setStatus("Requesting ledger for " .. username .. " ...")
    adminEvents.processCommand(getPlayer(), "lookup", {username = username})
end


function SRJAdminPanel:onLedgerData(username, ledger)
    self.currentUsername = username
    self.currentLedger = ledger

    self.journalList:clear()
    self:clearFieldRows()
    self.selectedLedgerID = nil

    if not ledger or not ledger.journals then
        self:setStatus("No ledger data for " .. tostring(username) .. " (empty or not found).")
        return
    end

    local count = 0
    for ledgerID, rec in pairs(ledger.journals) do
        count = count + 1
        self.journalList:addItem(ledgerID, {ledgerID = ledgerID, record = rec})
    end
    self:setStatus(count .. " journal(s) found for " .. username .. ".")
end


function SRJAdminPanel.drawJournalListItem(listSelf, y, item, alt)
    local rec = item.item.record
    local label = (rec.author or "?") .. "  [" .. item.item.ledgerID .. "]"
    listSelf:drawText(label, 4, y + 2, 1, 1, 1, 1, UIFont.Small)
    return y + listSelf.itemheight
end


function SRJAdminPanel:selectJournal(ledgerID)
    if not self.currentLedger or not self.currentLedger.journals then return end
    local rec = self.currentLedger.journals[ledgerID]
    if not rec then return end

    self:buildFieldRows(rec, ledgerID)
end


function SRJAdminPanel:clearFieldRows()
    if self.rowEntries then
        for _, box in pairs(self.rowEntries) do
            self.fieldList:removeChild(box)
        end
    end
    self.rowEntries = {}
    self.fieldList:clear()
    self.editingRecord = nil
end


function SRJAdminPanel:buildFieldRows(rec, ledgerID)
    self:clearFieldRows()
    self.editingRecord = rec
    self.selectedLedgerID = ledgerID

    local function addRow(path, value, valueType)
        self.fieldList:addItem(path, {path = path, value = value, valueType = valueType})
    end

    addRow("author", rec.author or "", "string")
    addRow("renamedJournal", rec.renamedJournal and "true" or "false", "bool")

    for skill, xp in pairs(rec.gainedXP or {}) do
        addRow("gainedXP." .. skill, tostring(xp), "number")
    end
    for skill, xp in pairs(rec.flatGainedXP or {}) do
        addRow("flatGainedXP." .. skill, tostring(xp), "number")
    end
    for recipeID, _ in pairs(rec.learnedRecipes or {}) do
        addRow("learnedRecipes." .. recipeID, "true", "recipe")
    end
    if rec.kills then
        addRow("kills.Zombie", tostring(rec.kills.Zombie or 0), "number")
        addRow("kills.Survivor", tostring(rec.kills.Survivor or 0), "number")
    end
    if rec.usedXP then
        for skill, xp in pairs(rec.usedXP) do
            if skill ~= "flat" then
                addRow("usedXP." .. skill, tostring(xp), "number")
            end
        end
        for skill, xp in pairs(rec.usedXP.flat or {}) do
            addRow("usedXP.flat." .. skill, tostring(xp), "number")
        end
    end

    self.rowEntries = {}
    for i, entry in ipairs(self.fieldList.items) do
        local d = entry.item
        local box = ISTextEntryBox:new(d.value, 0, 0, 140, ROW_H - 4)
        box:initialise()
        box:instantiate()
        box.path = d.path
        box.valueType = d.valueType
        self.fieldList:addChild(box) -- positioned in doDrawItem below
        self.rowEntries[d.path] = box
    end

    self:setStatus("Editing " .. (rec.author or "?") .. " [" .. ledgerID .. "]")
end


function SRJAdminPanel.drawFieldRow(listSelf, y, item, alt)
    local d = item.item
    listSelf:drawText(d.path, 4, y + 4, 0.9, 0.9, 0.9, 1, UIFont.Small)
    local panel = listSelf.parent
    local box = panel and panel.rowEntries and panel.rowEntries[d.path]
    if box then
        box:setX(200)
        box:setY(y)
        box:setWidth(listSelf.width - 210)
    end
    return y + listSelf.itemheight
end


-- Reconstructs a full journal record table from the current row entry values.
function SRJAdminPanel:collectEditedRecord()
    local base = self.editingRecord
    local rec = {
        identity = base.identity or {},
        lastInteracted = base.lastInteracted or {},
        pModData = base.pModData or {},
        author = base.author,
        renamedJournal = base.renamedJournal,
        gainedXP = {},
        flatGainedXP = {},
        learnedRecipes = {},
        kills = {Zombie = 0, Survivor = 0},
        usedXP = {flat = {}},
    }

    for path, box in pairs(self.rowEntries or {}) do
        local text = box:getText()

        if path == "author" then
            rec.author = text
        elseif path == "renamedJournal" then
            rec.renamedJournal = (text == "true")
        elseif path:sub(1, 9) == "gainedXP." then
            rec.gainedXP[path:sub(10)] = tonumber(text) or 0
        elseif path:sub(1, 13) == "flatGainedXP." then
            rec.flatGainedXP[path:sub(14)] = tonumber(text) or 0
        elseif path:sub(1, 15) == "learnedRecipes." then
            if text == "true" then
                rec.learnedRecipes[path:sub(16)] = true
            end
        elseif path == "kills.Zombie" then
            rec.kills.Zombie = tonumber(text) or 0
        elseif path == "kills.Survivor" then
            rec.kills.Survivor = tonumber(text) or 0
        elseif path:sub(1, 14) == "usedXP.flat." then
            rec.usedXP.flat[path:sub(15)] = tonumber(text) or 0
        elseif path:sub(1, 7) == "usedXP." then
            rec.usedXP[path:sub(8)] = tonumber(text) or 0
        end
    end

    return rec
end


function SRJAdminPanel:onSave()
    if not self.currentUsername or not self.selectedLedgerID then
        self:setStatus("Select a journal first.")
        return
    end
    local rec = self:collectEditedRecord()
    adminEvents.processCommand(getPlayer(), "saveJournal", {
        username = self.currentUsername,
        ledgerID = self.selectedLedgerID,
        record = rec,
    })
    self:setStatus("Save sent for " .. self.selectedLedgerID .. " ...")
end


function SRJAdminPanel:onDelete()
    if not self.currentUsername or not self.selectedLedgerID then
        self:setStatus("Select a journal first.")
        return
    end
    adminEvents.processCommand(getPlayer(), "deleteJournal", {
        username = self.currentUsername,
        ledgerID = self.selectedLedgerID,
    })
    self:setStatus("Delete sent for " .. self.selectedLedgerID .. " ...")
end


function SRJAdminPanel:onSpawn()
    if not self.currentUsername or not self.selectedLedgerID then
        self:setStatus("Select a journal first.")
        return
    end

    adminEvents.processCommand(getPlayer(), "spawnJournal", {
        username = self.currentUsername,
        ledgerID = self.selectedLedgerID,
    })
    self:setStatus("Spawn requested for " .. self.selectedLedgerID .. " ...")
end


function SRJAdminPanel:onServerResponse(command, args)
    if command == "ledgerData" then
        self:onLedgerData(args.username, args.ledger)
    elseif command == "saveResult" then
        if args.success then
            self:setStatus("Saved " .. args.ledgerID .. ".")
            if self.currentLedger and self.currentLedger.journals then
                self.currentLedger.journals[args.ledgerID] = self:collectEditedRecord()
            end
        else
            local reasonText = args.reason == "no_existing_ledger" and "no existing ledger for this username"
                or args.reason == "no_existing_record" and "no existing journal with this ID"
                or tostring(args.reason)
            self:setStatus("Save FAILED for " .. tostring(args.ledgerID) .. " (" .. reasonText .. ").")
        end
    elseif command == "deleteResult" then
        if args.success then
            self:setStatus("Deleted " .. args.ledgerID .. ".")
            if self.currentLedger and self.currentLedger.journals then
                self.currentLedger.journals[args.ledgerID] = nil
            end
            self.journalList:clear()
            if self.currentLedger and self.currentLedger.journals then
                for ledgerID, rec in pairs(self.currentLedger.journals) do
                    self.journalList:addItem(ledgerID, {ledgerID = ledgerID, record = rec})
                end
            end
            self.fieldList:clear()
        else
            self:setStatus("Delete FAILED for " .. tostring(args.ledgerID) .. ".")
        end
    elseif command == "spawnResult" then
        if args.success then
            self:setStatus("Spawned journal linked to " .. tostring(args.ledgerID) .. ".")
        else
            self:setStatus("Spawn FAILED (" .. tostring(args.reason) .. ").")
        end
    end
end


function SRJAdminPanel:new(x, y, width, height)
    local o = ISCollapsableWindow:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    o.title = "SRJ Admin - Ledger Editor"
    o.resizable = true
    o.rowEntries = {}
    return o
end


local instance = nil

local function toggleSRJAdminPanel()
    if instance and instance:getIsVisible() then
        instance:setVisible(false)
        instance:removeFromUIManager()
        instance = nil
        return
    end

    instance = SRJAdminPanel:new(200, 200, 680, 520)
    instance:initialise()
    instance:addToUIManager()
    instance:refreshOnlinePlayers()
end

local function onAdminResponse(command, args)
    if instance then
        instance:onServerResponse(command, args)
    end
end

local function onServerCommand(module, command, args)
    if module == "SkillRecoveryJournalAdmin" then
        onAdminResponse(command, args)
    end
end
Events.OnServerCommand.Add(onServerCommand)

adminEvents.spResponseHandler = onAdminResponse

SRJAdminPanel.toggle = toggleSRJAdminPanel

require("DebugUIs/DebugMenu/ISDebugMenu.lua")
if ISDebugMenu then
    local ISDebugMenu_setupButtons = ISDebugMenu.setupButtons
    function ISDebugMenu:setupButtons()
        self:addButtonInfo("SRJ Management Panel", function() toggleSRJAdminPanel() end, "MAIN")
        ISDebugMenu_setupButtons(self)
    end
end

require ("ISUI/AdminPanel/ISAdminPanelUI.lua")
if ISAdminPanelUI then
    local ISAdminPanelUI_createChildren = ISAdminPanelUI.createChildren
    function ISAdminPanelUI:createChildren()
        ISAdminPanelUI_createChildren(self)

        local btnW, btnH = 150, 25
        self.srjAdminButton = ISButton:new(self.width - btnW - 10, self.height - btnH - 10, btnW, btnH, "SRJ Ledger Editor", self, function()
            toggleSRJAdminPanel()
        end)
        self.srjAdminButton:initialise()
        self:addChild(self.srjAdminButton)
    end
end