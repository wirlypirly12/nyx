-- Main file is built with ext/Builder.exe
local lexer = require("./src/lexer")

local tokens = lexer
	.new([[
    print("Hello, World!");
]])
	:run()
