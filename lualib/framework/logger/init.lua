-- youliao task sub-system framework
-- error log
-- Fiathux Su
-- 2019-11-29

local errlog = require("ngx.errlog")
local _f = require("functional")
local _json = require("cjson.safe")

-- Object auto dump
local function seriallize(tab, nojson)
    return _f.list(_f.ival, function(v)
        local t = type(v)
        if t == "table" and not nojson then
            local j, err = _json.encode(v)
            if not j then
                return "failed JSON enc: " .. tostring(v) ..
                    " (" .. tostring(err)..")"
            end
            return j
        elseif t == "string" then
            return v
        else
            return tostring(v)
        end
    end)(tab)
end

-- Create log method 
local function mklog(sep, nojson)
    return function(level, detail)
        local stack_info = debug.getinfo(2)
        local log_stack = (function()
            if not stack_info then
                return "[Lua] unknown"
            end
            if stack_info.what ~= "Lua" then
                return "["..tostring(stack_info.what).."] external call"
            end
            local src = tostring(stack_info.short_src):match("[^/]*$")
            return "[Lua] " .. src .. ":" ..
                tostring(stack_info.currentline) ..
                " (func \"" .. tostring(stack_info.name) .. "\")"
        end)()
        errlog.raw_log(level, 
            log_stack .. " - " ..
            table.concat(seriallize(detail, nojson), sep))
    end
end

local _M = {}
_M.ex = {}

function _M.ex.debug(sep, nojson)
    return function (...)
        return mklog(sep, nojson)(ngx.DEBUG, {...})
    end
end

function _M.ex.info(sep, nojson)
    return function (...)
        return mklog(sep, nojson)(ngx.INFO, {...})
    end
end

function _M.ex.notice(sep, nojson)
    return function (...)
        return mklog(sep, nojson)(ngx.NOTICE, {...})
    end
end

function _M.ex.warn(sep, nojson)
    return function (...)
        return mklog(sep, nojson)(ngx.WARN, {...})
    end
end

function _M.ex.err(sep, nojson)
    return function (...)
        return mklog(sep, nojson)(ngx.ERR, {...})
    end
end

function _M.ex.crit(sep, nojson)
    return function (...)
        return mklog(sep, nojson)(ngx.CRIT, {...})
    end
end

_M.debug = _M.ex.debug("")
_M.info = _M.ex.info("")
_M.notice = _M.ex.notice("")
_M.warn = _M.ex.warn("")
_M.err = _M.ex.err("")
_M.crit = _M.ex.crit("")

return _M

