--!nolint
-- [[ linker bundled output ]]
-- built   : 2026-03-25 16:08:51
-- entry   : main.lua
-- inlined : 3 module(s) + entry

local __linker_modules = {}
local __linker_cache   = {}
local __linker_shared  = {}

local function __linker_require(name)
    if __linker_cache[name] ~= nil then
        return __linker_cache[name]
    end
    local mod = __linker_modules[name]
    if not mod then
        error("[linker] module not found: " .. tostring(name))
    end
    local result = mod()
    __linker_cache[name] = result
    return result
end

__linker_modules["src/lexer.lua"] = function()
local shared = __linker_shared
local lexer = {}
lexer.__index = lexer

local TOKEN_TYPES = {
	KEYWORD = "KEYWORD",
	IDENTIFIER = "IDENTIFIER",
	STRING = "STRING",
	NUMBER = "NUMBER",
	OPERATOR = "OPERATOR",
	SYMBOL = "SYMBOL",
	EOF = "EOF",
}

local KEYWORDS = {
	["if"] = true,
	["then"] = true,
	["else"] = true,
	["elseif"] = true,
	["end"] = true,
	["do"] = true,
	["while"] = true,
	["for"] = true,
	["in"] = true,
	["repeat"] = true,
	["until"] = true,
	["return"] = true,
	["local"] = true,
	["function"] = true,
	["and"] = true,
	["or"] = true,
	["not"] = true,
	["true"] = true,
	["false"] = true,
	["nil"] = true,
}

function lexer.new(source: string)
	local self = setmetatable({
		line = 1,
		pos = 1,
		column = 1,
		source = source,
		tokens = {},
		char = nil,
	}, lexer)

	if #source > 0 then
		self.char = source:sub(self.pos, self.pos)
	end

	return self
end

function lexer:advance()
	self.pos = self.pos + 1

	if self.pos <= #self.source then
		self.char = self.source:sub(self.pos, self.pos) -- get character at curr pos

		if self.char == "\n" then -- newline, reset the col and inc the line.
			self.line = self.line + 1
			self.column = 1
		else
			self.column = self.column + 1
		end
	else
		self.char = nil -- ran out of source to read
	end
end

function lexer:peek(offset)
	offset = offset or 1
	local peek_at = self.pos + offset

	if peek_at <= #self.source then -- ensure we are still in bounds of the source
		return self.source:sub(peek_at, peek_at)
	end
	return nil -- no more source to peek
end

function lexer:skip_whitespace()
	while self.char and self.char:match("%s") do
		self:advance()
	end
end

--
function lexer:skip_comment()
	if self.char == "-" and self:peek() == "-" then
		self:advance()
		self:advance() -- skip --

		if self.char == "[" then
			local level = 0
			local i = 1
			while self:peek(i) == "=" do
				level += 1
				i += 1
			end

			if self:peek(i) == "[" then
				self:advance() -- skip [
				for z = 1, level do
					self:advance() -- skip =
				end
				self:advance() -- skip second  [

				while self.char do
					if self.char == "]" then
						local close_level = 0
						local j = 1
						while self:peek(j) == "=" do
							close_level += 1
							j += 1
						end
						if close_level == level and self:peek(j) == "]" then
							self:advance() -- skip ]
							for z = 1, level do -- skip =
								self:advance()
							end
							self:advance() -- skip second ]
							return
						end
					end
					self:advance()
				end

				error(`unended block comment, expected ]{string.rep("=", level)}]`)
			end
		end

		while self.char and self.char ~= "\n" do
			self:advance()
		end
		if self.char then
			self:advance()
		end
	end
end

function lexer:string()
	local escapes = {
		n = "\n",
		t = "\t",
		r = "\r",
		["\\"] = "\\",
		['"'] = '"',
		["'"] = "'",
	}

	local quote = self.char -- store opening quote so we know when to stop advancing the string
	self:advance()
	local result = {}
	while self.char and self.char ~= quote do
		if self.char == "\\" then -- allow escapes to be parsed
			self:advance()
			local escaped = escapes[self.char]
			if escaped then
				table.insert(result, escaped)
			else
				error(`illegal escape: {self.char}`)
			end
		else
			table.insert(result, self.char)
		end
		self:advance()
	end
	if not self.char then -- ensure string closed
		error("illegal string! did you forget to close it?")
	end
	self:advance() -- skip closing quote
	self:emit(TOKEN_TYPES.STRING, table.concat(result))
