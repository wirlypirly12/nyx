local vm = require("./src/interpreter")

vm:runSource([[
    print("VM Running!")
]])

getgenv().vm = vm
