-- Main file is built with ext/Builder.exe
local lexer = require("./src/lexer")
local parser = require("./src/parser")

local source = require("./tests/lexertest")
local tokens = lexer.new(source):run()

local parserObject = parser.new(tokens)

local ast = parserObject:run()

parserObject:dump(ast)
