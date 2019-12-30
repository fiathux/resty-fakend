--[[ URI codec
-- Droi Tech.
-- Fiathux Su 2017-10-28
-- ]]

local _f = require("functional")

local URICODE_TAB = {
    ['*'] = '%2a',
    ['?'] = '%3f',
    ['|'] = '%7c',
    ['!'] = '%21',
    ['#'] = '%23',
    ['<'] = '%3c',
    ['('] = '%28',
    ['+'] = '%2b',
    ['['] = '%5b',
    ['_'] = '%5f',
    ['@'] = '%40',
    ['~'] = '%7e',
    [';'] = '%3b',
    ['&'] = '%26',
    [':'] = '%3a',
    ['$'] = '%24',
    ['-'] = '%2d',
    [')'] = '%29',
    ['>'] = '%3e',
    [']'] = '%5d',
    ['='] = '%3d',
    ['}'] = '%7d',
    ['^'] = '%5e',
    ['{'] = '%7b',
    [" "] = "%20",
}

local _M = {}

-- encode uri
function _M.encode(str)
    return table.concat(_f.list(_f.split, function(s)
        return URICODE_TAB[s] or s
    end)(str,""))
end

-- splite fusion URL to primary part and parameter part 
function _M.splitURL(url)
    local url_prim, _, url_para = string.match(url,"([^?]+)([?]?(.*))")
    return url_prim, url_para
end

return _M
