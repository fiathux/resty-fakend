-- youliao interface
-- main epic module
-- Your name
-- 20xx-mm-dd

local _modname_ = (...)

local _M = {
    -- sub-module namespace
    mod_name = _modname_,
    -- enabled sub-module list
    epic = {
        "sample",
    }
}

--[[ epic request pre-check method
function _M.precheck()
    return true -- return for allow request or not
end]]

return _M
