local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

-- === 可调时长（秒）===
local PREP_TIME   = 10   -- 准备：玩家在笼子里
local COMBAT_TIME = 60   -- 战斗：放出来对砍
local RESET_TIME  = 6    -- 结算：回笼子、清理

local RoundTimerEvent = ReplicatedStorage:WaitForChild("RoundTimer")
local inRoundAttr = "InRound"

-- 收集出生点（若未摆放，就用默认坐标）
local function collectSpawnPositions(folder)
	local list = {}
	if folder then
		for _, c in ipairs(folder:GetChildren()) do
			if c:IsA("BasePart") then table.insert(list, c.Position + Vector3.new(0, 4, 0)) end
		end
	end
	return list
end

local function getSpawnPositions()
	local spawns = workspace:FindFirstChild("Spawns")
	local cage = spawns and spawns:FindFirstChild("Cage")
	local arena = spawns and spawns:FindFirstChild("Arena")

	local cagePos = collectSpawnPositions(cage)
	local arenaPos = collectSpawnPositions(arena)

	if #cagePos == 0 then
		cagePos = {
			Vector3.new(-80, 6, 0), Vector3.new(-90, 6, -8),
			Vector3.new(-70, 6, 8), Vector3.new(-85, 6, 12),
		}
	end
	if #arenaPos == 0 then
		arenaPos = {
			Vector3.new(0, 6, 0), Vector3.new(8, 6, 8),
			Vector3.new(-8, 6, -8), Vector3.new(12, 6, -12),
		}
	end
	return cagePos, arenaPos
end

local cagePositions, arenaPositions = getSpawnPositions()
local cageIdx, arenaIdx = 1, 1

local function nextPos(list, idx)
	if #list == 0 then return Vector3.new(0, 10, 0), 1 end
	if idx > #list then idx = 1 end
	local v = list[idx]
	return v, idx + 1
end

-- 简易"笼门"：如果你在 workspace.Gates 下放了门的 Part，就能开关碰撞与透明度
local function setGates(open)
	local gates = workspace:FindFirstChild("Gates")
	if not gates then return end
	for _, g in ipairs(gates:GetChildren()) do
		if g:IsA("BasePart") then
			g.CanCollide = not open
			g.Transparency = open and 0.6 or 0
		end
	end
end

-- 工具：重置角色并移动到指定坐标
local function resetAndMoveTo(p, pos)
	if p.Backpack then
		for _, it in ipairs(p.Backpack:GetChildren()) do it:Destroy() end
	end
	local char = p.Character or p.CharacterAdded:Wait()
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then hum.Health = hum.MaxHealth end
	local hrp = char:WaitForChild("HumanoidRootPart", 5)
	if hrp then char:MoveTo(pos) end
end

-- 发武器功能
local swordTemplate = ServerStorage:FindFirstChild("Sword")
local function giveSword(p)
  if not swordTemplate then return end
  local s = swordTemplate:Clone()
  s.Parent = p.Backpack
end

local function broadcast(phase, secs)
	RoundTimerEvent:FireAllClients({ phase = phase, secs = secs })
end

local function aliveCount()
	local n = 0
	for _, p in ipairs(Players:GetPlayers()) do
		if p:GetAttribute(inRoundAttr) then
			local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 then n += 1 end
		end
	end
	return n
end

-- 根据阶段安置新加入/重生的玩家
local Phase = "WAITING" -- WAITING/COMBAT/RESET
local function placeAccordingToPhase(p, char)
	-- 刷新一次出生点（防止你后来在 Studio 加了点位）
	cagePositions, arenaPositions = getSpawnPositions()

	if Phase == "COMBAT" and p:GetAttribute(inRoundAttr) then
		local pos; pos, arenaIdx = nextPos(arenaPositions, arenaIdx)
		resetAndMoveTo(p, pos)
	else
		local pos; pos, cageIdx = nextPos(cagePositions, cageIdx)
		resetAndMoveTo(p, pos)
	end
end

Players.PlayerAdded:Connect(function(p)
	p:SetAttribute(inRoundAttr, false)
	p.CharacterAdded:Connect(function(char)
		char:WaitForChild("HumanoidRootPart", 5)
		placeAccordingToPhase(p, char)
	end)
end)

-- 主循环
task.spawn(function()
	while true do
		-- 准备阶段：把在线玩家都纳入本回合，拉进笼子
		Phase = "WAITING"
		cagePositions, arenaPositions = getSpawnPositions()
		for _, p in ipairs(Players:GetPlayers()) do
			p:SetAttribute(inRoundAttr, true)
			local pos; pos, cageIdx = nextPos(cagePositions, cageIdx)
			resetAndMoveTo(p, pos)
		end
		setGates(false)
		for t = PREP_TIME, 0, -1 do broadcast("WAITING", t); task.wait(1) end

		-- 战斗阶段：开门→传到竞技场→发武器
		Phase = "COMBAT"
		setGates(true)
		for _, p in ipairs(Players:GetPlayers()) do
			if p:GetAttribute(inRoundAttr) then
				local pos; pos, arenaIdx = nextPos(arenaPositions, arenaIdx)
				resetAndMoveTo(p, pos)
				giveSword(p)
			end
		end
		for t = COMBAT_TIME, 0, -1 do
			broadcast("COMBAT", t)
			if aliveCount() <= 1 then break end
			task.wait(1)
		end

		-- 结算阶段：关门→全部回笼子→清标记
		Phase = "RESET"
		setGates(false)
		for _, p in ipairs(Players:GetPlayers()) do
			p:SetAttribute(inRoundAttr, false)
			local pos; pos, cageIdx = nextPos(cagePositions, cageIdx)
			resetAndMoveTo(p, pos)
		end
		for t = RESET_TIME, 0, -1 do broadcast("RESET", t); task.wait(1) end
	end
end)
