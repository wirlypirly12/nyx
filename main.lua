-- Main file is built with ext/Builder.exe
local lexer = require("./src/lexer")
local parser = require("./src/parser")
local compiler = require("./src/compiler")
-- local source = require("./tests/compilerTest")
local vm = require("./src/vm")

local tokens = lexer
	.new([[
    print("Hi")
]])
	:run()

local parserObject = parser.new(tokens)

local ast = parserObject:run()
local compObject = compiler.new()

compObject:run(ast)
compObject:dump()
local vmObj = vm.new(compObject.chunk)
vmObj:load_stdlib()
vmObj:run()
