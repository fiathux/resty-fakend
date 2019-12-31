-- youliao framework
-- simple interface
-- Your name
-- 20xx-mm-dd

local _fullname_ = (...)
local _modname_ = _fullname_:match("(.*)%..-")

local _M = {
    story = {
        path = "sample",        -- install path
        available = {
            content = {         -- available content types
                "application/json",
                "application/x-www-form-urlencoded",
            },
            --req_content = true,    -- required content data
            sub_path = true,    -- available sub-path
            min_version = 0,    -- minium version available
            --max_version = 0,  -- maxium version available
            --pre_check = function(epic_inst) return true end
        },
        module_name = _fullname_,
        description = "test sample",
    },
    -- GET method interfaces (function or table)
    GET = function(get_req, epic_inst)
        return "Hello World!"
    end,
    POST = {},  -- POST method interfaces (function or table)
    --PUT = {},
    --PATCH = {},
    --DELETE = {},
}

-- test baas
function _M.POST.test(get_req, epic_inst)
    local req, code, msg = get_req({
        something = "string:1",
        addit = "?string",
    })
    if not req then
        return nil, code, msg
    end
    return { your_reqest_is = req }
end

-- test GET error
function _M.POST.err(get_req, epic_inst)
    return nil, -700000000, "test GET error"
end

return _M
