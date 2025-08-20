-- 回合控制 + 世界搭建 + 简易近战武器 + 服务器侧伤害与冷却
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local PhysicsService = game:GetService("PhysicsService")

-- ====== 配置 ======
local PREP_TIME   = 10   -- ⏳准备阶段（关笼子）
local COMBAT_TIME = 60   -- ⚔️战斗阶段
local RESET_TIME  = 6    -- 🔄结算阶段
local ATTACK_COOLDOWN = 0.7
local ATTACK_RANGE = 7
local ATTACK_DAMAGE = 25

local RoundTimerEvent = ReplicatedStorage:WaitForChild("RoundTimer")
local SwordAttackEvent = ReplicatedStorage:WaitForChild("SwordAttack")
local inRoundAttr = "InRound"
local Phase = "WAITING" -- WAITING / COMBAT / RESET

-- ====== 世界生成：如果你没手摆，我帮你造个最小笼子+竞技场 ======
local function ensureWorld()
	print("开始生成世界...")
	
	-- 清理旧的世界（如果存在）
	local oldArena = workspace:FindFirstChild("GeneratedArena")
	if oldArena then
		print("清理旧的世界...")
		oldArena:Destroy()
	end
	
	local oldGates = workspace:FindFirstChild("Gates")
	if oldGates then
		oldGates:Destroy()
	end
	
	local oldSpawns = workspace:FindFirstChild("Spawns")
	if oldSpawns then
		oldSpawns:Destroy()
	end
	
	local model = Instance.new("Model")
	model.Name = "GeneratedArena"
	model.Parent = workspace
	print("创建 GeneratedArena 模型")

	local function mkPart(props)
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = true
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		for k, v in pairs(props) do p[k] = v end
		p.Parent = model
		return p
	end

	-- Cage: 左侧 (-80, 0.5, 0)，40x40，墙高20，东侧留门
	print("生成笼子...")
	mkPart({Name="CageFloor", Size=Vector3.new(40,1,40), Position=Vector3.new(-80,0.5,0), Material=Enum.Material.Concrete, Color=Color3.fromRGB(200,200,200)})
	mkPart({Name="CageWall_N", Size=Vector3.new(40,20,1), Position=Vector3.new(-80,10.5,-20)})
	mkPart({Name="CageWall_S", Size=Vector3.new(40,20,1), Position=Vector3.new(-80,10.5,20)})
	mkPart({Name="CageWall_W", Size=Vector3.new(1,20,40), Position=Vector3.new(-100,10.5,0)})
	-- 东墙拆成两截留 6 宽门
	mkPart({Name="CageWall_E_L", Size=Vector3.new(1,20,17), Position=Vector3.new(-60,10.5,-11.5)})
	mkPart({Name="CageWall_E_R", Size=Vector3.new(1,20,17), Position=Vector3.new(-60,10.5, 11.5)})
	
	-- 门：默认关（可碰撞）
	local gatesFolder = Instance.new("Folder")
	gatesFolder.Name = "Gates"
	gatesFolder.Parent = workspace
	local gate = mkPart({Name="CageGate", Size=Vector3.new(1,12,6), Position=Vector3.new(-60,6.5,0), Color=Color3.fromRGB(255, 170, 0)})
	gate.Parent = gatesFolder
	print("生成笼门")

	-- Arena: 中间 (0, 0.5, 0)，120x120
	print("生成竞技场...")
	mkPart({Name="ArenaFloor", Size=Vector3.new(120,1,120), Position=Vector3.new(0,0.5,0), Material=Enum.Material.Concrete, Color=Color3.fromRGB(170,170,170)})
	mkPart({Name="ArenaWall_N", Size=Vector3.new(120,20,1), Position=Vector3.new(0,10.5,-60)})
	mkPart({Name="ArenaWall_S", Size=Vector3.new(120,20,1), Position=Vector3.new(0,10.5,60)})
	mkPart({Name="ArenaWall_W", Size=Vector3.new(1,20,120), Position=Vector3.new(-60,10.5,0)})
	mkPart({Name="ArenaWall_E", Size=Vector3.new(1,20,120), Position=Vector3.new(60,10.5,0)})

	-- Spawns（标记点，脚本会读取坐标）
	local spawns = Instance.new("Folder"); spawns.Name="Spawns"; spawns.Parent = workspace
	local cageF = Instance.new("Folder"); cageF.Name="Cage"; cageF.Parent = spawns
	local arenaF = Instance.new("Folder"); arenaF.Name="Arena"; arenaF.Parent = spawns

	local function mkSpawn(name, pos, parent)
		local s = Instance.new("Part")
		s.Name = name
		s.Size = Vector3.new(2,1,2)
		s.Anchored = true
		s.CanCollide = false
		s.Transparency = 1
		s.Position = pos
		s.Parent = parent
		return s
	end
	mkSpawn("CageSpawn1", Vector3.new(-88, 6, -12), cageF)
	mkSpawn("CageSpawn2", Vector3.new(-88, 6,  12), cageF)
	mkSpawn("CageSpawn3", Vector3.new(-72, 6, -12), cageF)
	mkSpawn("CageSpawn4", Vector3.new(-72, 6,  12), cageF)

	mkSpawn("ArenaSpawn1", Vector3.new( -8, 6, -8), arenaF)
	mkSpawn("ArenaSpawn2", Vector3.new(  8, 6,  8), arenaF)
	mkSpawn("ArenaSpawn3", Vector3.new(-12, 6, 12), arenaF)
	mkSpawn("ArenaSpawn4", Vector3.new( 12, 6,-12), arenaF)
	print("生成出生点")
	
	print("世界生成完成！")
