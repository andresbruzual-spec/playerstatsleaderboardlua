-- CustomLeaderboardUI - Local Script (place in StarterPlayer --> StarterPlayerScripts)
local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

local GUI_NAME = "CustomLeaderboard"
local PANEL_WIDTH = 510
local MAX_VISIBLE_ROWS = 10
local ROW_HEIGHT = 32
local ROW_GAP = 1
local TITLE_HEIGHT = 32
local HEADER_HEIGHT = 22
local OUTER_PADDING = 8
local INNER_PADDING_X = 10
local COLUMN_GAP = 8
local AVATAR_SIZE = 22

local STAT_FOLDER_NAMES = { "ProfileStats", "leaderstats" }

local STAT_COLUMNS = {
	{ Key = "Visits", Display = "Visits", ValueName = "Visits", Width = 78 },
	{ Key = "Active", Display = "Active", ValueName = "Active", Width = 62 },
	{ Key = "Followers", Display = "Followers", ValueName = "Followers", Width = 78 },
	{ Key = "Members", Display = "Members", ValueName = "Members", Width = 78 },
}

local statWidthTotal = 0
for _, column in ipairs(STAT_COLUMNS) do
	statWidthTotal += column.Width
end

local playerColumnOffset = -(statWidthTotal + (COLUMN_GAP * #STAT_COLUMNS) + (INNER_PADDING_X * 2))
local playerRows = {}
local sortQueued = false

local existingGui = playerGui:FindFirstChild(GUI_NAME)
if existingGui then
	existingGui:Destroy()
end

task.spawn(function()
	for _ = 1, 10 do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
		end)

		if ok then
			break
		end

		task.wait(0.25)
	end
end)

local function formatNumber(value)
	local number = tonumber(value) or 0
	local absNumber = math.abs(number)

	if absNumber >= 1e9 then
		local text = string.format(absNumber >= 1e11 and "%.0fB" or "%.1fB", number / 1e9)
		return text:gsub("%.0B$", "B")
	elseif absNumber >= 1e6 then
		local text = string.format(absNumber >= 1e8 and "%.0fM" or "%.1fM", number / 1e6)
		return text:gsub("%.0M$", "M")
	elseif absNumber >= 1e3 then
		local formatted = tostring(math.floor(number))
		local replacements

		repeat
			formatted, replacements = formatted:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
		until replacements == 0

		return formatted
	end

	return tostring(math.floor(number))
end

local function isStatsFolderName(name)
	for _, folderName in ipairs(STAT_FOLDER_NAMES) do
		if name == folderName then
			return true
		end
	end

	return false
end

local function findStatsFolder(player)
	for _, folderName in ipairs(STAT_FOLDER_NAMES) do
		local folder = player:FindFirstChild(folderName)

		if folder then
			return folder
		end
	end

	return nil
end

local function readStat(player, valueName)
	local statsFolder = findStatsFolder(player)
	local stat = statsFolder and statsFolder:FindFirstChild(valueName)

	if stat and stat:IsA("ValueBase") then
		return tonumber(stat.Value) or 0
	end

	return 0
end

local function disconnectAll(connections)
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end

	table.clear(connections)
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = GUI_NAME
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = false
screenGui.Parent = playerGui

local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.AnchorPoint = Vector2.new(1, 0)
mainFrame.Position = UDim2.new(1, -12, 0, 12)
mainFrame.Size = UDim2.fromOffset(PANEL_WIDTH, 120)
mainFrame.BackgroundColor3 = Color3.fromRGB(20, 21, 24)
mainFrame.BackgroundTransparency = 0.08
mainFrame.BorderSizePixel = 0
mainFrame.Parent = screenGui

local mainCorner = Instance.new("UICorner")
mainCorner.CornerRadius = UDim.new(0, 6)
mainCorner.Parent = mainFrame

local mainStroke = Instance.new("UIStroke")
mainStroke.Color = Color3.fromRGB(255, 255, 255)
mainStroke.Transparency = 0.9
mainStroke.Thickness = 1
mainStroke.Parent = mainFrame

local titleBar = Instance.new("Frame")
titleBar.Name = "TitleBar"
titleBar.Size = UDim2.new(1, 0, 0, TITLE_HEIGHT)
titleBar.BackgroundColor3 = Color3.fromRGB(25, 26, 30)
titleBar.BackgroundTransparency = 0
titleBar.BorderSizePixel = 0
titleBar.Parent = mainFrame

local titleCorner = Instance.new("UICorner")
titleCorner.CornerRadius = UDim.new(0, 6)
titleCorner.Parent = titleBar

local titleBottomFill = Instance.new("Frame")
titleBottomFill.Name = "BottomFill"
titleBottomFill.AnchorPoint = Vector2.new(0, 1)
titleBottomFill.Position = UDim2.new(0, 0, 1, 0)
titleBottomFill.Size = UDim2.new(1, 0, 0, 6)
titleBottomFill.BackgroundColor3 = titleBar.BackgroundColor3
titleBottomFill.BackgroundTransparency = titleBar.BackgroundTransparency
titleBottomFill.BorderSizePixel = 0
titleBottomFill.Parent = titleBar

local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "Title"
titleLabel.Position = UDim2.fromOffset(12, 0)
titleLabel.Size = UDim2.new(1, -94, 1, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Font = Enum.Font.GothamMedium
titleLabel.Text = "Players"
titleLabel.TextColor3 = Color3.fromRGB(242, 244, 247)
titleLabel.TextSize = 14
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
titleLabel.Parent = titleBar

local countLabel = Instance.new("TextLabel")
countLabel.Name = "PlayerCount"
countLabel.AnchorPoint = Vector2.new(1, 0)
countLabel.Position = UDim2.new(1, -34, 0, 0)
countLabel.Size = UDim2.fromOffset(44, TITLE_HEIGHT)
countLabel.BackgroundTransparency = 1
countLabel.Font = Enum.Font.Gotham
countLabel.Text = "0"
countLabel.TextColor3 = Color3.fromRGB(182, 186, 194)
countLabel.TextSize = 13
countLabel.TextXAlignment = Enum.TextXAlignment.Right
countLabel.Parent = titleBar

local closeButton = Instance.new("TextButton")
closeButton.Name = "CloseButton"
closeButton.AnchorPoint = Vector2.new(1, 0.5)
closeButton.Position = UDim2.new(1, -7, 0.5, 0)
closeButton.Size = UDim2.fromOffset(24, 24)
closeButton.BackgroundTransparency = 1
closeButton.AutoButtonColor = false
closeButton.Font = Enum.Font.GothamBold
closeButton.Text = "-"
closeButton.TextColor3 = Color3.fromRGB(190, 194, 202)
closeButton.TextSize = 18
closeButton.Parent = titleBar

local openButton = Instance.new("TextButton")
openButton.Name = "OpenButton"
openButton.AnchorPoint = Vector2.new(1, 0)
openButton.Position = UDim2.new(1, -12, 0, 12)
openButton.Size = UDim2.fromOffset(92, 30)
openButton.BackgroundColor3 = Color3.fromRGB(20, 21, 24)
openButton.BackgroundTransparency = 0.08
openButton.BorderSizePixel = 0
openButton.AutoButtonColor = true
openButton.Font = Enum.Font.GothamMedium
openButton.Text = "Players"
openButton.TextColor3 = Color3.fromRGB(242, 244, 247)
openButton.TextSize = 14
openButton.Visible = false
openButton.Parent = screenGui

local openCorner = Instance.new("UICorner")
openCorner.CornerRadius = UDim.new(0, 6)
openCorner.Parent = openButton

local headerRow = Instance.new("Frame")
headerRow.Name = "HeaderRow"
headerRow.Position = UDim2.fromOffset(OUTER_PADDING, TITLE_HEIGHT + 4)
headerRow.Size = UDim2.new(1, -(OUTER_PADDING * 2), 0, HEADER_HEIGHT)
headerRow.BackgroundTransparency = 1
headerRow.BorderSizePixel = 0
headerRow.Parent = mainFrame

local scrollingFrame = Instance.new("ScrollingFrame")
scrollingFrame.Name = "PlayerList"
scrollingFrame.Position = UDim2.fromOffset(OUTER_PADDING, TITLE_HEIGHT + HEADER_HEIGHT + 6)
scrollingFrame.Size = UDim2.new(1, -(OUTER_PADDING * 2), 1, -(TITLE_HEIGHT + HEADER_HEIGHT + OUTER_PADDING + 8))
scrollingFrame.BackgroundTransparency = 1
scrollingFrame.BorderSizePixel = 0
scrollingFrame.ScrollBarThickness = 3
scrollingFrame.ScrollBarImageColor3 = Color3.fromRGB(122, 126, 136)
scrollingFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
scrollingFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
scrollingFrame.Parent = mainFrame

local listLayout = Instance.new("UIListLayout")
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Padding = UDim.new(0, ROW_GAP)
listLayout.Parent = scrollingFrame

local function addColumnLayout(parent)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, INNER_PADDING_X)
	padding.PaddingRight = UDim.new(0, INNER_PADDING_X)
	padding.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, COLUMN_GAP)
	layout.Parent = parent
