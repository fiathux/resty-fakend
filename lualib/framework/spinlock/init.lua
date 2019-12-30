--[[ spin-lock
-- Droi Tech.
-- Fiathux Su 2019-11-27
-- ]]

local _f = require("functional")

local _M = {}

-- create lock
function _M.new(share_mem, exptime)
    local _lock = require("resty.lock")
    local lock, err = _lock:new(share_mem, {
        exptime = exptime or 1,
        timeout = 0
    })
    if not lock then
        return nil, err
    end
    return function(lock_name)
        return function(proc)
            return _f.loop(function(r, ctr)
                if ctr < 1 then
                    return nil
                end
                local exp, err = lock:lock(lock_name)
                if exp then
                    local ret = proc()
                    local ok, err = lock:unlock("random_key")
                    if not ok then
                        logger.err("random unlock error: " .. err)
                    end
                    return ret, 0
                end
                return r, ctr - 1
            end)(false, 1000000)
        end
    end
end

return _M

