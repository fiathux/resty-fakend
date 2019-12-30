--[[ Time simple pack
-- this is a comppatibility library for Droi BaaS an some other time source
-- Fiathux Su 2017-10-28
-- ]]

-- get current unix timestamp
local function getTimestampNow()
    return ngx.now()
    --return os.time()
end

local _f = require("functional")

-- Gregorianum begin at
local GREGO_TS = -12219292800       -- timestamp
local GREGO_YEAR = 1582             -- year
local GREGO_MON = 10                -- month
local GREGO_DAY = 15                -- day
local GERGO_WEEK = 5                -- weekday
local GREGO_YDAY = 287              -- year days (start at 0)
-- days in Gregorianum cycle
local GERGO_DAYS_CYC = 146097
local GERGO_DAYS_1600 = 6287
local GERGO_DAYS_1583 = 78
local GERGO_CENT_DAYS = 36524
-- Julian reference
local JULIAN_END_DAYS = 277         -- Julian end at 1582 days (start at 0)
-- days cycle
local YEAR_CYC = 365
local LEAP_CYC = 1461

-- full month name
local FULL_MONTH = {
    "Januare", "Februare", "March", "April", "May", "June", "July", "August",
    "September", "October", "November", "December",
}
-- abbreviated month name
local ABBR_MONTH = {
    "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug",
    "Sep", "Oct", "Nov", "Dec",
}
-- full week name
local FULL_WEEK = {
    "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday",
}
-- abbreviated week name
local ABBR_WEEK = {
    "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun",
}
-- normal month
local MONTHTHROUGH = { 0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334 }
local MONTHTHROUGH_LEAP = { 0, 31, 60, 91, 121, 152, 182, 213, 244, 274, 305, 335 }

-- convert timestamp to gregorianum days
local function getTS2Days_grego(ts)
    return math.floor((ts - GREGO_TS) / 86400)
end

-- conver gregorianum days to year and year days (start at 0)
local function getDays2Year_grego(days)
    local function filtStep(orig, lp1, lp2, lp3)
        if lp1 < 0 then return 0, orig end
        if lp2 < 0 then return 1, lp1 end
        if lp3 < 0 then return 2, lp2 end
        return 3, lp3
    end
    -- get Gregorianum cycle
    local function countGrego(d) return math.floor(d / GERGO_DAYS_CYC), d % GERGO_DAYS_CYC end
    -- get Century in one Gregorianum cycle
    local function countCentury(d)
        if d >= GERGO_CENT_DAYS + 1 then
            d = d - GERGO_CENT_DAYS - 1
            return math.floor(d / GERGO_CENT_DAYS) + 1, d % GERGO_CENT_DAYS
        end
        return 0, d
    end
    -- get leap cycle in one Century
    local function countLeap(d,forceleap)
        if not forceleap then
            if d < LEAP_CYC - 1 then
              return 0, d
            end
            d = d - LEAP_CYC + 1  -- jump leap in hundred year
            return math.floor(d / LEAP_CYC) + 1, d % LEAP_CYC
        end
        return math.floor(d / LEAP_CYC), d % LEAP_CYC
    end
    -- before 1600
    local function countYearBfr1600(d)
        local leaps, cycdays = countLeap(d, true)
        local leapyear, yearday = filtStep(cycdays, cycdays - 365, cycdays - 731, cycdays- 1096)
        return leaps * 4 + leapyear + 1583, yearday
    end
    -- after 1600
    local function countYearAft1600(d)
        local grego, invday = countGrego(d)
        local century, invday = countCentury(invday)
        local leapcyc, invday = countLeap(invday, century == 0)
        local lpdays = (century ~= 0 and leapcyc == 0 and 365) or 366
        local leapyear, yearday = filtStep(invday, 
            invday - lpdays, invday - lpdays - 365, invday - lpdays - 730)
        return grego * 400 + century * 100 + leapcyc * 4 + leapyear + 1600, yearday
    end
    -- condition path
    if days < GERGO_DAYS_1583 then
        return GREGO_YEAR, GREGO_YDAY + days
    elseif days < GERGO_DAYS_1600 then
        return countYearBfr1600(days - GERGO_DAYS_1583)
    else
        return countYearAft1600(days - GERGO_DAYS_1600)
    end
end

-- conver gregorianum year-days to month and month-days (days start at 0)
local function getYearDay2Month_grego(year, days)
    local leap = year % 4 == 0 and (year % 100 > 0 or  year % 400 == 0)
    local mtab = (leap and MONTHTHROUGH_LEAP) or MONTHTHROUGH
    local month = _f.foreach(function(mon, monidx)
        if days - mtab[monidx] < 0 then return nil end
        return monidx
    end,0,_f.irange)(1,12)
    return month, days - mtab[month]
end

-- conver gregorianum days to year and year days (start at 0) with Julian
local function getDays2Year_julian(days)
end

-- conver gregorianum days to week
local function getDays2Week(days)
    return (days + GERGO_WEEK - 1) % 7 + 1
end

-- Time object meta
local _TMMeta = {}

function _TMMeta:ts()
end

-- Duration object meta
local _DuraMeta = {}

local _M = {}

function _M.ts(inttype)
    if inttype then
        return math.floor(getTimestampNow())
    else
        return getTimestampNow()
    end
end

function _M.Time(ts)
end

function _M.Duration(inv)
end

function _M.strFmt(fmt, ts)
end

function _M.fromStr(fmt, timestr)
end

function _M.dateNum(ts,zone)
    if not ts then ts = _M.ts() end
    if not zone then zone = 0 end
    ts = ts + (zone * 3600)
    local days = getTS2Days_grego(ts)
    local year,yday = getDays2Year_grego(days)
    local month,mday = getYearDay2Month_grego(year,yday)
    return year * 10000 + month * 100 + mday + 1
end

function _M.normalDateTime(ts,zone)
    if not ts then ts = _M.ts() end
    ts = ts + ((zone or 0) * 3600)
    local days = getTS2Days_grego(ts)
    local year,yday = getDays2Year_grego(days)
    local month,mday = getYearDay2Month_grego(year,yday)
    local time = math.floor(ts) % 86400
    local hour = math.floor(time / 3600)
    local min = math.floor((time % 3600) / 60)
    local sec = time % 60
    return year.."-"..month.."-"..mday.." "..hour..":"..min..":"..sec
end

function _M.printDate(ts)
  local days = getTS2Days_grego(ts)
  local year,yday = getDays2Year_grego(days)
  local month,mday = getYearDay2Month_grego(year,yday)
  local week = getDays2Week(days)
  print("day="..days.."\nyear="..year.."\nmonth="..month.."\nmday="..mday.."\nweek="..week)
end

return _M
