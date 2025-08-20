-- 简单的测试客户端脚本
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

print("测试客户端脚本已加载")

-- 等待测试事件
local testEvent = ReplicatedStorage:WaitForChild("TestEvent")

-- 监听测试事件
testEvent.OnClientEvent:Connect(function(message)
    print("收到服务器消息:", message)
    
    -- 创建一个简单的 UI 显示消息
    local player = Players.LocalPlayer
    if player then
        local gui = Instance.new("ScreenGui")
        gui.Name = "TestUI"
        gui.Parent = player:WaitForChild("PlayerGui")
        
        local label = Instance.new("TextLabel")
        label.Text = message
        label.Size = UDim2.new(0, 300, 0, 50)
        label.Position = UDim2.new(0.5, -150, 0.1, 0)
        label.BackgroundColor3 = Color3.new(0, 0, 0)
        label.TextColor3 = Color3.new(1, 1, 1)
        label.Parent = gui
        
        -- 3秒后自动删除
        task.wait(3)
        gui:Destroy()
    end
end)

print("测试客户端脚本设置完成")
