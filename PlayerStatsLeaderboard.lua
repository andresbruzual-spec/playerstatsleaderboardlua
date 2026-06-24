--- PlayerStatsLeaderboard - Server Script (place in ServerScriptService)
-- Public Roblox profile/game/group stats for the custom leaderboard.

print("[Stats] PlayerStatsLeaderboard running")

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local PROXY_DOMAIN = "roproxy.com"

-- Public web APIs rate-limit quickly. Keep this high for real servers.
local UPDATE_INTERVAL = 600
local UPDATE_JITTER = 60
local JOIN_SPREAD_SECONDS = 10

local HTTP_CACHE_SECONDS = 300
local HTTP_STALE_SECONDS = 1800
local HTTP_429_BACKOFF_SECONDS = 180
local HTTP_REQUEST_GAP_SECONDS = 0.2

local GAMES_PAGE_LIMIT = 50
local GAMES_TOTALS_CHUNK_SIZE = 50
local MAX_USER_UNIVERSE_IDS = 200
local MAX_GROUP_UNIVERSE_IDS = 200
local MAX_TOTAL_UNIVERSE_IDS = 500
local MAX_OWNED_GROUPS_TO_SCAN_FOR_GAMES = math.huge

local OWNER_RANK = 255

local STAT_DEFINITIONS = {
	{ Name = "Active", ClassName = "IntValue" },
	{ Name = "Visits", ClassName = "NumberValue" },
	{ Name = "Followers", ClassName = "IntValue" },
	{ Name = "Members", ClassName = "IntValue" },
	{ Name = "Favorites", ClassName = "NumberValue" },
}

local playerLoops = {}
local lastGoodStats = {}
local requestCache = {}
local nextHttpRequestAt = 0

local function now()
	return os.clock()
end

local function api(subdomain, path)
	return "https://" .. subdomain .. "." .. PROXY_DOMAIN .. path
end

local function addQuery(path, query)
	if string.find(path, "?", 1, true) then
		return path .. "&" .. query
	end

	return path .. "?" .. query
end

local function warnOncePerWindow(cacheEntry, message, windowSeconds)
	local currentTime = now()

	if cacheEntry.nextWarnAt and cacheEntry.nextWarnAt > currentTime then
		return
	end

	cacheEntry.nextWarnAt = currentTime + windowSeconds
	warn(message)
end

local function waitForHttpSlot()
	local currentTime = now()

	if nextHttpRequestAt > currentTime then
		task.wait(nextHttpRequestAt - currentTime)
	end

	nextHttpRequestAt = now() + HTTP_REQUEST_GAP_SECONDS
end

local function getCachedJSON(url, cacheSeconds)
	local currentTime = now()
	local cacheEntry = requestCache[url]

	if cacheEntry and cacheEntry.data and cacheEntry.expiresAt > currentTime then
		return cacheEntry.data
	end

	if cacheEntry and cacheEntry.backoffUntil and cacheEntry.backoffUntil > currentTime then
		if cacheEntry.data and cacheEntry.staleUntil > currentTime then
			return cacheEntry.data
		end

		return nil, "rate-limited"
	end

	cacheEntry = cacheEntry or {}
	requestCache[url] = cacheEntry
	waitForHttpSlot()

	local ok, response = pcall(function()
		return HttpService:GetAsync(url)
	end)

	if not ok then
		local errorText = tostring(response)

		if string.find(errorText, "429", 1, true) then
			cacheEntry.backoffUntil = currentTime + HTTP_429_BACKOFF_SECONDS
			warnOncePerWindow(cacheEntry, "[Stats] Rate limited, reusing last good data if available: " .. url, 30)
		else
			warnOncePerWindow(cacheEntry, "[Stats] GET failed: " .. url .. " -> " .. errorText, 30)
		end

		if cacheEntry.data and cacheEntry.staleUntil > currentTime then
			return cacheEntry.data
		end

		return nil, errorText
	end

	local decodedOk, decoded = pcall(function()
		return HttpService:JSONDecode(response)
	end)

	if not decodedOk then
		warnOncePerWindow(cacheEntry, "[Stats] JSON decode failed: " .. url, 30)

		if cacheEntry.data and cacheEntry.staleUntil > currentTime then
			return cacheEntry.data
		end

		return nil, "json-decode-failed"
	end

	cacheEntry.data = decoded
	cacheEntry.expiresAt = currentTime + (cacheSeconds or HTTP_CACHE_SECONDS)
	cacheEntry.staleUntil = currentTime + HTTP_STALE_SECONDS
	cacheEntry.backoffUntil = nil

	return decoded
end

local function appendUniqueIds(target, seen, source, maxTotal)
	for _, id in ipairs(source) do
		local universeId = tonumber(id)

		if universeId and not seen[universeId] then
			seen[universeId] = true
			table.insert(target, universeId)
		end

		if #target >= maxTotal then
			break
		end
	end
end

