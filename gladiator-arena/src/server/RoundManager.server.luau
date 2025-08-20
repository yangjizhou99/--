-- RoundManager：回合控制 + 世界生成 + 三选一武器（刀/锤子/弓）+ 服务器判定伤害
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ====== 配置 ======
local PREP_TIME   = 10
local COMBAT_TIME = 60
local RESET_TIME  = 6
local BOT_ENABLED = true  -- 是否启用机器人

-- 近战/远程参数
local WEAPON_META = {
	sword  = { kind = "melee",  range = 7,  damage = 25, cooldown = 0.5 },
	hammer = { kind = "melee",  range = 6,  damage = 40, cooldown = 1.0 },
	bow    = { kind = "ranged", range = 65, damage = 30, cooldown = 0.8 }, -- 射线
}
local VALID_KEYS = { sword = true, hammer = true, bow = true }

local RoundTimerEvent = ReplicatedStorage:WaitForChild("RoundTimer")
local ChooseEvent     = ReplicatedStorage:WaitForChild("WeaponChoose")
local AttackEvent     = ReplicatedStorage:WaitForChild("WeaponAttack")

local inRoundAttr = "InRound"
local Phase = "WAITING" -- WAITING / COMBAT / RESET

-- 记录：每回合的玩家选择 & 冷却
local selectedWeapon: {[number]: string} = {}    -- userId -> "sword"/"hammer"/"bow"
local lastAttackAt:   {[number]: number} = {}    -- userId -> timestamp

-- ====== 世界生成（若你没摆东西）======
local function ensureWorld()
	if workspace:FindFirstChild("GeneratedArena") then return end
	local model = Instance.new("Model"); model.Name = "GeneratedArena"; model.Parent = workspace
	local function mkPart(props)
		local p = Instance.new("Part")
		p.Anchored = true; p.CanCollide = true
		p.TopSurface = Enum.SurfaceType.Smooth; p.BottomSurface = Enum.SurfaceType.Smooth
		for k, v in pairs(props) do p[k] = v end
		p.Parent = model; return p
	end
	-- Cage（左侧，留门）
	mkPart({Name="CageFloor", Size=Vector3.new(40,1,40), Position=Vector3.new(-80,0.5,0), Material=Enum.Material.Concrete, Color=Color3.fromRGB(200,200,200)})
	mkPart({Name="CageWall_N", Size=Vector3.new(40,20,1), Position=Vector3.new(-80,10.5,-20)})
	mkPart({Name="CageWall_S", Size=Vector3.new(40,20,1), Position=Vector3.new(-80,10.5,20)})
	mkPart({Name="CageWall_W", Size=Vector3.new(1,20,40), Position=Vector3.new(-100,10.5,0)})
	mkPart({Name="CageWall_E_L", Size=Vector3.new(1,20,17), Position=Vector3.new(-60,10.5,-11.5)})
	mkPart({Name="CageWall_E_R", Size=Vector3.new(1,20,17), Position=Vector3.new(-60,10.5, 11.5)})
	local gatesFolder = Instance.new("Folder"); gatesFolder.Name = "Gates"; gatesFolder.Parent = workspace
	local gate = mkPart({Name="CageGate", Size=Vector3.new(1,12,6), Position=Vector3.new(-60,6.5,0), Color=Color3.fromRGB(255, 170, 0)}); gate.Parent = gatesFolder
	-- Arena（中间）
	mkPart({Name="ArenaFloor", Size=Vector3.new(120,1,120), Position=Vector3.new(0,0.5,0), Material=Enum.Material.Concrete, Color=Color3.fromRGB(170,170,170)})
	mkPart({Name="ArenaWall_N", Size=Vector3.new(120,20,1), Position=Vector3.new(0,10.5,-60)})
	mkPart({Name="ArenaWall_S", Size=Vector3.new(120,20,1), Position=Vector3.new(0,10.5,60)})
	mkPart({Name="ArenaWall_W", Size=Vector3.new(1,20,120), Position=Vector3.new(-60,10.5,0)})
	mkPart({Name="ArenaWall_E", Size=Vector3.new(1,20,120), Position=Vector3.new(60,10.5,0)})

	-- Spawns
	local spawns = Instance.new("Folder"); spawns.Name="Spawns"; spawns.Parent = workspace
	local cageF = Instance.new("Folder"); cageF.Name="Cage";  cageF.Parent  = spawns
	local arenaF= Instance.new("Folder"); arenaF.Name="Arena"; arenaF.Parent = spawns
	local function mkSpawn(name, pos, parent)
		local s = Instance.new("Part")
		s.Name = name; s.Size = Vector3.new(2,1,2); s.Anchored = true; s.CanCollide = false; s.Transparency = 1
		s.Position = pos; s.Parent = parent
	end
	mkSpawn("CageSpawn1", Vector3.new(-88,6,-12), cageF)
	mkSpawn("CageSpawn2", Vector3.new(-88,6, 12), cageF)
	mkSpawn("CageSpawn3", Vector3.new(-72,6,-12), cageF)
	mkSpawn("CageSpawn4", Vector3.new(-72,6, 12), cageF)
	mkSpawn("ArenaSpawn1", Vector3.new(-8,6,-8), arenaF)
	mkSpawn("ArenaSpawn2", Vector3.new( 8,6, 8), arenaF)
	mkSpawn("ArenaSpawn3", Vector3.new(-12,6,12), arenaF)
	mkSpawn("ArenaSpawn4", Vector3.new(12,6,-12), arenaF)
