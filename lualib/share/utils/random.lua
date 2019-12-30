--[[ global random generator
-- Droi Tech.
-- Fiathux Su 2017-10-30
-- ]]

local _f = require("functional")

-- random source
local random_src = (function()
    local _time = require("calendar")
    local lastts = _time.ts()
    math.randomseed(lastts*1000000) -- init random seed
    return math.random
end)()

-- charater dictionary cache
local CHARTAB = {
    'a', 'A', 'b', 'B', 'c', 'C', 'd', 'D', 'e', 'E', 'f', 'F',
    'g', 'G', 'h', 'H', 'i', 'I', 'j', 'J', 'k', 'K', 'l', 'L',
    'm', 'M', 'n', 'N', 'o', 'O', 'p', 'P', 'q', 'Q', 'r', 'R',
    's', 'S', 't', 'T', 'u', 'U', 'v', 'V', 'w', 'W', 'x', 'X',
    'y', 'Y', 'z', 'Z', '0', '1', '2', '3', '4', '5', '6', '7',
    '8', '9', '~', '!', '@', '#', '$', '^', '&', '*', ')', '(',
    '_', '+', '-', '=', '{', '}', '[', ']', '|', '?', '>', '<',
}
local OffSet = {
    Alpha = function() return CHARTAB[math.floor(random_src(1,52))] end,
    Num = function() return CHARTAB[math.floor(random_src(1,10) + 52)] end,
    NumAlp = function() return CHARTAB[math.floor(random_src(1,62))] end,
    Full = function() return CHARTAB[math.floor(random_src(1,#CHARTAB))] end,
}

local _M = {}

-- random number
function _M.rnd(...)
    return random_src(...)
end

-- random string
function _M.rndstr(len, class)
    local randtab = (class and OffSet[class]) or OffSet["Full"]
    return table.concat(_f.list(_f.irange, function(idx)
        return randtab()
    end)(1,len))
end


return _M

