-- youliao task sub-system framework
-- access controller utils
-- module support
-- Fiathux Su
-- 2019-11-28

local _modname_ = (...):match("(.*)%..-")
local _cnt_parse = require(_modname_ .. "." .. "content")
local _paramchk = require("paramchk")
local _f = require("functional")

-- available methods
local method_list = {
    ["GET"] = "head-body",
    ["POST"] = "body-body",
    ["PUT"] = "body-head",
    ["DELETE"] = "head-body",
    ["PATCH"] = "body-body",
    ["OPTIONS"] = "head-body",
}

-- create method check function
local function mk_method_check(methods, modname)
    if #_f.list(_f.keys)(methods) < 1 then
        error("no methods available in module: " .. modname)
    end
    return function(epic_inst)
        local method = epic_inst.method
        if not methods[method] then
            return nil, -715000000, "method not allowed"
        end
        return true
    end
end

-- create content type parse function
local function mk_content_parse(mimes, req_tag)
    if not mimes then return nil end
    return _cnt_parse.create(mimes, req_tag)
end

-- create strict path name check function
local function mk_path_check(path)
    return function(epic_inst)
        local ret = epic_inst.path == path or (
            epic_inst.path == "/" and path == "")
        if not ret then
            return nil, -715000001, "invalid sub-path"
        end
        return true
    end
end

-- create API version check function
local function mk_version_check(min, max)
    if min == 0 and max == 0 then return nil end
    return function(epic_inst)
        if min > 0 and epic_inst.version < min then
            return nil, -709000000, "require version "..tostring(min)
        end
        if max > 0 and epic_inst.version > max then
            return nil, -709000001, "not support version over"..tostring(max)
        end
        return true
    end
end

-- access REST API as 'action based style'
local function mk_action_style(app, req, epic_inst)
    local rst, p = _paramchk.check({
        act = "string:1",
    }, "(Req)")(req)
    if not rst then
        return nil, -702000001, "no named \"act\" argument found"
    end
    if not app[req.act] then
        return nil, -702000002, "invalid \"act\":" .. req.act
    end
    local detail = req.detail
    local get_req_func = function(exp, rwpath)
        if not exp then return detail end
        local ppath = rwpath or "(Req).detail"
        local rst, p = _paramchk.check(exp, ppath)(detail)
        if not rst then
            return nil, -702000000,
                "error request argument - " .. tostring(p)
        end
        return detail
    end
    epic_inst.rest_act = req.act
    return app[req.act](get_req_func, epic_inst)
end

-- simplely access REST API
local function mk_simp_style(app, req, epic_inst)
    local get_req_func = function(exp, rwpath)
        if not exp then return req end
        local ppath = rwpath or "(Req)"
        local rst, p = _paramchk.check(exp, ppath)(req)
        if not rst then
            return nil, -702000000,
                "error request argument - " .. tostring(p)
        end
        return req
    end
    return app(get_req_func, epic_inst)
end

-- create story process function
local function mk_story_pipe(mod, check_proc)
    return function(epic_inst)
        local err_rst = _f.foreach(function(r, p)
            if r then return nil end
            local rst, code, msg = p(epic_inst)
            if not rst then
                return {code=code, msg=msg}
            end
            return r
        end, false, _f.ival)(check_proc)
        if err_rst then return nil, err_rst.code, err_rst.msg end
        -- access
        local reqobj = epic_inst.form or epic_inst.qs_args
        local app = mod[epic_inst.method]
        if type(app) == "function" then
            return mk_simp_style(app, reqobj, epic_inst)
        elseif type(app) == "table" then
            return mk_action_style(app, reqobj, epic_inst)
        else
            _qlog.err("in path:" .. epic_inst.path ..
                " method:" .. epic_inst.method ..
                " interface reference error")
            return nil, -701000000, "interface reference error"
        end
    end
end

local _M = {}

-- create REST module
function _M.create(mod)
    local story = mod.story
    local avail = story.available or {}
    local method_chk = mk_method_check(_f.foreach(function (r, m)
        if method_list[m] then
            r[m] = method_list[m]
        end
        return r
    end, {} ,_f.keys)(mod), story.module_name)
    local cnt_check = mk_content_parse(avail.content, avail.req_content)
    local path_check = not avail.sub_path and mk_path_check(story.path)
    local ver_check = mk_version_check(
        avail.min_version or 0, avail.max_version or 0)
    local pre_check = avail.pre_check
    --
    return mk_story_pipe(mod,
        _f.list(_f.filter(_f.ival))({
            ver_check or false, method_chk or false,
            path_check  or false, cnt_check  or false,
            pre_check or false,
        }))
end

return _M

