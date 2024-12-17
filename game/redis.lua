local skynet = require "skynet.manager"
local redis = require "skynet.db.redis"

skynet.start(function ()
	local rds = redis.connect({
		host	= "127.0.0.1",
		port	= 6379,
		db		= 0,
		-- auth	= "123456",
	})

end)