end

function lexer:number()
	local result = {}

	if self.char == "0" and (self:peek() == "x" or self:peek() == "X") then
		table.insert(result, self.char)
		self:advance()
		table.insert(result, self.char)
		while self.char and self.char:match("[%x_]") do
			if self.char ~= "_" then
				table.insert(result, self.char)
			end
			self:advance()
		end
	else
		while self.char and self.char:match("[%d_]") do
			if self.char ~= "_" then
				table.insert(result, self.char)
			end
			self:advance()
		end
		if self.char == "e" and self.char == "E" then
			table.insert(result, self.char)
			self:advance()
			if self.char == "+" or self.char == "-" then
				table.insert(result, self.char)
				self:advance()
			end
			while self.char and self.char:match("%d") do
				table.insert(result, self.char)
				self:advance()
			end
		end
	end
	self:emit(TOKEN_TYPES.NUMBER, tonumber(table.concat(result)))
end

function lexer:identifier()
	local result = {}
	while self.char and self.char:match("[%a%d_]") do
		table.insert(result, self.char)
		self:advance()
	end
	local word = table.concat(result)
	if KEYWORDS[word] then
		self:emit(TOKEN_TYPES.KEYWORD, word)
	else
		self:emit(TOKEN_TYPES.IDENTIFIER, word)
	end
end

function lexer:operator()
	local c = self.char
	local p = self:peek()

	local two = c .. (p or "")
	local two_char = {
		["=="] = true,
		["~="] = true,
		["<="] = true,
		[">="] = true,
		[".."] = true,
		["//"] = true,
		["<<"] = true,
		[">>"] = true,
	}

	if two_char[two] then
		self:advance()
		self:advance()
		self:emit(TOKEN_TYPES.OPERATOR, two)
	else
		self:advance()
		self:emit(TOKEN_TYPES.OPERATOR, c)
	end
end

function lexer:symbol()
	local symbols = {
		["("] = true,
		[")"] = true,
		["{"] = true,
		["}"] = true,
		["["] = true,
		["]"] = true,
		[","] = true,
		[";"] = true,
		["."] = true,
		[":"] = true,
	}
	if symbols[self.char] then
		self:emit(TOKEN_TYPES.SYMBOL, self.char)
		self:advance()
	else
		error(`unexpected character: {self.char} at line {self.line} col: {self.column}`)
	end
end

function lexer:emit(type, value)
	table.insert(self.tokens, {
		type = type,
		value = value,
		line = self.line,
		column = self.column,
	})
end

function lexer:run()
	while self.char do
		self:skip_whitespace()
		if not self.char then
			break
		end

		if self.char == "-" and self:peek() == "-" then
			self:skip_comment()
		elseif self.char == '"' or self.char == "'" then
			self:string()
		elseif self.char:match("%d") then
			self:number()
		elseif self.char:match("[%a_]") then
			self:identifier()
		elseif self.char:match("[%+%-%*/%%^#&|~<>=%.!]") then
			self:operator()
		else
			self:symbol()
		end
	end
	self:emit(TOKEN_TYPES.EOF, nil)
	return self.tokens
end

return lexer

end

__linker_modules["src/parser.lua"] = function()
local shared = __linker_shared
type LexerToken = {
	type: string,
	value: any,
	line: number,
	column: number,
}

-- expression parsing using pratt parsing for operator precedence
local BINARY_PRECEDENCE = {
	["or"] = 1,
	["and"] = 2,
	["<"] = 3,
	[">"] = 3,
	["<="] = 3,
	[">="] = 3,
	["=="] = 3,
	["~="] = 3,
	[".."] = 4,
	["+"] = 5,
	["-"] = 5,
	["*"] = 6,
	["/"] = 6,
	["%"] = 6,
	["//"] = 6,
	["^"] = 7, -- right associative
}
local RIGHT_ASSOC = { ["^"] = true, [".."] = true }

local parser = {}
parser.__index = parser

function parser.new(tokens: { [number]: LexerToken })
	local self = setmetatable({
		tokens = tokens,
		pos = 1,
	}, parser)

	return self
end

function parser:peek(offset): LexerToken
	offset = offset or 0
	local t = self.tokens[self.pos + offset]
	return t or { type = "EOF", value = nil } -- if the specified token doesn't exist, we probably hit EOF
end

function parser:advance(): LexerToken
	local t = self.tokens[self.pos]
	self.pos = self.pos + 1
	return t