end

local function setGates(open: boolean)
	local gates = workspace:FindFirstChild("Gates")
	if not gates then return end
	for _, g in ipairs(gates:GetChildren()) do
		if g:IsA("BasePart") then
			g.CanCollide = not open
			g.Transparency = open and 0.6 or 0
		end
	end
end

-- ====== 出生点读取 ======
local function collectSpawnPositions(folder: Instance?): {Vector3}
	local list = {}
	if folder then
		for _, c in ipairs(folder:GetChildren()) do
			if c:IsA("BasePart") then table.insert(list, c.Position + Vector3.new(0, 3, 0)) end
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
		cagePos = {Vector3.new(-88,6,-12), Vector3.new(-88,6,12), Vector3.new(-72,6,-12), Vector3.new(-72,6,12)}
	end
	if #arenaPos == 0 then
		arenaPos = {Vector3.new(-8,6,-8), Vector3.new(8,6,8), Vector3.new(-12,6,12), Vector3.new(12,6,-12)}
	end
	return cagePos, arenaPos
end

local function rotateIndex(idx, n) return (idx % n) + 1 end

-- ====== 发简易武器（不需要 Tool 内脚本）======
local function giveWeapon(p: Player)
	print("尝试给玩家", p.Name, "发放武器")
	
	-- 如玩家已有则不重复发
	if p.Backpack:FindFirstChild("Gladius") or (p.Character and p.Character:FindFirstChild("Gladius")) then 
		print("玩家", p.Name, "已有武器，跳过")
		return 
	end

	local tool = Instance.new("Tool")
	tool.Name = "Gladius"
	tool.RequiresHandle = true
	tool.CanBeDropped = false

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(1,1,3)
	handle.Color = Color3.fromRGB(230, 230, 230)
	handle.Massless = true
	handle.CanCollide = false
	handle.Parent = tool

	tool.Parent = p.Backpack
	print("成功给玩家", p.Name, "发放武器")
end

-- ====== 服务器侧攻击判定（防作弊：冷却、距离、阶段）======
local lastSwingAt: {[number]: number} = {} -- userId -> timestamp

local function doMeleeDamage(attacker: Player)
	if Phase ~= "COMBAT" then return end
	if not attacker.Character then return end

	local now = os.clock()
	local last = lastSwingAt[attacker.UserId] or 0
	if now - last < ATTACK_COOLDOWN then return end

	local hrp = attacker.Character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	-- 圆形范围检索
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { attacker.Character }

	local parts = workspace:GetPartBoundsInRadius(hrp.Position, ATTACK_RANGE, params)
	local hitHumanoids = {}
	for _, part in ipairs(parts) do
		local m = part:FindFirstAncestorOfClass("Model")
		if m and m ~= attacker.Character then
			local hum = m:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 then
				hitHumanoids[hum] = true
			end
		end
	end

	for hum, _ in pairs(hitHumanoids) do
		hum:TakeDamage(ATTACK_DAMAGE)
	end

	lastSwingAt[attacker.UserId] = now
end

SwordAttackEvent.OnServerEvent:Connect(function(p: Player, payload)
	if typeof(payload) ~= "table" or payload.action ~= "swing" then return end
	-- 只有持有武器的参赛者才能攻击
	if not p:GetAttribute(inRoundAttr) then return end
	local has = (p.Backpack and p.Backpack:FindFirstChild("Gladius")) or (p.Character and p.Character:FindFirstChild("Gladius"))
	if not has then return end
	doMeleeDamage(p)
end)

-- ====== 阶段内通用 ======
local function broadcast(phase: string, secs: number)
	RoundTimerEvent:FireAllClients({ phase = phase, secs = secs })
end

local function resetPlayer(p: Player)
	-- 清背包与血量
	if p.Backpack then for _, it in ipairs(p.Backpack:GetChildren()) do if it:IsA("Tool") then it:Destroy() end end end
	local char = p.Character
	if char then
		for _, it in ipairs(char:GetChildren()) do if it:IsA("Tool") then it:Destroy() end end
		local hum = char:FindFirstChildOfClass("Humanoid"); if hum then hum.Health = hum.MaxHealth end
	end
