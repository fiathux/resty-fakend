-- youliao task sub-system
-- legacy BaaS API adapt 
-- Fiathux Su
-- 2019-12-1

local _module_ = (...)

local _baas_admin = require(_module_ .. "." .. "admin")
local _http = require("resty.http")
local _json = require("cjson.safe")
local _f = require("functional")

-- general baas require
local function ylbaas_req(pool_size, idle_timeout)
    return function(appid, apikey, url, data)
        local htconn = _http:new()
        local res, err = htconn:request_uri(url, {
            method = "POST",
            body = data,
            headers = {
                ["Content-Type"] = "application/json",
                ["X-Droi-AppID"] = appid,
                ["X-Droi-Api-Key"] = apikey,
            },
            ssl_verify = false,
            keepalive_timeout = idle_timeout,
            keepalive_pool = pool_size,
        })
        if not res then
            return nil, "None reponse, " .. tostring(err)
        end
        if res.status ~= 200 then
            return nil, "HTTP error [" .. tostring(res.status) .. "]"
        end
        if not res.has_body then
            return nil, "None reponse body"
        end
        if not res.headers["Content-Type"] or
            res.headers["Content-Type"]:match("^[^;]+") ~= "application/json"
            then
                return nil, "unsupport content type"
        end
        local rst, err = _json.decode(res.body)
        if not rst then
            return nil, "except unserialize body, " .. tostring(err)
        end
        if rst.Code ~= 0 then
            return nil, "BaaS reponse error [" .. tostring(rst.Code) ..
                "] - " .. tostring(rst.Message), rst.Code
        end
        if not rst.Result then
            return nil, "none response Result"
        end
        local appresp = rst.Result
        if appresp.success == nil then
            return nil, "expcet reponse Result"
        end
        if not appresp.success then
            return nil, "failed operation [" .. tostring(appresp.feature) ..
                "] - " .. tostring(appresp.msg), appresp.code
        end
        if appresp.detail == nil then
            return nil, "none reponse detail data"
        end
        return appresp.detail
    end
end

-- Youliao BaaS call implements
local ylbaas_term = {}
-- Youliao BaaS API meta
local ylbaas_meta = {__index = function(self, name)
    if ylbaas_term[name] then
        return ylbaas_term[name] 
    end
    return rawget(self, name)
end}

-- Youliao BaaS admin call
function ylbaas_term:admin(modname, act, data)
    local mod = self.admin_mods[modname]
    if not mod then
        return nil, "no BaaS module named \"" .. tostring(modname) .. "\""
    end
    return mod(act, data)
end

-- Youliao BaaS client call
function ylbaas_term:cli(modname, act, data)
    local mod = self.cli_mods[modname]
    if not mod then
        return nil, "no BaaS module named \"" .. tostring(modname) .. "\""
    end
    return mod(act, data)
end

-- admin data sign unique function
function ylbaas_term:admin_sign(act, detail)
    return self.admin_pack(act, detail)
end

-- admin sign check unique function
function ylbaas_term:admin_check(act, ts, detail, hash)
    return self.admin_chk(act, ts, detail, hash)
end

local _M = {}

-- create Youliao BaaS API RPCer
function _M.create(conf)
    local htreq = ylbaas_req(conf.pool_size or 100, conf.idle_timeout or 60000)
    local admin_pack = _baas_admin.admin_signer(
        conf.admin_uuid, conf.admin_token)
    local admin_check = _baas_admin.admin_check(
        conf.admin_uuid, conf.admin_token)
    local appid = conf.appid
    local admin_apikey = conf.admin_key
    local cli_apikey = conf.cli_key
    -- admin request
    local admin_mods = _f.foreach(function(r, k, v)
        r[k] = function(act, detail)
            local dpack, err = _json.encode(admin_pack(act, detail))
            if not dpack then
                return nil, err
            end
            return htreq(appid, admin_apikey, v, dpack)
        end
        return r
    end, {}, pairs)(conf.admin_if)
    -- app client request
    local cli_mods = _f.foreach(function(r, k, v)
        r[k] = function(act, detail)
            local dpack, err = _json.encode(
                (act and {act = act, detail = detail}) or detail)
            if not dpack then
                return nil, err
            end
            return htreq(appid, cli_apikey, v, dpack)
        end
        return r
    end, {}, pairs)(conf.cli_if)
    --
    local ret = {
        admin_mods = admin_mods,
        cli_mods = cli_mods,
        admin_pack = admin_pack,
        admin_chk = admin_check,
    }
    return setmetatable(ret, ylbaas_meta)
end

return _M
