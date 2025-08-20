-- ClientMain: 倒计时 UI + 武器选择 UI + 客户端发起攻击（服务端判定）
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer

local timerEvent   = ReplicatedStorage:WaitForChild("RoundTimer")
local chooseEvent  = ReplicatedStorage:WaitForChild("WeaponChoose")
local attackEvent  = ReplicatedStorage:WaitForChild("WeaponAttack")
local combatFX    = ReplicatedStorage:WaitForChild("CombatFX")

-- ===== 视觉/镜头工具函数 =====
local TweenService = game:GetService("TweenService")

local function cameraShake(mag: number, dur: number)
	local cam = workspace.CurrentCamera
	if not cam then return end
	local originalCF = cam.CFrame
	local t0 = os.clock()
	while os.clock() - t0 < dur do
		local off = Vector3.new(
			(math.random() - 0.5) * mag,
			(math.random() - 0.5) * mag,
			(math.random() - 0.5) * mag
		)
		cam.CFrame = originalCF * CFrame.new(off)
		task.wait()
	end
	cam.CFrame = originalCF
end

local function flashVignette()
	-- 一个简单的红色半透明覆盖，0.15s 衰退
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(1,1)
	f.BackgroundColor3 = Color3.fromRGB(255,0,0)
	f.BackgroundTransparency = 0.6
	f.ZIndex = 10
	f.Parent = gui
	TweenService:Create(f, TweenInfo.new(0.15), {BackgroundTransparency = 1}):Play()
	task.delay(0.2, function() f:Destroy() end)
end

local function floatDamageText(head: Instance, amount: number)
	if not head then return end
	local bg = Instance.new("BillboardGui")
	bg.Size = UDim2.new(0, 0, 0, 0)
	bg.StudsOffset = Vector3.new(0, 2.6, 0)
	bg.AlwaysOnTop = true
	bg.Parent = head

	local tl = Instance.new("TextLabel")
	tl.BackgroundTransparency = 1
	tl.TextColor3 = Color3.fromRGB(255, 240, 120)
	tl.TextStrokeTransparency = 0.3
	tl.TextScaled = true
	tl.Font = Enum.Font.SourceSansBold
	tl.Size = UDim2.new(0, 0, 0, 0)
	tl.Text = "-" .. tostring(amount)
	tl.Parent = bg

	-- 简单弹跳动画
	tl.Size = UDim2.fromOffset(0, 0)
	local tween1 = TweenService:Create(tl, TweenInfo.new(0.12), {Size = UDim2.fromOffset(48, 28)})
	local tween2 = TweenService:Create(bg, TweenInfo.new(0.45), {StudsOffset = Vector3.new(0, 4, 0)})
	local tween3 = TweenService:Create(tl, TweenInfo.new(0.45), {TextTransparency = 1})
	tween1:Play(); tween2:Play(); tween3:Play()
	task.delay(0.5, function() bg:Destroy() end)
end

-- 给武器加 Trail（两端 Attachment）
local function ensureTrail(tool: Instance)
	if not tool:IsA("Tool") then return end
	local handle = tool:FindFirstChild("Handle")
	if not handle or handle:FindFirstChild("BladeTrail") then return end

	local a0 = Instance.new("Attachment")
	a0.Name = "A0"
	a0.Position = Vector3.new(0, 0.4, -1.2)
	a0.Parent = handle

	local a1 = Instance.new("Attachment")
	a1.Name = "A1"
	a1.Position = Vector3.new(0, -0.4, 1.2)
	a1.Parent = handle

	local trail = Instance.new("Trail")
	trail.Name = "BladeTrail"
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Brightness = 2
	trail.Transparency = NumberSequence.new(0.1, 1)
	trail.Lifetime = 0.15
	trail.Enabled = false
	trail.Parent = handle
end

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

-- 攻击提示UI
local attackHint = Instance.new("TextLabel")
attackHint.Name = "AttackHint"
attackHint.BackgroundTransparency = 1
attackHint.TextScaled = true
attackHint.Font = Enum.Font.SourceSans
attackHint.Size = UDim2.new(0, 200, 0, 30)
attackHint.Position = UDim2.fromScale(0.5, 0.85)
attackHint.AnchorPoint = Vector2.new(0.5, 0)
attackHint.Text = "按 F 键攻击"
attackHint.TextColor3 = Color3.fromRGB(255, 255, 255)
attackHint.TextStrokeTransparency = 0.5
attackHint.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
attackHint.Visible = false
attackHint.Parent = gui

