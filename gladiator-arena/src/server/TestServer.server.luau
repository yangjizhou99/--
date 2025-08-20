-- 简单的测试服务器脚本
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

print("测试服务器脚本已加载")

-- 创建一个简单的远程事件用于测试
local testEvent = Instance.new("RemoteEvent")
testEvent.Name = "TestEvent"
testEvent.Parent = ReplicatedStorage

-- 当玩家加入时发送测试消息
Players.PlayerAdded:Connect(function(player)
    print("玩家加入:", player.Name)
    testEvent:FireClient(player, "欢迎来到角斗士竞技场！")
end)

print("测试服务器脚本设置完成")
