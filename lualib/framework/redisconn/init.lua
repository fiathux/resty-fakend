-- youliao task sub-system framework
-- redis connector
-- Fiathux Su
-- 2019-11-24

local _M = {}

-- create redis connect factory
function _M.create_redis_factory(conf)
    local _redis = require("resty.redis")
    local connect_timeout = conf.connect_timeout or 500
    local read_timeout = conf.read_timeout or 500
    local write_timeout = conf.write_timeout or 500
    local idle_time = conf.idle_time or 600000
    local auth = conf.auth
    local ops = {
        pool_size = conf.pool_size or 100,
        backlog = conf.backlog or 100,
    }
    if conf.ssl then
        ops.ssl = true
    end
    -- make connect
    local function conncet_to_rds()
        local rdscli = _redis:new()
        rdscli:set_timeouts(connect_timeout, write_timeout, read_timeout)
        local ok, err = rdscli:connect(conf.host, conf.port, ops)
        if not ok then
            return nil, err
        end
        local reuse, err = rdscli:get_reused_times()
        if not reuse then
            return nil, err
        end
        qje.qlog.debug("redis reuse - "..reuse)
        if reuse == 0 then
            if auth then    -- authorization
                local res, err = rdscli:auth(auth)
                if not res then
                    return nil, err
                end
            end
        end
        return rdscli, function() return rdscli:set_keepalive(idle_time) end
    end
    -- export
    return function()
        return conncet_to_rds()
    end
end

return _M
