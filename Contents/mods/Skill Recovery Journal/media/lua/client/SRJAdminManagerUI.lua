require "ISUI/ISPanel"
require "ISUI/ISScrollingListBox"
require "ISUI/ISRichTextPanel"
require "ISUI/ISButton"

---@class SRJAdminManagerUI : ISPanel
SRJAdminManagerUI = ISPanel:derive("SRJAdminManagerUI")
SRJAdminManagerUI.instance = nil

function SRJAdminManagerUI:initialise()
    ISPanel.initialise(self)

    local btnWidth = 100
    local btnHeight = 25
    local padding = 10

    -- Header / Title
    self.titleLabel = ISLabel:new(15, 10, 20, "Skill Recovery Journal - Admin Data Manager", 1, 1, 1, 1, UIFont.Medium, true)
    self:addChild(self.titleLabel)

    -- Refresh Button
    self.refreshBtn = ISButton:new(self.width - 230, 10, btnWidth, btnHeight, "Refresh List", self, SRJAdminManagerUI.onRefreshList)
    self.refreshBtn:initialise()
    self.refreshBtn:instantiate()
    self.refreshBtn.borderColor = {r=0.4, g=0.4, b=0.4, a=1}
    self:addChild(self.refreshBtn)

    -- Close Button
    self.closeBtn = ISButton:new(self.width - 115, 10, btnWidth, btnHeight, "Close", self, SRJAdminManagerUI.onClose)
    self.closeBtn:initialise()
    self.closeBtn:instantiate()
    self.closeBtn.borderColor = {r=0.4, g=0.4, b=0.4, a=1}
    self:addChild(self.closeBtn)

    -- Left Panel: User List Box
    local listWidth = 260
    local listTop = 45
    local listHeight = self.height - listTop - 15

    self.userListBox = ISScrollingListBox:new(15, listTop, listWidth, listHeight)
    self.userListBox:initialise()
    self.userListBox:instantiate()
    self.userListBox.selected = 1
    self.userListBox.onmousedown = SRJAdminManagerUI.onSelectUser
    self.userListBox.target = self
    self.userListBox.drawBorder = true
    self:addChild(self.userListBox)

    -- Right Panel: User Detail RichText Panel
    local detailLeft = 15 + listWidth + 15
    local detailWidth = self.width - detailLeft - 15

    self.detailTextPanel = ISRichTextPanel:new(detailLeft, listTop, detailWidth, listHeight)
    self.detailTextPanel:initialise()
    self.detailTextPanel:instantiate()
    self.detailTextPanel.marginRight = 10
    self.detailTextPanel.marginLeft = 10
    self.detailTextPanel.autosetheight = false
    self.detailTextPanel.clip = true
    self:addChild(self.detailTextPanel)

    self:requestListFromServer()
end


function SRJAdminManagerUI:requestListFromServer()
    if isClient() then
        sendClientCommand(self.player, "SkillRecoveryJournal", "requestSavedJournalsList", {})
    end
end


function SRJAdminManagerUI:onRefreshList()
    self.userListBox:clear()
    self.detailTextPanel:setText("<RGB:0.8,0.8,0.8> Fetching saved player journal files from server...")
    self:requestListFromServer()
end


function SRJAdminManagerUI:onClose()
    self:setVisible(false)
    self:removeFromUIManager()
    SRJAdminManagerUI.instance = nil
end


function SRJAdminManagerUI:onSelectUser(item)
    if not item then return end
    local username = item.text
    self.detailTextPanel:setText("<RGB:0.8,0.8,0.8> Loading data for <RGB:1,1,1>" .. username .. " <RGB:0.8,0.8,0.8>...")
    if isClient() then
        sendClientCommand(self.player, "SkillRecoveryJournal", "requestPlayerJournalData", { username = username })
    end
end


function SRJAdminManagerUI:populateUserList(indexMap)
    self.userListBox:clear()
    if not indexMap then return end

    for username, meta in pairs(indexMap) do
        local label = username
        if meta and meta.author and meta.author ~= "" then
            label = username .. " (" .. meta.author .. ")"
        end
        self.userListBox:addItem(label, meta)
    end

    if #self.userListBox.items > 0 then
        self.userListBox.selected = 1
        self:onSelectUser(self.userListBox.items[1])
    else
        self.detailTextPanel:setText("<RGB:1,0.5,0.5> No cached player journal JSON files found on server.")
    end
