-- youliao framework
-- openresty initialize template
-- Your name
-- 20xx-mm-dd

local origin_pkgs = package.path

-- project package name
local __XPROJ__ = "youliao"

-- global package path
local basepath = "/home/deploy"
package.path = origin_pkgs .. ";" ..
    basepath .. "/lualib/share/?.lua;" ..
    basepath .. "/lualib/share/?/init.lua;" ..
    basepath .. "/lualib/framework/?.lua;" ..
    basepath .. "/lualib/framework/?/init.lua;" ..
    basepath .. "/lualib/misc/?.lua;" ..
    basepath .. "/lualib/misc/?/init.lua"

-- sandbox path
local sandbox_path = basepath .. "/lualib/share/?.lua;" .. 
    basepath .. "/lualib/share/?/init.lua;" ..
    basepath .. "/lualib/framework/?.lua;" ..
    basepath .. "/lualib/framework/?/init.lua;" ..
    basepath .. "/"..__XPROJ__.."/lib/?.lua;" ..
    basepath .. "/"..__XPROJ__.."/lib/?/init.lua;" ..
    basepath .. "/"..__XPROJ__.."/interfaces/?/init.lua;" ..
    basepath .. "/"..__XPROJ__.."/interfaces/?.lua"

local _f = require("functional")

-- environment blacklist
local env_blacklist = {
    _G = true, _VERSION = true, loadfile = true, dofile = true, ngx = true,
}
-- backup global variable
local origin_G = _f.foreach(function(r, k, v)
    if not env_blacklist[k] then r[k] = v end
    return r
end, {}, pairs)(_G)

-- framework name space
qje = {}
qje.json = require("cjson.safe")
qje.qlog = require("logger")

-- session access name space {{{
local env_installer = {}    -- session namespace init list
local function add_installer(f)
    table.insert(env_installer, f)
end

qje.preset = require("preset")
local _xconf = qje.preset("crossconf")

-- mongodb config {{{
add_installer(function(genv)    -- init
    local _resty_mongol = require("qje.mongol") -- resty mongol
    local _mongo = require("qje.mongodb")
    
    -- create mongo connect factory
    local function create_mgodb_factory(task_db_uri, inner)
        local cluster = _mongo.cluster(task_db_uri)
        -- export
        return function()
            local conn, err = cluster:connect()
            if not conn then
                return nil, err
            end
            -- defer to clean function
            local clean_conn = function()
                return conn:set_keepalive()
            end
            if not inner.mongo_conn then
                inner.mongo_conn = {clean_conn}
            else
                table.insert(inner.mongo_conn, clean_conn)
            end
            -- export connection
            return conn()
        end
    end

    -- access
    return function(pub, inner)
        -- load mongo DB config
        pub.qje = _f.foreach(function (r, k)
            r["db_" .. k] = create_mgodb_factory(
                _xconf.DB["mgo_"..k.."_URL"], inner)
            return r
        end, pub.qje, _f.filter(_f.keys, function(s)
            return s:match("^mgo_([a-zA-Z]+[a-zA-Z0-9_]*[a-zA-Z0-9])_URL$")
        end))(_xconf.DB or {})

        -- clean
        return function(pub, inner)
            if not inner.mongo_conn then return end
            _f.foreach(function(r, c)
                local rst, err = c()
                if not rst then
                    qje.qlog.debug(
                        "release mongodb connection error - "..
                        tostring(err))
                end
                return r
            end, 0, _f.ival)(inner.mongo_conn)
        end
    end
end)
--}}}

-- redis config {{{
add_installer(function(genv) -- init
    local _redis_conn = require("redisconn")

    -- advance redis connection factory
    local function create_redis_factory_ex(conf, inner)
        local facto = _redis_conn.create_redis_factory(conf)

        return function()
            local conn, recycle = facto()
            if not conn then
                return conn, recycle -- recycle as error
            end
            if not inner.redis_conn then
                inner.redis_conn = {recycle}
            else
                table.insert(inner.redis_conn, recycle)
            end
            return conn
        end
    end

    -- access
    return function(pub, inner)
        -- load common redis cache
        pub.qje = _f.foreach(function (r, k)
            r["cache_" .. k] = create_redis_factory_ex(
                _xconf.DB["rds_"..k.."_conf"], inner)
            return r
        end, pub.qje, _f.filter(_f.keys, function(s)
            return s:match("^rds_([a-zA-Z]+[a-zA-Z0-9_]*[a-zA-Z0-9])_conf$")
        end))(_xconf.Cache or {})

        -- clean
        return function(pub, inner)
            if not inner.redis_conn then return end
            _f.foreach(function(r, c)
                local rst, err = c()
                if not rst then
                    qje.qlog.debug(
                        "release redis connection error - "..tostring(err))
                end
                return r
            end, 0, _f.ival)(inner.redis_conn)
        end
    end
end)
--}}}

-- sandbox source file load cache
qje.sand_load_cache = {}
local sand_require = (function()
    local codecache = _xconf.FrameWork.REST_code_cache
    local sbox_pp = _f.list(_f.filter(_f.badlz(_f.split, function(p)
        local prf, suf = p:match("^([^%?]*)%?([^%?]*)$")
        if not prf then return nil end
        return function(mid)
            return prf..mid..suf
        end
    end)))(sandbox_path, ";")
    -- try load file
    local try_req_file = function(name, sheet_path)
        if qje.sand_load_cache[name] and codecache then
            return qje.sand_load_cache[name]
        end
        local tryreq = _f.foreach(function(r, pcat)
            if r.f then return nil end
            local loadcode = pcat(
                table.concat(_f.list(_f.split)(name, "%."), "/"))
            table.insert(r.try, loadcode)
            local f, err = loadfile(loadcode)
            if f then
                r.f = f
            end
            if err and not err:match("No such file or directory$") then
                error(err)
            end
            return r
        end, {try = {}}, _f.ival)(sbox_pp)
        if not tryreq.f then
            error("module " .. "name" .. " not found:\n" ..
                table.concat(tryreq.try, "\n"))
        end
        qje.sand_load_cache[name] = tryreq.f
        return tryreq.f
    end
    -- do require in current env
    return function(name)
        local f = try_req_file(name)
        return setfenv(f, getfenv(1))(name)
    end
end)()

-- BaaS legacy client and admin API
add_installer(function(genv) -- init
    if not _xconf.BaaSLegacy then
        return nil
    end
    local _baas_req = require("baas")
    -- general baas require
    genv._baas = _baas_req.create(_xconf.BaaSLegacy)
end)

-- basic libs
add_installer(function(genv)
    -- http request
    local _http = require("resty.http")
    local function simp_http(...)
        local htconn = _http:new()
        local res, err = htconn:request_uri(...)
        if not res then
            qje.qlog.err("can not access task config - " .. tostring(err))
            return nil, "can not access"
        end
        if res.status ~= 200 then
            return nil, "remote error (HTTP code:" ..
                tostring(res.status) .. ")"
        end
        if not res.has_body then
            return nil, "none body"
        end
        return res.body
    end
    --
    genv._qlog = qje.qlog
    genv._preset = qje.preset
    genv.crypto = {                     -- crypto tools
        md5 = require("resty.md5"),
        sha1 = require("resty.sha1"),
        sha256 = require("resty.sha256"),
        rsa = require("resty.rsa"),
    }
    genv.utils = {
        str = require("resty.string"),  -- string
        rnd = require("utils.random"),  -- random
        spinlock = require("spinlock").new(__XPROJ__.."_locks"), -- spinlock
        lfs = require("lfs"),           -- file system
        sjson = qje.json,               -- json with safe error
        json = require("cjson"),        -- json with throw exception
        http = _http,                   -- http requester
        http_req = simp_http,           -- simply http request
    }
    genv.REST = {}
    -- sandbox require
    genv.require = setfenv(sand_require, genv)
end)
--}}}

