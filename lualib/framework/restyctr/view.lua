-- youliao task sub-system framework
-- access controller utils
-- view
-- Fiathux Su
-- 2017-12-22

--local const = require("const")
local _pcheck = require("paramchk")
local _f = require("functional")
local _vcfg = _preset("restview")

-- general error result
local function generalError(feature, msg, addit, code)
    return {
        success = false,
        feature = feature,
        msg = msg,
        code = code or "-1",
        more = addit,
    }
end

-- general success result
local function generalSuccess(detail)
    return {
        success = true,
        detail = detail,
    }
end

local metaRst = {}
-- parse module result
local function modRst(pDeco)
    -- news-stream module error code
    local function modCode(code, msg)
        local vcode = code - 610000000
        local mod = math.floor(vcode / 100000)
        local modcode
        if mod >= 100 then
            modcode = tostring(mod + 100)
        else
            modcode = "L"..mod
        end
        local feature = _vcfg.CodeErr[math.floor((vcode % 100000) / 1000)] or
            _vcfg.Err.Default
        local errseri = vcode % 1000
        local pmsg = "Error in module ["..modcode.."] code ["..code.."] - "..tostring(msg)
        return feature, pmsg
    end
    -- new-resty module error code
    local function restmodCode(code, msg)
        local vcode = code - 700000000
        local feature = _vcfg.CodeErr[math.floor(vcode / 1000000)] or _vcfg.Err.Default
        local errseri = vcode % 1000000
        local pmsg = "Error REST code [" .. code .. "] - " .. tostring(msg)
        return feature, pmsg
    end
    -- BaaS general error code
    local function droiCode(code, msg)
        local feature = _vcfg.BaaSErr[math.floor(code / 10000)] or _vcfg.Err.Default
        local pmsg = "Error in baas code ["..code.."] - "..tostring(msg)
        return feature, pmsg
    end
    -- web scraper error code
    local function wsCode(code, msg)
        local pmsg = "Error Web request code ["..code.."] - "..tostring(msg)
        return _vcfg.Err.Program, pmsg
    end
    -- default error parser
    local function dftErrorParse(code, msg)
        if type(code) ~= "number" then
            return _vcfg.Err.Default, "Error ["..tostring(code).."] - "..tostring(msg)
        end
        code = math.abs(code)
        local prcode = code / 10000000
        if prcode > 60 and prcode < 69 then return modCode(code, msg) end 
        if prcode >= 70 and prcode < 79 then return restmodCode(code, msg) end
        if math.floor(code / 1000000) == 1 then return droiCode(code, msg) end
        if math.floor(code / 130000) == 1 then return wsCode(code, msg) end
        return _vcfg.Err.Default,
            "Undefined source error code ["..code.."] - "..tostring(msg)
    end
    local errParse = (pDeco or (function(r) return r end))(dftErrorParse)

    -- export result object
    return function(result, code, msg, addit)
        -- support result object return
        if result and type(result) == "table" and getmetatable(result) == metaRst then
            return result
        end
        -- modules return
        local _prst = {}
        _prst.original = function()
            return result, code, msg
        end
        _prst.code = code
        if not result then
            _prst.success = false
            _prst.feature, _prst.msg = errParse(code, msg)
            _prst.addit = addit
        else
            _prst.success = true
            _prst.feature, _prst.msg, _prst.addit = code, msg, addit
        end
        _prst.result = result
        _prst.response = function(resultDeo)
            if _prst.success then
                local dtail = result
                if resultDeo then dtail = resultDeo(result) end
                return generalSuccess(dtail)
            else
                return generalError(_prst.feature, _prst.msg, _prst.addit, _prst.code)
            end
        end
        return setmetatable(_prst, metaRst)
    end
end

-- make phony mod-response for custom error
local function phonyErr(feature, msg, addit)
    return modRst(function(f)
        return function()
            return feature, msg
        end
    end)()
end

-- make phony parameter error
local function paramErr(path)
    return phonyErr(_vcfg.Err.Param, "Invalid parameter : "..tostring(path))
end

--------- module export ---------
local _M = {}

-- simple result parser
function _M.m(rst, code, msg, addit)
    return modRst()(rst, code, msg, addit)
end

-- advance result parser
function _M.M(pDeco)
    return modRst(pDeco)
end

-- create multi module call-chain
function _M.mm(init)
    if init == nil then init = {} end
    local calllist = {}
    local callchain = {}
    function callchain:add(callmod)
        table.insert(calllist, callmod)
        return callchain
    end
    return setmetatable(callchain,{__call = function()
        -- call meta-expression
        local rst, code, msg, addit
        for i = 1,#calllist do
            rst, code, msg, addit = calllist[i](init, rst, code, msg, addit)
            if not rst then return rst, code, msg, addit end
        end
        return rst, code, msg, addit
    end})
end

-- parameter check chain
-- param(chk, root)(param)(modcall, pDeco)(reject) -> modResponse
function _M.param(...)
    local chkobj = _pcheck.check(...)
    return function(param)
        return function(modcall, pDeco)
            return function(reject)
                local chk,path = chkobj(param)
                if not chk then
                    if not reject then
                        return paramErr(path)
                    else
                        return modRst(pDeco)(reject(param, path))
                    end
                end
                return modRst(pDeco)(modcall(param))
            end
        end
    end
end

-- make parameter error response
function _M.paramerr(path)
    return paramErr(path).response()
end

-- make parameter error response object
function _M.Paramerr(path)
    return paramErr(path)
end

-- success response
function _M.ok(detail)
    return generalSuccess(detail)
end

-- error response
function _M.fail(feature, msg, addit, code)
    return generalError(feature, msg, addit, code)
end

-- make paging result
function _M.paging(list, pagesize, mapper, total)
    local function checkPaging()
        if #list > pagesize then
            return true, pagesize
        else
            return false, #list
        end
    end
    mapper = mapper or (function(a) return a end)
    local more, len = checkPaging()
    return {
        list = _f.list(_f.irange, function(i)
            return mapper(list[i])
        end)(1, len),
        more = more,
        total = total,
    }
end

return _M 