end


function SRJAdminManagerUI:displayUserData(record)
    if not record then
        self.detailTextPanel:setText("<RGB:1,0.5,0.5> Failed to parse player journal record.")
        return
    end

    local text = "<RGB:1,0.9,0.3> <SIZE:medium> Player Journal Record <SIZE:normal> \n"
    text = text .. "<RGB:0.7,0.7,0.7> Username: <RGB:1,1,1> " .. (record.username or "N/A") .. "\n"
    text = text .. "<RGB:0.7,0.7,0.7> Steam ID: <RGB:1,1,1> " .. tostring(record.steamID or "N/A") .. "\n"
    text = text .. "<RGB:0.7,0.7,0.7> Author Name: <RGB:1,1,1> " .. (record.author or "N/A") .. "\n"
    text = text .. "--------------------------------------------------------\n\n"

    -- Skills & XP
    text = text .. "<RGB:0.3,0.9,0.3> <SIZE:medium> Recoverable Skills & XP: <SIZE:normal> \n"
    local hasSkills = false
    if record.gainedXP then
        for perkID, xp in pairs(record.gainedXP) do
            hasSkills = true
            local perkName = getTextOrNull("IGUI_perks_" .. perkID) or perkID
            text = text .. "  * " .. perkName .. ": " .. string.format("%.2f", tonumber(xp) or 0) .. " XP\n"
        end
    end
    if not hasSkills then text = text .. "  (No skill XP recorded)\n" end
    text = text .. "\n"

    -- Zombie & Survivor Kills
    text = text .. "<RGB:0.3,0.9,0.9> <SIZE:medium> Kill Statistics: <SIZE:normal> \n"
    local zKills = record.kills and record.kills.Zombie or 0
    local sKills = record.kills and record.kills.Survivor or 0
    text = text .. "  * Zombies Killed: " .. zKills .. "\n"
    text = text .. "  * Survivors Killed: " .. sKills .. "\n\n"

    -- Learned Recipes
    text = text .. "<RGB:0.9,0.5,0.9> <SIZE:medium> Learned Recipes: <SIZE:normal> \n"
    local hasRecipes = false
    if record.learnedRecipes then
        for recipeID, _ in pairs(record.learnedRecipes) do
            hasRecipes = true
            text = text .. "  * " .. tostring(recipeID) .. "\n"
        end
    end
    if not hasRecipes then text = text .. "  (No custom recipes learned)\n" end
    text = text .. "\n"

    -- Learned Traits
    text = text .. "<RGB:0.9,0.7,0.3> <SIZE:medium> Learned Traits: <SIZE:normal> \n"
    local hasTraits = false
    if record.learnedTraits then
        for traitID, _ in pairs(record.learnedTraits) do
            hasTraits = true
            local traitObj = TraitFactory.getTrait(traitID)
            local traitName = traitObj and traitObj:getLabel() or traitID
            text = text .. "  * " .. traitName .. "\n"
        end
    end
    if not hasTraits then text = text .. "  (No extra traits learned)\n" end

    self.detailTextPanel:setText(text)
end


function SRJAdminManagerUI:new(player)
    local width = 720
    local height = 500
    local x = (getCore():getOptionWidth() - width) / 2
    local y = (getCore():getOptionHeight() - height) / 2

    local o = ISPanel:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self

    o.player = player
    o.backgroundColor = {r=0, g=0, b=0, a=0.85}
    o.borderColor = {r=0.4, g=0.4, b=0.4, a=1}
    o.moveWithMouse = true

    SRJAdminManagerUI.instance = o
    return o
end


---Listen for server responses
local function onServerCommand(module, command, args)
    if module == "SkillRecoveryJournal" and SRJAdminManagerUI.instance then
        if command == "receiveSavedJournalsList" then
            SRJAdminManagerUI.instance:populateUserList(args)
        elseif command == "receivePlayerJournalData" then
            SRJAdminManagerUI.instance:displayUserData(args)
        end
    end
end

Events.OnServerCommand.Add(onServerCommand)

return SRJAdminManagerUI