-- 切换 UI（由服务器广播阶段）
timerEvent.OnClientEvent:Connect(function(data)
	local p = data.phase or "WAITING"
	local s = tonumber(data.secs) or 0
	label.Text = string.format("%s：%ds", phaseText[p] or p, s)
	picker.Visible = (p == "WAITING")
	attackHint.Visible = (p == "COMBAT") -- 战斗阶段显示攻击提示
end)

-- ========== 客户端发起攻击（按键 + Tool.Activated），服务端再做校验与判定 ==========
local UserInputService = game:GetService("UserInputService")
local currentWeapon = nil

local function hookTool(tool: Instance)
	if not tool:IsA("Tool") then return end
	local name = tool.Name
	if name ~= "Sword" and name ~= "Hammer" and name ~= "Bow" then return end

	print("绑定武器:", name) -- 调试信息
	ensureTrail(tool)

	-- 当装备武器时，设置为当前武器
	tool.Equipped:Connect(function()
		currentWeapon = tool
		print("装备武器:", name)
	end)
	
	tool.Unequipped:Connect(function()
		if currentWeapon == tool then
			currentWeapon = nil
			print("卸下武器:", name)
		end
	end)

	-- 保留原有的点击攻击功能
	tool.Activated:Connect(function()
		print("武器被激活:", name) -- 调试信息
		performAttack(name)
	end)
end

-- 统一的攻击函数
local function performAttack(weaponName)
	if not weaponName then return end
	
	print("执行攻击:", weaponName) -- 调试信息
	
	-- 本地立即给点手感：镜头轻微抖动 + Trail 开启 0.18s
	cameraShake(0.15, 0.08)
	
	-- 如果有当前装备的武器，启用Trail效果
	if currentWeapon then
		local tr = currentWeapon:FindFirstChild("Handle") and currentWeapon.Handle:FindFirstChild("BladeTrail")
		if tr and weaponName ~= "Bow" then
			tr.Enabled = true
			task.delay(0.18, function() if tr then tr.Enabled = false end end)
		end
	end

	-- 通知服务器执行判定
	local action = (weaponName == "Bow") and "shoot" or "swing"
	print("发送攻击事件:", action) -- 调试信息
	attackEvent:FireServer({ action = action })
end

-- 按键攻击系统
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end -- 如果UI正在处理输入，则不响应
	
	-- 攻击按键：F键
	if input.KeyCode == Enum.KeyCode.F then
		if currentWeapon then
			performAttack(currentWeapon.Name)
		else
			-- 如果没有装备武器，尝试从背包中找到武器
			local backpack = player:FindFirstChild("Backpack")
			if backpack then
				for _, tool in ipairs(backpack:GetChildren()) do
					if tool:IsA("Tool") and (tool.Name == "Sword" or tool.Name == "Hammer" or tool.Name == "Bow") then
						performAttack(tool.Name)
						break
					end
				end
			end
		end
	end
end)

local function watchContainer(container: Instance)
	for _, c in ipairs(container:GetChildren()) do hookTool(c) end
	container.ChildAdded:Connect(hookTool)
end

watchContainer(player:WaitForChild("Backpack"))
if player.Character then watchContainer(player.Character) end
player.CharacterAdded:Connect(function(char) watchContainer(char) end)

-- ===== 服务器战斗特效回传 =====
combatFX.OnClientEvent:Connect(function(msg)
	if typeof(msg) ~= "table" then return end
	if msg.type == "hitConfirm" then
		-- 我命中了：更强的摄像机抖动 + 若有命中点就闪一下粒子 + 飘字
		cameraShake(0.35, 0.09)
		if msg.points then
			for _, p in ipairs(msg.points) do
				-- 命中点微小火花
				local pe = Instance.new("ParticleEmitter")
				pe.Rate = 0
				pe.Speed = NumberRange.new(4,8)
				pe.Lifetime = NumberRange.new(0.2,0.3)
				pe.Texture = "rbxassetid://243098098" -- 小火花贴图（可换）
				pe.Parent = workspace.Terrain
				pe:Emit(12)
				task.delay(0.3, function() pe:Destroy() end)
			end
		end
	elseif msg.type == "gotHit" then
		-- 我被打了：红晕 + 抖动 + 飘字
		flashVignette()
		cameraShake(0.25, 0.08)
		local char = Players.LocalPlayer.Character
		local head = char and char:FindFirstChild("Head")
		floatDamageText(head, msg.damage or 0)
	end
end)
