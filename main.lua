-- Main file is built with ext/Builder.exe
local vm = require("./src/vm")

vm:runSource([[
    print("VM Running!")
]])

getgenv().customVM = vm