-- create content env {{{

local global_env = setmetatable({}, {__index = origin_G})
local global_meta = {__index = global_env}


-- create content environment program
qje.exec_content = (function()
    -- init environment
    local access_pproc = _f.list(_f.filter(_f.ival, function(f)
        return f(global_env) or false
    end))(env_installer)

    -- install epic 
    local function epic_default()
        local _restctrl = require("restyctr")
        local _epic = require(__XPROJ__)
        REST.ctrl = _restctrl
        REST.epic = _restctrl.init_epic(_epic)
    end
    setfenv(epic_default, global_env)()

    -- export exec_content
    return function(ctr_f)
        local pub = {qje = {}, scratch = {}, ngx = ngx}
        local inner = {}
        pub.require = setfenv(sand_require, pub)
        -- access
        local clean_pproc = _f.list(_f.filter(_f.ival, function(facc)
            return facc(pub, inner)
        end))(access_pproc)
        setmetatable(pub, global_meta)
        local ses_env = setmetatable({}, {
            __index = pub,
            __newindex = function()
                error("readonly global environment")
            end
        })

        -- content generate
        local function err_hnd(e)
            qje.qlog.err("except response - "..tostring(e))
        end
        local status = xpcall(setfenv, err_hnd, ctr_f, ses_env)
        --qje.qlog.debug(status)
        --qje.qlog.debug(tostring(ses_env))
        --qje.qlog.debug(tostring(getmetatable(ses_env)))
        --qje.qlog.debug(tostring(getmetatable(getmetatable(ses_env))))
        ctr_f()

        -- clean
        --setmetatable(pub, nil)
        _f.foreach(function(r, fcl)
            fcl(pub, inner)
            return r
        end, 0, _f.ival)(clean_pproc)
    end
end)()
--}}}
