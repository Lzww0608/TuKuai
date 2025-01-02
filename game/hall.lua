--[[
hall.lua 文件流程说明:

1. 服务初始化
   - 加载必要的模块(skynet, queue, socket)
   - 定义CMD表存储hall命令处理函数
   - 初始化queues和resps表用于存储玩家信息

2. 命令处理
   - ready: 处理玩家准备加入游戏
   - offline: 处理玩家退出游戏

3. 主要功能命令(CMD表)
   - ready: 处理玩家准备加入游戏
   - offline: 处理玩家退出游戏
]]

local skynet = require "skynet"
local queue = require "skynet.queue"
local socket = require "skynet.socket"

local cs = queue()


local tinsert = table.insert
local tremove = table.remove
-- local tconcat = table.concat
local CMD = {}

local queues = {}

local resps = {}

local function sendto(clientfd, arg)
    -- local ret = tconcat({"fd:", clientfd, arg}, " ")
    -- socket.write(clientfd, ret .. "\n")
    socket.write(clientfd, arg .. "\n")
end

function CMD.ready(client)
    if not client or not client.name then
        return skynet.retpack(false, "准备：非法操作")
    end

    if resps[client.name] then
        return skynet.retpack(false, "重复准备")
    end

    -- 将玩家加入等待队列
    tinsert(queues, 1, client)
    -- 保存玩家的响应回调
    resps[client.name] = skynet.response()

    -- 当等待队列人数达到3人时,创建新房间
    if #queues >= 3 then
        -- 创建新的房间服务
        local roomd = skynet.newservice("room")
        -- 从队列中取出3个玩家
        local members = {tremove(queues), tremove(queues), tremove(queues)}
        -- 通知每个玩家进入房间
        for i=1, 3 do
            local cli = members[i]
            -- 调用玩家的响应回调,传入房间服务id
            resps[cli.name](true, roomd)
            -- 清除响应回调
            resps[cli.name] = nil
        end
        -- 通知房间服务开始游戏
        -- type = lua
        -- action = start
        -- args = members
        skynet.send(roomd, "lua", "start", members)
        return
    end

    sendto(client.fd, "等待其他玩家加入")
end

function CMD.offline(name)
    for pos, client in ipairs(queues) do
        if client.name == name then
            tremove(queues, pos)
            break
        end
    end
    
    if resps[name] then
        resps[name](true, false, "退出")
        resps[name] = nil
    end

    skynet.retpack()
end


skynet.start(function()
    -- 注册lua消息处理函数
    skynet.dispatch("lua", function(session, address, cmd, ...)
        local func = CMD[cmd]
        if not func then
            skynet.retpack({ok = false, msg = "非法操作"})
            return
        end
        -- 异步处理
        cs(func, ...)
    end)
end)

