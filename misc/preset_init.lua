-- youliao task sub-system framework
-- framework config
-- Fiathux Su
-- 2019-11-28

local _modname_ = (...)

-- main config
local config = {
    -- global timezone
    time_zone = 28800,
}

-- sub config
local sub_set = {}

-- export preset module
local _MMeta = {
    __call = function(self, name) -- load sub config
        if sub_set[name] then return sub_set[name] end
        if not name or name == "" then return nil end
        local status, ret = xpcall(require,
            function(e) qje.qlog.err("error import preset [" .. name ..
                "] - ".. tostring(e) .. "\n" .. debug.traceback()) end,
            _modname_.."."..name)
        if not status then
            return nil
        end
        sub_set[name] = ret
        return ret
    end,
    __newindex = function(self, name, value)
        error("can not set value to preset. object readonly")
    end,
    __metatable = false,
}

return setmetatable(config, _MMeta)