end

local function setGates(open: boolean)
	local gates = workspace:FindFirstChild("Gates"); if not gates then return end
	for _, g in ipairs(gates:GetChildren()) do
		if g:IsA("BasePart") then
			g.CanCollide = not open
			g.Transparency = open and 0.6 or 0
		end
	end
end

-- ====== 出生点 ======
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
local function rotateIndex(i, n) return (i % n) + 1 end

-- ====== 发三种简易武器（Tool，无需本地脚本）======
local function makeTool_Sword()
	local t = Instance.new("Tool"); t.Name = "Sword"; t.RequiresHandle = true; t.CanBeDropped = false
	local h = Instance.new("Part"); h.Name="Handle"; h.Size=Vector3.new(1,1,3); h.Massless=true; h.CanCollide=false; h.Parent=t
	return t
end
local function makeTool_Hammer()
	local t = Instance.new("Tool"); t.Name = "Hammer"; t.RequiresHandle = true; t.CanBeDropped = false
	local h = Instance.new("Part"); h.Name="Handle"; h.Size=Vector3.new(1.2,1.2,3.5); h.Massless=true; h.CanCollide=false; h.Parent=t
	return t
end
local function makeTool_Bow()
	local t = Instance.new("Tool"); t.Name = "Bow"; t.RequiresHandle = true; t.CanBeDropped = false
	local h = Instance.new("Part"); h.Name="Handle"; h.Size=Vector3.new(1,1,2); h.Massless=true; h.CanCollide=false; h.Parent=t
	return t
end

local function giveChosenWeapon(p: Player, key: string)
	if not VALID_KEYS[key] then key = "sword" end
	-- 若已有，先清掉
	if p.Backpack then for _, it in ipairs(p.Backpack:GetChildren()) do if it:IsA("Tool") then it:Destroy() end end end
	local char = p.Character
	if char then for _, it in ipairs(char:GetChildren()) do if it:IsA("Tool") then it:Destroy() end end end

	local tool
	if key == "sword" then tool = makeTool_Sword()
	elseif key == "hammer" then tool = makeTool_Hammer()
	else tool = makeTool_Bow() end
	tool.Parent = p.Backpack
end

-- ====== 机器人系统 ======
local botModel = nil
local botHumanoid = nil
local botHRP = nil

