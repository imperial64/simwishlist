local ADDON_NAME = ...
local SimWishlist = {}
_G[ADDON_NAME] = SimWishlist

SimWishlistDB = SimWishlistDB or {}
SimWishlistDB.catalystData = SimWishlistDB.catalystData or {}
SimWishlistDB.developerMode = SimWishlistDB.developerMode or false
SimWishlistDB.showDebugMessages = SimWishlistDB.showDebugMessages or false

local initialized = false
local mainFrame, importFrame, helpFrame, panel, optionsFrame

-- Forward declarations
local BuildAllProfilesPanel

-- Minimap icon data
local minimapButton

-- ===== Debug System =====
local function DebugPrint(message, color)
    if not SimWishlistDB or not SimWishlistDB.developerMode or not SimWishlistDB.showDebugMessages then
        return
    end
    
    local colorCode = color or "|cff1eff00"
    print(colorCode .. "SimWishlist Debug:|r " .. message)
end

local function DebugError(message)
    if not SimWishlistDB or not SimWishlistDB.developerMode or not SimWishlistDB.showDebugMessages then
        return
    end
    
    print("|cffff2020SimWishlist Debug Error:|r " .. message)
end

-- ===== Utils =====
local function CharKey()
    local n = UnitName("player") or "Player";
    local r = GetRealmName() or "Realm";
    return n .. "-" .. r
end

