-- youliao task sub-system framework
-- access controller utils
-- Fiathux Su
-- 2019-11-24

local _modname_ = (...)
local _vwmod_name_ = _modname_ .. "." .. "module"
local _view = require(_modname_ .. "." .. "view")
local _f = require("functional")


local subpath_method = {}
local subpath_meta = {__index = subpath_method}

-- regist path
function subpath_method:set_path(p, mod)
    if not p or p == "" or p == "/" then
        -- root path
        if self.mod then
            error("root path already registed")
        end
        self.mod = mod
        return
    end
    if p:sub(1,1) == "/" then
        p = p:sub(2)
    end
    -- sub-path
    local sub_p = _f.foreach(function(r, sp)
        if not r.path[sp] then
            r.path[sp] = {path={}, path_str = r.path_str .. "/" .. sp}
        end
        return r.path[sp]
    end, self, _f.split)(p, "/")
    if sub_p.mod then
        error("path " .. sub_p.path_str .. " already registed")
    end
    sub_p.mod = mod
end

-- get story module in path
function subpath_method:get_story(p)
    if not p or p == "/" or p == "" then
        return self.mod
    end
    if p:sub(1,1) == "/" then
        p = p:sub(2)
    end
    local sub_p = _f.foreach(function(r, sp)
        return r.path[sp]
    end, self, _f.split)(p, "/")
    return sub_p.mod
end

-- create path object
function subpath_meta.create()
    local ret = {path = {}, path_str = "/"}
    return setmetatable(ret, subpath_meta)
end

-- create REST epic content function
function create_epic_function(pathobj)
    -- export epic function
    return function()
        -- in current env module loader
        local _vwmod = require(_vwmod_name_)

        local function play_epic(epic_inst)
            local story_name = pathobj:get_story(epic_inst.path)
            if not story_name then
                return nil, -715000002, "invalid URL path"
            end
            local story_exec = _vwmod.create(require(story_name))
            
            local rest_err
            local stat, rst, code, msg, addit = xpcall(
                story_exec, function(e)
                    _qlog.err("REST API ERROR - " .. tostring(e) .. "\n" ..
                        tostring(debug.traceback()))
                    rest_err = e
                end, epic_inst)
            if not stat then
                return nil, -701000001, "internal error"
            end
            return rst, code, msg, addit
        end
        -- get request info
        local ver, uri_path = (function (u)
            if not u or u == "" or u == "/" then
                return 0, "/"
            end
            local ver_str = u:match("^([0-9]+)/?")
            if ver_str then
                local ver = tonumber(ver_str)
                local api_path = u:sub(#ver_str + 2)
                return ver, api_path
            end
            return 0, u
        end)(ngx.var.qje_home or ngx.var.uri)
        local create_rsp = function(...) return _view.m(...).response() end
        -- epic instance
        local epic_inst = {
            version = ver,
            path = uri_path,
            method = ngx.var.request_method,
            qs_args = ngx.req.get_uri_args(),
            headers = ngx.req.get_headers(),
        }
        local rsp = _view.m(play_epic(epic_inst)).response()
        ngx.header.content_type = "application/json"
        ngx.say(utils.json.encode(rsp))
    end
end

local _M = {view = _view}

-- initialize a epic
function _M.init_epic(story_mod)
    assert(story_mod.mod_name, "invalid module. no name found")
    assert(story_mod.epic, "invalid module. no epic found")
    if #story_mod.epic < 1 then
        error("none story in epic module: " .. story_mod.mod_name)
    end
    local mod_name = story_mod.mod_name
    local _vwmod = require(_vwmod_name_)
    -- load stories
    local path_obj = _f.foreach(function(r, v)
        local mod = require(mod_name .. "." .. v)
        assert(mod.story, "invalid story module.")
        local path = mod.story.path
        -- prepare module loader
        r:set_path(path, mod_name .. "." .. v)
        return r
    end, subpath_meta.create(), _f.ival)(story_mod.epic)
    return create_epic_function(path_obj)
end

return _M
