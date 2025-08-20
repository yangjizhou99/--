-- 倒计时 UI + 武器出招（客户端发起，服务端判定）
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local timerEvent = ReplicatedStorage:WaitForChild("RoundTimer")
local attackEvent = ReplicatedStorage:WaitForChild("SwordAttack")
local player = Players.LocalPlayer

-- ====== UI ======
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

timerEvent.OnClientEvent:Connect(function(data)
	local p = data.phase or "WAITING"
	local s = tonumber(data.secs) or 0
	label.Text = string.format("%s：%ds", phaseText[p] or p, s)
end)

-- ====== 武器激活（客户端 -> 服务端）======
local function hookTool(tool: Instance)
	if not tool:IsA("Tool") or tool.Name ~= "Gladius" then return end
	tool.Activated:Connect(function()
		-- 只发送"我要挥击"的意图；真正的判定和冷却在服务端做
		attackEvent:FireServer({ action = "swing" })
	end)
end

local function watchContainer(container: Instance)
	for _, c in ipairs(container:GetChildren()) do hookTool(c) end
	container.ChildAdded:Connect(hookTool)
end

watchContainer(player:WaitForChild("Backpack"))
if player.Character then watchContainer(player.Character) end
player.CharacterAdded:Connect(function(char) watchContainer(char) end)
