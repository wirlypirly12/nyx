-- MIT License
-- Copyright (c) 2026 Bradley
-- https://github.com/wirlypirly12/nyx

local vm = require("./src/interpreter")

vm:runSource([[
    print("VM Running!")
]])

if getgenv then
	getgenv().vm = vm
end

return vm
