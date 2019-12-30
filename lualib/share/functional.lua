--[[ functional tools
-- Droi Tech.
-- Fiathux Su 2017-02-28
-- ]]

local _f = {}

-- create iterate convert function
local function createConvert(lmd)
    local lmd = lmd or (function(obj) return obj end)
    return function (var,...)
        if var ~= nil then
            return var,lmd(var,...)
        else
            return nil
        end
    end
end

-- generate a function that expand iterator to list
function _f.list(iter,lmd)
    local convert = createConvert(lmd)
    local function fillList(li,itr,init,var)
        local one
        var,one = convert(itr(init,var))
        if var~=nil then
            table.insert(li,one)
            return fillList(li,itr,init,var)
        end
    end
    return function(...)
        local result = {}
        fillList(result,iter(...))
        return result
    end
end

-- loop iterate
function _f.loop(action)
    local function procLoop(roundobj, nextobj, ...)
        if nextobj ~= nil then
            return procLoop(nextobj, action(nextobj, ...))
        else
            return roundobj
        end
    end
    return function(init, ...)
        return procLoop(init, action(init, ...))
    end
end

-- loop each element of iterator
function _f.foreach(action,initObj,iter)
    return function(...)
        return _f.loop(function(reduceObj, nextiter, init , var, ...)
            local nextObj, var = (function(var,...)
                if var == nil then return nil end
                local roundObj = action(reduceObj,var,...)
                if roundObj == nil then return nil end
                return roundObj, var
            end)(nextiter(init , var))
            return nextObj, nextiter, init, var
        end)(initObj,iter(...))
    end
end

-- convert iterator to closure-style
function _f.badlz(iter,lmd)
    local convert = createConvert(lmd)
    local function round(itr,init,var)
        return function()
            local one
            var,one = convert(itr(init,var))
            if var~=nil then
                return one
            else
                return nil
            end
        end
    end
    return function(...)
        return round(iter(...))
    end
end

-- reduce iterator
function _f.reduce(iter,lmd,combine)
    local convert = createConvert(lmd)
    local function doIter(last,itr,init,var)
        local one
        var,one = convert(itr(init,var))
        if var~=nil then
            last = combine(one,last)
            return doIter(last,itr,init,var)
        else
            return last
        end
    end
    return function(...)
        local last
        local itr,init,var = iter(...)
        var,last = convert(itr(init,var))
        if var ~= nil then
            last = doIter(last,itr,init,var)
        end
        return last
    end
end

-- filter iterator
function _f.filter(iter, lmd, filter)
    filter = filter or (function(v) return v end)
    local baditer = _f.badlz(iter,lmd)
    return function(...)
        local iterProc = baditer(...)
        local function filterIter()
            local current = iterProc()
            if current == nil or filter(current) then
                return current
            else
                return filterIter()
            end
        end
        return function()
            return filterIter()
        end
    end
end

-- some iterators {{{

-- range iterator
function _f.irange(start,stop,step)
    if type(start) == "table" then -- range from table
        stop = #start
        start = 1
        step = 1
    end
    if not stop then -- parse from 1 to end postion
        stop = start
        start = 1
    end
    step = math.abs(step or 1) * ((stop < start and -1) or 1)
    return function(init,varb)
        if not varb then return start end
        if varb == init then
            return nil
        else
            return varb + step
        end
    end, stop, nil
end

-- iterate values from array
function _f.ival(tab)
    return _f.badlz(ipairs,function(k,v) return v end)(tab)
end

-- iterate values from typic-table
function _f.values(tab)
    return _f.badlz(pairs,function(k,v) return v end)(tab)
end

-- iterate keys from typic-table
function _f.keys(tab)
    return _f.badlz(pairs,function(k,v) return k end)(tab)
end

-- iterate as a list slice
function _f.slice(tab,start,stop)
    local function fixpos(pos,default)
        if pos and pos ~= 0 then
            if pos > 0 then
                return (pos > #tab and #tab) or pos
            else
                return #tab + pos + 1
            end
        else
            return default
        end
    end
    local fixstart = fixpos(start,1)
    local fixstop = fixpos(stop,#tab)
    if fixstart <= 0 or fixstop <= 0 or fixstop < fixstart then
        return function() return nil end
    end
    return _f.badlz(_f.irange, function(idx) return tab[idx] end)(fixstart,fixstop)
end

-- iterate splite a string
function _f.split(str, sep, enab_pattern)
    if not enab_pattern then
        local sep = string.gsub(sep,"[%(%)%.%%%+%-%*%?%[%^%$]","%%%1")
    end
    return _f.badlz(function()
        return function(sp, last)
            if not last then return nil end
            local spleft, spright = sp()
            if not spleft then return false, string.sub(str,last) end
            return spright, string.sub(str,last, spleft - 1)
        end, string.gmatch(str,"()"..sep.."()"), 1
    end,function(last,v) return v end)()
end

--}}}

return _f