end

local function moveTo(p: Player, pos: Vector3)
	local char = p.Character or p.CharacterAdded:Wait()
	local hrp = char:WaitForChild("HumanoidRootPart", 5)
	if hrp then char:MoveTo(pos) end
end

local function aliveCount()
	local n = 0
	local totalPlayers = 0
	for _, p in ipairs(Players:GetPlayers()) do
		totalPlayers += 1
		local inRound = p:GetAttribute(inRoundAttr)
		if inRound then
			local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 then 
				n += 1 
				print("玩家", p.Name, "存活，血量:", hum.Health)
			else
				print("玩家", p.Name, "死亡或无角色")
			end
		else
			print("玩家", p.Name, "不在回合中")
		end
	end
	print("总玩家数:", totalPlayers, "存活玩家数量:", n)
	return n
end

-- 新玩家/重生时放对位置
local function placeAccordingToPhase(p: Player)
	local cagePos, arenaPos = getSpawnPositions()
	if Phase == "COMBAT" and p:GetAttribute(inRoundAttr) then
		moveTo(p, arenaPos[1])
	else
		moveTo(p, cagePos[1])
	end
end

Players.PlayerAdded:Connect(function(p)
	print("玩家加入:", p.Name)
	p:SetAttribute(inRoundAttr, false)
	p.CharacterAdded:Connect(function() 
		print("玩家角色生成:", p.Name)
		task.wait() 
		placeAccordingToPhase(p) 
	end)
end)

-- ====== 主循环 ======
task.spawn(function()
	print("=== 角斗士竞技场启动 ===")
	
	-- 添加错误处理
	local success, err = pcall(function()
		ensureWorld()
		print("世界已生成，开始游戏循环...")

		local cageIdx, arenaIdx = 1, 1
		while true do
			-- 等待至少一个玩家加入
			print("等待玩家加入...")
			while #Players:GetPlayers() == 0 do
				task.wait(1)
			end
			print("检测到玩家，开始游戏循环")

			-- 准备：全部参赛，拉进笼子，关门
			Phase = "WAITING"
			print("=== 准备阶段开始 ===")
			local cagePos, arenaPos = getSpawnPositions()
			print("准备阶段：当前玩家数量:", #Players:GetPlayers())
			
			for _, p in ipairs(Players:GetPlayers()) do
				print("设置玩家", p.Name, "加入回合")
				p:SetAttribute(inRoundAttr, true)
				resetPlayer(p)
				moveTo(p, cagePos[cageIdx]); cageIdx = rotateIndex(cageIdx, #cagePos)
				print("玩家", p.Name, "加入回合，属性设置为:", p:GetAttribute(inRoundAttr))
			end
			setGates(false)
			print("开始准备阶段倒计时...")
			for t = PREP_TIME, 0, -1 do 
				broadcast("WAITING", t); 
				print("准备倒计时:", t)
				task.wait(1) 
			end

			-- 战斗：开门，传到竞技场并发武器
			Phase = "COMBAT"
			print("=== 战斗阶段开始 ===")
			setGates(true)
			local cagePos2, arenaPos2 = getSpawnPositions()
			print("战斗阶段：检查玩家状态...")
			
			for _, p in ipairs(Players:GetPlayers()) do
				local inRound = p:GetAttribute(inRoundAttr)
				print("检查玩家", p.Name, "回合状态:", inRound)
				
				if inRound then
					resetPlayer(p)
					moveTo(p, arenaPos2[arenaIdx]); arenaIdx = rotateIndex(arenaIdx, #arenaPos2)
					giveWeapon(p)
					print("给玩家", p.Name, "发放武器")
				else
					print("玩家", p.Name, "不在回合中，跳过")
				end
			end
			
			print("开始战斗倒计时...")
			for t = COMBAT_TIME, 0, -1 do
				broadcast("COMBAT", t)
				local alive = aliveCount()
				print("战斗倒计时:", t, "存活:", alive)
				if alive <= 0 then 
					print("战斗结束，没有存活玩家")
					break 
				end
				task.wait(1)
			end

			-- 结算：关门，回笼子，清参赛标记
			Phase = "RESET"
			print("=== 结算阶段开始 ===")
			setGates(false)
			local cagePos3 = select(1, getSpawnPositions())
			for _, p in ipairs(Players:GetPlayers()) do
				p:SetAttribute(inRoundAttr, false)
				resetPlayer(p)
				moveTo(p, cagePos3[cageIdx]); cageIdx = rotateIndex(cageIdx, #cagePos3)
			end
			print("开始结算阶段倒计时...")
			for t = RESET_TIME, 0, -1 do 
				broadcast("RESET", t); 
				print("结算倒计时:", t)
				task.wait(1) 
			end
		end
	end)
	
	if not success then
		print("主循环发生错误:", err)
		print("错误堆栈:", debug.traceback())
	end
end)