local function Trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function SplitLines(str)
    local t = {}
    for line in (str or ""):gmatch("([^\r\n]+)") do
        t[#t + 1] = line
    end
    return t
end

local function ShortNumber(n)
    if not n or n == 0 or n ~= n then
        return "0"
    end
    local a = math.abs(n);
    if a >= 1000000 then
        return string.format("%.1fm", n / 1000000)
    elseif a >= 10000 then
        return string.format("%.1fk", n / 1000)
    else
        return string.format("%.0f", n)
    end
end

local function GetTableSize(t)
    if not t then
        return 0
    end
    local count = 0;
    for _ in pairs(t) do
        count = count + 1
    end
    return count
end

local function NowISO()
    local t = GetServerTime()
    -- Use WoW's date function instead of os.date
    local utc = date("!%Y-%m-%dT%H:%M:%SZ", t)
    return utc
end

-- ===== Bonus ID Handling System =====
local function StripBonusID(itemLink)
    if not itemLink then return nil end
    
    -- Pattern to remove the last numeric component (bonus ID) from item links
    -- This preserves the base item structure while removing bonus IDs
    local stripped = itemLink:gsub("(item:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:)%d+:", "%1:")
    return stripped
end

local function NormalizeItemLink(itemLink)
    if not itemLink then return nil end
    
    local stripped = StripBonusID(itemLink)
    local itemID = C_Item.GetItemInfoInstant(stripped)
    
    return {
        original = itemLink,
        normalized = stripped,
        itemID = itemID,
        hasBonusID = itemLink ~= stripped,
        bonusID = nil -- Will be extracted if present
    }
end

local function ExtractBonusID(itemLink)
    if not itemLink then return nil end
    
    -- Extract the last numeric component which represents the bonus ID
    local bonusID = itemLink:match(":([^:]*)$")
    if bonusID and tonumber(bonusID) then
        return tonumber(bonusID)
    end
    return nil
end

-- ===== Item Icon Loading System =====
local function LoadItemIcon(itemID, callback)
    if not itemID then
        callback(nil)
        return
    end
    
    -- Check if item data is already cached
    if C_Item.IsItemDataCachedByID(itemID) then
        -- Try GetItemInfoInstant first (faster)
        local _, _, _, quality, _, _, _, _, _, icon = C_Item.GetItemInfoInstant(itemID)
        if icon then
            callback(icon, quality)
            return
        end
        
        -- Fallback to GetItemInfo
        local itemName, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(itemID)
        if itemTexture then
            callback(itemTexture, quality)
            return
        end
    end
    
    -- Item data not cached, request it asynchronously
    C_Item.RequestLoadItemDataByID(itemID)
    
    -- Wait for the item to load
    local function WaitForItem()
        if C_Item.IsItemDataCachedByID(itemID) then
            -- Try GetItemInfoInstant first
            local _, _, _, quality, _, _, _, _, _, icon = C_Item.GetItemInfoInstant(itemID)
            if icon then
                callback(icon, quality)
                return
            end
            
            -- Fallback to GetItemInfo
            local itemName, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(itemID)
            if itemTexture then
                callback(itemTexture, quality)
                return
            end
            
            -- If still no icon, use fallback
            callback(134400, quality) -- Default fallback texture
        else
            -- Still not loaded, wait a bit more
            C_Timer.After(0.1, WaitForItem)
        end
    end
    
    -- Start waiting
    C_Timer.After(0.1, WaitForItem)
end

-- Cache for normalized item links to avoid repeated processing
local normalizedLinkCache = {}
local function GetNormalizedItemLink(itemLink)
    if not itemLink then 
        DebugError("GetNormalizedItemLink called with nil itemLink")
        return nil 
    end
    
    if not normalizedLinkCache[itemLink] then
        normalizedLinkCache[itemLink] = NormalizeItemLink(itemLink)
        if normalizedLinkCache[itemLink] then
            DebugPrint("Created normalized link for: " .. itemLink)
        else
            DebugError("Failed to create normalized link for: " .. itemLink)
        end
    end
    
    return normalizedLinkCache[itemLink]
end

-- Function to check if two item links represent the same base item
local function IsSameBaseItem(itemLink1, itemLink2)
    if not itemLink1 or not itemLink2 then return false end
    
    local norm1 = GetNormalizedItemLink(itemLink1)
    local norm2 = GetNormalizedItemLink(itemLink2)
    
    if not norm1 or not norm2 then return false end
    
    return norm1.normalized == norm2.normalized
end

-- Enhanced CreateItemMetadata with proper icon loading
local function CreateItemMetadata(itemID, itemLink, profileData)
    if not itemID then return nil end
    
    local normalized = NormalizeItemLink(itemLink or ("item:" .. itemID))
    
    -- Start with a temporary metadata object
    local metadata = {
        itemID = itemID,
        itemLink = itemLink or ("item:" .. itemID),
        normalizedLink = normalized.normalized,
        hasBonusID = normalized.hasBonusID,
        bonusID = ExtractBonusID(itemLink or ""),
        quality = nil,
        icon = 134400, -- Default fallback texture
        profileData = profileData,
        location = nil,
        guid = nil,
        tooltipGetter = function() 
            return C_TooltipInfo and C_TooltipInfo.GetItemByID(itemID) or nil
        end,
        iconLoaded = false
    }
    
    -- Load the icon asynchronously
    LoadItemIcon(itemID, function(icon, quality)
        if icon then
            metadata.icon = icon
            metadata.quality = quality
            metadata.iconLoaded = true
            
            DebugPrint(string.format("CreateItemMetadata: Icon loaded for item %d: texture=%s", itemID, tostring(icon)))
        else
            DebugError(string.format("CreateItemMetadata: Failed to load icon for item %d", itemID))
        end
    end)
    
    return metadata
end

-- ===== DB =====
function SimWishlist.EnsureCharacterData()
    local ck = CharKey()
    SimWishlistDB.characters = SimWishlistDB.characters or {}

    -- Migrate legacy data if it exists
    if SimWishlistDB.profiles and SimWishlistDB.profiles[ck] and not SimWishlistDB.characters[ck] then
        local oldProfile = SimWishlistDB.profiles[ck]
        SimWishlistDB.characters[ck] = {
            options = oldProfile.options or {
                welcomeMessage = true,
                enableTooltip = true,
                developerMode = false,
                showDebugMessages = false
            },
            profiles = {},
            activeProfile = nil
        }

        -- Migrate the old profile to new format
        if oldProfile.byDungeon and next(oldProfile.byDungeon) then
            local profileName = oldProfile.meta and oldProfile.meta.specName or "Legacy Profile"
            SimWishlistDB.characters[ck].profiles[profileName] = {
                meta = oldProfile.meta or {
                    created = NowISO(),
                    profileName = profileName,
                    baseDPS = nil
                },
                bySource = oldProfile.byDungeon, -- Renamed from byDungeon to bySource
                lookup = oldProfile.lookup or {}
            }
            SimWishlistDB.characters[ck].activeProfile = profileName
            print("|cff1eff00SimWishlist:|r Migrated legacy profile to '" .. profileName .. "'")
        end

        -- Clear old data
        SimWishlistDB.profiles[ck] = nil
    end

    SimWishlistDB.characters[ck] = SimWishlistDB.characters[ck] or {
        options = {
            welcomeMessage = true,
            enableTooltip = true,
            developerMode = false,
            showDebugMessages = false
        },
        profiles = {},
        activeProfile = nil
    }
    return SimWishlistDB.characters[ck]
end

function SimWishlist.GetProfile(profileName)
    local char = SimWishlist.EnsureCharacterData()
    profileName = profileName or char.activeProfile or "Default"

    if not char.profiles[profileName] then
        char.profiles[profileName] = {
            meta = {
                created = NowISO(),
                profileName = profileName,
                baseDPS = nil
            },
            bySource = {},
            lookup = {},
            links = {
                _global = {},
                bySource = {}
            }
        }
    end

    -- Normalize legacy profiles that may have had links as a flat table
    local L = char.profiles[profileName].links
    if not (L and L._global and L.bySource) then
        char.profiles[profileName].links = {
            _global = L or {},
            bySource = {}
        }
    end

    return char.profiles[profileName], profileName
end

function SimWishlist.GetAllProfiles()
    local char = SimWishlist.EnsureCharacterData()
    return char.profiles
end

function SimWishlist.SetActiveProfile(profileName)
    local char = SimWishlist.EnsureCharacterData()
    char.activeProfile = profileName
end

-- Legacy compatibility
function SimWishlist.EnsureProfile()
    return SimWishlist.GetProfile()
end

local function RebuildLookup(profile)
    profile.lookup = {}
    profile.normalizedLookup = {} -- New: lookup by normalized item links
    
    for source, items in pairs(profile.bySource or {}) do
        for id, score in pairs(items) do
            if type(score) == "number" then
                -- Get or create the item metadata
                local itemLink = profile.links and (profile.links._global[id] or profile.links.bySource[source] and profile.links.bySource[source][id])
                local metadata = CreateItemMetadata(id, itemLink, {score = score, source = source})
                
                if score > 0 then
                    -- Regular positive score item
                    local L = profile.lookup[id] or {
                        score = 0,
                        sources = {},
                        metadata = metadata
                    }
                    if score > (L.score or 0) then
                        L.score = score
                        L.metadata = metadata
                    end
                    L.sources[source] = true
                    profile.lookup[id] = L
                    
                    -- Also store in normalized lookup for bonus ID handling
                    if metadata.normalizedLink then
                        local normKey = metadata.normalizedLink
                        if not profile.normalizedLookup[normKey] then
                            profile.normalizedLookup[normKey] = {}
                        end
                        table.insert(profile.normalizedLookup[normKey], {
                            itemID = id,
                            score = score,
                            source = source,
                            metadata = metadata
                        })
                    end
                elseif score < 0 and catalystData[id] then
                    -- Negative score catalyst source item - use catalyst result score for lookup
                    local catalyst = catalystData[id][1]
                    if catalyst then
                        local L = profile.lookup[id] or {
                            score = 0,
                            sources = {},
                            isCatalystSource = true,
                            metadata = metadata
                        }
                        -- We'll get the actual catalyst score when we need it
                        L.catalystId = catalyst.catalystId
                        L.sources[source] = true
                        profile.lookup[id] = L
                        
                        -- Also store in normalized lookup for catalyst items
                        if metadata.normalizedLink then
                            local normKey = metadata.normalizedLink
                            if not profile.normalizedLookup[normKey] then
                                profile.normalizedLookup[normKey] = {}
                            end
                            table.insert(profile.normalizedLookup[normKey], {
                                itemID = id,
                                score = score,
                                source = source,
                                metadata = metadata,
                                isCatalystSource = true,
                                catalystId = catalyst.catalystId
                            })
                        end
                    end
                end
            end
        end
    end
end

-- Global lookup across all profiles for tooltips
function SimWishlist.GetItemInfo(itemID)
    local allProfiles = SimWishlist.GetAllProfiles()
    local results = {}
    local bestScore = 0

    for profileName, profile in pairs(allProfiles) do
        local L = profile.lookup and profile.lookup[itemID]
        if L then
            if L.score and L.score > 0 then
                -- Regular positive score item
                table.insert(results, {
                    profileName = profileName,
                    score = L.score,
                    sources = L.sources,
                    baseDPS = profile.meta.baseDPS,
                    metadata = L.metadata -- Include metadata for enhanced tooltips
                })
                if L.score > bestScore then
                    bestScore = L.score
                end
            elseif L.isCatalystSource and L.catalystId then
                -- Catalyst source item - get the catalyst result score from items in this profile
                local catalystScore = nil
                for _, sourceItems in pairs(profile.bySource) do
                    if sourceItems[L.catalystId] and sourceItems[L.catalystId] > 0 then
                        catalystScore = sourceItems[L.catalystId]
                        break
                    end
                end

                if catalystScore and catalystScore > 0 then
                    table.insert(results, {
                        profileName = profileName,
                        score = catalystScore,
                        sources = L.sources,
                        baseDPS = profile.meta.baseDPS,
                        isCatalystSource = true,
                        metadata = L.metadata -- Include metadata for enhanced tooltips
                    })
                    if catalystScore > bestScore then
                        bestScore = catalystScore
                    end
                end
            end
        end
    end

    -- Sort by score descending
    table.sort(results, function(a, b)
        return (a.score or 0) > (b.score or 0)
    end)

    return results, bestScore
end

-- Enhanced item lookup that can find items by normalized links (bonus ID handling)
function SimWishlist.GetItemInfoByLink(itemLink)
    if not itemLink then return nil end
    
    local normalized = GetNormalizedItemLink(itemLink)
    if not normalized then return nil end
    
    local allProfiles = SimWishlist.GetAllProfiles()
    local results = {}
    local bestScore = 0
    
    -- First try direct item ID lookup
    local directResults, directBestScore = SimWishlist.GetItemInfo(normalized.itemID)
    if directResults and #directResults > 0 then
        results = directResults
        bestScore = directBestScore
    end
    
    -- Then check normalized lookup for bonus ID variations
    for profileName, profile in pairs(allProfiles) do
        if profile.normalizedLookup and profile.normalizedLookup[normalized.normalized] then
            for _, itemData in ipairs(profile.normalizedLookup[normalized.normalized]) do
                -- Skip if we already have this item ID
                local alreadyHave = false
                for _, existing in ipairs(results) do
                    if existing.metadata and existing.metadata.itemID == itemData.itemID then
                        alreadyHave = true
                        break
                    end
                end
                
                if not alreadyHave then
                    local result = {
                        profileName = profileName,
                        score = itemData.score,
                        sources = itemData.sources,
                        baseDPS = profile.meta.baseDPS,
                        metadata = itemData.metadata,
                        isCatalystSource = itemData.isCatalystSource,
                        catalystId = itemData.catalystId
                    }
                    
                    table.insert(results, result)
                    if itemData.score > bestScore then
                        bestScore = itemData.score
                    end
                end
            end
        end
    end
    
    -- Sort by score descending
    table.sort(results, function(a, b)
        return (a.score or 0) > (b.score or 0)
    end)
    
    return results, bestScore
end

-- ===== SIMWISH Import (text only) =====
local function Import_SIMWISH(text)
    local lines = SplitLines(text or "")
    local negativeItems = {} -- Track negative items for summary
    if #lines == 0 then
        return false, "Empty import"
    end
    local header = lines[1]
    if not header:find("^%s*SIMWISH%s+v1") then
        return false, "Header missing. Expected 'SIMWISH v1'"
    end
    local ts = header:match("v1%s+([^%s]+)")
    local profileName = header:match("v1%s+[^%s]+%s+(.+)$") or "Unknown"
    profileName = Trim(profileName)

    -- Check if this profile already exists and has data
    local char = SimWishlist.EnsureCharacterData()
    local existingProfile = char.profiles[profileName]
    local hasExistingData = existingProfile and existingProfile.bySource and next(existingProfile.bySource)

    -- If profile exists with data, create a unique name instead of overwriting
    if hasExistingData then
        local originalName = profileName
        local counter = 2
        while char.profiles[profileName] and char.profiles[profileName].bySource and
            next(char.profiles[profileName].bySource) do
            profileName = originalName .. " (" .. counter .. ")"
            counter = counter + 1
        end

    end

    -- Get or create the profile with this name
    local profile = SimWishlist.GetProfile(profileName)
    profile.meta = profile.meta or {}
    profile.meta.imported = NowISO()
    profile.meta.srcTimestamp = ts or "unknown"
    profile.meta.profileName = profileName
    profile.bySource = {}
    profile.meta.baseDPS = nil
    profile.links = {
        _global = {},
        bySource = {}
    }

    -- First pass: Parse catalyst data and base DPS
    -- Clear existing catalyst data but maintain reference to saved data
    for k in pairs(catalystData) do
        catalystData[k] = nil
    end
    for i = 2, #lines do
        local line = Trim(lines[i])
        if line ~= "" then
            local base = line:match("^#%s*base_dps%s*=%s*([%d%.]+)")
            if base then
                profile.meta.baseDPS = tonumber(base) or profile.meta.baseDPS
            elseif line:match("^!CatalystData") then
                -- Parse simple catalyst data
                local dataStr = line:match("^!CatalystData%s+(.+)!$")
                if dataStr then
                    -- Parse using the same logic as regular items
                    for pair in dataStr:gmatch("([^,]+)") do
                        local sourceIdStr, catalystIdStr = pair:match("^(%d+):(%d+)$")
                        if sourceIdStr and catalystIdStr then
                            local sourceId = tonumber(sourceIdStr)
                            local catalystId = tonumber(catalystIdStr)

                            if sourceId and catalystId then
                                catalystData[sourceId] = {{
                                    catalystId = catalystId,
                                    catalystName = "Catalyst Item " .. catalystId,
                                    isBetterWhenCatalyzed = true
                                }}
                            end
                        end
                    end
                end
            end
        end
    end

    -- Parse item hyperlink maps
    -- Global format:  !Links <id>=<|Hitem:...|h[Name]|h|r>,<id>=<link>!
    -- Per-source:     !Links[<source>] <id>=<link>,<id>=<link>!
    for i = 2, #lines do
        local line = Trim(lines[i])
        -- Per-source
        local src, dataStr = line:match("^!Links%[(.-)%]%s+(.+)!$")
        if src and dataStr then
            profile.links.bySource[src] = profile.links.bySource[src] or {}
            for pair in dataStr:gmatch("([^,]+)") do
                local idStr, linkStr = pair:match("^(%d+)%s*=%s*(.+)$")
                if idStr and linkStr then
                    profile.links.bySource[src][tonumber(idStr)] = linkStr
                end
            end
        else
            -- Global
            local gData = line:match("^!Links%s+(.+)!$")
            if gData then
                for pair in gData:gmatch("([^,]+)") do
                    local idStr, linkStr = pair:match("^(%d+)%s*=%s*(.+)$")
                    if idStr and linkStr then
                        profile.links._global[tonumber(idStr)] = linkStr
                    end
                end
            end
        end
    end

    -- Call RebuildLookup after catalyst data is populated so it's available during item parsing
    RebuildLookup(profile)

    -- Second pass: Parse items now that catalyst data is available
    local totalItems = 0
    for i = 2, #lines do
        local line = Trim(lines[i])
        if line ~= "" and not line:match("^[#!]") then
            local source, rest = line:match("^(.-)\t(.+)$")
            if not source then
                source, rest = line:match("^(.-)\\t(.+)$")
            end
            if not source then
                source, rest = line:match("^(.-)%s%s+(.+)$")
            end
            if source and rest then
                local items = {}
                for pair in rest:gmatch("([^,]+)") do
                    local id, sc = pair:match("^(%d+):?([%-%d%.]*)$")
                    id = tonumber(id)
                    local score = tonumber(sc) or 0
                    if id then
                        if score > 0 then
                            -- Regular positive score item
                            items[id] = score
                            totalItems = totalItems + 1
                        elseif score < 0 then
                            -- Check if it has catalyst conversion
                            if catalystData[id] then
                                local catalyst = catalystData[id][1]
                                local itemName = GetItemInfo(id) or ("Item " .. id)
                                local catalystName = GetItemInfo(catalyst.catalystId) or
                                                         ("Catalyst " .. catalyst.catalystId)

                                -- This is a catalyst source item, include it
                                items[id] = score
                                totalItems = totalItems + 1
                                table.insert(negativeItems, {
                                    id = id,
                                    name = itemName,
                                    score = score,
                                    catalystId = catalyst.catalystId,
                                    catalystName = catalystName
                                })
                            end
                        end
                    end
                end
                if next(items) then
                    profile.bySource[source] = items
                end
            end
        end
    end

    -- Save catalyst data in profile metadata for repopulation after reload
    profile.meta.catalystData = {}
    for sourceId, catalystInfo in pairs(catalystData) do
        profile.meta.catalystData[tostring(sourceId)] = catalystInfo
    end

    RebuildLookup(profile)
    SimWishlist.SetActiveProfile(profileName)
    local sourceCount = 0;
    for _ in pairs(profile.bySource) do
        sourceCount = sourceCount + 1
    end

    print(string.format("|cff1eff00SimWishlist:|r imported profile '%s' with %d sources, %d items.", profileName,
        sourceCount, totalItems))
    return true, "Imported " .. tostring(#lines - 1) .. " lines (SIMWISH)", profileName
end

-- ===== Catalyst Detection Using Raidbots Data =====
-- Store catalyst data from SIMWISH import (use saved data)
catalystData = SimWishlistDB.catalystData -- sourceItemID -> array of {catalystId, catalystName, sourceName} (GLOBAL)

-- Function to repopulate catalyst data from saved profile metadata
local function RepopulateCatalystData()
    -- Clear existing catalyst data
    for k in pairs(catalystData) do
        catalystData[k] = nil
    end

    -- Scan all characters and profiles for saved catalyst data
    local foundMappings = 0
    for charKey, charData in pairs(SimWishlistDB.characters or {}) do
        for profileName, profile in pairs(charData.profiles or {}) do
            if profile.meta and profile.meta.catalystData then
                -- Restore catalyst data from this profile's metadata
                for sourceId, catalystInfo in pairs(profile.meta.catalystData) do
                    if not catalystData[tonumber(sourceId)] then
                        catalystData[tonumber(sourceId)] = catalystInfo
                        foundMappings = foundMappings + 1
                    end
                end
            end
        end
    end

    return foundMappings
end

-- Catalyst parsing is now done inline in Import_SIMWISH function
local function ParseCompactCatalystData(catalystLine)
    local dataStr = catalystLine:match("^#%s*catalyst%s*=%s*(.+)$")
    if not dataStr then
        return
    end

    DebugPrint("Parsing compact catalyst data: " .. dataStr)

    -- Simple parsing for compact format: {"sourceId": catalystId, ...}
    catalystData = {} -- Reset catalyst data

    -- Simple string-based parsing to avoid regex issues
    -- Remove braces and split by commas
    local cleanData = dataStr:gsub("[{}]", "")
    DebugPrint("Cleaned data: " .. cleanData)

    for pair in cleanData:gmatch("([^,]+)") do
        local trimmedPair = pair:gsub("^%s+", ""):gsub("%s+$", "") -- trim whitespace
        DebugPrint("Processing pair: " .. trimmedPair)

        local sourceIdStr, catalystIdStr = trimmedPair:match('"(%d+)"%s*:%s*(%d+)')
        if sourceIdStr and catalystIdStr then
            local sourceId = tonumber(sourceIdStr)
            local catalystId = tonumber(catalystIdStr)

            DebugPrint("Parsed: " .. sourceId .. " -> " .. catalystId)

            if sourceId and catalystId then
                catalystData[sourceId] = {{
                    catalystId = catalystId,
                    catalystName = "Catalyst Item " .. catalystId, -- We'll get the real name from game
                    isBetterWhenCatalyzed = true -- Only better items are included in compact format
                }}
                DebugPrint("Added catalyst mapping: " .. sourceId .. " -> " .. catalystId)
            end
        end
    end

    DebugPrint("Loaded " .. GetTableSize(catalystData) .. " catalyst mappings")
end

-- Function to parse catalyst data from SIMWISH import line (legacy format)
local function ParseCatalystData(catalystLine)
    local dataStr = catalystLine:match("^#%s*catalyst_data%s*=%s*(.+)$")
    if not dataStr then
        return
    end

    -- Try to parse the JSON data
    local success, data = pcall(function()
        -- Simple JSON parser for our specific format
        -- Format: {"sourceId": [{"catalystId": id, "catalystName": "name", ...}], ...}
        local result = {}
        DebugPrint("Parsing catalyst data: " .. dataStr)

        -- Parse the simplified JSON format
        for sourceIdStr, catalystArrayStr in dataStr:gmatch('"(%d+)"%s*:%s*(%[.-%])') do
            local sourceId = tonumber(sourceIdStr)
            DebugPrint("Found source ID: " .. sourceId)
            if sourceId then
                result[sourceId] = {}
                -- Parse catalyst array
                for catalystStr in catalystArrayStr:gmatch('{.-}') do
                    local catalystId = catalystStr:match('"catalystId":(%d+)')
                    local catalystName = catalystStr:match('"catalystName":"([^"]*)"')
                    local sourceName = catalystStr:match('"sourceName":"([^"]*)"')
                    local sourceScore = catalystStr:match('"sourceScore":([%d%.%-]+)')
                    local catalystScore = catalystStr:match('"catalystScore":([%d%.%-]+)')
                    local isBetterWhenCatalyzed = catalystStr:match('"isBetterWhenCatalyzed":(%w+)')

                    if catalystId and catalystName then
                        table.insert(result[sourceId], {
                            catalystId = tonumber(catalystId),
                            catalystName = catalystName,
                            sourceName = sourceName,
                            sourceScore = tonumber(sourceScore) or 0,
                            catalystScore = tonumber(catalystScore) or 0,
                            isBetterWhenCatalyzed = isBetterWhenCatalyzed == "true"
                        })
                        DebugPrint("Added catalyst " .. catalystId .. " for source " .. sourceId)
                    end
                end
            end
        end
        return result
    end)

    if success and data then
        for sourceId, catalysts in pairs(data) do
            catalystData[sourceId] = catalysts
            DebugPrint("Loaded " .. #catalysts .. " catalyst(s) for source item " .. sourceId)
        end
        DebugPrint("Total catalyst sources loaded: " .. GetTableSize(data))
    else
        DebugPrint("Failed to parse catalyst data")
    end
end

-- Function to find potential catalyst upgrades for an item
local function FindCatalystUpgrades(itemID)
    local potentialUpgrades = {}
    local char = SimWishlist.EnsureCharacterData()

    -- Check if this item has catalyst conversions
    local catalysts = catalystData[itemID]
    if not catalysts then
        return nil
    end

    -- For each potential catalyst conversion
    for _, catalyst in ipairs(catalysts) do
        local catalystItemID = catalyst.catalystId

        -- Check if the catalyst item is in any of our wishlists
        for profileName, profile in pairs(char.profiles or {}) do
            if profile.lookup and profile.lookup[catalystItemID] then
                local itemData = profile.lookup[catalystItemID]
                table.insert(potentialUpgrades, {
                    profileName = profileName,
                    itemID = catalystItemID,
                    score = itemData.score,
                    baseDPS = profile.meta.baseDPS,
                    catalystName = catalyst.catalystName,
                    sourceName = catalyst.sourceName,
                    isBetterWhenCatalyzed = catalyst.isBetterWhenCatalyzed
                })
            end
        end
    end

    -- Sort by score descending
    table.sort(potentialUpgrades, function(a, b)
        return (a.score or 0) > (b.score or 0)
    end)

    return #potentialUpgrades > 0 and potentialUpgrades or nil
end

-- Function to check if an item should show catalyst information (source item that's better when catalyzed)
local function ShouldShowCatalystInfo(itemID)
    local catalysts = catalystData[itemID]
    if not catalysts then
        return false
    end

    -- Check if any of the catalyst conversions are better than the source
    for _, catalyst in ipairs(catalysts) do
        if catalyst.isBetterWhenCatalyzed then
            return true
        end
    end

    return false
end

-- ===== Tooltip hook (single registration) =====
local function SetupTooltipHook()
    local function AnnotateTooltip(tooltip, data)
        if not tooltip then
            return
        end
        local char = SimWishlist.EnsureCharacterData()
        if not char.options.enableTooltip then
            return
        end

        local link
        if data and data.hyperlink then
            link = data.hyperlink
        end
        if not link and data and data.id then
            link = ("item:%d"):format(data.id)
        end
        if not link and tooltip.GetItem then
            local _;
            _, link = tooltip:GetItem()
        end
        if not link then
            return
        end

        -- Use enhanced item lookup that handles bonus IDs
        local results, bestScore = SimWishlist.GetItemInfoByLink(link)
        local id = C_Item.GetItemInfoInstant(link)
        local catalystUpgrades = id and FindCatalystUpgrades(id) or nil
        local shouldShowCatalyst = id and ShouldShowCatalystInfo(id) or false
        
        -- Get item metadata for enhanced display
        local itemMetadata = nil
        if results and #results > 0 and results[1].metadata then
            itemMetadata = results[1].metadata
        end

        -- Check if this item has only catalyst sources (negative scores)
        local hasOnlyNegativeScores = true
        local hasRegularItems = false

        if results and #results > 0 then
            for _, result in ipairs(results) do
                if result.score > 0 and not result.isCatalystSource then
                    hasOnlyNegativeScores = false
                    hasRegularItems = true
                    break
                end
            end
        end

        -- Show regular SIMWISH data if available and not catalyst-only
        if results and #results > 0 and hasRegularItems then
            -- Add empty line for separation
            tooltip:AddLine(" ")

            -- Add SIMWISH header
            tooltip:AddLine("|cffffd100SIMWISH|r")

            -- Add profile details (show up to 5 profiles)
            for i = 1, math.min(5, #results) do
                local result = results[i]
                if result.score > 0 and not result.isCatalystSource then -- Only show positive scores that are NOT catalyst sources
                    local dataText
                    local baseDPSNum = type(result.baseDPS) == "number" and result.baseDPS or tonumber(result.baseDPS) or 0
                    if baseDPSNum and baseDPSNum > 0 then
                        local dps = baseDPSNum * (result.score / 100)
                        dataText = string.format("+%s dps (+%.1f%%)", ShortNumber(dps), result.score)
                    else
                        dataText = string.format("+%.1f%%", result.score)
                    end
                    local profileText = string.format("|cffaaaaaa%s - %s|r", result.profileName, dataText)
                    tooltip:AddLine(profileText)
                end
            end

            if #results > 5 then
                tooltip:AddLine("|cffaaaaaa... and " .. (#results - 5) .. " more profiles|r")
            end
        end

        -- Show catalyst upgrade information if available
        if catalystUpgrades and #catalystUpgrades > 0 then
            -- Add separator
            tooltip:AddLine(" ")

            -- Add SIMWISH header only if we haven't shown regular SIMWISH data
            if hasOnlyNegativeScores then
                tooltip:AddLine("|cffffd100SIMWISH|r")
            end
            tooltip:AddLine("|cff00ff96WHEN CATALYZED|r")

            -- Show potential upgrades (limit to top 3)
            for i = 1, math.min(3, #catalystUpgrades) do
                local upgrade = catalystUpgrades[i]
                local dataText
                local baseDPSNum = type(upgrade.baseDPS) == "number" and upgrade.baseDPS or tonumber(upgrade.baseDPS) or 0
                if baseDPSNum and baseDPSNum > 0 then
                    local dps = baseDPSNum * (upgrade.score / 100)
                    dataText = string.format("+%s dps (+%.1f%%)", ShortNumber(dps), upgrade.score)
                else
                    dataText = string.format("+%.1f%%", upgrade.score)
                end

                local upgradeText = string.format("|cffaaaaaa%s - %s|r", upgrade.profileName, dataText)
                tooltip:AddLine(upgradeText)

                -- Show catalyst name if available - use actual item name instead of ID
                if upgrade.catalystId then
                    local catalystItemName = GetItemInfo(upgrade.catalystId) or upgrade.catalystName or
                                                 ("Item " .. upgrade.catalystId)
                    tooltip:AddLine("|cff888888Becomes: " .. catalystItemName .. "|r")
                end
            end

            if #catalystUpgrades > 3 then
                tooltip:AddLine("|cffaaaaaa... and " .. (#catalystUpgrades - 3) .. " more catalyst upgrades|r")
            end
        end

        -- Enhanced item information display
        if itemMetadata then
            -- Add separator
            tooltip:AddLine(" ")
            
            -- Show item quality information
            if itemMetadata.quality and itemMetadata.quality > 1 then
                local qualityColor = ITEM_QUALITY_COLORS[itemMetadata.quality]
                if qualityColor then
                    local qualityName = _G["ITEM_QUALITY" .. itemMetadata.quality .. "_DESC"] or "Unknown"
                    tooltip:AddLine("|cff" .. qualityColor.color .. "Quality: " .. qualityName .. "|r")
                end
            end
            
            -- Show bonus ID information if present
            if itemMetadata.hasBonusID and itemMetadata.bonusID then
                tooltip:AddLine("|cff00ffffBonus ID: " .. itemMetadata.bonusID .. "|r")
            end
            
            -- Removed the "Base Item:" line for cleaner tooltips
        end
        
        -- Only show tooltip if we added any information
        if (results and #results > 0) or (catalystUpgrades and #catalystUpgrades > 0) or itemMetadata then
            tooltip:Show()
        end
    end

    local hooked = false
    if TooltipDataProcessor and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
            AnnotateTooltip(tooltip, data)
        end)
        hooked = true
    end
    if not hooked then
        if GameTooltip and GameTooltip.HookScript and GameTooltip:HasScript("OnTooltipSetItem") then
            GameTooltip:HookScript("OnTooltipSetItem", function(tip)
                AnnotateTooltip(tip, nil)
            end)
        end
        if ItemRefTooltip and ItemRefTooltip.HookScript and ItemRefTooltip:HasScript("OnTooltipSetItem") then
            ItemRefTooltip:HookScript("OnTooltipSetItem", function(tip)
                AnnotateTooltip(tip, nil)
            end)
        end
    end
end

-- Compose a link; prefer stored hyperlink
local function ComposeItemLink(itemID)
    local char = SimWishlist.EnsureCharacterData()
    if char and char.activeProfile then
        local p = char.profiles and char.profiles[char.activeProfile]
        if p and p.links and p.links._global and p.links._global[itemID] then
            return p.links._global[itemID]
        end
    end
    return "item:" .. tostring(itemID) -- fallback
end

-- ===== UI helpers =====
local function AddEscClose(frameName)
    if not frameName then
        return
    end
    if UISpecialFrames then
        for _, n in ipairs(UISpecialFrames) do
            if n == frameName then
                return
            end
        end
        table.insert(UISpecialFrames, frameName)
    end
end

local function MakeBackButton(parent, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(56, 22)
    b:SetPoint("TOPLEFT", 6, -6)
    b:SetText("Back")
    b:SetScript("OnClick", onClick)
    return b
end

-- ===== Grid builder =====
local function CreateItemButton(parent, itemID, pct, baseDPS, isCatalystSource, link)
    -- Add error handling and validation
    if not parent then
        print("|cffff2020SimWishlist Error:|r CreateItemButton called with nil parent")
        return nil
    end
    
    if not itemID or not pct then
        DebugError(string.format("CreateItemButton called with invalid itemID or pct: %s, %s", tostring(itemID), tostring(pct)))
        return nil
    end
    
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(36, 36)
    
    -- Create icon
    btn.icon = btn:CreateTexture(nil, "ARTWORK");
    btn.icon:SetAllPoints(true)
    
    -- Get item metadata for enhanced display
    local itemLink = link or ComposeItemLink(itemID)
    local metadata = GetNormalizedItemLink(itemLink)
    
    -- Set initial fallback texture
    btn.icon:SetTexture(134400)
    btn.link = itemLink
    btn.metadata = metadata
    
    -- Load the icon asynchronously using our new system
    LoadItemIcon(itemID, function(icon, quality)
        if icon and btn.icon then
            btn.icon:SetTexture(icon)
            DebugPrint(string.format("CreateItemButton: Icon loaded for item %d: texture=%s", itemID, tostring(icon)))
            
            -- Add quality border if item has quality (ensure quality is a number)
            if quality and type(quality) == "number" and quality > 1 then
                if btn.qualityBorder then
                    btn.qualityBorder:Hide()
                end
                btn.qualityBorder = btn:CreateTexture(nil, "OVERLAY")
                btn.qualityBorder:SetAllPoints(true)
                local qualityColor = ITEM_QUALITY_COLORS[quality]
                if qualityColor then
                    btn.qualityBorder:SetVertexColor(qualityColor.r, qualityColor.g, qualityColor.b)
                end
            end
        else
            DebugError(string.format("CreateItemButton: Failed to load icon for item %d", itemID))
        end
    end)

    -- Bonus ID indicator (small text in top-left corner)
    if metadata and metadata.hasBonusID and metadata.bonusID then
        btn.bonusIDText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        btn.bonusIDText:SetPoint("TOPLEFT", 1, -1)
        btn.bonusIDText:SetText("|cff00ffff" .. metadata.bonusID .. "|r")
        btn.bonusIDText:SetShadowOffset(1, -1)
    end

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(self.link) -- global hook adds our SIMWISH line once
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Main DPS badge
    btn.badge = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    btn.badge:SetPoint("BOTTOMRIGHT", -1, 1)
    local label
    -- Ensure baseDPS is a number before comparison
    local baseDPSNum = type(baseDPS) == "number" and baseDPS or tonumber(baseDPS) or 0
    if baseDPSNum and baseDPSNum > 0 then
        label = "+" .. ShortNumber(baseDPSNum * (pct / 100))
    else
        label = string.format("+%.1f%%", pct)
    end
    btn.badge:SetText(label)

    -- Different color for catalyst source items
    if isCatalystSource then
        btn.badge:SetTextColor(0, 1, 0.6) -- Green color for catalyst items
    else
        btn.badge:SetTextColor(1, 0.85, 0.25) -- Regular yellow
    end
    btn.badge:SetShadowOffset(1, -1)
    
    -- Debug: Log successful button creation
    if btn and btn.icon and btn.badge then
        DebugPrint(string.format("Button created successfully for item %d", itemID))
    else
        DebugError(string.format("Button creation failed for item %d", itemID))
    end
    
    return btn
end

-- ===== Profile State Management =====
-- Store collapsed states per character
local function GetProfileCollapsedStates()
    local char = SimWishlist.EnsureCharacterData()
    char.collapsedProfiles = char.collapsedProfiles or {}
    return char.collapsedProfiles
end

local function IsProfileCollapsed(profileName)
    local collapsed = GetProfileCollapsedStates()
    -- Default to collapsed (true) if not explicitly set
    return collapsed[profileName] ~= false
end

local function SetProfileCollapsed(profileName, isCollapsed)
    local collapsed = GetProfileCollapsedStates()
    collapsed[profileName] = isCollapsed
end

-- ===== Profile Management Functions =====
local function ShowProfileRenameDialog(oldName)
    local dialog = CreateFrame("Frame", "SimWishRenameDialog", UIParent, "BasicFrameTemplateWithInset")
    dialog:SetSize(320, 140)
    dialog:SetPoint("CENTER")
    dialog:SetFrameStrata("DIALOG")
    dialog.title = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    dialog.title:SetPoint("TOP", 0, -8)
    dialog.title:SetText("Rename Profile")

    local label = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", 15, -35)
    label:SetText("New name:")

    local editBox = CreateFrame("EditBox", nil, dialog, "InputBoxTemplate")
    editBox:SetSize(200, 20)
    editBox:SetPoint("TOPLEFT", 15, -55)
    editBox:SetText(oldName)
    editBox:HighlightText()
    editBox:SetAutoFocus(true)

    local function doRename()
        local newName = Trim(editBox:GetText() or "")
        if newName == "" or newName == oldName then
            dialog:Hide()
            return
        end

        local char = SimWishlist.EnsureCharacterData()
        if char.profiles[newName] then
            print("|cffff2020SimWishlist:|r Profile '" .. newName .. "' already exists!")
            return
        end

        -- Rename the profile
        char.profiles[newName] = char.profiles[oldName]
        char.profiles[newName].meta.profileName = newName
        char.profiles[oldName] = nil

        -- Update active profile if needed
        if char.activeProfile == oldName then
            char.activeProfile = newName
        end

        -- Update collapsed state tracking
        local collapsed = GetProfileCollapsedStates()
        if collapsed[oldName] ~= nil then
            collapsed[newName] = collapsed[oldName]
            collapsed[oldName] = nil
        end

        print("|cff1eff00SimWishlist:|r Profile renamed from '" .. oldName .. "' to '" .. newName .. "'")
        dialog:Hide()
        RepopulateCatalystData() -- Refresh catalyst data
        -- Check if we're in the new tabbed system
        if SimWishlist.RefreshProfilesTab and mainFrame and mainFrame:IsShown() then
            SimWishlist.RefreshProfilesTab() -- Use new refresh for tabbed UI
            SimWishlist.RefreshBrowseTab() -- Also refresh browse tab
        elseif BuildAllProfilesPanel then
            BuildAllProfilesPanel() -- Use original refresh for old UI
        end
    end

    local okBtn = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    okBtn:SetSize(60, 22)
    okBtn:SetPoint("BOTTOMRIGHT", -15, 10)
    okBtn:SetText("OK")
    okBtn:SetScript("OnClick", doRename)

    local cancelBtn = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    cancelBtn:SetSize(60, 22)
    cancelBtn:SetPoint("RIGHT", okBtn, "LEFT", -10, 0)
    cancelBtn:SetText("Cancel")
    cancelBtn:SetScript("OnClick", function()
        dialog:Hide()
    end)

    editBox:SetScript("OnEnterPressed", doRename)
    editBox:SetScript("OnEscapePressed", function()
        dialog:Hide()
    end)

    dialog:Show()
    editBox:SetFocus()
end

local function ShowProfileDeleteDialog(profileName)
    local dialog = CreateFrame("Frame", "SimWishDeleteDialog", UIParent, "BasicFrameTemplateWithInset")
    dialog:SetSize(300, 120)
    dialog:SetPoint("CENTER")
    dialog:SetFrameStrata("DIALOG")
    dialog.title = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    dialog.title:SetPoint("TOP", 0, -8)
    dialog.title:SetText("Delete Profile")

    local label = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("CENTER", 0, 10)
    label:SetText("Delete profile '" .. profileName .. "'?")

    local function doDelete()
        local char = SimWishlist.EnsureCharacterData()
        char.profiles[profileName] = nil

        -- Update active profile if it was the deleted one
        if char.activeProfile == profileName then
            local remainingProfiles = {}
            for name in pairs(char.profiles) do
                table.insert(remainingProfiles, name)
            end
            char.activeProfile = remainingProfiles[1] or nil
        end

        -- Clean up collapsed state tracking
        local collapsed = GetProfileCollapsedStates()
        collapsed[profileName] = nil

        print("|cffff2020SimWishlist:|r Profile '" .. profileName .. "' deleted")
        dialog:Hide()
        RepopulateCatalystData() -- Refresh catalyst data
        -- Check if we're in the new tabbed system
        if SimWishlist.RefreshProfilesTab and mainFrame and mainFrame:IsShown() then
            SimWishlist.RefreshProfilesTab() -- Use new refresh for tabbed UI
            SimWishlist.RefreshBrowseTab() -- Also refresh browse tab
        elseif BuildAllProfilesPanel then
            BuildAllProfilesPanel() -- Use original refresh for old UI
        end
    end

    local deleteBtn = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    deleteBtn:SetSize(60, 22)
    deleteBtn:SetPoint("BOTTOMRIGHT", -15, 10)
    deleteBtn:SetText("Delete")
    deleteBtn:SetScript("OnClick", doDelete)

    local cancelBtn = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    cancelBtn:SetSize(60, 22)
    cancelBtn:SetPoint("RIGHT", deleteBtn, "LEFT", -10, 0)
    cancelBtn:SetText("Cancel")
    cancelBtn:SetScript("OnClick", function()
        dialog:Hide()
    end)

    dialog:Show()
end

-- ===== Simple Profile Display =====
local function BuildAllProfilesPanel()
    if not panel then
        return
    end

    -- Recreate content frame fresh each time
    if panel.content then
        panel.content:Hide()
        panel.content:SetParent(nil)
    end

    panel.content = CreateFrame("Frame", nil, panel.scroll)
    panel.content:SetSize(1, 1)
    panel.scroll:SetScrollChild(panel.content)

    local allProfiles = SimWishlist.GetAllProfiles()
    local profileNames = {}
    for name in pairs(allProfiles) do
        table.insert(profileNames, name)
    end
    table.sort(profileNames)

    if #profileNames == 0 then
        -- No profiles, show empty message
        local emptyText = panel.content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        emptyText:SetPoint("CENTER", 0, 0)
        emptyText:SetText(
            "No profiles imported yet.\\n\\nUse /simwish import to add SIMWISH data.\\n\\nType /simwish debug to check profile status.")
        emptyText:SetJustifyH("CENTER")
        panel.content:SetSize(400, 200)
        return
    end

    local y = -6
    local leftPadding = 10
    local itemSize, gap = 36, 6
    local contentWidth = panel.scroll:GetWidth() - 24
    if contentWidth <= 0 then
        contentWidth = 360
    end
    local cols = math.max(1, math.floor((contentWidth) / (itemSize + gap)))

    -- Display each profile
    for _, profileName in ipairs(profileNames) do
        local profile = allProfiles[profileName]
        local isCollapsed = IsProfileCollapsed(profileName)

        -- Collapse/Expand button
        local collapseBtn = CreateFrame("Button", nil, panel.content, "UIPanelButtonTemplate")
        collapseBtn:SetSize(20, 18)
        collapseBtn:SetPoint("TOPLEFT", leftPadding, y)
        collapseBtn:SetText(isCollapsed and "+" or "-")
        collapseBtn:SetScript("OnClick", function()
            SetProfileCollapsed(profileName, not isCollapsed)
            -- Check if we're in the new tabbed system
            if SimWishlist.RefreshProfilesTab and mainFrame and mainFrame:IsShown() then
                SimWishlist.RefreshProfilesTab() -- Use new refresh for tabbed UI
            else
                BuildAllProfilesPanel() -- Use original refresh for old UI
            end
        end)

        -- Profile header with management buttons
        local profileHeader = panel.content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        profileHeader:SetPoint("LEFT", collapseBtn, "RIGHT", 5, 0)
        profileHeader:SetText("|cff00ff00" .. profileName .. "|r")

        -- Rename button
        local renameBtn = CreateFrame("Button", nil, panel.content, "UIPanelButtonTemplate")
        renameBtn:SetSize(50, 18)
        renameBtn:SetPoint("LEFT", profileHeader, "RIGHT", 10, 0)
        renameBtn:SetText("Rename")
        renameBtn:SetScript("OnClick", function()
            ShowProfileRenameDialog(profileName)
        end)

        -- Update button
        local updateBtn = CreateFrame("Button", nil, panel.content, "UIPanelButtonTemplate")
        updateBtn:SetSize(50, 18)
        updateBtn:SetPoint("LEFT", renameBtn, "RIGHT", 5, 0)
        updateBtn:SetText("Update")
        updateBtn:SetScript("OnClick", function()
            RepopulateCatalystData()
            -- Check if we're in the new tabbed system
            if SimWishlist.RefreshProfilesTab and mainFrame and mainFrame:IsShown() then
                SimWishlist.RefreshProfilesTab() -- Use new refresh for tabbed UI
            else
                BuildAllProfilesPanel() -- Use original refresh for old UI
            end
        end)

        -- Delete button
        local deleteBtn = CreateFrame("Button", nil, panel.content, "UIPanelButtonTemplate")
        deleteBtn:SetSize(45, 18)
        deleteBtn:SetPoint("LEFT", updateBtn, "RIGHT", 5, 0)
        deleteBtn:SetText("Delete")
        deleteBtn:SetScript("OnClick", function()
            ShowProfileDeleteDialog(profileName)
        end)

        y = y - 25

        -- Only show profile content if not collapsed
        if not isCollapsed then

            -- Profile info
            local profileInfo = panel.content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            profileInfo:SetPoint("TOPLEFT", leftPadding + 5, y)
            profileInfo:SetText(("|cffccccccImported:|r %s (%s)"):format(profile.meta.imported or "?",
                profile.meta.srcTimestamp or "?"))
            y = y - 18

            -- Get sources for this profile
            local sourceNames = {}
            for k in pairs(profile.bySource or {}) do
                table.insert(sourceNames, k)
            end
            table.sort(sourceNames)

            -- Display sources
            for _, sourceName in ipairs(sourceNames) do
                local items = profile.bySource[sourceName]
                local sourceLinks = (profile.links and profile.links.bySource and profile.links.bySource[sourceName]) or
                                        nil
                local arr = {}

                -- Add all items from this source
                for id, score in pairs(items) do
                    if score > 0 then
                        local lnk = (sourceLinks and sourceLinks[id]) or
                                        (profile.links and profile.links._global and profile.links._global[id])
                        table.insert(arr, {
                            id = id,
                            score = score,
                            link = lnk
                        })
                    elseif score < 0 and catalystData[id] then
                        -- Negative score item (catalyst source) - only show if catalyst result is in wishlist
                        local catalyst = catalystData[id][1]
                        if catalyst then
                            -- Check if the catalyst result is actually in this profile with positive score
                            local catalystScore = nil
                            for _, sourceItems in pairs(profile.bySource) do
                                if sourceItems[catalyst.catalystId] and sourceItems[catalyst.catalystId] > 0 then
                                    catalystScore = sourceItems[catalyst.catalystId]
                                    break
                                end
                            end

                            -- Only add if catalyst result is in the wishlist
                            if catalystScore and catalystScore > 0 then
                                local lnk = (sourceLinks and sourceLinks[id]) or
                                                (profile.links and profile.links._global and profile.links._global[id])
                                table.insert(arr, {
                                    id = id,
                                    score = catalystScore,
                                    isCatalystSource = true,
                                    link = lnk
                                })
                            end
                        end
                    end

                end

                table.sort(arr, function(a, b)
                    return (a.score or 0) > (b.score or 0)
                end)

                if #arr > 0 then
                    -- Source header
                    local sourceHeader = panel.content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                    sourceHeader:SetPoint("TOPLEFT", leftPadding + 10, y)
                    sourceHeader:SetText("|cffffff00" .. sourceName .. "|r")
                    y = y - 20

                    -- Items for this source
                    local row, col = 0, 0
                    for _, it in ipairs(arr) do
                        local btn = CreateItemButton(panel.content, it.id, it.score, profile.meta.baseDPS,
                            it.isCatalystSource, it.link)
                        local x = leftPadding + 20 + col * (itemSize + gap)
                        local yy = y - row * (itemSize + gap)
                        btn:SetPoint("TOPLEFT", x, yy)
                        col = col + 1
                        if col >= cols then
                            col = 0;
                            row = row + 1
                        end
                    end
                    y = y - (row + 1) * (itemSize + gap) - 10
                end
            end

        end -- End of collapsed content if statement

        -- Add space between profiles
        y = y - 15
    end

    panel.content:SetSize(contentWidth, math.max(200, math.abs(y) + 20))
end

-- ===== Navigation =====
function SimWishlist.ShowMain()
    if not mainFrame then
        return
    end
    mainFrame:Show()
    if importFrame then
        importFrame:Hide()
    end
    if helpFrame then
        helpFrame:Hide()
    end
    if panel then
        panel:Hide()
    end
    if optionsFrame then
        optionsFrame:Hide()
    end

    -- Set default tab if none selected
    if SimWishlist.ShowTab then
        local anySelected = false
        for _, tab in pairs(mainFrame.tabs or {}) do
            if tab.selected then
                anySelected = true;
                break
            end
        end
        if not anySelected then
            SimWishlist.ShowTab("import")
        end
    end
end

function SimWishlist.ShowImport()
    SimWishlist.ShowMain()
    if SimWishlist.ShowTab then
        SimWishlist.ShowTab("import")
    end
end

function SimWishlist.ShowHelp()
    if helpFrame then
        helpFrame:Show();
        if mainFrame then
            mainFrame:Hide()
        end
    end
end

function SimWishlist.ShowPanel()
    SimWishlist.ShowMain()
    if SimWishlist.ShowTab then
        SimWishlist.ShowTab("browse")
    end
end

function SimWishlist.ShowOptions()
    SimWishlist.ShowMain()
    if SimWishlist.ShowTab then
        SimWishlist.ShowTab("settings")
    else
        -- Fallback to old options system
        if not optionsFrame then
            return
        end
        optionsFrame:Show()
        if mainFrame then
            mainFrame:Hide()
        end
    end
    -- Update checkbox states
    local char = SimWishlist.EnsureCharacterData()
    if optionsFrame.welcomeCheck then
        optionsFrame.welcomeCheck:SetChecked(char.options.welcomeMessage)
    end
    if optionsFrame.tooltipCheck then
        optionsFrame.tooltipCheck:SetChecked(char.options.enableTooltip)
    end
    if optionsFrame.minimapCheck then
        optionsFrame.minimapCheck:SetChecked(char.options.showMinimap ~= false) -- Default to true
    end
    if optionsFrame.devModeCheck then
        optionsFrame.devModeCheck:SetChecked(char.options.developerMode)
    end
    if optionsFrame.debugCheck then
        optionsFrame.debugCheck:SetChecked(char.options.showDebugMessages)
    end
    -- Hide reload prompt when first opening options
    if optionsFrame.reloadPrompt then
        optionsFrame.reloadPrompt:Hide()
        optionsFrame.reloadBtn:Hide()
    end
end

-- ===== Minimap Icon =====
local function CreateMinimapButton()
    if minimapButton then
        return
    end

    local char = SimWishlist.EnsureCharacterData()
    -- Default to showing minimap icon
    if char.options.showMinimap == nil then
        char.options.showMinimap = true
    end

    -- Don't create if disabled
    if not char.options.showMinimap then
        return
    end

    minimapButton = CreateFrame("Button", "SimWishlistMinimapButton", Minimap)
    minimapButton:SetFrameStrata("MEDIUM")
    minimapButton:SetSize(32, 32)
    minimapButton:SetFrameLevel(8)
    minimapButton:RegisterForClicks("AnyUp")
    minimapButton:SetHighlightTexture(136477) -- Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight

    -- Icon texture
    local icon = minimapButton:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", 0, 0)
    icon:SetTexture(134400) -- Interface\\Icons\\INV_Scroll_05 (scroll icon)
    minimapButton.icon = icon

    -- Border
    local border = minimapButton:CreateTexture(nil, "OVERLAY")
    border:SetSize(52, 52)
    border:SetPoint("TOPLEFT", 0, 0)
    border:SetTexture(136430) -- Interface\\Minimap\\MiniMap-TrackingBorder

    -- Tooltip
    minimapButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("|cffffd100SimWishlist|r")
        GameTooltip:AddLine("Left-click: Open SimWishlist", 1, 1, 1)
        GameTooltip:AddLine("Right-click: Quick Import", 1, 1, 1)
        GameTooltip:Show()
    end)

    minimapButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Click handler
    minimapButton:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            SimWishlist.ShowMain()
        elseif button == "RightButton" then
            SimWishlist.ShowImport()
        end
    end)

    -- Position the button
    char.minimapPos = char.minimapPos or 225 -- Default position

    local function UpdatePosition()
        local angle = math.rad(char.minimapPos or 225)
        local x, y = math.sin(angle) * 80, math.cos(angle) * 80
        minimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
    end

    UpdatePosition()

    -- Make it draggable
    minimapButton:SetScript("OnDragStart", function()
        minimapButton:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local px, py = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            px, py = px / scale, py / scale
            local angle = math.deg(math.atan2(px - mx, py - my))
            char.minimapPos = angle
            UpdatePosition()
        end)
    end)

    minimapButton:SetScript("OnDragStop", function()
        minimapButton:SetScript("OnUpdate", nil)
    end)

    minimapButton:RegisterForDrag("LeftButton")
end

-- ===== Interface Options Panel =====
local function CreateInterfaceOptionsPanel()
    local panel = CreateFrame("Frame")
    panel.name = "SimWishlist"

    -- Title
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("|cffffd100SimWishlist|r")

    -- Description
    local desc = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    desc:SetText("SIMWISH importer with grouped display and item tooltips")

    -- Command button
    local commandBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    commandBtn:SetSize(120, 22)
    commandBtn:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -20)
    commandBtn:SetText("/simwish")
    commandBtn:SetScript("OnClick", function()
        SimWishlist.ShowMain()
        -- Close the interface options if it's open
        if SettingsPanel and SettingsPanel:IsVisible() then
            SettingsPanel:Hide()
        elseif InterfaceOptionsFrame and InterfaceOptionsFrame:IsVisible() then
            InterfaceOptionsFrame:Hide()
        end
    end)

    -- Info text
    local info = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    info:SetPoint("TOPLEFT", commandBtn, "BOTTOMLEFT", 0, -16)
    info:SetText("Click the button above to open SimWishlist")

    -- Features list
    local features = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    features:SetPoint("TOPLEFT", info, "BOTTOMLEFT", 0, -20)
    features:SetWidth(500)
    features:SetJustifyH("LEFT")
    features:SetText("Features:\n" .. "• Import SIMWISH data from Raidbots simulations\n" ..
                         "• Enhanced item tooltips with DPS upgrade information\n" ..
                         "• Multi-profile support for different gear sets\n" ..
                         "• Catalyst item detection and tooltip enhancement\n" ..
                         "• Organized item display by source (dungeons, raids)\n" ..
                         "• Minimap icon for quick access")

    -- Version info
    local version = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    version:SetPoint("BOTTOMRIGHT", -16, 16)
    version:SetText("Version 0.9.7")

    -- Register the panel
    if InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    elseif Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        Settings.RegisterAddOnCategory(category)
    end

    return panel
end

-- ===== UI Helper Functions =====
local SimWishLC = {}

function SimWishLC:MakeTab(parent, text, index, onClick, totalTabs)
    local tab = CreateFrame("Button", nil, parent)

    -- Calculate dynamic width based on total tabs (minus some margin)
    local totalWidth = parent:GetWidth() - 20 -- 10px margin on each side
    local tabWidth = totalWidth / totalTabs

    tab:SetSize(tabWidth, 28)
    tab:SetPoint("TOPLEFT", (index - 1) * tabWidth + 10, -30)

    -- Tab background - Darker theme
    tab.bg = tab:CreateTexture(nil, "BACKGROUND")
    tab.bg:SetAllPoints()
    tab.bg:SetColorTexture(0.1, 0.1, 0.1, 0.9) -- Much darker

    -- Tab highlight
    tab.highlight = tab:CreateTexture(nil, "HIGHLIGHT")
    tab.highlight:SetAllPoints()
    tab.highlight:SetColorTexture(0.3, 0.3, 0.3, 0.5)

    -- Tab text
    tab.text = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    tab.text:SetPoint("CENTER")
    tab.text:SetText(text)

    -- Tab selection state
    tab.selected = false

    function tab:SetSelected(selected)
        self.selected = selected
        if selected then
            self.bg:SetColorTexture(0.25, 0.35, 0.45, 1.0)
            self.text:SetTextColor(1.0, 1.0, 1.0)
        else
            self.bg:SetColorTexture(0.1, 0.1, 0.1, 0.9) -- Darker unselected
            self.text:SetTextColor(0.8, 0.8, 0.8)
        end
    end

    if onClick then
        tab:SetScript("OnClick", onClick)
    end
    return tab
end

-- Additional styling functions for consistent UI
function SimWishLC:MakeBtn(parent, text, x, y, width, height, onClick, style)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(width or 100, height or 24)
    btn:SetPoint("TOPLEFT", x, y)

    -- Custom button background - Darker theme
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.08, 0.08, 0.08, 0.95) -- Much darker
    btn.bg = bg

    -- Button border
    local border = btn:CreateTexture(nil, "BORDER")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(0.25, 0.25, 0.25, 0.9) -- Darker border

    -- Button text
    local btnText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btnText:SetPoint("CENTER")
    btnText:SetText(text)
    btnText:SetTextColor(0.9, 0.9, 0.9)
    btn.text = btnText

    -- Style variants
    if style == "primary" then
        bg:SetColorTexture(0.15, 0.4, 0.6, 0.9) -- Blue
        btnText:SetTextColor(1.0, 1.0, 1.0)
    elseif style == "danger" then
        bg:SetColorTexture(0.6, 0.15, 0.15, 0.9) -- Red
        btnText:SetTextColor(1.0, 1.0, 1.0)
    elseif style == "success" then
        bg:SetColorTexture(0.15, 0.6, 0.15, 0.9) -- Green
        btnText:SetTextColor(1.0, 1.0, 1.0)
    end

    -- Moderately vibrant hover effects (middle ground)
    btn:SetScript("OnEnter", function()
        if style == "primary" then
            bg:SetColorTexture(0.25, 0.55, 0.8, 1.0) -- Moderate blue
            btnText:SetTextColor(1.0, 1.0, 1.0)
            border:SetColorTexture(0.4, 0.7, 0.9, 1.0) -- Moderate blue border
        elseif style == "danger" then
            bg:SetColorTexture(0.8, 0.25, 0.25, 1.0) -- Moderate red
            btnText:SetTextColor(1.0, 1.0, 1.0)
            border:SetColorTexture(0.9, 0.4, 0.4, 1.0) -- Moderate red border
        elseif style == "success" then
            bg:SetColorTexture(0.25, 0.8, 0.25, 1.0) -- Moderate green
            btnText:SetTextColor(1.0, 1.0, 1.0)
            border:SetColorTexture(0.4, 0.9, 0.4, 1.0) -- Moderate green border
        else
            bg:SetColorTexture(0.3, 0.3, 0.3, 1.0) -- Moderate gray
            btnText:SetTextColor(1.0, 1.0, 1.0)
            border:SetColorTexture(0.45, 0.45, 0.45, 1.0) -- Moderate gray border
        end
    end)

    btn:SetScript("OnLeave", function()
        if style == "primary" then
            bg:SetColorTexture(0.15, 0.4, 0.6, 0.9)
            btnText:SetTextColor(1.0, 1.0, 1.0)
            border:SetColorTexture(0.25, 0.25, 0.25, 0.9) -- Back to normal border
        elseif style == "danger" then
            bg:SetColorTexture(0.6, 0.15, 0.15, 0.9)
            btnText:SetTextColor(1.0, 1.0, 1.0)
            border:SetColorTexture(0.25, 0.25, 0.25, 0.9) -- Back to normal border
        elseif style == "success" then
            bg:SetColorTexture(0.15, 0.6, 0.15, 0.9)
            btnText:SetTextColor(1.0, 1.0, 1.0)
            border:SetColorTexture(0.25, 0.25, 0.25, 0.9) -- Back to normal border
        else
            bg:SetColorTexture(0.08, 0.08, 0.08, 0.95) -- Back to darker default
            btnText:SetTextColor(0.9, 0.9, 0.9) -- Back to original text color
            border:SetColorTexture(0.25, 0.25, 0.25, 0.9) -- Back to normal border
        end
    end)

    if onClick then
        btn:SetScript("OnClick", onClick)
    end
    return btn
end

function SimWishLC:MakeEditBox(parent, x, y, width, height, placeholder)
    local editBox = CreateFrame("EditBox", nil, parent)
    editBox:SetSize(width or 150, height or 20)
    editBox:SetPoint("TOPLEFT", x, y)
    editBox:SetAutoFocus(false)
    editBox:SetMaxLetters(0)

    -- Custom background - Much more visible for text input
    local bg = editBox:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.03, 0.03, 0.03, 0.98) -- Very dark for contrast

    -- Border - More prominent
    local border = editBox:CreateTexture(nil, "BORDER")
    border:SetPoint("TOPLEFT", -2, 2)
    border:SetPoint("BOTTOMRIGHT", 2, -2)
    border:SetColorTexture(0.4, 0.4, 0.4, 0.95) -- More visible border

    -- Font
    editBox:SetFontObject("GameFontHighlight")
    editBox:SetTextColor(1.0, 1.0, 1.0)
    editBox:SetTextInsets(5, 5, 0, 0)

    -- Focus effects
    editBox:SetScript("OnEditFocusGained", function()
        border:SetColorTexture(0.5, 0.7, 1.0, 0.8)
    end)

    editBox:SetScript("OnEditFocusLost", function()
        border:SetColorTexture(0.3, 0.3, 0.3, 0.8)
    end)

    return editBox
end

function SimWishLC:MakeImportBox(parent, x, y, width, height)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(width or 500, height or 250)
    frame:SetPoint("TOPLEFT", x, y)

    -- Highly visible background for import area
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.01, 0.01, 0.01, 0.98) -- Almost black for maximum contrast

    -- Bright border to make it obvious where to paste
    local border = frame:CreateTexture(nil, "BORDER")
    border:SetPoint("TOPLEFT", -3, 3)
    border:SetPoint("BOTTOMRIGHT", 3, -3)
    border:SetColorTexture(0.6, 0.6, 0.6, 0.95) -- Bright border

    -- Inner border for extra definition
    local innerBorder = frame:CreateTexture(nil, "ARTWORK", nil, 1)
    innerBorder:SetPoint("TOPLEFT", -1, 1)
    innerBorder:SetPoint("BOTTOMRIGHT", 1, -1)
    innerBorder:SetColorTexture(0.3, 0.3, 0.3, 0.8)

    -- Scroll frame
    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 5, -5)
    scroll:SetPoint("BOTTOMRIGHT", -25, 5)

    -- Edit box
    local editBox = CreateFrame("EditBox", nil, scroll)
    editBox:SetFontObject("ChatFontNormal")
    editBox:SetTextColor(1.0, 1.0, 1.0) -- Bright white text
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetMaxLetters(0)
    editBox:SetTextInsets(6, 6, 6, 6)
    editBox:SetWidth(width - 30)
    editBox:SetHeight(height - 10)
    scroll:SetScrollChild(editBox)

    -- Make the entire frame area clickable to focus the editbox
    frame:EnableMouse(true)
    frame:SetScript("OnMouseDown", function()
        editBox:SetFocus()
        editBox:SetCursorPosition(editBox:GetNumLetters()) -- Set cursor to end
    end)

    -- Also make the scroll frame clickable
    scroll:EnableMouse(true)
    scroll:SetScript("OnMouseDown", function()
        editBox:SetFocus()
        editBox:SetCursorPosition(editBox:GetNumLetters())
    end)

    -- Placeholder text when empty
    local placeholder = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    placeholder:SetPoint("CENTER", frame, "CENTER", 0, 0)
    placeholder:SetText("Paste your SIMWISH data here")
    placeholder:SetTextColor(0.5, 0.5, 0.5, 0.8)

    -- Make placeholder clickable too
    placeholder:EnableMouse(true)
    placeholder:SetScript("OnMouseDown", function()
        editBox:SetFocus()
        editBox:SetCursorPosition(0)
    end)

    -- Hide placeholder when there's text or when focused
    editBox:SetScript("OnTextChanged", function(self)
        if self:GetText() and self:GetText():trim() ~= "" then
            placeholder:Hide()
        else
            placeholder:Show()
        end
    end)

    editBox:SetScript("OnEditFocusGained", function()
        placeholder:Hide()
    end)

    editBox:SetScript("OnEditFocusLost", function(self)
        if not self:GetText() or self:GetText():trim() == "" then
            placeholder:Show()
        end
    end)

    frame.editBox = editBox
    frame.scroll = scroll
    frame.placeholder = placeholder
    return frame
end

function SimWishLC:MakeCheckBox(parent, text, x, y, checked, onClick)
    local cb = CreateFrame("Button", nil, parent)
    cb:SetSize(16, 16)
    cb:SetPoint("TOPLEFT", x, y)

    -- Custom checkbox background - Darker theme
    local bg = cb:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.03, 0.03, 0.03, 0.95) -- Much darker

    -- Border
    local border = cb:CreateTexture(nil, "BORDER")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(0.3, 0.3, 0.3, 0.9) -- Slightly darker border

    -- Check mark - more visible when checked
    local check = cb:CreateTexture(nil, "OVERLAY")
    check:SetAllPoints()
    check:SetColorTexture(0.2, 0.7, 1.0, 1.0) -- Bright blue when checked
    cb.check = check

    -- Checkmark icon overlay
    local checkIcon = cb:CreateTexture(nil, "OVERLAY", nil, 1)
    checkIcon:SetPoint("CENTER")
    checkIcon:SetSize(12, 12)
    checkIcon:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    checkIcon:SetVertexColor(1.0, 1.0, 1.0, 1.0) -- White checkmark
    cb.checkIcon = checkIcon

    -- Label
    local label = cb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", cb, "RIGHT", 5, 0)
    label:SetText(text)
    label:SetTextColor(0.9, 0.9, 0.9)

    -- State management functions
    cb.SetChecked = function(self, state)
        self.checked = state
        self.check:SetShown(state) -- Blue background
        self.checkIcon:SetShown(state) -- White checkmark

        -- Update border color based on state
        if state then
            border:SetColorTexture(0.2, 0.7, 1.0, 1.0) -- Bright blue border when checked
        else
            border:SetColorTexture(0.3, 0.3, 0.3, 0.9) -- Gray border when unchecked
        end
    end

    cb.GetChecked = function(self)
        return self.checked
    end

    -- Set initial state
    cb.checked = checked or false
    cb:SetChecked(cb.checked) -- This will set the visual state correctly

    -- Click handler
    cb:SetScript("OnClick", function(self)
        self:SetChecked(not self.checked)
        if onClick then
            onClick(self.checked)
        end
    end)

    return cb
end

-- ===== Build UI =====
local function BuildUI()
    -- Main Tabbed Frame with custom styling
    mainFrame = CreateFrame("Frame", "SimWishMainFrame", UIParent)
    mainFrame:SetSize(580, 460)
    mainFrame:SetPoint("CENTER")
    mainFrame:Hide()

    -- Custom frame background - Much darker theme
    local mainBg = mainFrame:CreateTexture(nil, "BACKGROUND")
    mainBg:SetAllPoints()
    mainBg:SetColorTexture(0.02, 0.02, 0.02, 0.98) -- Much darker

    -- Custom frame border
    local mainBorder = mainFrame:CreateTexture(nil, "BORDER")
    mainBorder:SetPoint("TOPLEFT", -2, 2)
    mainBorder:SetPoint("BOTTOMRIGHT", 2, -2)
    mainBorder:SetColorTexture(0.2, 0.2, 0.2, 0.9) -- Darker border

    -- Title bar
    local titleBar = mainFrame:CreateTexture(nil, "ARTWORK")
    titleBar:SetPoint("TOPLEFT", 0, 0)
    titleBar:SetPoint("TOPRIGHT", 0, 0)
    titleBar:SetHeight(30)
    titleBar:SetColorTexture(0.08, 0.08, 0.08, 0.95) -- Darker title bar

    -- Title text
    mainFrame.title = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    mainFrame.title:SetPoint("CENTER", titleBar, "CENTER", 0, 0)
    mainFrame.title:SetText("SimWishlist")
    mainFrame.title:SetTextColor(1.0, 0.82, 0.0)

    -- Close button
    local closeBtn = SimWishLC:MakeBtn(mainFrame, "×", 548, -5, 20, 20, function()
        mainFrame:Hide()
    end, "danger")
    closeBtn.text:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE")

    mainFrame:EnableMouse(true)
    mainFrame:SetMovable(true)
    mainFrame:RegisterForDrag("LeftButton")
    mainFrame:SetScript("OnDragStart", mainFrame.StartMoving)
    mainFrame:SetScript("OnDragStop", mainFrame.StopMovingOrSizing)
    mainFrame:SetFrameStrata("FULLSCREEN_DIALOG") -- Render above WeakAuras and other addons
    mainFrame:SetFrameLevel(1000) -- Very high frame level
    AddEscClose("SimWishMainFrame")

    -- Create tabs
    mainFrame.tabs = {}
    mainFrame.panels = {}

    local tabData = {{
        name = "Import",
        id = "import"
    }, {
        name = "Browse",
        id = "browse"
    }, {
        name = "Profiles",
        id = "profiles"
    }, {
        name = "Settings",
        id = "settings"
    }, {
        name = "Customization",
        id = "customization"
    }}

    -- Tab content area
    mainFrame.contentArea = CreateFrame("Frame", nil, mainFrame)
    mainFrame.contentArea:SetPoint("TOPLEFT", 10, -58)
    mainFrame.contentArea:SetPoint("BOTTOMRIGHT", -10, 10)

    -- Create tabs and panels
    for i, data in ipairs(tabData) do
        local tab = SimWishLC:MakeTab(mainFrame, data.name, i, function()
            SimWishlist.ShowTab(data.id)
        end, #tabData) -- Pass total number of tabs
        mainFrame.tabs[data.id] = tab

        local panel = CreateFrame("Frame", nil, mainFrame.contentArea)
        panel:SetAllPoints()
        panel:Hide()
        mainFrame.panels[data.id] = panel
    end

    -- Tab switching function
    function SimWishlist.ShowTab(tabId)
        for id, panel in pairs(mainFrame.panels) do
            panel:Hide()
            mainFrame.tabs[id]:SetSelected(false)
        end

        if mainFrame.panels[tabId] then
            mainFrame.panels[tabId]:Show()
            mainFrame.tabs[tabId]:SetSelected(true)

            -- Special handling for different tabs
            if tabId == "browse" then
                SimWishlist.RefreshBrowseTab()
            elseif tabId == "profiles" then
                SimWishlist.RefreshProfilesTab()
            end
        end
    end

    -- Import Tab
    local importPanel = mainFrame.panels.import

    local importTitle = importPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    importTitle:SetPoint("TOPLEFT", 20, -20)
    importTitle:SetText("Import SIMWISH Data")
    importTitle:SetTextColor(1.0, 0.82, 0.0)

    local importDesc = importPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    importDesc:SetPoint("TOPLEFT", 20, -45)
    importDesc:SetWidth(520)
    importDesc:SetJustifyH("LEFT")
    importDesc:SetText("Paste your SIMWISH v1 data here to import simulation results.")
    importDesc:SetTextColor(0.9, 0.9, 0.9)

    -- Use the new highly visible import box
    local importFrame = SimWishLC:MakeImportBox(importPanel, 20, -70, 520, 250)
    local importEditBox = importFrame.editBox

    local importBtn = SimWishLC:MakeBtn(importPanel, "Import SIMWISH Text", 20, -340, 180, 28, nil, "success")
    importBtn:SetScript("OnClick", function()
        local text = importEditBox:GetText()
        if text and text:trim() ~= "" then
            local success, msg, profileName = Import_SIMWISH(text)
            if success then
                importEditBox:SetText("")
                print("|cff1eff00SimWishlist:|r " .. msg)
                -- Refresh both tabs
                if SimWishlist.RefreshBrowseTab then
                    SimWishlist.RefreshBrowseTab()
                end
                if SimWishlist.RefreshProfilesTab then
                    SimWishlist.RefreshProfilesTab()
                end
                SimWishlist.ShowTab("browse")
            end
        else
            print("|cffff2020SimWishlist:|r Please paste SIMWISH data first.")
        end
    end)

    local clearBtn = SimWishLC:MakeBtn(importPanel, "Clear", 210, -340, 80, 28, function()
        importEditBox:SetText("")
        importEditBox:ClearFocus() -- Remove focus to show placeholder
        importFrame.placeholder:Show()
    end)

    -- Browse Tab - Clean and Simple
    local browsePanel = mainFrame.panels.browse

    local browseTitle = browsePanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    browseTitle:SetPoint("TOPLEFT", 20, -20)
    browseTitle:SetText("Browse Items")
    browseTitle:SetTextColor(1.0, 0.82, 0.0)

    -- View mode toggle buttons with custom styling
    local ungroupedBtn = SimWishLC:MakeBtn(browsePanel, "Ungrouped", 20, -50, 100, 24, nil, "primary")
    local groupedBtn = SimWishLC:MakeBtn(browsePanel, "By Profile", 130, -50, 100, 24, nil, "primary")

    -- Search box with custom styling
    local searchLabel = browsePanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    searchLabel:SetPoint("LEFT", groupedBtn, "RIGHT", 20, 0)
    searchLabel:SetText("Search:")
    searchLabel:SetTextColor(0.9, 0.9, 0.9)

    local searchBox = SimWishLC:MakeEditBox(browsePanel, 295, -50, 150, 20)

    -- Browse content area
    local browseScroll = CreateFrame("ScrollFrame", nil, browsePanel, "UIPanelScrollFrameTemplate")
    browseScroll:SetPoint("TOPLEFT", 20, -85)
    browseScroll:SetPoint("BOTTOMRIGHT", -30, 20)

    local browseContent = CreateFrame("Frame", nil, browseScroll)
    browseContent:SetSize(1, 1)
    browseScroll:SetScrollChild(browseContent)

    browsePanel.scroll = browseScroll
    browsePanel.content = browseContent
    browsePanel.viewMode = "grouped" -- Default to grouped view

    -- View mode button handlers with custom button state management
    ungroupedBtn:SetScript("OnClick", function()
        browsePanel.viewMode = "ungrouped"
        -- Update button appearance
        ungroupedBtn.bg:SetColorTexture(0.15, 0.4, 0.6, 0.9) -- Active blue
        groupedBtn.bg:SetColorTexture(0.08, 0.08, 0.08, 0.95) -- Darker inactive
        SimWishlist.RefreshBrowseTab()
    end)

    groupedBtn:SetScript("OnClick", function()
        browsePanel.viewMode = "grouped"
        -- Update button appearance
        groupedBtn.bg:SetColorTexture(0.15, 0.4, 0.6, 0.9) -- Active blue
        ungroupedBtn.bg:SetColorTexture(0.08, 0.08, 0.08, 0.95) -- Darker inactive
        SimWishlist.RefreshBrowseTab()
    end)

    -- Set initial button states (grouped active by default)
    groupedBtn.bg:SetColorTexture(0.15, 0.4, 0.6, 0.9) -- Active blue
    ungroupedBtn.bg:SetColorTexture(0.08, 0.08, 0.08, 0.95) -- Darker inactive

    -- Search handler
    searchBox:SetScript("OnTextChanged", function()
        SimWishlist.RefreshBrowseTab()
    end)

    -- Helper function for thorough content cleanup
    local function ClearFrameContent(frame)
        if not frame then
            return
        end

        -- Clear all children frames
        local children = {frame:GetChildren()}
        for _, child in ipairs(children) do
            if child.Hide then
                child:Hide()
            end
            if child.SetParent then
                child:SetParent(nil)
            end
            if child.ClearAllPoints then
                child:ClearAllPoints()
            end
        end

        -- Clear all regions (font strings, textures, etc)
        local regions = {frame:GetRegions()}
        for _, region in ipairs(regions) do
            if region and region.Hide then
                region:Hide()
                if region.SetParent then
                    region:SetParent(nil)
                end
            end
        end
    end

    -- Clean browse tab refresh function
    function SimWishlist.RefreshBrowseTab()
        if not browsePanel.content then
            return
        end

        -- Thoroughly clear existing content
        ClearFrameContent(browsePanel.content)

        local char = SimWishlist.EnsureCharacterData()
        if not char.profiles or not next(char.profiles) then
            local noItemsText = browsePanel.content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            noItemsText:SetPoint("CENTER", 0, 0)
            noItemsText:SetText("No profiles found. Import some SIMWISH data first!")
            noItemsText:SetTextColor(0.7, 0.7, 0.7)
            return
        end

        local searchText = searchBox:GetText():lower()
        local y = -10
        local contentWidth = browseScroll:GetWidth() - 20

        if browsePanel.viewMode == "ungrouped" then
            -- Ungrouped view - show all items in one flat list
            local allItems = {}
            for profileName, profile in pairs(char.profiles) do
                for sourceName, items in pairs(profile.bySource or {}) do
                    for itemID, score in pairs(items) do
                        if score > 0 then
                            -- Only show items with positive score
                            local itemName = GetItemInfo(itemID) or ("Item " .. itemID)
                            if searchText == "" or itemName:lower():find(searchText) or sourceName:lower():find(searchText) then
                                local plinks = char.profiles[profileName].links
                                local srcLinks = plinks and plinks.bySource and plinks.bySource[sourceName]
                                local gLink = plinks and plinks._global and plinks._global[itemID]
                                local link = (srcLinks and srcLinks[itemID]) or gLink

                                table.insert(allItems, {
                                    itemID = itemID,
                                    score = score,
                                    sourceName = sourceName,
                                    profileName = profileName,
                                    baseDPS = profile.meta.baseDPS,
                                    link = link
                                })
                            end
                        elseif score < 0 and catalystData[itemID] then
                            -- Negative score item (catalyst source) - only show if catalyst result is in wishlist
                            local catalyst = catalystData[itemID][1]
                            if catalyst then
                                -- Check if the catalyst result is actually in this profile with positive score
                                local catalystScore = nil
                                for _, sourceItems in pairs(profile.bySource) do
                                    if sourceItems[catalyst.catalystId] and sourceItems[catalyst.catalystId] > 0 then
                                        catalystScore = sourceItems[catalyst.catalystId]
                                        break
                                    end
                                end

                                -- Only add if catalyst result is in the wishlist
                                if catalystScore and catalystScore > 0 then
                                    local itemName = GetItemInfo(itemID) or ("Item " .. itemID)
                                    if searchText == "" or itemName:lower():find(searchText) or sourceName:lower():find(searchText) then
                                        local plinks = char.profiles[profileName].links
                                        local srcLinks = plinks and plinks.bySource and plinks.bySource[sourceName]
                                        local gLink = plinks and plinks._global and plinks._global[itemID]
                                        local link = (srcLinks and srcLinks[itemID]) or gLink

                                        table.insert(allItems, {
                                            itemID = itemID,
                                            score = catalystScore,
                                            sourceName = sourceName,
                                            profileName = profileName,
                                            baseDPS = profile.meta.baseDPS,
                                            link = link,
                                            isCatalystSource = true
                                        })
                                    end
                                end
                            end
                        end
                    end
                end
            end

            -- Sort by score descending
            table.sort(allItems, function(a, b)
                return (a.score or 0) > (b.score or 0)
            end)

            -- Display items in grid
            local cols = math.floor(contentWidth / 40)
            local col, row = 0, 0

            for _, item in ipairs(allItems) do
                local btn = CreateItemButton(browsePanel.content, item.itemID, item.score, item.baseDPS, item.isCatalystSource or false, item.link)
                btn:SetPoint("TOPLEFT", col * 40, y - row * 40)

                col = col + 1
                if col >= cols then
                    col = 0
                    row = row + 1
                end
            end

            browseContent:SetHeight(math.max(200, (row + 1) * 40 + 20))

        else
            -- Grouped view - show items grouped by profile (but clean, no collapsing)
            for profileName, profile in pairs(char.profiles) do
                -- Profile header
                local profileHeader = browsePanel.content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
                profileHeader:SetPoint("TOPLEFT", 10, y)
                profileHeader:SetText(profileName)
                profileHeader:SetTextColor(0.2, 1.0, 0.2)
                y = y - 30

                -- Profile info
                local totalItems = 0
                for _, items in pairs(profile.bySource or {}) do
                    for _ in pairs(items) do
                        totalItems = totalItems + 1
                    end
                end
                local infoText = browsePanel.content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                infoText:SetPoint("TOPLEFT", 10, y)
                infoText:SetText(string.format("Items: %d | Base DPS: %s", totalItems,
                    ShortNumber(profile.meta.baseDPS or 0)))
                y = y - 25

                -- Show items by source
                for sourceName, items in pairs(profile.bySource or {}) do
                    if next(items) then
                        -- Source header
                        local sourceHeader = browsePanel.content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                        sourceHeader:SetPoint("TOPLEFT", 20, y)
                        sourceHeader:SetText(sourceName)
                        sourceHeader:SetTextColor(1.0, 0.82, 0.0)
                        y = y - 25

                        -- Items in grid
                        local sourceItems = {}
                        for itemID, score in pairs(items) do
                            if score > 0 then
                                -- Only show items with positive score
                                local itemName = GetItemInfo(itemID) or ("Item " .. itemID)
                                if searchText == "" or itemName:lower():find(searchText) or
                                    sourceName:lower():find(searchText) then
                                    table.insert(sourceItems, {
                                        itemID = itemID,
                                        score = score
                                    })
                                end
                            elseif score < 0 and catalystData[itemID] then
                                -- Negative score item (catalyst source) - only show if catalyst result is in wishlist
                                local catalyst = catalystData[itemID][1]
                                if catalyst then
                                    -- Check if the catalyst result is actually in this profile with positive score
                                    local catalystScore = nil
                                    for _, sourceItems in pairs(profile.bySource) do
                                        if sourceItems[catalyst.catalystId] and sourceItems[catalyst.catalystId] > 0 then
                                            catalystScore = sourceItems[catalyst.catalystId]
                                            break
                                        end
                                    end

                                    -- Only add if catalyst result is in the wishlist
                                    if catalystScore and catalystScore > 0 then
                                        local itemName = GetItemInfo(itemID) or ("Item " .. itemID)
                                        if searchText == "" or itemName:lower():find(searchText) or
                                            sourceName:lower():find(searchText) then
                                            table.insert(sourceItems, {
                                                itemID = itemID,
                                                score = score,
                                                isCatalystSource = true
                                            })
                                        end
                                    end
                                end
                            end
                        end

                        table.sort(sourceItems, function(a, b)
                            return (a.score or 0) > (b.score or 0)
                        end)

                        local cols = math.floor((contentWidth - 30) / 40)
                        local col, row = 0, 0

                        for _, item in ipairs(sourceItems) do
                            local btn = CreateItemButton(browsePanel.content, item.itemID, item.score,
                                profile.meta.baseDPS, item.isCatalystSource or false)
                            btn:SetPoint("TOPLEFT", 30 + col * 40, y - row * 40)

                            col = col + 1
                            if col >= cols then
                                col = 0
                                row = row + 1
                            end
                        end

                        if #sourceItems > 0 then
                            y = y - ((row + 1) * 40) - 10
                        end
                    end
                end

                y = y - 20 -- Extra space between profiles
            end
        end

        browseContent:SetSize(contentWidth, math.max(200, math.abs(y) + 20))
    end

    -- Profiles Tab - Use the original collapsible UI
    local profilesPanel = mainFrame.panels.profiles

    local profilesTitle = profilesPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    profilesTitle:SetPoint("TOPLEFT", 20, -20)
    profilesTitle:SetText("Profile Management")
    profilesTitle:SetTextColor(1.0, 0.82, 0.0)

    local profilesDesc = profilesPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    profilesDesc:SetPoint("TOPLEFT", 20, -45)
    profilesDesc:SetText("Manage your simulation profiles with the full collapsible interface.")

    -- Use original panel system for profiles tab
    local profilesScroll = CreateFrame("ScrollFrame", nil, profilesPanel, "UIPanelScrollFrameTemplate")
    profilesScroll:SetPoint("TOPLEFT", 20, -70)
    profilesScroll:SetPoint("BOTTOMRIGHT", -30, 60)

    local profilesContent = CreateFrame("Frame", nil, profilesScroll)
    profilesContent:SetSize(1, 1)
    profilesScroll:SetScrollChild(profilesContent)

    profilesPanel.scroll = profilesScroll
    profilesPanel.content = profilesContent

    -- Clear All button for profiles with custom styling
    local clearAllBtn = SimWishLC:MakeBtn(profilesPanel, "Clear All", 20, -430, 120, 24, function()
        local char = SimWishlist.EnsureCharacterData()
        char.profiles = {}
        char.activeProfile = nil
        print("|cffff2020SimWishlist:|r Cleared all profiles.")
        SimWishlist.RefreshProfilesTab()
    end, "danger")

    -- Profiles tab refresh - use original BuildAllProfilesPanel
    function SimWishlist.RefreshProfilesTab()
        if not profilesPanel.content then
            return
        end

        -- Thoroughly clear existing content first
        ClearFrameContent(profilesPanel.content)

        -- Temporarily redirect to profiles panel and use original logic
        local tempPanel = panel
        panel = profilesPanel
        panel.scroll = profilesScroll
        panel.content = profilesContent

        -- Use the original BuildAllProfilesPanel which has all the collapsing logic
        BuildAllProfilesPanel()

        panel = tempPanel -- Restore original panel
    end

    -- Settings Tab
    local settingsPanel = mainFrame.panels.settings

    local settingsTitle = settingsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    settingsTitle:SetPoint("TOPLEFT", 20, -20)
    settingsTitle:SetText("Settings & Options")
    settingsTitle:SetTextColor(1.0, 0.82, 0.0)

    -- Tooltip section
    local tooltipHeader = settingsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    tooltipHeader:SetPoint("TOPLEFT", 20, -60)
    tooltipHeader:SetText("Tooltip Options")
    tooltipHeader:SetTextColor(1.0, 0.82, 0.0)

    local char = SimWishlist.EnsureCharacterData()

    -- Enable tooltips checkbox with custom styling
    local tooltipCheck = SimWishLC:MakeCheckBox(settingsPanel, "Enable tooltip enhancements", 20, -85,
        char.options.enableTooltip, function(checked)
            char.options.enableTooltip = checked
        end)

    -- Welcome message checkbox with custom styling
    local welcomeCheck = SimWishLC:MakeCheckBox(settingsPanel, "Show welcome message on login", 20, -115,
        char.options.welcomeMessage, function(checked)
            char.options.welcomeMessage = checked
        end)

    -- Developer Mode section
    local devHeader = settingsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    devHeader:SetPoint("TOPLEFT", 20, -150)
    devHeader:SetText("Developer Mode")
    devHeader:SetTextColor(1.0, 0.82, 0.0)

    local devModeCheck = SimWishLC:MakeCheckBox(settingsPanel, "Enable developer mode", 20, -175,
        char.options.developerMode, function(checked)
            char.options.developerMode = checked
            -- Update global setting
            SimWishlistDB.developerMode = checked
            -- If developer mode is disabled, also disable debug messages
            if not checked then
                char.options.showDebugMessages = false
                SimWishlistDB.showDebugMessages = false
                if devDebugCheck then
                    devDebugCheck:SetChecked(false)
                end
            end
        end)

    local devDebugCheck = SimWishLC:MakeCheckBox(settingsPanel, "Show debug messages", 40, -200,
        char.options.showDebugMessages, function(checked)
            char.options.showDebugMessages = checked
            -- Update global setting
            SimWishlistDB.showDebugMessages = checked
        end)

    -- Debug section
    local debugHeader = settingsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    debugHeader:SetPoint("TOPLEFT", 20, -240)
    debugHeader:SetText("Debug")
    debugHeader:SetTextColor(1.0, 0.82, 0.0)

    local debugBtn = SimWishLC:MakeBtn(settingsPanel, "Show Debug Info", 20, -265, 120, 24, function()
        local char = SimWishlist.EnsureCharacterData()
        local profileCount = 0
        local totalItems = 0

        for profileName, profile in pairs(char.profiles or {}) do
            profileCount = profileCount + 1
            for source, items in pairs(profile.bySource or {}) do
                for _ in pairs(items) do
                    totalItems = totalItems + 1
                end
            end
        end

        DebugPrint("|cff1eff00SimWishlist Debug:|r")
        DebugPrint("Character: " .. CharKey())
        DebugPrint("Profiles: " .. profileCount)
        DebugPrint("Total Items: " .. totalItems)
        DebugPrint("Active Profile: " .. (char.activeProfile or "None"))
    end)

    -- About section
    local aboutHeader = settingsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    aboutHeader:SetPoint("TOPLEFT", 20, -295)
    aboutHeader:SetText("About")
    aboutHeader:SetTextColor(1.0, 0.82, 0.0)

    local aboutText = settingsPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    aboutText:SetPoint("TOPLEFT", 20, -320)
    aboutText:SetWidth(520)
    aboutText:SetJustifyH("LEFT")
    aboutText:SetText(
        "SimWishlist v0.9.8\n\nEnhances item tooltips with DPS upgrade information from simulation data.\nConverter: https://imperial64.github.io/simwishlist")

    -- Customization Tab - TODO: Implement color customization feature
    local customizationPanel = mainFrame.panels.customization

    local customizationTitle = customizationPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    customizationTitle:SetPoint("TOPLEFT", 20, -20)
    customizationTitle:SetText("Theme Customization")
    customizationTitle:SetTextColor(1.0, 0.82, 0.0)

    local customizationDesc = customizationPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    customizationDesc:SetPoint("TOPLEFT", 20, -45)
    customizationDesc:SetWidth(520)
    customizationDesc:SetJustifyH("LEFT")
    customizationDesc:SetText("Customize the colors and appearance of the SimWishlist interface.")
    customizationDesc:SetTextColor(0.9, 0.9, 0.9)

    -- Coming Soon placeholder
    local comingSoonText = customizationPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    comingSoonText:SetPoint("CENTER", customizationPanel, "CENTER", 0, 0)
    comingSoonText:SetText("Coming Soon!")
    comingSoonText:SetTextColor(1.0, 0.82, 0.0)

    local comingSoonDesc = customizationPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    comingSoonDesc:SetPoint("TOP", comingSoonText, "BOTTOM", 0, -10)
    comingSoonDesc:SetText("Color customization features will be available in a future update.")
    comingSoonDesc:SetTextColor(0.8, 0.8, 0.8)

    -- Set default tab
    SimWishlist.ShowTab("import")

    -- Import UI
    importFrame = CreateFrame("Frame", "SimWishImportFrame", UIParent, "BasicFrameTemplateWithInset")
    importFrame:SetSize(600, 380);
    importFrame:SetPoint("CENTER");
    importFrame:Hide()
    importFrame.title = importFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    importFrame.title:SetPoint("TOP", 0, -8);
    importFrame.title:SetText("SimWishlist - Import (SIMWISH v1)")
    importFrame:EnableMouse(true);
    importFrame:SetMovable(true);
    importFrame:RegisterForDrag("LeftButton")
    importFrame:SetScript("OnDragStart", importFrame.StartMoving);
    importFrame:SetScript("OnDragStop", importFrame.StopMovingOrSizing)
    AddEscClose("SimWishImportFrame")
    local back1 = MakeBackButton(importFrame, function()
        SimWishlist.ShowMain()
    end)

    local ebScroll = CreateFrame("ScrollFrame", nil, importFrame, "UIPanelScrollFrameTemplate")
    ebScroll:SetPoint("TOPLEFT", 12, -30);
    ebScroll:SetPoint("BOTTOMRIGHT", -32, 60)
    local editBox = CreateFrame("EditBox", nil, ebScroll);
    editBox:SetMultiLine(true);
    editBox:SetFontObject(ChatFontNormal);
    editBox:SetAutoFocus(true)
    editBox:SetTextInsets(6, 6, 6, 6);
    editBox:SetWidth(ebScroll:GetWidth() - 20);
    editBox:SetHeight(ebScroll:GetHeight() - 20)
    editBox:ClearAllPoints();
    editBox:SetPoint("TOPLEFT", 0, 0);
    editBox:SetPoint("RIGHT", -4, 0)
    ebScroll:SetScrollChild(editBox)
    ebScroll:HookScript("OnSizeChanged", function(self, w, h)
        editBox:SetWidth((w or 320) - 20);
        editBox:SetHeight((h or 280) - 20)
    end)

    local importBtn2 = CreateFrame("Button", nil, importFrame, "UIPanelButtonTemplate");
    importBtn2:SetPoint("BOTTOMRIGHT", -12, 12);
    importBtn2:SetSize(180, 24);
    importBtn2:SetText("Import SIMWISH Text")
    local clearBtn2 = CreateFrame("Button", nil, importFrame, "UIPanelButtonTemplate");
    clearBtn2:SetPoint("BOTTOMLEFT", 12, 12);
    clearBtn2:SetSize(120, 24);
    clearBtn2:SetText("Clear")
    local statusText = importFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
    statusText:SetPoint("BOTTOM", 0, 36);
    statusText:SetText("Paste SIMWISH v1 lines here and click Import.")

    importBtn2:SetScript("OnClick", function()
        local txt = editBox:GetText() or ""
        if #txt < 3 then
            statusText:SetText("|cffff2020Import failed:|r Empty import");
            return
        end
        local ok, msg, profileName = Import_SIMWISH(txt)
        if ok then
            statusText:SetText("|cff1eff00" .. msg .. "|r");
            print("|cff1eff00SimWishlist:|r Import complete.");
            importFrame:Hide();
            SimWishlist.ShowMain()
        else
            statusText:SetText("|cffff2020Import failed:|r " .. tostring(msg))
        end
    end)
    clearBtn2:SetScript("OnClick", function()
        editBox:SetText("")
    end)

    -- Help UI
    helpFrame = CreateFrame("Frame", "SimWishHelpFrame", UIParent, "BasicFrameTemplateWithInset")
    helpFrame:SetSize(540, 340);
    helpFrame:SetPoint("CENTER");
    helpFrame:Hide()
    helpFrame.title = helpFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    helpFrame.title:SetPoint("TOP", 0, -8);
    helpFrame.title:SetText("SimWishlist - Help")
    helpFrame:EnableMouse(true);
    helpFrame:SetMovable(true);
    helpFrame:RegisterForDrag("LeftButton")
    helpFrame:SetScript("OnDragStart", helpFrame.StartMoving);
    helpFrame:SetScript("OnDragStop", helpFrame.StopMovingOrSizing)
    AddEscClose("SimWishHelpFrame")
    local back2 = MakeBackButton(helpFrame, function()
        SimWishlist.ShowMain()
    end)
    local helpText = helpFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    helpText:SetPoint("TOPLEFT", 16, -36);
    helpText:SetPoint("RIGHT", -80, 0)
    helpText:SetJustifyH("LEFT");
    helpText:SetJustifyV("TOP")
    helpText:SetText("|cff00ff00Quick Start Guide:|r\n" .. "1. Run Droptimizer on Raidbots for your content\n" ..
                         "2. Download the data.json file\n" ..
                         "3. Convert at: |cff1eff00https://imperial64.github.io/simwishlist|r\n" ..
                         "4. Copy the SIMWISH output\n" .. "5. Use |cffffff00/simwish import|r to paste and import\n\n" ..
                         "|cff00ff00Profile Management:|r\n" ..
                         "• Use |cffffff00/simwish show|r to view all profiles\n" ..
                         "• Click |cffffff00Rename|r or |cffffff00Delete|r buttons on profiles\n" ..
                         "• Click |cffffff00+/-|r buttons to collapse/expand profiles\n" ..
                         "• Multiple profiles supported for comparison\n\n" .. "|cff00ff00Features:|r\n" ..
                         "• Enhanced tooltips show DPS upgrades\n" ..
                         "• Works with dungeons, raids, and mixed content\n" ..
                         "• Automatic profile naming prevents data loss\n\n" ..
                         "|cff00ff00Commands:|r\n" ..
                         "• |cffffff00/simwish|r - Open main interface\n" ..
                         "• |cffffff00/simwish import|r - Import SIMWISH data\n" ..
                         "• |cffffff00/simwish show|r - Browse items\n" ..
                         "• |cffffff00/simwish profiles|r - Manage profiles\n" ..
                         "• |cffffff00/simwish settings|r - Configure options\n" ..
                         "• |cffffff00/simwish debug|r - Show debug info\n" ..
                         "• |cffffff00/simwish testicon|r - Test icon system\n" ..
                         "• |cffffff00/simwish testdb|r - Test database state\n" ..
                         "• |cffffff00/simwish testcurrent|r - Test current profile items\n" ..
                         "• |cffffff00/simwish testtexture|r - Test texture system\n" ..
                                                   "• |cffffff00/simwish testitem <id>|r - Test specific item\n" ..
                          "• |cffffff00/simwish testprofile|r - Test current profile icons\n" ..
                          "• |cffffff00/simwish fixicons|r - Attempt to fix icon display\n" ..
                          "• |cffffff00/simwish testnewicons|r - Test new icon loading system\n\n" ..
                         "|cffaaaaaa** Full documentation and support:\n" ..
                         "|cff1eff00https://github.com/imperial64/simwishlist|r")

    -- Copy button for converter website
    local converterCopyBtn = CreateFrame("Button", nil, helpFrame, "UIPanelButtonTemplate")
    converterCopyBtn:SetSize(50, 18)
    converterCopyBtn:SetPoint("TOPLEFT", 450, -88)
    converterCopyBtn:SetText("Copy")
    converterCopyBtn:SetScript("OnClick", function()
        local editBox = CreateFrame("EditBox", nil, UIParent)
        editBox:SetText("https://imperial64.github.io/simwishlist")
        editBox:SetFocus()
        editBox:HighlightText()
        editBox:Hide()
        C_Timer.After(0.1, function()
            editBox:SetParent(nil)
        end)
        DebugPrint("|cff1eff00SimWishlist:|r Converter URL copied to clipboard!")
    end)

    -- Copy button for GitHub repository
    local githubCopyBtn = CreateFrame("Button", nil, helpFrame, "UIPanelButtonTemplate")
    githubCopyBtn:SetSize(50, 18)
    githubCopyBtn:SetPoint("TOPLEFT", 450, -264)
    githubCopyBtn:SetText("Copy")
    githubCopyBtn:SetScript("OnClick", function()
        local editBox = CreateFrame("EditBox", nil, UIParent)
        editBox:SetText("https://github.com/imperial64/simwishlist")
        editBox:SetFocus()
        editBox:HighlightText()
        editBox:Hide()
        C_Timer.After(0.1, function()
            editBox:SetParent(nil)
        end)
        DebugPrint("|cff1eff00SimWishlist:|r GitHub URL copied to clipboard!")
    end)

    -- Panel UI
    panel = CreateFrame("Frame", "SimWishContentFrame", UIParent, "BasicFrameTemplateWithInset")
    panel:SetSize(520, 420);
    panel:SetPoint("CENTER");
    panel:Hide()
    panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight");
    panel.title:SetPoint("TOP", 0, -8);
    panel.title:SetText("SimWishlist")
    panel.scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate");
    panel.scroll:SetPoint("TOPLEFT", 8, -28);
    panel.scroll:SetPoint("BOTTOMRIGHT", -30, 8)
    panel.content = CreateFrame("Frame", nil, panel.scroll);
    panel.content:SetSize(1, 1);
    panel.scroll:SetScrollChild(panel.content)
    panel.close = CreateFrame("Button", nil, panel, "UIPanelCloseButton");
    panel.close:SetPoint("TOPRIGHT", 0, 0)
    local back3 = MakeBackButton(panel, function()
        panel:Hide();
        SimWishlist.ShowMain()
    end)
    panel:EnableMouse(true);
    panel:SetMovable(true);
    panel:RegisterForDrag("LeftButton");
    panel:SetScript("OnDragStart", panel.StartMoving);
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    AddEscClose("SimWishContentFrame")

    panel.scroll:HookScript("OnSizeChanged", function()
        if panel:IsShown() then
            C_Timer.After(0.01, BuildAllProfilesPanel)
        end
    end)

    -- Options UI
    optionsFrame = CreateFrame("Frame", "SimWishOptionsFrame", UIParent, "BasicFrameTemplateWithInset")
    optionsFrame:SetSize(420, 330);
    optionsFrame:SetPoint("CENTER");
    optionsFrame:Hide()
    optionsFrame.title = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    optionsFrame.title:SetPoint("TOP", 0, -8);
    optionsFrame.title:SetText("SimWishlist - Options")
    optionsFrame:EnableMouse(true);
    optionsFrame:SetMovable(true);
    optionsFrame:RegisterForDrag("LeftButton")
    optionsFrame:SetScript("OnDragStart", optionsFrame.StartMoving);
    optionsFrame:SetScript("OnDragStop", optionsFrame.StopMovingOrSizing)
    AddEscClose("SimWishOptionsFrame")
    local back4 = MakeBackButton(optionsFrame, function()
        optionsFrame:Hide();
        SimWishlist.ShowMain()
    end)

    -- Function to show/hide reload prompt
    local function ShowReloadPrompt()
        if optionsFrame.reloadPrompt then
            optionsFrame.reloadPrompt:Show()
            optionsFrame.reloadBtn:Show()
        end
    end

    -- Welcome message checkbox
    optionsFrame.welcomeCheck = CreateFrame("CheckButton", nil, optionsFrame, "ChatConfigCheckButtonTemplate")
    optionsFrame.welcomeCheck:SetPoint("TOPLEFT", 20, -50)
    optionsFrame.welcomeCheck.Text:SetText("Display welcome message on login")
    optionsFrame.welcomeCheck:SetScript("OnClick", function(self)
        local char = SimWishlist.EnsureCharacterData()
        char.options.welcomeMessage = self:GetChecked()
        DebugPrint("|cff1eff00SimWishlist:|r Welcome message ", char.options.welcomeMessage and "enabled" or "disabled")
        ShowReloadPrompt()
    end)

    -- Enable tooltip checkbox
    optionsFrame.tooltipCheck = CreateFrame("CheckButton", nil, optionsFrame, "ChatConfigCheckButtonTemplate")
    optionsFrame.tooltipCheck:SetPoint("TOPLEFT", 20, -90)
    optionsFrame.tooltipCheck.Text:SetText("Enable tooltip enhancements")
    optionsFrame.tooltipCheck:SetScript("OnClick", function(self)
        local char = SimWishlist.EnsureCharacterData()
        char.options.enableTooltip = self:GetChecked()
        DebugPrint("|cff1eff00SimWishlist:|r Tooltip enhancements ", char.options.enableTooltip and "enabled" or "disabled")
        ShowReloadPrompt()
    end)

    -- Minimap icon checkbox
    optionsFrame.minimapCheck = CreateFrame("CheckButton", nil, optionsFrame, "ChatConfigCheckButtonTemplate")
    optionsFrame.minimapCheck:SetPoint("TOPLEFT", 20, -130)
    optionsFrame.minimapCheck.Text:SetText("Show minimap icon")
    optionsFrame.minimapCheck:SetScript("OnClick", function(self)
        local char = SimWishlist.EnsureCharacterData()
        char.options.showMinimap = self:GetChecked()
        if char.options.showMinimap then
            if minimapButton then
                minimapButton:Show()
            else
                CreateMinimapButton()
            end
            DebugPrint("|cff1eff00SimWishlist:|r Minimap icon shown")
        else
            if minimapButton then
                minimapButton:Hide()
            end
            DebugPrint("|cff1eff00SimWishlist:|r Minimap icon hidden")
        end
        ShowReloadPrompt()
    end)

    -- Developer Mode checkbox
    optionsFrame.devModeCheck = CreateFrame("CheckButton", nil, optionsFrame, "ChatConfigCheckButtonTemplate")
    optionsFrame.devModeCheck:SetPoint("TOPLEFT", 20, -170)
    optionsFrame.devModeCheck.Text:SetText("Enable developer mode")
    optionsFrame.devModeCheck:SetScript("OnClick", function(self)
        local char = SimWishlist.EnsureCharacterData()
        char.options.developerMode = self:GetChecked()
        SimWishlistDB.developerMode = self:GetChecked()
        -- If developer mode is disabled, also disable debug messages
        if not self:GetChecked() then
            char.options.showDebugMessages = false
            SimWishlistDB.showDebugMessages = false
            if optionsFrame.debugCheck then
                optionsFrame.debugCheck:SetChecked(false)
            end
        end
        ShowReloadPrompt()
    end)

    -- Debug Messages checkbox
    optionsFrame.debugCheck = CreateFrame("CheckButton", nil, optionsFrame, "ChatConfigCheckButtonTemplate")
    optionsFrame.debugCheck:SetPoint("TOPLEFT", 40, -195)
    optionsFrame.debugCheck.Text:SetText("Show debug messages")
    optionsFrame.debugCheck:SetScript("OnClick", function(self)
        local char = SimWishlist.EnsureCharacterData()
        char.options.showDebugMessages = self:GetChecked()
        SimWishlistDB.showDebugMessages = self:GetChecked()
        ShowReloadPrompt()
    end)

    -- UI Reload prompt (initially hidden)
    optionsFrame.reloadPrompt = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    optionsFrame.reloadPrompt:SetPoint("TOPLEFT", 20, -140)
    optionsFrame.reloadPrompt:SetPoint("RIGHT", -20, 0)
    optionsFrame.reloadPrompt:SetJustifyH("CENTER")
    optionsFrame.reloadPrompt:SetText("|cffffd100⚠ Changes require UI reload to take effect|r")
    optionsFrame.reloadPrompt:Hide()

    -- UI Reload button (initially hidden)
    optionsFrame.reloadBtn = CreateFrame("Button", nil, optionsFrame, "UIPanelButtonTemplate")
    optionsFrame.reloadBtn:SetSize(120, 32)
    optionsFrame.reloadBtn:SetPoint("TOP", optionsFrame.reloadPrompt, "BOTTOM", 0, -10)
    optionsFrame.reloadBtn:SetText("Reload UI")
    optionsFrame.reloadBtn:SetScript("OnClick", function()
        ReloadUI()
    end)
    optionsFrame.reloadBtn:Hide()

    -- Save button
    local saveBtn = CreateFrame("Button", nil, optionsFrame, "UIPanelButtonTemplate")
    saveBtn:SetSize(100, 24);
    saveBtn:SetPoint("BOTTOMRIGHT", -12, 12);
    saveBtn:SetText("Save")
    saveBtn:SetScript("OnClick", function()
        DebugPrint("|cff1eff00SimWishlist:|r Options saved.")
        optionsFrame:Hide()
        SimWishlist.ShowMain()
    end)
end

-- ===== Slash =====
SLASH_SIMWISH1 = "/simwish";
SLASH_SIMWISH2 = "/swish"
SlashCmdList.SIMWISH = function(msg)
    msg = (msg or ""):lower()
    if msg:find("debug") then
        DebugPrint("|cffffd100SimWishlist debug:|r initialized=", initialized and "yes" or "no")
        local char = SimWishlist.EnsureCharacterData()
        local profileCount = 0
        for name, profile in pairs(char.profiles) do
            profileCount = profileCount + 1
            local itemCount = 0
            for source, items in pairs(profile.bySource or {}) do
                for id, score in pairs(items) do
                    itemCount = itemCount + 1
                end
            end
            DebugPrint("|cffffd100 Profile:|r", name, "- Items:", itemCount)
        end
        DebugPrint("|cffffd100 Total Profiles:|r", profileCount)
        DebugPrint("|cffffd100 Active Profile:|r", char.activeProfile or "none")
        DebugPrint("|cffffd100 Catalyst Data:|r", GetTableSize(catalystData), "source items")
        if GetTableSize(catalystData) > 0 then
            for sourceId, catalysts in pairs(catalystData) do
                DebugPrint("|cffffd100  Source " .. sourceId .. ":|r", #catalysts, "catalyst(s)")
            end
        end
        return
    end
    if msg:find("bonusid") or msg:find("bonus") then
        DebugBonusIDSystem()
        return
    end
    if msg:find("testbonus") or msg:find("test") then
        TestBonusIDWithRealItems()
        return
    end
    if msg:find("testicon") or msg:find("icon") then
        DebugPrint("Testing icon system...")
        -- Test with the specific item that was mentioned in the error and some others
        local testItems = {237649, 237650, 237651, 134400} -- 134400 is the fallback texture
        for _, itemID in ipairs(testItems) do
            DebugPrint(string.format("Testing item ID: %d", itemID))
            
            -- Test GetItemInfoInstant
            local _, _, _, quality, _, _, _, _, _, icon = C_Item.GetItemInfoInstant(itemID)
            DebugPrint(string.format("  GetItemInfoInstant: quality=%s, icon=%s", tostring(quality), tostring(icon)))
            
            -- Test GetItemInfo
            local itemName, itemLink, itemQuality, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount, itemEquipLoc, itemTexture, itemSellPrice = GetItemInfo(itemID)
            DebugPrint(string.format("  GetItemInfo: name=%s, texture=%s", tostring(itemName), tostring(itemTexture)))
            
            -- Test if we can create metadata
            local metadata = CreateItemMetadata(itemID, nil, {})
            if metadata then
                DebugPrint(string.format("  Metadata created: icon=%s", tostring(metadata.icon)))
            else
                DebugError(string.format("  Failed to create metadata for item %d", itemID))
            end
            
            -- Test if we can create a button
            local testFrame = CreateFrame("Frame", "TestFrame", UIParent)
            testFrame:SetSize(100, 100)
            testFrame:SetPoint("CENTER")
            testFrame:Hide()
            
            local btn = CreateItemButton(testFrame, itemID, 5.0, 1000000, false, nil)
            if btn and btn.icon then
                local texture = btn.icon:GetTexture()
                DebugPrint(string.format("  Button created: icon texture=%s", tostring(texture)))
            else
                DebugError(string.format("  Failed to create button for item %d", itemID))
            end
            
            testFrame:Hide()
            DebugPrint("  ---")
        end
        return
    end
    if msg:find("testdb") or msg:find("database") then
        DebugPrint("Testing database state...")
        local char = SimWishlist.EnsureCharacterData()
        
        if not char.profiles or not next(char.profiles) then
            DebugPrint("  No profiles found in database")
            return
        end
        
        for profileName, profile in pairs(char.profiles) do
            DebugPrint(string.format("Profile: %s", profileName))
            
            if profile.bySource then
                for source, items in pairs(profile.bySource) do
                    DebugPrint(string.format("  Source: %s", source))
                    local itemCount = 0
                    for itemID, score in pairs(items) do
                        itemCount = itemCount + 1
                        if itemCount <= 5 then -- Only show first 5 items per source
                            DebugPrint(string.format("    Item %d: score %.2f", itemID, score))
                            
                            -- Test icon retrieval for this item
                            local _, _, _, quality, _, _, _, _, _, icon = C_Item.GetItemInfoInstant(itemID)
                            local itemName, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(itemID)
                            DebugPrint(string.format("      GetItemInfoInstant: quality=%s, icon=%s", tostring(quality), tostring(icon)))
                            DebugPrint(string.format("      GetItemInfo: name=%s, texture=%s", tostring(itemName), tostring(itemTexture)))
                        end
                    end
                    DebugPrint(string.format("    Total items in source: %d", itemCount))
                end
            else
                DebugPrint("  No items found in profile")
            end
            DebugPrint("  ---")
        end
        return
    end
    if msg:find("testcurrent") or msg:find("current") then
        DebugPrint("Testing icon system with current profile items...")
        local char = SimWishlist.EnsureCharacterData()
        
        if not char.activeProfile then
            DebugPrint("  No active profile")
            return
        end
        
        local profile = char.profiles[char.activeProfile]
        if not profile or not profile.bySource then
            DebugPrint("  No items found in active profile")
            return
        end
        
        DebugPrint(string.format("Active profile: %s", char.activeProfile))
        
        -- Test first few items from each source
        for source, items in pairs(profile.bySource) do
            DebugPrint(string.format("Source: %s", source))
            local itemCount = 0
            for itemID, score in pairs(items) do
                itemCount = itemCount + 1
                if itemCount <= 3 then -- Only test first 3 items per source
                    DebugPrint(string.format("  Testing item %d (score: %.2f)", itemID, score))
                    
                    -- Test icon retrieval
                    local _, _, _, quality, _, _, _, _, _, icon = C_Item.GetItemInfoInstant(itemID)
                    local itemName, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(itemID)
                    
                    DebugPrint(string.format("    GetItemInfoInstant: quality=%s, icon=%s", tostring(quality), tostring(icon)))
                    DebugPrint(string.format("    GetItemInfo: name=%s, texture=%s", tostring(itemName), tostring(itemTexture)))
                    
                    -- Test metadata creation
                    local metadata = CreateItemMetadata(itemID, nil, {})
                    if metadata then
                        DebugPrint(string.format("    Metadata icon: %s", tostring(metadata.icon)))
                    end
                    
                    -- Test button creation
                    local testFrame = CreateFrame("Frame", "TestCurrentFrame", UIParent)
                    testFrame:SetSize(50, 50)
                    testFrame:SetPoint("CENTER")
                    testFrame:Hide()
                    
                    local btn = CreateItemButton(testFrame, itemID, score, 1000000, false, nil)
                    if btn and btn.icon then
                        local texture = btn.icon:GetTexture()
                        DebugPrint(string.format("    Button icon texture: %s", tostring(texture)))
                    else
                        DebugError(string.format("    Failed to create button for item %d", itemID))
                    end
                    
                    testFrame:Hide()
                    DebugPrint("    ---")
                end
            end
            DebugPrint(string.format("  Total items in source: %d", itemCount))
        end
        return
    end
    if msg:find("testtexture") or msg:find("texture") then
        DebugPrint("Testing texture system...")
        
        -- Test with known working textures
        local testTextures = {
            {id = 134400, name = "Fallback Texture (INV_Scroll_05)"},
            {id = 136477, name = "Minimap Highlight"},
            {id = 136430, name = "Minimap Border"}
        }
        
        for _, textureInfo in ipairs(testTextures) do
            DebugPrint(string.format("Testing texture: %s (ID: %d)", textureInfo.name, textureInfo.id))
            
            -- Create a test frame to display the texture
            local testFrame = CreateFrame("Frame", "TestTextureFrame", UIParent)
            testFrame:SetSize(64, 64)
            testFrame:SetPoint("CENTER")
            testFrame:Show()
            
            -- Create texture
            local texture = testFrame:CreateTexture(nil, "ARTWORK")
            texture:SetAllPoints(true)
            texture:SetTexture(textureInfo.id)
            
            -- Check if texture is valid
            local actualTexture = texture:GetTexture()
            DebugPrint(string.format("  Texture set: %s, Actual: %s", tostring(textureInfo.id), tostring(actualTexture)))
            
            -- Hide frame after a short delay
            C_Timer.After(2.0, function()
                testFrame:Hide()
            end)
            
            DebugPrint("  ---")
        end
        
        -- Test creating an item button with a known texture
        DebugPrint("Testing CreateItemButton with fallback texture...")
        local testFrame = CreateFrame("Frame", "TestButtonFrame", UIParent)
        testFrame:SetSize(100, 100)
        testFrame:SetPoint("CENTER", 0, -100)
        testFrame:Show()
        
        -- Use a dummy item ID that should fall back to the default texture
        local btn = CreateItemButton(testFrame, 999999, 5.0, 1000000, false, nil)
        if btn and btn.icon then
            local texture = btn.icon:GetTexture()
            DebugPrint(string.format("  Button created with texture: %s", tostring(texture)))
        else
            DebugError("  Failed to create button with fallback texture")
        end
        
        -- Hide frame after a short delay
        C_Timer.After(3.0, function()
            testFrame:Hide()
        end)
        
        return
    end
    if msg:find("testitem") then
        local itemID = tonumber(msg:match("testitem%s+(%d+)"))
        if not itemID then
            DebugPrint("Usage: /simwish testitem <itemID>")
            DebugPrint("Example: /simwish testitem 237649")
            return
        end
        
        DebugPrint(string.format("Testing specific item ID: %d", itemID))
        
        -- Test GetItemInfoInstant
        local _, _, _, quality, _, _, _, _, _, icon = C_Item.GetItemInfoInstant(itemID)
        DebugPrint(string.format("GetItemInfoInstant: quality=%s, icon=%s", tostring(quality), tostring(icon)))
        
        -- Test GetItemInfo
        local itemName, itemLink, itemQuality, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount, itemEquipLoc, itemTexture, itemSellPrice = GetItemInfo(itemID)
        DebugPrint(string.format("GetItemInfo: name=%s, texture=%s", tostring(itemName), tostring(itemTexture)))
        
        -- Test metadata creation
        local metadata = CreateItemMetadata(itemID, nil, {})
        if metadata then
            DebugPrint(string.format("Metadata created: icon=%s", tostring(metadata.icon)))
        else
            DebugError(string.format("Failed to create metadata for item %d", itemID))
        end
        
        -- Test button creation
        local testFrame = CreateFrame("Frame", "TestItemFrame", UIParent)
        testFrame:SetSize(100, 100)
        testFrame:SetPoint("CENTER")
        testFrame:Show()
        
        local btn = CreateItemButton(testFrame, itemID, 5.0, 1000000, false, nil)
        if btn and btn.icon then
            local texture = btn.icon:GetTexture()
            DebugPrint(string.format("Button created: icon texture=%s", tostring(texture)))
            
            -- Show the button for a few seconds
            C_Timer.After(3.0, function()
                testFrame:Hide()
            end)
        else
            DebugError(string.format("Failed to create button for item %d", itemID))
            testFrame:Hide()
        end
        
        return
    end
    if not initialized then
        DebugPrint("SimWishlist: still initializing… try again in a second or /reload if it persists.");
        return
    end
    if msg == "" then
        SimWishlist.ShowMain()
    elseif msg:find("import") then
        SimWishlist.ShowImport()
    elseif msg:find("^help") then
        SimWishlist.ShowHelp()
    elseif msg:find("show") or msg:find("browse") then
        SimWishlist.ShowPanel()
    elseif msg:find("profiles") then
        SimWishlist.ShowMain();
        if SimWishlist.ShowTab then
            SimWishlist.ShowTab("profiles")
        end
    elseif msg:find("options") or msg:find("settings") then
        SimWishlist.ShowOptions()
    elseif msg:find("hide") then
        if mainFrame then
            mainFrame:Hide()
        end
        if importFrame then
            importFrame:Hide()
        end
        if helpFrame then
            helpFrame:Hide()
        end
        if panel then
            panel:Hide()
        end
        if optionsFrame then
            optionsFrame:Hide()
        end
    elseif msg:find("clear") then
        local char = SimWishlist.EnsureCharacterData();
        char.profiles = {};
        char.activeProfile = nil;
        DebugPrint("|cffff2020SimWishlist:|r cleared all profiles.")
        -- Refresh both tabs if they exist
        if SimWishlist.RefreshBrowseTab then
            SimWishlist.RefreshBrowseTab()
        end
        if SimWishlist.RefreshProfilesTab then
            SimWishlist.RefreshProfilesTab()
        end
            elseif msg:find("testprofile") then
        DebugPrint("Testing icon system with current profile...")
        local char = SimWishlist.EnsureCharacterData()
        
        if not char.activeProfile then
            DebugPrint("  No active profile")
            return
        end
        
        local profile = char.profiles[char.activeProfile]
        if not profile or not profile.bySource then
            DebugPrint("  No items found in active profile")
            return
        end
        
        DebugPrint(string.format("Active profile: %s", char.activeProfile))
        
        -- Test all items from the profile
        local totalItems = 0
        local itemsWithIcons = 0
        local itemsWithoutIcons = 0
        
        for source, items in pairs(profile.bySource) do
            DebugPrint(string.format("Source: %s", source))
            local sourceItemCount = 0
            local sourceItemsWithIcons = 0
            local sourceItemsWithoutIcons = 0
            
            for itemID, score in pairs(items) do
                totalItems = totalItems + 1
                sourceItemCount = sourceItemCount + 1
                
                DebugPrint(string.format("  Item %d (score: %.2f)", itemID, score))
                
                -- Test icon retrieval
                local _, _, _, quality, _, _, _, _, _, icon = C_Item.GetItemInfoInstant(itemID)
                local itemName, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(itemID)
                
                DebugPrint(string.format("    GetItemInfoInstant: quality=%s, icon=%s", tostring(quality), tostring(icon)))
                DebugPrint(string.format("    GetItemInfo: name=%s, texture=%s", tostring(itemName), tostring(itemTexture)))
                
                -- Test metadata creation
                local metadata = CreateItemMetadata(itemID, nil, {})
                if metadata and metadata.icon then
                    DebugPrint(string.format("    Metadata icon: %s", tostring(metadata.icon)))
                    itemsWithIcons = itemsWithIcons + 1
                    sourceItemsWithIcons = sourceItemsWithIcons + 1
                else
                    DebugError(string.format("    No metadata icon for item %d", itemID))
                    itemsWithoutIcons = itemsWithoutIcons + 1
                    sourceItemsWithoutIcons = sourceItemsWithoutIcons + 1
                end
                
                DebugPrint("    ---")
            end
            
            DebugPrint(string.format("  Source %s: %d items, %d with icons, %d without icons", 
                source, sourceItemCount, sourceItemsWithIcons, sourceItemsWithoutIcons))
        end
        
        DebugPrint(string.format("Profile %s summary: %d total items, %d with icons, %d without icons", 
            char.activeProfile, totalItems, itemsWithIcons, itemsWithoutIcons))
        
        return
    elseif msg:find("fixicons") then
        DebugPrint("Attempting to fix icon display issue...")
        local char = SimWishlist.EnsureCharacterData()
        
        if not char.activeProfile then
            DebugPrint("  No active profile")
            return
        end
        
        local profile = char.profiles[char.activeProfile]
        if not profile or not profile.bySource then
            DebugPrint("  No items found in active profile")
            return
        end
        
        DebugPrint(string.format("Active profile: %s", char.activeProfile))
        
        -- Try to fix icons for all items
        local fixedCount = 0
        local totalCount = 0
        
        for source, items in pairs(profile.bySource) do
            DebugPrint(string.format("Source: %s", source))
            
            for itemID, score in pairs(items) do
                totalCount = totalCount + 1
                
                DebugPrint(string.format("  Fixing item %d (score: %.2f)", itemID, score))
                
                -- Try multiple methods to get the icon
                local icon = nil
                
                -- Method 1: GetItemInfoInstant
                local _, _, _, quality, _, _, _, _, _, icon1 = C_Item.GetItemInfoInstant(itemID)
                if icon1 then
                    icon = icon1
                    DebugPrint(string.format("    Method 1 (GetItemInfoInstant): icon=%s", tostring(icon)))
                else
                    DebugPrint(string.format("    Method 1 (GetItemInfoInstant): failed"))
                end
                
                -- Method 2: GetItemInfo
                if not icon then
                    local itemName, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(itemID)
                    if itemTexture then
                        icon = itemTexture
                        DebugPrint(string.format("    Method 2 (GetItemInfo): icon=%s", tostring(icon)))
                    else
                        DebugPrint(string.format("    Method 2 (GetItemInfo): failed"))
                    end
                end
                
                -- Method 3: Try to get from item link if available
                if not icon and profile.links then
                    local itemLink = profile.links._global and profile.links._global[itemID] or 
                                   profile.links.bySource and profile.links.bySource[source] and profile.links.bySource[source][itemID]
                    if itemLink then
                        DebugPrint(string.format("    Method 3 (Item Link): found link=%s", tostring(itemLink)))
                        -- Try to extract icon from link
                        local _, _, _, linkQuality, _, _, _, _, _, linkIcon = C_Item.GetItemInfoInstant(itemLink)
                        if linkIcon then
                            icon = linkIcon
                            DebugPrint(string.format("    Method 3 (Item Link): icon=%s", tostring(icon)))
                        end
                    else
                        DebugPrint(string.format("    Method 3 (Item Link): no link found"))
                    end
                end
                
                -- Method 4: Fallback to default texture
                if not icon then
                    icon = 134400 -- Default fallback texture
                    DebugPrint(string.format("    Method 4 (Fallback): using default texture %d", icon))
                end
                
                -- Update the metadata with the found icon
                if icon then
                    local metadata = CreateItemMetadata(itemID, nil, {})
                    if metadata then
                        metadata.icon = icon
                        DebugPrint(string.format("    Updated metadata with icon: %s", tostring(icon)))
                        fixedCount = fixedCount + 1
                    end
                end
                
                DebugPrint("    ---")
            end
        end
        
        DebugPrint(string.format("Icon fix attempt complete: %d/%d items processed", fixedCount, totalCount))
        DebugPrint("Note: Icons will load asynchronously. Refresh the UI to see changes.")
        
        return
    elseif msg:find("testnewicons") then
        DebugPrint("Testing new asynchronous icon loading system...")
        
        -- Test with the specific item that was mentioned in the error
        local testItems = {237649, 237650, 237651, 134400}
        
        for _, itemID in ipairs(testItems) do
            DebugPrint(string.format("Testing new icon system for item ID: %d", itemID))
            
            -- Test our new LoadItemIcon function
            LoadItemIcon(itemID, function(icon, quality)
                if icon then
                    DebugPrint(string.format("  SUCCESS: Icon loaded for item %d: texture=%s, quality=%s", 
                        itemID, tostring(icon), tostring(quality)))
                else
                    DebugError(string.format("  FAILED: No icon for item %d", itemID))
                end
            end)
            
            DebugPrint("  ---")
        end
        
        return
    else
        DebugPrint("|cff1eff00SimWishlist:|r /simwish | import | browse | profiles | settings | help | hide | clear | debug | bonusid | testbonus | testicon | testdb | testcurrent | testtexture | testitem <id> | testprofile | fixicons | testnewicons")
    end
end

-- ===== Init =====
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        SimWishlist.EnsureCharacterData()
    elseif event == "PLAYER_LOGIN" and not initialized then
        local ok, err = pcall(function()
            RepopulateCatalystData(); -- Restore catalyst data from saved profiles
            SetupTooltipHook();
            BuildUI();
            CreateMinimapButton(); -- Create minimap icon
            CreateInterfaceOptionsPanel(); -- Add to interface options
        end)
        if not ok then
            DebugPrint("|cffff2020SimWishlist init error:|r", tostring(err));
            return
        end
        initialized = true
        local char = SimWishlist.EnsureCharacterData()
        if char.options.welcomeMessage then
            DebugPrint("|cff1eff00SimWishlist loaded|r – type |cffffff80/simwish|r")
        end
    end
end)

-- ===== Bonus ID System Debug Functions =====
local function DebugBonusIDSystem()
    DebugPrint("Testing bonus ID handling system...")
    
    -- Test with various item link formats
    local testLinks = {
        "item:12345:0:0:0:0:0:0:0:0:0:0:0:0", -- No bonus ID
        "item:12345:0:0:0:0:0:0:0:0:0:0:0:123", -- With bonus ID 123
        "item:12345:0:0:0:0:0:0:0:0:0:0:0:456", -- With bonus ID 456
        "item:12345:0:0:0:0:0:0:0:0:0:0:0:789", -- With bonus ID 789
    }
    
    for i, link in ipairs(testLinks) do
        local normalized = NormalizeItemLink(link)
        local bonusID = ExtractBonusID(link)
        DebugPrint(string.format("Test %d: %s", i, link))
        DebugPrint(string.format("  Normalized: %s", normalized.normalized or "nil"))
        DebugPrint(string.format("  Has Bonus ID: %s", tostring(normalized.hasBonusID)))
        DebugPrint(string.format("  Bonus ID: %s", tostring(bonusID)))
        DebugPrint("  ---")
    end
    
    -- Test item comparison
    local link1 = "item:12345:0:0:0:0:0:0:0:0:0:0:0:123"
    local link2 = "item:12345:0:0:0:0:0:0:0:0:0:0:0:456"
    local link3 = "item:67890:0:0:0:0:0:0:0:0:0:0:0:123"
    
    DebugPrint("Item comparison tests:")
    DebugPrint(string.format("Same base item (123 vs 456): %s", tostring(IsSameBaseItem(link1, link2))))
    DebugPrint(string.format("Different base items (123 vs 67890): %s", tostring(IsSameBaseItem(link1, link3))))
    
    DebugPrint("Bonus ID system debug complete.")
end

-- Function to test bonus ID handling with real items
local function TestBonusIDWithRealItems()
    DebugPrint("Testing bonus ID handling with real items...")
    
    local foundItems = 0
    local itemsWithBonusIDs = 0
    
    -- Check all bags
    for bagID = 0, 4 do
        local numSlots = C_Container.GetContainerNumSlots(bagID)
        for slotID = 1, numSlots do
            local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
            if itemInfo and itemInfo.hyperlink then
                foundItems = foundItems + 1
                local normalized = NormalizeItemLink(itemInfo.hyperlink)
                if normalized.hasBonusID then
                    itemsWithBonusIDs = itemsWithBonusIDs + 1
                    local bonusID = ExtractBonusID(itemInfo.hyperlink)
                    local itemName = GetItemInfo(normalized.itemID) or "Unknown"
                    DebugPrint(string.format("Item with Bonus ID: %s (ID: %d, Bonus: %d)", 
                        itemName, normalized.itemID, bonusID))
                end
            end
        end
    end
    
    DebugPrint(string.format("Found %d items, %d with bonus IDs", foundItems, itemsWithBonusIDs))
end