end

function parser:match(type, value): LexerToken | nil
	local t = self:peek()
	if t.type == type and (value == nil or t.value == value) then
		return self:advance()
	end
	return nil
end

function parser:expect(type, value): LexerToken
	local t = self:peek()
	if t.type ~= type or (value and t.value ~= value) then
		error(`expected {value or type} but got '{t.value}' at line {t.line}`)
	end
	return self:advance()
end

function parser:parse_local()
	self:expect("KEYWORD", "local")

	-- parse local func
	if self:peek().type == "KEYWORD" and self:peek().value == "function" then
		self:advance()

		local name = self:expect("IDENTIFIER").value
		local func = self:parse_function_body()
		return { kind = "LocalFunction", name = name, func = func }
	end

	-- local a, b, c
	local names = { self:expect("IDENTIFIER").value }
	while self:match("SYMBOL", ",") do
		table.insert(names, self:expect("IDENTIFIER").value)
	end

	local values = {}
	if self:match("OPERATOR", "=") then
		table.insert(values, self:parse_expression())
		while self:match("SYMBOL", ",") do
			table.insert(values, self:parse_expression())
		end
	end

	return { kind = "LocalStatement", names = names, values = values }
end

function parser:parse_block(stop_at)
	local statements = {}
	local stop = {}
	for i, v in ipairs(stop_at) do
		stop[v] = true
	end
	while self:peek().type ~= "EOF" and not stop[self:peek().value] do
		table.insert(statements, self:parse_statement())
		self:match("SYMBOL", ";") -- allow semicolons!
	end
	return { kind = "Block", body = statements }
end

function parser:parse_if()
	self:expect("KEYWORD", "if")
	local condition = self:parse_expression()
	self:expect("KEYWORD", "then")

	local body = self:parse_block({ "end", "else", "elseif" })
	local elseifs = {}
	local else_body = nil

	while self:peek().value == "elseif" do
		self:advance()
		local ei_cond = self:parse_expression()
		self:expect("KEYWORD", "then")
		local ei_body = self:parse_block({ "end", "else", "elseif" })
		table.insert(elseifs, { condition = ei_cond, body = ei_body })
	end
	if self:match("KEYWORD", "else") then
		else_body = self:parse_block({ "end" })
	end

	self:expect("KEYWORD", "end")
	return { kind = "IfStatement", condition = condition, body = body, elseifs = elseifs, else_body = else_body }
end

function parser:parse_while()
	self:expect("KEYWORD", "while")
	local cond = self:parse_expression()
	self:expect("KEYWORD", "do")
	local body = self:parse_block({ "end" })
	self:expect("KEYWORD", "end")
	return { kind = "WhileStatement", condition = cond, body = body }
end

function parser:parser_for()
	self:expect("KEYWORD", "for")
	local name = self:expect("IDENTIFIER").value

	if self:match("OPERATOR", "=") then
		-- for x = x, x
		local start = self:parse_expression()
		self:expect("SYMBOL", ",")
		local limit = self:parse_expression()
		local step = nil
		if self:match("SYMBOL", ",") then
			step = self:parse_expression()
		end
		self:expect("KEYWORD", "do")
		local body = self:parse_block({ "end" })
		self:expect("KEYWORD", "end")
		return { kind = "NumericFor", name = name, start = start, limit = limit, step = step, body = body }
	else
		-- for x, x in pairs(x) do
		local names = { name }

		while self:match("SYMBOL", ",") do
			table.insert(names, self:expect("IDENTIFIER").value)
		end
		self:expect("KEYWORD", "in")
		local itr = { self:parse_expression() }
		while self:match("SYMBOL", ",") do
			table.insert(itr, self:parse_expression())
		end
		self:expect("KEYWORD", "do")
		local body = self:parse_block({ "end" })
		self:expect("KEYWORD", "end")
		return { kind = "GenericFor", names = name, iterators = itr, body = body }
	end
end

function parser:parse_function()
	self:expect("KEYWORD", "function")
	local name = self:expect("IDENTIFIER").value

	-- handle methods and index
	local chain = { name }
	local is_method = false
	while self:peek().value == "." do
		self:advance()
		table.insert(chain, self:expect("IDENTIFIER").value)
	end
	if self:peek().value == ":" then
		self:advance()
		table.insert(chain, self:expect("IDENTIFIER").value)
		is_method = true
	end
	local func = self:parse_function_body(is_method)
	return { kind = "FunctionStatement", name = chain, is_method = is_method, func = func }
