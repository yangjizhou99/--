-- 创建屏幕 UI
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local event = ReplicatedStorage:WaitForChild("RoundTimer")

local gui = Instance.new("ScreenGui")
gui.Name = "RoundUI"
gui.ResetOnSpawn = false
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

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

event.OnClientEvent:Connect(function(data)
	local p = data.phase or "WAITING"
	local s = tonumber(data.secs) or 0
	label.Text = string.format("%s：%ds", phaseText[p] or p, s)
end)