local function getUniverseIdsFromGamesEndpoint(basePath, maxIds)
	local ids = {}
	local cursor = ""

	repeat
		local pagePath = addQuery(basePath, "limit=" .. GAMES_PAGE_LIMIT)

		if cursor ~= "" then
			pagePath = addQuery(pagePath, "cursor=" .. HttpService:UrlEncode(cursor))
		end

		local data, err = getCachedJSON(api("games", pagePath), HTTP_CACHE_SECONDS)

		if not data then
			return nil, err
		end

		if type(data.data) ~= "table" then
			return nil, "bad-games-response"
		end

		for _, gameInfo in ipairs(data.data) do
			local universeId = tonumber(gameInfo.id)

			if universeId then
				table.insert(ids, universeId)
			end

			if #ids >= maxIds then
				break
			end
		end

		cursor = data.nextPageCursor or ""
	until cursor == "" or #ids >= maxIds

	return ids
end

local function getOwnedUniverseIds(userId)
	return getUniverseIdsFromGamesEndpoint(
		"/v2/users/" .. userId .. "/games?accessFilter=Public&sortOrder=Desc",
		MAX_USER_UNIVERSE_IDS
	)
end

local function getGroupUniverseIds(groupId)
	return getUniverseIdsFromGamesEndpoint(
		"/v2/groups/" .. groupId .. "/games?accessFilter=Public&sortOrder=Desc",
		MAX_GROUP_UNIVERSE_IDS
	)
end

