-- ClientMain: 倒计时 UI + 武器选择 UI + 客户端发起攻击（服务端判定）
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer

local timerEvent   = ReplicatedStorage:WaitForChild("RoundTimer")
local chooseEvent  = ReplicatedStorage:WaitForChild("WeaponChoose")
local attackEvent  = ReplicatedStorage:WaitForChild("WeaponAttack")

-- ========== 顶部倒计时 ==========
local gui = Instance.new("ScreenGui")
gui.Name = "RoundUI"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local label = Instance.new("TextLabel")
label.Name = "TimerLabel"
label.BackgroundTransparency = 1
label.TextScaled = true
label.Font = Enum.Font.SourceSansBold
label.Size = UDim2.new(0, 320, 0, 52)
label.Position = UDim2.fromScale(0.5, 0.03)
label.AnchorPoint = Vector2.new(0.5, 0)
label.Text = "准备中：--s"
label.Parent = gui

local phaseText = { WAITING = "准备中", COMBAT = "战斗中", RESET = "结算中" }

-- ========== 武器选择面板 ==========
local picker = Instance.new("Frame")
picker.Name = "WeaponPicker"
picker.AnchorPoint = Vector2.new(0.5, 1)
picker.Position = UDim2.fromScale(0.5, 0.95)
picker.Size = UDim2.new(0, 460, 0, 90)
picker.BackgroundTransparency = 0.2
picker.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
picker.Visible = false
picker.Parent = gui

local uiList = Instance.new("UIListLayout")
uiList.FillDirection = Enum.FillDirection.Horizontal
uiList.Padding = UDim.new(0, 12)
uiList.HorizontalAlignment = Enum.HorizontalAlignment.Center
uiList.VerticalAlignment = Enum.VerticalAlignment.Center
uiList.Parent = picker

local function mkButton(text, key)
	local btn = Instance.new("TextButton")
	btn.Name = "Btn_" .. key
	btn.Size = UDim2.new(0, 140, 1, -20)
	btn.Position = UDim2.new(0, 0, 0, 10)
	btn.Text = text
	btn.TextScaled = true
	btn.Font = Enum.Font.SourceSansBold
	btn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)

	-- 选中样式
	local selected = Instance.new("UIStroke")
	selected.Thickness = 3
	selected.Color = Color3.fromRGB(255, 200, 0)
	selected.Enabled = false
	selected.Parent = btn

	btn.MouseButton1Click:Connect(function()
		chooseEvent:FireServer(key) -- 通知服务器：我的选择
		-- 高亮自己
		for _, c in ipairs(picker:GetChildren()) do
			if c:IsA("TextButton") then
				local s = c:FindFirstChildOfClass("UIStroke")
				if s then s.Enabled = (c == btn) end
			end
		end
	end)
	return btn
end

mkButton("刀",  "sword").Parent  = picker
mkButton("锤子","hammer").Parent = picker
mkButton("弓",  "bow").Parent    = picker

-- 切换 UI（由服务器广播阶段）
timerEvent.OnClientEvent:Connect(function(data)
	local p = data.phase or "WAITING"
	local s = tonumber(data.secs) or 0
	label.Text = string.format("%s：%ds", phaseText[p] or p, s)
	picker.Visible = (p == "WAITING")
end)

-- ========== 客户端发起攻击（Tool.Activated），服务端再做校验与判定 ==========
local function hookTool(tool: Instance)
	if not tool:IsA("Tool") then return end
	local name = tool.Name
	if name ~= "Sword" and name ~= "Hammer" and name ~= "Bow" then return end

	tool.Activated:Connect(function()
		-- 对于 Bow，传 action="shoot"；近战是 "swing"
		local action = (name == "Bow") and "shoot" or "swing"
		attackEvent:FireServer({ action = action })
	end)
end

local function watchContainer(container: Instance)
	for _, c in ipairs(container:GetChildren()) do hookTool(c) end
	container.ChildAdded:Connect(hookTool)
end

watchContainer(player:WaitForChild("Backpack"))
if player.Character then watchContainer(player.Character) end
player.CharacterAdded:Connect(function(char) watchContainer(char) end)
