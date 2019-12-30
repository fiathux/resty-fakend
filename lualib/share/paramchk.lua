--[[ common parameter checker
-- Droi Tech.
-- Fiathux Su 2017-08-22
-- ]]

local _f = require("functional")

-- feature parser
local _feature = {}

-- parse none feature
local function noparse() return false end

-- parse exists feature
local function existsparse() return true end

-- parse len
local function lenparse(minlen, maxlen)
    minlen, maxlen = tonumber(minlen),tonumber(maxlen)
    if minlen and maxlen then
        if minlen > maxlen then minlen, maxlen = maxlen, minlen end
        return function(unit)
            return #unit >= minlen and #unit <= maxlen
        end
    elseif minlen then
        return function(unit)
            return #unit >= minlen
        end
    elseif maxlen then
        return function(unit)
            return #unit <= maxlen
        end
    end
    return existsparse
end

-- parse string
function _feature.string(minlen, maxlen)
    return lenparse(minlen, maxlen)
end

-- parse number
function _feature.number(valarea, forceint)
    local function vareaConv(val)
        if not val then return existsparse end
        if val == "0" or val == "n" then
            return function(unit) return unit >= 0 end
        elseif val == "-0" then
            return function(unit) return unit <= 0 end
        elseif val == "nz" then
            return function(unit) return unit ~= 0 end
        else
            local valconv = tonumber(val)
            if valconv and valconv > 0 then
                return function(unit) return unit >= valconv end
            elseif valconv and valconv < 0 then
                return function(unit) return unit <= valconv end
            else
                return existsparse
            end
        end
    end
    local chkproc = vareaConv(valarea)
    forceint =  forceint == "true" or valarea == "n"
    if forceint then chkproc = (function(prevproc) -- advance: check integer
            return function(unit)
                if unit - math.floor(unit) ~= 0 then
                    return false
                else
                    return prevproc(unit)
                end
            end
        end)(chkproc)
    end
    return chkproc
end

-- parse list
function _feature.table(minlen, maxlen)
    return lenparse(minlen, maxlen)
end

-- parse boolean
function _feature.boolean(...)
    return existsparse
end

-- export splited feature string
local function exportSpFeature(ftexp)
    local opti, ft, fpstr = string.match(ftexp,"([?]?)(%w+):([-:%w]*)")
    if not ft then
        opti, ft = string.match(ftexp,"([?]?)(%w+)$")
        if not ft then return noparse end
    end
    local fplist = _f.list(function(fullstr)
        return function(init,inpt,varb)
            if inpt and #inpt > 0 then
                local sp0,sp1 = string.match(inpt, "([%w-]*):([-:%w]*)")
                if sp0 then return sp1,sp0 end
                return "", inpt
            else
                return nil, nil
            end
        end, nil, fullstr
    end,function(ctr,one) return one end)(fpstr or "")
    if _feature[ft] then
        local ftproc = (function(ftproc)
            return function(unit)
                if type(unit) ~= ft then return false end
                return ftproc(unit)
            end
        end)(_feature[ft](unpack(fplist)))
        if opti=="?" then    -- optional parameter
            return function(unit)
                if unit ~= nil then return ftproc(unit) end
                return true
            end
        else    -- required parameter
            return ftproc
        end
    else
        return noparse
    end
end

local expOneParse

-- export dict unit parser
local function expTreeParse(tree, path)
    return function(unit)
        if type(unit) ~= "table" then return false, path end
        if _f.keys(tree)() == nil then return true end
        return unpack(_f.reduce(pairs,function(k,v)
            return {expOneParse(v, path.."."..k)(unit[k])}
        end,function(a,b)
            return {a[1] and b[1], (a[1] and b[2]) or a[2]}
        end)(tree))
    end
end

-- export any unit parse
function expOneParse(feature, path)
    local ftparse = type(feature)
    if ftparse == "table" then 
        return expTreeParse(feature, path)
    elseif ftparse == "function" then
        return function(unit)
            local rst, rpath = feature(unit, path)
            return rst, rpath or path
        end
    elseif ftparse == "string" then
        return function(unit) return exportSpFeature(feature)(unit), path end
    elseif ftparse == "boolean" then
        if feature then
            return function(unit) return unit ~= nil, path end
        else
            return function(unit) return unit == nil, path end
        end
    end
    return function() return noparse(), path end
end

local _M = {}

-- export root prase
function _M.check(feature, rootname)
    return expOneParse(feature, rootname or "[ROOT]")
end

-- export batch prase
function _M.listCheck(feature, minlen, maxlen)
    local function failLen(tab) -- length check
        if (minlen and #tab < minlen) or (maxlen and #tab > maxlen) then
            return true
        end
    end
    return function(list, rootname) -- export
        if type(list) ~= "table" or failLen(list) then
            return false, rootname
        end
        return unpack(_f.reduce(ipairs,function(i,v)
            return {expOneParse(feature, (rootname or "") .. "[".. tostring(i) .."]")(v)}
        end, function(a, b)
            return {a[1] and b[1], (a[1] and b[2]) or a[2]}
        end)(list))
    end
end

return _M
