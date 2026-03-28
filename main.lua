-- MIT License
-- Copyright (c) 2026 Bradley

local vm = require("./src/interpreter")

vm:runSource([[
    print("VM Running!")
]])

getgenv().vm = vm
