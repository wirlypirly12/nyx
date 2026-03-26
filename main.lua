local vm = require("./src/vm")

vm:runSource([[
    print("VM Running!")
]])

getgenv().vm = vm
