-- youliao framework
-- REST API entery

-- root loader
qje.exec_content(function()
    setfenv(REST.epic,getfenv(1))()
end)