end

local function createStatLabel(parent, column, height, isHeader)
	local label = Instance.new("TextLabel")
	label.Name = column.Key
	label.LayoutOrder = 10
	label.Size = UDim2.fromOffset(column.Width, height)
	label.BackgroundTransparency = 1
	label.Font = isHeader and Enum.Font.GothamMedium or Enum.Font.Gotham
	label.Text = isHeader and column.Display or "0"
	label.TextColor3 = isHeader and Color3.fromRGB(151, 156, 166) or Color3.fromRGB(235, 237, 242)
	label.TextSize = isHeader and 11 or 13
	label.TextXAlignment = Enum.TextXAlignment.Right
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Parent = parent

	return label
end

local function createHeader()
	addColumnLayout(headerRow)

	local playerHeader = Instance.new("TextLabel")
	playerHeader.Name = "Player"
	playerHeader.LayoutOrder = 1
	playerHeader.Size = UDim2.new(1, playerColumnOffset, 1, 0)
	playerHeader.BackgroundTransparency = 1
	playerHeader.Font = Enum.Font.GothamMedium
	playerHeader.Text = "Player"
	playerHeader.TextColor3 = Color3.fromRGB(151, 156, 166)
	playerHeader.TextSize = 11
	playerHeader.TextXAlignment = Enum.TextXAlignment.Left
	playerHeader.TextYAlignment = Enum.TextYAlignment.Center
	playerHeader.TextTruncate = Enum.TextTruncate.AtEnd
	playerHeader.Parent = headerRow

	for index, column in ipairs(STAT_COLUMNS) do
		local label = createStatLabel(headerRow, column, HEADER_HEIGHT, true)
		label.LayoutOrder = index + 1
	end