end

function parser:parse_function_body(is_method)
	self:expect("SYMBOL", "(")
	local params = {}
	if is_method then
		table.insert(params, "self") -- implicit self
	end
	if self:peek().value ~= ")" then
		table.insert(params, self:expect("IDENTIFIER").value)
		while self:match("SYMBOL", ",") do
			if self:peek().value == "..." then
				self:advance()
				table.insert(params, "...")
				break
			end
			table.insert(params, self:expect("IDENTIFIER").value)
		end
	end
	self:expect("SYMBOL", ")")
	local body = self:parse_block({ "end" })
	self:expect("KEYWORD", "end")
	return { kind = "Function", params = params, body = body }
end

function parser:parse_repeat()
	self:expect("KEYWORD", "repeat")
	local body = self:parse_block({ "until" })
	self:expect("KEYWORD", "until")
	local condition = self:parse_expression()
	return { kind = "RepeatStatement", body = body, condition = condition }
end

function parser:parse_do()
	self:expect("KEYWORD", "do")
	local body = self:parse_block({ "end" })
	self:expect("KEYWORD", "end")
	return { kind = "DoStatement", body = body }
end

function parser:parse_return()
	self:expect("KEYWORD", "return")
	local values = {}
	if self:peek().type ~= "EOF" and self:peek().value ~= "end" then
		table.insert(values, self:parse_expression())
		while self:match("SYMBOL", ",") do
			table.insert(values, self:parse_expression())
		end
	end
	return { kind = "ReturnStatement", values = values }
end

function parser:parse_postfix()
	local node = self:parse_primary()

	while true do
		local t = self:peek()
		if t.value == "." then
			self:advance()
			local field = self:expect("IDENTIFIER").value
			node = { kind = "FieldAccess", object = node, field = field }
		elseif t.value == "[" then
			self:advance()
			local index = self:parse_expression()
			self:expect("SYMBOL", "]")
			node = { kind = "IndexAccess", object = node, index = index }
		elseif t.value == "(" then
			local args = self:parse_call_args()
			node = { kind = "CallExpr", callee = node, args = args }
		elseif t.value == ":" then
			self:advance()
			local method = self:expect("IDENTIFIER").value
			local args = self:parse_call_args()
			node = { kind = "MethodCall", object = node, method = method, args = args }
		else
			break
		end
	end
	return node
end

function parser:parse_call_args()
	self:expect("SYMBOL", "(")
	local args = {}
	if self:peek().value ~= ")" then
		table.insert(args, self:parse_expression())
		while self:match("SYMBOL", ",") do
			table.insert(args, self:parse_expression())
		end
	end
	self:expect("SYMBOL", ")")
	return args
end

function parser:parse_primary()
	local t = self:peek()
	if t.type == "NUMBER" then
		self:advance()
		return { kind = "Number", value = t.value }
	end

	if t.type == "STRING" then
		self:advance()
		return { kind = "String", value = t.value }
	end

	if t.type == "KEYWORD" and (t.value == "true" or t.value == "false") then
		self:advance()
		return { kind = "Boolean", value = t.value == "true" }
	end

	if t.type == "KEYWORD" and t.value == "nil" then
		self:advance()
		return { kind = "Nil" }
	end

	if t.type == "IDENTIFIER" then
		self:advance()
		return { kind = "Identifier", name = t.value }
	end

	if t.value == "function" then
		self:advance()
		return self:parse_function_body()
	end

	if t.value == "{" then
		return self:parse_table()
	end

	if t.value == "(" then
		self:advance()
		local expr = self:parse_expression()
		self:expect("SYMBOL", ")")
		return { kind = "Grouped", expr = expr }
	end

	error(`unexpected token '{t.value}' at line {t.line}`)
end

function parser:parse_table()
	self:expect("SYMBOL", "{")
	local fields = {}

	while self:peek().value ~= "}" do
		if self:peek().value == "[" then
			self:advance()
			local key = self:parse_expression()
			self:expect("SYMBOL", "]")
			self:expect("OPERATOR", "=")
			local value = self:parse_expression()
			table.insert(fields, { kind = "IndexedField", key = key, value = value })
		elseif self:peek().type == "IDENTIFIER" and self:peek(1).value == "=" then
			-- name = value
			local key = self:advance().value
			self:advance() -- skip '='
			local value = self:parse_expression()
			table.insert(fields, { kind = "NamedField", key = key, value = value })
		else
			-- plain value
			local value = self:parse_expression()
			table.insert(fields, { kind = "ValueField", value = value })
		end

		if not self:match("SYMBOL", ",") then
			self:match("SYMBOL", ";")
			break
		end
	end

	self:expect("SYMBOL", "}")
	return { kind = "Table", fields = fields }
