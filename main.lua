-- Main file is built with ext/Builder.exe
local lexer = require("./src/lexer")
local parser = require("./src/parser")
local compiler = require("./src/compiler")
local source = require("./tests/allOpcodes")
local vm = require("./src/vm")

local tokens = lexer.new(source):run()

local parserObject = parser.new(tokens)

local ast = parserObject:run()
local compObject = compiler.new()

compObject:run(ast)
local vmObj = vm.new(compObject.chunk)

vmObj:load_stdlib()
vmObj:run()