end

local function createNameCell(parent, player)
	local nameCell = Instance.new("Frame")
	nameCell.Name = "Player"
	nameCell.LayoutOrder = 1
	nameCell.Size = UDim2.new(1, playerColumnOffset, 1, 0)
	nameCell.BackgroundTransparency = 1
	nameCell.ClipsDescendants = true
	nameCell.Parent = parent

	local nameLayout = Instance.new("UIListLayout")
	nameLayout.FillDirection = Enum.FillDirection.Horizontal
	nameLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	nameLayout.SortOrder = Enum.SortOrder.LayoutOrder
	nameLayout.Padding = UDim.new(0, 6)
	nameLayout.Parent = nameCell

	local avatar = Instance.new("ImageLabel")
	avatar.Name = "Avatar"
	avatar.LayoutOrder = 1
	avatar.Size = UDim2.fromOffset(AVATAR_SIZE, AVATAR_SIZE)
	avatar.BackgroundTransparency = 1
	avatar.ImageTransparency = 0.05
	avatar.Parent = nameCell

	local avatarCorner = Instance.new("UICorner")
	avatarCorner.CornerRadius = UDim.new(1, 0)
	avatarCorner.Parent = avatar

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "Name"
	nameLabel.LayoutOrder = 2
	nameLabel.Size = UDim2.new(1, -(AVATAR_SIZE + 6), 1, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamMedium
	nameLabel.Text = player.DisplayName
	nameLabel.TextColor3 = Color3.fromRGB(244, 246, 250)
	nameLabel.TextSize = 13
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextYAlignment = Enum.TextYAlignment.Center
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Parent = nameCell

	task.spawn(function()
		local ok, image = pcall(function()
			return Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
		end)

		if ok and playerRows[player] then
			avatar.Image = image
		end
	end)

	return nameLabel
end

local function rowCount()
	local count = 0

	for _ in pairs(playerRows) do
		count += 1
	end

	return count
end

local function updatePanelHeight()
	local visibleRows = math.clamp(rowCount(), 1, MAX_VISIBLE_ROWS)
	local rowsHeight = (visibleRows * ROW_HEIGHT) + (math.max(visibleRows - 1, 0) * ROW_GAP)
	local totalHeight = TITLE_HEIGHT + HEADER_HEIGHT + rowsHeight + OUTER_PADDING + 10

	mainFrame.Size = UDim2.fromOffset(PANEL_WIDTH, totalHeight)
	countLabel.Text = tostring(rowCount())
end

local function refreshSorting()
	local sortedPlayers = {}

	for player in pairs(playerRows) do
		table.insert(sortedPlayers, player)
	end

	table.sort(sortedPlayers, function(a, b)
		local aVisits = readStat(a, "Visits")
		local bVisits = readStat(b, "Visits")

		if aVisits == bVisits then
			return a.DisplayName:lower() < b.DisplayName:lower()
		end

		return aVisits > bVisits
	end)

	for index, player in ipairs(sortedPlayers) do
		local rowData = playerRows[player]

		if rowData then
			rowData.Frame.LayoutOrder = index
		end
	end
end

local function queueRefreshSorting()
	if sortQueued then
		return
	end

	sortQueued = true

	task.defer(function()
		sortQueued = false
		refreshSorting()
	end)
end

local function updateRow(player)
	local rowData = playerRows[player]

	if not rowData then
		return
	end

	rowData.NameLabel.Text = player.DisplayName

	for _, column in ipairs(STAT_COLUMNS) do
		local label = rowData.StatLabels[column.Key]

		if label then
			label.Text = formatNumber(readStat(player, column.ValueName))
		end
	end

	queueRefreshSorting()
end

local function bindStatsFolder(player)
	local rowData = playerRows[player]

	if not rowData then
		return
	end

	disconnectAll(rowData.StatConnections)

	local statsFolder = findStatsFolder(player)

	if statsFolder then
		for _, child in ipairs(statsFolder:GetChildren()) do
			if child:IsA("ValueBase") then
				table.insert(rowData.StatConnections, child:GetPropertyChangedSignal("Value"):Connect(function()
					updateRow(player)
				end))
			end
		end

		table.insert(rowData.StatConnections, statsFolder.ChildAdded:Connect(function(child)
			if child:IsA("ValueBase") then
				table.insert(rowData.StatConnections, child:GetPropertyChangedSignal("Value"):Connect(function()
					updateRow(player)
				end))
			end

			updateRow(player)
		end))

		table.insert(rowData.StatConnections, statsFolder.ChildRemoved:Connect(function()
			updateRow(player)
		end))
	end

	updateRow(player)
end

local function createRow(player)
	if playerRows[player] then
		return
	end

	local row = Instance.new("Frame")
	row.Name = tostring(player.UserId)
	row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
	row.BackgroundColor3 = player == localPlayer and Color3.fromRGB(56, 73, 112) or Color3.fromRGB(255, 255, 255)
	row.BackgroundTransparency = player == localPlayer and 0.18 or 0.96
	row.BorderSizePixel = 0
	row.Parent = scrollingFrame

	local rowCorner = Instance.new("UICorner")
	rowCorner.CornerRadius = UDim.new(0, 3)
	rowCorner.Parent = row

	local rowStroke = Instance.new("UIStroke")
	rowStroke.Color = Color3.fromRGB(255, 255, 255)
	rowStroke.Transparency = player == localPlayer and 0.9 or 0.96
	rowStroke.Thickness = 1
	rowStroke.Parent = row

	addColumnLayout(row)

	local rowData = {
		Frame = row,
		NameLabel = createNameCell(row, player),
		StatLabels = {},
		StatConnections = {},
		PlayerConnections = {},
	}

	for index, column in ipairs(STAT_COLUMNS) do
		local label = createStatLabel(row, column, ROW_HEIGHT, false)
		label.LayoutOrder = index + 1
		rowData.StatLabels[column.Key] = label
	end

	table.insert(rowData.PlayerConnections, player:GetPropertyChangedSignal("DisplayName"):Connect(function()
		updateRow(player)
	end))

	table.insert(rowData.PlayerConnections, player.ChildAdded:Connect(function(child)
		if isStatsFolderName(child.Name) then
			bindStatsFolder(player)
		end
	end))

	table.insert(rowData.PlayerConnections, player.ChildRemoved:Connect(function(child)
		if isStatsFolderName(child.Name) then
			bindStatsFolder(player)
		end
	end))

	if player ~= localPlayer then
		row.MouseEnter:Connect(function()
			row.BackgroundTransparency = 0.91
		end)

		row.MouseLeave:Connect(function()
			row.BackgroundTransparency = 0.96
		end)
	end

	playerRows[player] = rowData
	bindStatsFolder(player)
	updatePanelHeight()
end

local function removeRow(player)
	local rowData = playerRows[player]

	if not rowData then
		return
	end

	disconnectAll(rowData.StatConnections)
	disconnectAll(rowData.PlayerConnections)
	rowData.Frame:Destroy()
	playerRows[player] = nil
	updatePanelHeight()
	queueRefreshSorting()
end

local function setLeaderboardVisible(isVisible)
	mainFrame.Visible = isVisible
	openButton.Visible = not isVisible
end

closeButton.MouseButton1Click:Connect(function()
	setLeaderboardVisible(false)
end)

openButton.MouseButton1Click:Connect(function()
	setLeaderboardVisible(true)
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	if input.KeyCode == Enum.KeyCode.Tab then
		setLeaderboardVisible(not mainFrame.Visible)
	end
end)

createHeader()

for _, player in ipairs(Players:GetPlayers()) do
	createRow(player)
end

Players.PlayerAdded:Connect(createRow)
Players.PlayerRemoving:Connect(removeRow)
