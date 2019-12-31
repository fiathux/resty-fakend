-- youliao task sub-system
-- REST viewer configure
-- 2019-11-29

-- all error features
local err_features = {
    Default = "error",
    Logic = "logic",
    Param = "parameter",
    DB = "database",
    Empty = "empty",
    Limited = "limited",
    Unique = "unique",
    Result = "result",
    Cache = "cache",
    Rights = "permission",
    Auth = "authorize",
    Temp = "temp",
    Callback = "callback",
    Noeffect = "noeffect",
    Program = "program",
    APIErr = "apierror",
}

-- export config
return {
    Err = err_features,
    CodeErr = {
        [0]  = err_features.Default,
        [1]  = err_features.Logic,
        [2]  = err_features.Param,
        [3]  = err_features.DB,
        [4]  = err_features.Empty,
        [5]  = err_features.Limited,
        [6]  = err_features.Unique,
        [7]  = err_features.Result,
        [8]  = err_features.Cache,
        [9]  = err_features.Rights,
        [10] = err_features.Auth,
        [11] = err_features.Temp,
        [12] = err_features.Callback,
        [13] = err_features.Noeffect,
        [14] = err_features.Program,
        [15] = err_features.APIErr,
    },
    BaaSErr = {
        [103] = err_features.DB,
        [104] = err_features.Program,
    },
}
