local crossRefMods = {
    ["M13ReadingTweaks"]="M13Reading",
}
local loadedModIDs = {};
local activeModIDs = getActivatedMods()
for i=1, activeModIDs:size() do
    local modID = activeModIDs:get(i-1)
    if crossRefMods[modID] and not loadedModIDs[modID] then
        require (crossRefMods[modID])
        loadedModIDs[modID] = true
    end
end