local function getGameTotals(universeIds)
	local totals = {
		Active = 0,
		Visits = 0,
		Favorites = 0,
	}

	for i = 1, #universeIds, GAMES_TOTALS_CHUNK_SIZE do
		local chunk = {}

		for j = i, math.min(i + GAMES_TOTALS_CHUNK_SIZE - 1, #universeIds) do
			table.insert(chunk, universeIds[j])
		end

		local data, err = getCachedJSON(
			api("games", "/v1/games?universeIds=" .. table.concat(chunk, ",")),
			HTTP_CACHE_SECONDS
		)

		if not data then
			return nil, err
		end

		if type(data.data) ~= "table" then
			return nil, "bad-game-totals-response"
		end

		for _, gameInfo in ipairs(data.data) do
			totals.Active += tonumber(gameInfo.playing) or 0
			totals.Visits += tonumber(gameInfo.visits) or 0
			totals.Favorites += tonumber(gameInfo.favoritedCount or gameInfo.favorites) or 0
		end
	end

	return totals
end

local function getFollowers(userId)
	local data, err = getCachedJSON(api("friends", "/v1/users/" .. userId .. "/followers/count"), HTTP_CACHE_SECONDS)

	if not data then
		return nil, err
	end

	if data.count == nil then
		return nil, "bad-followers-response"
	end

	return tonumber(data.count) or 0
end

local function collectOwnedGroupsFromResponse(data, groupsById)
	if type(data.data) ~= "table" then
		return false
	end

	for _, entry in ipairs(data.data) do
		local group = entry.group
		local rank = entry.role and tonumber(entry.role.rank)

		if group and group.id and rank == OWNER_RANK then
			local groupId = tonumber(group.id)

			if groupId and not groupsById[groupId] then
				groupsById[groupId] = {
					id = groupId,
					memberCount = tonumber(group.memberCount) or 0,
					rank = rank,
				}
			end
		end
	end

	return true
end

local function sortedGroupList(groupsById)
	local groups = {}

	for _, groupInfo in pairs(groupsById) do
		table.insert(groups, groupInfo)
	end

	table.sort(groups, function(a, b)
		if a.rank == b.rank then
			return a.memberCount > b.memberCount
		end

		return a.rank > b.rank
	end)

	return groups
end

local function getOwnedGroups(userId)
	local groupsById = {}
	local v2Data = getCachedJSON(api("groups", "/v2/users/" .. userId .. "/groups/roles"), HTTP_CACHE_SECONDS)

	if v2Data and collectOwnedGroupsFromResponse(v2Data, groupsById) then
		return sortedGroupList(groupsById)
	end

	local v1Data, err = getCachedJSON(api("groups", "/v1/users/" .. userId .. "/groups/roles"), HTTP_CACHE_SECONDS)

	if not v1Data then
		return nil, err
	end

	if not collectOwnedGroupsFromResponse(v1Data, groupsById) then
		return nil, "bad-groups-response"
	end

	return sortedGroupList(groupsById)
end

local function copyStats(stats)
	return {
		Active = stats and stats.Active or 0,
		Visits = stats and stats.Visits or 0,
		Followers = stats and stats.Followers or 0,
		Members = stats and stats.Members or 0,
		Favorites = stats and stats.Favorites or 0,
	}
end

local function computeStats(player)
	local stats = copyStats(lastGoodStats[player])
	local universeIds = {}
	local seenUniverseIds = {}
	local errors = {}
	local hasFreshData = false
	local hasCompleteGameSources = true

	local followers, followersErr = getFollowers(player.UserId)

	if followers ~= nil then
		stats.Followers = followers
		hasFreshData = true
	else
		table.insert(errors, "followers: " .. tostring(followersErr))
	end

	local groups, groupsErr = getOwnedGroups(player.UserId)

	if groups then
		local members = 0

		for _, groupInfo in ipairs(groups) do
			members += groupInfo.memberCount
		end

		stats.Members = members
		hasFreshData = true
	else
		hasCompleteGameSources = false
		table.insert(errors, "groups: " .. tostring(groupsErr))
	end

	local userOwnedIds, ownedErr = getOwnedUniverseIds(player.UserId)

	if userOwnedIds then
		appendUniqueIds(universeIds, seenUniverseIds, userOwnedIds, MAX_TOTAL_UNIVERSE_IDS)
	else
		hasCompleteGameSources = false
		table.insert(errors, "user games: " .. tostring(ownedErr))
	end

	if groups then
		local scannedGroups = 0

		for _, groupInfo in ipairs(groups) do
			if scannedGroups >= MAX_OWNED_GROUPS_TO_SCAN_FOR_GAMES or #universeIds >= MAX_TOTAL_UNIVERSE_IDS then
				break
			end

			scannedGroups += 1
			local groupUniverseIds, groupErr = getGroupUniverseIds(groupInfo.id)

			if groupUniverseIds then
				appendUniqueIds(universeIds, seenUniverseIds, groupUniverseIds, MAX_TOTAL_UNIVERSE_IDS)
			else
				hasCompleteGameSources = false
				table.insert(errors, "group " .. groupInfo.id .. " games: " .. tostring(groupErr))
			end
		end

		if #groups > MAX_OWNED_GROUPS_TO_SCAN_FOR_GAMES then
			hasCompleteGameSources = false
			table.insert(errors, "owned group games capped at " .. MAX_OWNED_GROUPS_TO_SCAN_FOR_GAMES .. "/" .. #groups)
		end
	end

	if #universeIds > 0 then
		local totals, totalsErr = getGameTotals(universeIds)

		if totals then
			stats.Active = totals.Active
			stats.Visits = totals.Visits
			stats.Favorites = totals.Favorites
			hasFreshData = true
		else
			table.insert(errors, "game totals: " .. tostring(totalsErr))
		end
	elseif hasCompleteGameSources then
		stats.Active = 0
		stats.Visits = 0
		stats.Favorites = 0
		hasFreshData = true
	end

	if hasFreshData then
		return stats, (#errors > 0 and table.concat(errors, "; ") or nil)
	end

	return nil, table.concat(errors, "; ")
end

local function getOrCreateFolder(player, folderName)
	local folder = player:FindFirstChild(folderName)

	if folder and folder:IsA("Folder") then
		return folder
	end

	if folder then
		warn("[Stats] Replacing non-folder " .. folderName .. " under " .. player.Name)
		folder:Destroy()
	end

	folder = Instance.new("Folder")
	folder.Name = folderName
	folder.Parent = player

	return folder
end

local function getOrCreateValue(folder, name, className)
	local value = folder:FindFirstChild(name)

	if value and (value:IsA("IntValue") or value:IsA("NumberValue")) then
		return value
	end

	if value then
		warn("[Stats] Replacing non-numeric value " .. folder.Name .. "." .. name)
		value:Destroy()
	end

	value = Instance.new(className)
	value.Name = name
	value.Value = 0
	value.Parent = folder

	return value
end

local function setupStatFolders(player)
	local folders = {
		getOrCreateFolder(player, "ProfileStats"),
		getOrCreateFolder(player, "leaderstats"),
	}

	local stats = {}

	for _, statInfo in ipairs(STAT_DEFINITIONS) do
		stats[statInfo.Name] = {}

		for _, folder in ipairs(folders) do
			table.insert(stats[statInfo.Name], getOrCreateValue(folder, statInfo.Name, statInfo.ClassName))
		end
	end

	return stats
end

local function writeStats(statObjects, stats)
	for _, statInfo in ipairs(STAT_DEFINITIONS) do
		local value = tonumber(stats[statInfo.Name]) or 0

		for _, object in ipairs(statObjects[statInfo.Name]) do
			object.Value = value
		end
	end
end

local function setupPlayer(player)
	if playerLoops[player] then
		return
	end

	playerLoops[player] = true

	local statObjects = setupStatFolders(player)

	task.spawn(function()
		task.wait(math.random() * JOIN_SPREAD_SECONDS)

		while playerLoops[player] and player.Parent == Players do
			local stats, err = computeStats(player)

			if stats then
				lastGoodStats[player] = stats
				writeStats(statObjects, stats)
				if err then
					warn("[Stats] Partial stats for " .. player.Name .. ": " .. tostring(err))
				end
			elseif lastGoodStats[player] then
				writeStats(statObjects, lastGoodStats[player])
				warn("[Stats] Kept last good stats for " .. player.Name .. ": " .. tostring(err))
			else
				warn("[Stats] No stats yet for " .. player.Name .. ": " .. tostring(err))
			end

			task.wait(math.max(60, UPDATE_INTERVAL + math.random(-UPDATE_JITTER, UPDATE_JITTER)))
		end
	end)
end

Players.PlayerAdded:Connect(setupPlayer)

Players.PlayerRemoving:Connect(function(player)
	playerLoops[player] = nil
	lastGoodStats[player] = nil
end)

for _, player in ipairs(Players:GetPlayers()) do
	setupPlayer(player)
end