local function createBot()
	if botModel then botModel:Destroy() end
	
	-- 创建机器人模型
	botModel = Instance.new("Model")
	botModel.Name = "CombatBot"
	botModel.Parent = workspace
	
	-- 创建身体部件
	local torso = Instance.new("Part")
	torso.Name = "Torso"
	torso.Size = Vector3.new(2, 2, 1)
	torso.BrickColor = BrickColor.new("Really red")
	torso.Material = Enum.Material.Plastic
	torso.Parent = botModel
	
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(1.2, 1.2, 1.2)
	head.BrickColor = BrickColor.new("Really red")
	head.Material = Enum.Material.Plastic
	head.Parent = botModel
	
	local leftArm = Instance.new("Part")
	leftArm.Name = "LeftArm"
	leftArm.Size = Vector3.new(1, 2, 1)
	leftArm.BrickColor = BrickColor.new("Really red")
	leftArm.Material = Enum.Material.Plastic
	leftArm.Parent = botModel
	
	local rightArm = Instance.new("Part")
	rightArm.Name = "RightArm"
	rightArm.Size = Vector3.new(1, 2, 1)
	rightArm.BrickColor = BrickColor.new("Really red")
	rightArm.Material = Enum.Material.Plastic
	rightArm.Parent = botModel
	
	local leftLeg = Instance.new("Part")
	leftLeg.Name = "LeftLeg"
	leftLeg.Size = Vector3.new(1, 2, 1)
	leftLeg.BrickColor = BrickColor.new("Really red")
	leftLeg.Material = Enum.Material.Plastic
	leftLeg.Parent = botModel
	
	local rightLeg = Instance.new("Part")
	rightLeg.Name = "RightLeg"
	rightLeg.Size = Vector3.new(1, 2, 1)
	rightLeg.BrickColor = BrickColor.new("Really red")
	rightLeg.Material = Enum.Material.Plastic
	rightLeg.Parent = botModel
	
	-- 创建 HumanoidRootPart
	botHRP = Instance.new("Part")
	botHRP.Name = "HumanoidRootPart"
	botHRP.Size = Vector3.new(2, 2, 1)
	botHRP.Transparency = 1
	botHRP.CanCollide = false
	botHRP.Parent = botModel
	
	-- 创建 Humanoid
	botHumanoid = Instance.new("Humanoid")
	botHumanoid.MaxHealth = 100
	botHumanoid.Health = 100
	botHumanoid.WalkSpeed = 16
	botHumanoid.Parent = botModel
	
	-- 设置身体部件位置
	local weld = Instance.new("Weld")
	weld.Part0 = botHRP
	weld.Part1 = torso
	weld.C0 = CFrame.new(0, 0, 0)
	weld.Parent = botHRP
	
	local headWeld = Instance.new("Weld")
	headWeld.Part0 = torso
	headWeld.Part1 = head
	headWeld.C0 = CFrame.new(0, 1.5, 0)
	headWeld.Parent = torso
	
	local leftArmWeld = Instance.new("Weld")
	leftArmWeld.Part0 = torso
	leftArmWeld.Part1 = leftArm
	leftArmWeld.C0 = CFrame.new(-1.5, 0, 0)
	leftArmWeld.Parent = torso
	
	local rightArmWeld = Instance.new("Weld")
	rightArmWeld.Part0 = torso
	rightArmWeld.Part1 = rightArm
	rightArmWeld.C0 = CFrame.new(1.5, 0, 0)
	rightArmWeld.Parent = torso
	
	local leftLegWeld = Instance.new("Weld")
	leftLegWeld.Part0 = torso
	leftLegWeld.Part1 = leftLeg
	leftLegWeld.C0 = CFrame.new(-0.5, -2, 0)
	leftLegWeld.Parent = torso
	
	local rightLegWeld = Instance.new("Weld")
	rightLegWeld.Part0 = torso
	rightLegWeld.Part1 = rightLeg
	rightLegWeld.C0 = CFrame.new(0.5, -2, 0)
	rightLegWeld.Parent = torso
	
	-- 给机器人武器
	local botTool = makeTool_Sword()
	botTool.Parent = botModel
	
	return botModel
