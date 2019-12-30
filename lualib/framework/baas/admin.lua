-- youliao task sub-system
-- legacy BaaS Admin API support
-- Fiathux Su
-- 2019-12-1

local _f = require("functional")
local _cal = require("calendar")
local _sha256 = require("resty.sha256")
local _str =  require("resty.string")

-- convert detail data to string
local function detail2str(detail)
    local typeDispatch
    local function encKV(d)
        local keys = _f.list(_f.filter(_f.keys, nil, function(k)
            return d[k] ~= nil
        end))(d)
        table.sort(keys)
        return table.concat(_f.list(_f.ival,function(k)
            return k.."="..typeDispatch(d[k])
        end)(keys), ",")
    end
    local function encList(d)
        return table.concat(_f.list(_f.ival, function(itm)
            return typeDispatch(itm) or ""
        end)(d), ",")
    end
    local function encGen(d)
        if d == nil then return nil end
        if type(d) == "string" then return d end
        if type(d) == "number" then return ("%.12g"):format(d) end
        return cjson.encode(d)
    end
    function typeDispatch(d)
        if type(d) == "table" and #d > 0 then
            return encList(d)
        elseif type(d) == "table" then
            return encKV(d)
        else
            return encGen(d)
        end
    end
    return typeDispatch(detail) or ""
end

--local hash = Droi.CloudUtils.sha256(act..dstr..tostring(ts)..ro.token)

local _M = {}

-- create admin sign
function _M.admin_signer(uuid, token)
    return function(act, detail)
        local ts = _cal.ts(true)
        local hash = _sha256:new()
        hash:update(act..detail2str(detail)..tostring(ts)..token)
        local sign = hash:final()
        return {
            act = act,
            detail = detail,
            role = uuid,
            ts = ts,
            checksum = _str.to_hex(sign),
        }
    end
end

-- check admin sign
function _M.admin_check(uuid, token)
    return function(act, ts, data, hash)
        local hash_exec = _sha256:new()
        hash_exec:update(act..detail2str(data)..tostring(ts)..token)
        local sign = _str.to_hex(hash_exec:final())
        return hash == sign
    end
end

return _M
