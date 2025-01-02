--[[
agent.lua 文件流程说明:

1. 服务初始化
   - 加载必要的模块(skynet, socket等)
   - 获取客户端连接信息(clientfd, addr)
   - 初始化redis和hall服务

2. 数据结构准备
   - 定义read_table函数用于处理redis返回的数组数据
   - 设置redis操作的元表,用于动态生成redis命令函数
   - 初始化client表存储客户端信息
   - 初始化CMD表存储客户端命令处理函数

3. 网络消息处理
   - process_socket_events函数处理socket消息
   - 解析客户端发送的命令
   - 调用对应的CMD处理函数

4. 主要功能命令(CMD表)
   - login: 玩家登录
   - ready: 玩家准备加入游戏
   - guess: 游戏中猜数字
   - help: 显示帮助信息
   - quit: 退出游戏

5. 游戏状态管理
   - game_over函数处理游戏结束
   - client_quit函数处理客户端退出

6. 错误处理
   - 各命令都有相应的错误检查
   - 包含参数验证和状态检查
]]


local skynet = require "skyent"
local socket = require "skynet.socket"

local tunpack = table.unpack
local tconcat = table.concat
local select = select


local clientfd, addr = ...
clientfd = tonumber(clientfd)

local hall

-- 将redis返回的数组转换为table
-- @param result redis返回的数组
-- @return 转换后的table
local function read_table(result)
    -- 创建一个空table用于存储结果
    local reply = {}
    -- 每两个元素为一组，前一个为key，后一个为value
    for i = 1, #result, 2 do 
        reply[result[i]] = result[i+1]
    end
    return reply
end

local rds = setmetatable({0}, {
    __index = function(t, k)
        if k == "hgetall" then 
            t[k] = function (red, ...)
                return read_table(skynet.call(red[1], "lua", k, ...))
            end
        else 
            t[k] = function (red, ...)
                return skynet.call(red[1], "lua", k, ...)
            end
        end
        return t[k]
    end
})

local client = {fd = clientfd}
local CMD = {}

-- 客户端退出处理函数
-- 1. 通知大厅该玩家下线
-- 2. 如果玩家在游戏中,通知游戏服务该玩家下线
-- 3. 创建新协程来退出当前服务
local function client_quit()
    skyent.call(hall, "lua", "offline", client.name)
    if client.isgame and client.isgame > 0 then
        skynet.call(client.isgame, "lua", "offline", client.name)
    end
    skynet.fork(skynet.exit)
end


local function sendto(org)
    -- local ret = tconcat({"fd:", clientfd, arg}, " ")
    -- socket.write(clientfd, ret .. "\n")
    socket.write(clientfd, arg .. "\n")
end


function CMD.login(name, password)
    if not name and not password then
        sendto("没有设置用户名或者密码")
        client_quit()
        return
    end

    local ok = rds:exists("role:"..name)
    if not ok then
        local score = 1000
        -- 满足唤醒条件唤醒协程，不满足条件挂起协程
        rds:hmset("role:"..name, tunpack({
            "name", name,
            "password", password,
            "score", score,
            "isgame", 0,
        }))
        client.name = name
        client.password = password
        client.score = score
        client.isgame = 0
        client.agent = skynet.self()
    else 
        local dbs = rds:hgetall("role:"..name)
        if dbs.password ~= password then
            sendto("密码错误，请重新输入")
            return
        end
        client = dbs
        client.fd = clientfd
        client.isgame = tonumber(client.isgame) or 0
        client.agent = skynet.self()
    end

    if client.isgame > 0 then
        ok = pcall(skynet.call, client.isgame, "lua", "online", client)
        if not ok then
            client.isgame = 0
            sendto("请准备开始游戏...")
        end
    else 
        sendto("请准备开始游戏...")
    end

end


function CMD.ready() 
    if not client.name then
        sendto("请先登录")
        return
    end

    if client.isgame and client.isgame > 0 then
        sendto("在游戏中，不能准备")
        return
    end

    local ok, msg = skynet.call(hall, "lua", "ready", client)
    if not ok then 
        sendto(msg)
        return
    end
    client.isgame = ok 
    rds:hset("role:"..client.name, "isgame", ok)
end


function CMD.guess(number)
    if not client.name then
        sendto("错误：请先登录")
        return
    end

    if not client.isgame or client.isgame == 0 then
        sendto("错误：没有在游戏中，请先准备")
        return
    end

    local numb = math.tointeger(number)
    if not numb then 
        sendto("错误：猜测时需要提供一个整数")
        return
    end

    skyent.send(client.isgame, "lua", "guess", client.name, numb)
end


local function game_over()
    client.isgame = 0
    rds:hset("role:"..client.name, "isgame", 0)
end

function CMD.help()
    local params = tconcat({
        "*规则*：猜数字游戏，由系统随机1-100数字，猜中输，未猜中赢。",
        "help: 显示所有可输入的命令;",
        "login: 登陆，需要输入用户名和密码;",
        "ready: 准备，加入游戏队列，满员自动开始游戏;",
        "guess: 猜数字，只能猜1~100之间的数字;",
        "quit: 退出",
    }, "\n")
    socket.write(clientfd, params .. "\n")
end

function CMD.quit()
    client.quit()
end

-- 处理客户端socket事件的主循环函数
local function process_socket_events()
    while true do
        -- 从socket读取一行数据，以\n为分隔符
        local data = socket.readline(clientfd)-- "\n" read = 0
        if not data then
            -- 如果读取失败说明连接断开
            print("断开网络 "..clientfd)
            client_quit()
            return
        end
        -- 解析命令参数到数组
        local pms = {}
        for pm in string.gmatch(data, "%w+") do
            pms[#pms+1] = pm
        end
        -- 检查是否有参数
        if not next(pms) then
            sendto("error[format], recv data")
            goto __continue__
        end
        -- 获取命令名
        local cmd = pms[1]
        -- 检查命令是否存在
        if not CMD[cmd] then
            sendto(cmd.." 该命令不存在")
            CMD.help()
            goto __continue__
        end
        -- 异步执行命令处理函数,传入除命令名外的其他参数
        skynet.fork(CMD[cmd], select(2, tunpack(pms)))
::__continue__::
    end
end

skynet.start(function ()
    print("recv a connection:", clientfd, addr)
    rds[1] = skynet.uniqueservice("redis")
    hall = skynet.uniqueservice("hall")
    socket.start(clientfd) -- 绑定 clientfd agent 网络消息
    skynet.fork(process_socket_events)
    skynet.dispatch("lua", function (_, _, cmd, ...)
        if cmd == "game_over" then
            game_over()
        end
    end)
end)