end

local function moveBotToPosition(pos: Vector3)
	if botHRP then
		botHRP.CFrame = CFrame.new(pos)
	end
end

local function botAttack()
	if not botModel or not botHumanoid or botHumanoid.Health <= 0 then return end
	
	-- 找到最近的玩家
	local nearestPlayer = nil
	local nearestDistance = math.huge
	
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character and player:GetAttribute(inRoundAttr) then
			local playerHRP = player.Character:FindFirstChild("HumanoidRootPart")
			if playerHRP then
				local distance = (playerHRP.Position - botHRP.Position).Magnitude
				if distance < nearestDistance and distance < 20 then
					nearestDistance = distance
					nearestPlayer = player
				end
			end
		end
	end
	
	if nearestPlayer and nearestPlayer.Character then
		local playerHRP = nearestPlayer.Character:FindFirstChild("HumanoidRootPart")
		if playerHRP then
			-- 面向玩家
			botHRP.CFrame = CFrame.lookAt(botHRP.Position, playerHRP.Position)
			
			-- 模拟攻击
			local fakePlayer = {
				Character = botModel,
				UserId = 999999,
				GetAttribute = function() return true end
			}
			
			-- 使用刀进行攻击
			local meta = WEAPON_META.sword
			local hits = {}
			local success, result = pcall(function()
				return doMelee(fakePlayer, meta)
			end)
			if success then
				hits = result
			else
				print("机器人攻击错误:", result)
			end
			
			-- 发送攻击特效给所有玩家
			local points = {}
			for _, h in ipairs(hits) do 
				table.insert(points, h.pos)
				-- 给被攻击的玩家发送受击效果
				for _, pl in ipairs(Players:GetPlayers()) do
					if pl.Character == h.hum.Parent then
						ReplicatedStorage.CombatFX:FireClient(pl, { type = "gotHit", damage = meta.damage })
						break
					end
				end
			end
			
			-- 给机器人发送命中确认
			for _, pl in ipairs(Players:GetPlayers()) do
				ReplicatedStorage.CombatFX:FireClient(pl, { type = "hitConfirm", points = points })
			end
		end
	end
end

-- ====== 服务器攻击判定 ======
-- 返回 { {hum=Humanoid, pos=Vector3} , ... }
local function doMelee(attacker: Player, meta)
	local char = attacker.Character; if not char then return {} end
	local hrp = char:FindFirstChild("HumanoidRootPart"); if not hrp then return {} end

	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char }

	local parts = workspace:GetPartBoundsInRadius(hrp.Position, meta.range, params)
	local victims = {}
	for _, part in ipairs(parts) do
		local m = part:FindFirstAncestorOfClass("Model")
		if m and m ~= char then
			local hum = m:FindFirstChildOfClass("Humanoid")
			local hhrp = m:FindFirstChild("HumanoidRootPart")
			if hum and hhrp and hum.Health > 0 then
				victims[hum] = hhrp.Position
			end
		end
	end

	local hits = {}
	for hum, pos in pairs(victims) do
		hum:TakeDamage(meta.damage)
		table.insert(hits, {hum = hum, pos = pos})
	end
	return hits
end

-- [REPLACE] doRanged 支持 overrideDamage
local function doRanged(attacker: Player, meta, overrideDamage)
	local char = attacker.Character; if not char then return {} end
	local hrp = char:FindFirstChild("HumanoidRootPart"); if not hrp then return {} end

	local origin = hrp.Position + Vector3.new(0, 1.5, 0)
	local dir = hrp.CFrame.LookVector * meta.range
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char }

	local result = workspace:Raycast(origin, dir, params)
	if result then
		local m = result.Instance:FindFirstAncestorOfClass("Model")
		if m then
			local hum = m:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 then
				local dmg = overrideDamage or meta.damage
				hum:TakeDamage(dmg)
				return { { hum = hum, pos = result.Position, damage = dmg } }
			end
		end
	end
	return {}
