-- youliao task sub-system framework
-- access controller utils
-- content mime-type parse
-- Fiathux Su
-- 2019-11-28

local _f = require("functional")

local mime_proc = {
    -- JSON
    ["application/json"] = function(epic_inst)
        local reqdata = ngx.req.get_body_data()
        if not reqdata then
            return nil, -702000006, "failed read content"
        end
        local obj, err = utils.json.decode(reqdata)
        if not obj then
            _qlog.debug("REST failed JSON form parse - "..tostring(err))
            return nil, -702000007, "failed JSON parse"
        end
        epic_inst.form = obj
        return true
    end,
    -- URI encode form
    ["application/x-www-form-urlencoded"] = function(epic_inst)
        local args, err = ngx.req.get_post_args()
        if not args then
            _qlog.debug("REST failed post form parse - "..tostring(err))
            return nil, -702000008, "failed post form parse"
        end
        epic_inst.form = args
        return true
    end,
}

local _M = {}

function _M.create(mime, req_tag)
    local mime_support = _f.foreach(function(r, n)
        if mime_proc[n] then
            r[n] = mime_proc[n]
        end
        return r
    end, {}, _f.ival)(mime)
    return function (epic_inst)
        local cnt_parse, code, msg = (function()
            local cnt_len = ngx.var.content_length
            if not cnt_len then
                return nil, -702000003, "none content data"
            end
            local cnt_type = ngx.var.content_type:match("^[^;]+")
            local cnt_enc = ngx.var.content_type:match(
                ";%s*charset=([a-zA-Z0-9%-%_]+)")
            if cnt_enc and cnt_enc:lower() ~= "utf-8" then
                return nil, -702000004, "invalid content charset"
            end
            local ret = mime_support[cnt_type]
            if not ret then
                return nil, -702000005, "invalid content type"
            end
            return ret
        end)()
        if not cnt_parse then
            if req_tag then return nil, code, msg end
            return true
        end
        ngx.req.read_body()
        return cnt_parse(epic_inst)
    end
end

return _M