end

function parser:parse_expression_statement()
	local expr = self:parse_postfix()

	if
		self:peek().value == "="
		or self:peek().value == "+="
		or self:peek().value == "-="
		or self:peek().value == "*="
		or self:peek().value == "/="
	then
		local op = self:advance().value
		local values = { self:parse_expression() }
		while self:match("SYMBOL", ",") do
			table.insert(values, self:parse_expression())
		end
		return { kind = "Assignment", target = expr, op = op, values = values }
	end

	if expr.kind == "CallExpr" or expr.kind == "MethodCall" then
		return { kind = "CallStatement", expr = expr }
	end

	error(`unexpected expression at line {self:peek().line}`)
end

function parser:parse_unary()
	local op = self:peek().value
	if op == "-" or op == "not" or op == "#" then
		self:advance()
		return { kind = "UnaryExpr", op = op, operand = self:parse_unary() }
	end
	return self:parse_postfix()
end

function parser:parse_expression(min_prec)
	min_prec = min_prec or 0
	local left = self:parse_unary()

	while true do
		local op = self:peek().value
		local prec = BINARY_PRECEDENCE[op]
		if not prec or prec <= min_prec then
			break
		end
		self:advance()

		local next_prec = RIGHT_ASSOC[op] and (prec - 1) or prec
		local right = self:parse_expression(next_prec)
		left = { kind = "BinaryExpr", op = op, left = left, right = right }
	end
	return left
end

function parser:parse_statement()
	local t = self:peek()

	if t.type == "KEYWORD" then
		if t.value == "local" then
			return self:parse_local()
		elseif t.value == "if" then
			return self:parse_if()
		elseif t.value == "while" then
			return self:parse_while()
		elseif t.value == "for" then
			return self:parse_for()
		elseif t.value == "return" then
			return self:parse_return()
		elseif t.value == "function" then
			return self:parse_function()
		elseif t.value == "do" then
			return self:parse_do()
		elseif t.value == "repeat" then
			return self:parse_repeat()
		elseif t.value == "break" then
			self:advance()
			return { Kind = "Break" }
		end
	end
	return self:parse_expression_statement()
end

function parser:run()
	local statements = {}
	while self:peek().type ~= "EOF" do
		table.insert(statements, self:parse_statement())
	end
	return { kind = "Block", body = statements }
end

function parser:dump(node)
	print(self:serialize(node))
end

function parser:serialize(node, indent)
	indent = indent or 0
	local pad = string.rep("    ", indent)
	local inner = string.rep("    ", indent + 1)

	if type(node) ~= "table" then
		return tostring(node)
	end

	if node.kind then
		local parts = {}
		for k, v in pairs(node) do
			if k ~= "kind" then
				table.insert(parts, inner .. k .. " = " .. self:serialize(v, indent + 1))
			end
		end
		if #parts == 0 then
			return "[" .. node.kind .. "]"
		end
		return "[" .. node.kind .. "]\n" .. table.concat(parts, "\n")
	elseif #node > 0 then
		local parts = {}
		for i, v in ipairs(node) do
			table.insert(parts, inner .. self:serialize(v, indent + 1))
		end
		return "{\n" .. table.concat(parts, ",\n") .. "\n" .. pad .. "}"
	end

	return "{}"
end

return parser

end

__linker_modules["tests/lexertest.lua"] = function()
local shared = __linker_shared
return [==[
    local identifer = "this is a string!"

    local keyword = print

    keyword(identifer)

    if true then
        --[[
            This is inside a comment!!!
        ]]
    end

    local m = "h" .. "i"
    local isHi = m == "hi"
]==]

end

-- [[ entry point: main.lua ]]
-- Main file is built with ext/Builder.exe
local lexer = __linker_require("src/lexer.lua")
local parser = __linker_require("src/parser.lua")

local source = __linker_require("tests/lexertest.lua")
local tokens = lexer.new(source):run()

local parserObject = parser.new(tokens)

local ast = parserObject:run()

parserObject:dump(ast)