end

AttackEvent.OnServerEvent:Connect(function(p: Player, payload)
	print("收到攻击事件，玩家:", p.Name, "阶段:", Phase, "在回合中:", p:GetAttribute(inRoundAttr)) -- 调试信息
	
	if Phase ~= "COMBAT" or not p:GetAttribute(inRoundAttr) then 
		print("攻击被拒绝：阶段或状态不正确") -- 调试信息
		return 
	end
	if typeof(payload) ~= "table" then 
		print("攻击被拒绝：payload不是table") -- 调试信息
		return 
	end

	local key = selectedWeapon[p.UserId] or "sword"
	local meta = WEAPON_META[key]; if not meta then 
		print("攻击被拒绝：无效武器类型") -- 调试信息
		return 
	end

	-- [MODIFY] 读取弓的蓄力（0..1），并按 50%~100% 线性缩放伤害
	local charge = 0
	if typeof(payload) == "table" and typeof(payload.charge) == "number" then
		charge = math.clamp(payload.charge, 0, 1)
	end

	local overrideDamage = nil
	if key == "bow" then
		overrideDamage = math.max(10, math.floor(meta.damage * (0.5 + 0.5 * charge)))
	end

	-- 冷却
	local now = os.clock()
	if (now - (lastAttackAt[p.UserId] or 0)) < meta.cooldown then 
		print("攻击被拒绝：冷却中") -- 调试信息
		return 
	end
	lastAttackAt[p.UserId] = now

	print("执行攻击，武器:", key, "类型:", meta.kind, "蓄力:", charge) -- 调试信息

	-- 命中计算
	local hits
	if meta.kind == "melee" then
		hits = doMelee(p, meta)               -- 近战保持不变
	else
		hits = doRanged(p, meta, overrideDamage)  -- [MODIFY] 传入 overrideDamage
	end

	print("命中数量:", #hits) -- 调试信息

	-- 回传给攻击者：命中确认 + 命中点集合（用于粒子/镜头）
	local points = {}
	for _, h in ipairs(hits) do table.insert(points, h.pos) end
	ReplicatedStorage.CombatFX:FireClient(p, { type = "hitConfirm", points = points })

	-- 对每个受击者：轻微击退 + 受击提示
	local attackerHRP = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
	for _, h in ipairs(hits) do
		local hum = h.hum
		local model = hum and hum.Parent
		local hrp = model and model:FindFirstChild("HumanoidRootPart")
		if attackerHRP and hrp then
			local dir = (hrp.Position - attackerHRP.Position)
			local u = (dir.Magnitude > 0) and dir.Unit or Vector3.new(0,1,0)
			-- 轻微击退：按质量给个冲量
			local impulse = u * (hrp.AssemblyMass * 30)
			hrp:ApplyImpulse(impulse)
		end
		-- 如果是玩家，给其客户端发受击提示
		for _, pl in ipairs(Players:GetPlayers()) do
			if pl.Character == model then
				-- [MODIFY] 如果 hits 元素里带 damage，则用它；否则用 meta.damage
				local dmgToSend = (h and h.damage) or meta.damage
				ReplicatedStorage.CombatFX:FireClient(pl, { type = "gotHit", damage = dmgToSend })
				break
			end
		end
	end
end)

-- ====== 阶段/广播/移动/重置 ======
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
	for _, p in ipairs(Players:GetPlayers()) do
		if p:GetAttribute(inRoundAttr) then
			local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 then 
				n += 1 
			end
		end
	end
	
	-- 计算机器人
	if botHumanoid and botHumanoid.Health > 0 then
		n += 1
	end
	
	return n
end

-- 玩家选择（仅准备阶段可改）
ChooseEvent.OnServerEvent:Connect(function(p: Player, key: string)
	if Phase ~= "WAITING" then return end
	if not p:GetAttribute(inRoundAttr) then return end
	if not VALID_KEYS[key] then return end
	selectedWeapon[p.UserId] = key
end)

-- 新人/重生放置
local function placeAccordingToPhase(p: Player)
	local cagePos, arenaPos = getSpawnPositions()
	if Phase == "COMBAT" and p:GetAttribute(inRoundAttr) then
		moveTo(p, arenaPos[1])
	else
		moveTo(p, cagePos[1])
	end
end

Players.PlayerAdded:Connect(function(p)
	p:SetAttribute(inRoundAttr, false)
	selectedWeapon[p.UserId] = "sword" -- 默认刀
	p.CharacterAdded:Connect(function() task.wait() placeAccordingToPhase(p) end)
end)
Players.PlayerRemoving:Connect(function(p)
	selectedWeapon[p.UserId] = nil
	lastAttackAt[p.UserId] = nil
end)

-- ====== 主循环 ======
task.spawn(function()
	ensureWorld()

	local cageIdx, arenaIdx = 1, 1
	while true do
		-- 等待至少一个玩家加入
		while #Players:GetPlayers() == 0 do
			print("等待玩家加入...")
			task.wait(1)
		end
		print("玩家已加入，开始新回合")

		-- 准备：参赛、进笼子、可选择武器、关门
		Phase = "WAITING"
		local cagePos, arenaPos = getSpawnPositions()
		for _, p in ipairs(Players:GetPlayers()) do
			p:SetAttribute(inRoundAttr, true)
			resetPlayer(p)
			-- 若上轮没选或离线回来，确保有默认
			if not VALID_KEYS[selectedWeapon[p.UserId] or ""] then selectedWeapon[p.UserId] = "sword" end
			moveTo(p, cagePos[cageIdx]); cageIdx = rotateIndex(cageIdx, #cagePos)
		end
		setGates(false)
		for t = PREP_TIME, 0, -1 do 
			print("准备阶段倒计时:", t)
			broadcast("WAITING", t); 
			task.wait(1) 
		end

		-- 战斗：开门、传竞技场、发所选武器
		print("进入战斗阶段")
		Phase = "COMBAT"
		setGates(true)
		local _, arenaPos2 = getSpawnPositions()
		for _, p in ipairs(Players:GetPlayers()) do
			if p:GetAttribute(inRoundAttr) then
				resetPlayer(p)
				moveTo(p, arenaPos2[arenaIdx]); arenaIdx = rotateIndex(arenaIdx, #arenaPos2)
				giveChosenWeapon(p, selectedWeapon[p.UserId] or "sword")
				lastAttackAt[p.UserId] = 0
			end
		end
		
		-- 创建机器人（如果启用且玩家数量少于2）
		if BOT_ENABLED and #Players:GetPlayers() < 2 then
			createBot()
			if botModel then
				moveBotToPosition(Vector3.new(10, 6, 10)) -- 机器人出生位置
				print("机器人已创建")
			end
		end
		for t = COMBAT_TIME, 0, -1 do
			local alive = aliveCount()
			print("战斗倒计时:", t, "存活:", alive)
			broadcast("COMBAT", t)
			
			-- 机器人攻击循环
			if botModel and botHumanoid and botHumanoid.Health > 0 then
				botAttack()
			end
			
			if alive <= 0 then 
				print("战斗结束，没有存活玩家")
				break 
			end
			task.wait(1)
		end

		-- 结算：关门、回笼子、清参赛标记
		Phase = "RESET"
		setGates(false)
		
		-- 清理机器人
		if botModel then
			botModel:Destroy()
			botModel = nil
			botHumanoid = nil
			botHRP = nil
			print("机器人已清理")
		end
		
		local cagePos3 = select(1, getSpawnPositions())
		for _, p in ipairs(Players:GetPlayers()) do
			p:SetAttribute(inRoundAttr, false)
			resetPlayer(p)
			moveTo(p, cagePos3[cageIdx]); cageIdx = rotateIndex(cageIdx, #cagePos3)
		end
		for t = RESET_TIME, 0, -1 do broadcast("RESET", t); task.wait(1) end
	end
end)
