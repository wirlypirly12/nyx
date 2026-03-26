--!nolint
-- [[ linker bundled output ]]
-- built   : 2026-03-26 00:28:11
-- entry   : main.lua
-- inlined : 6 module(s) + entry

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

function lexer.new(source)
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
				level = level + 1
				i = i + 1
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
							close_level = close_level + 1
							j = j + 1
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
		if self.char == "e" or self.char == "E" then
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

function parser.new(tokens)
	local self = setmetatable({
		tokens = tokens,
		pos = 1,
	}, parser)

	return self
end

function parser:peek(offset)
	offset = offset or 0
	local t = self.tokens[self.pos + offset]
	return t or { type = "EOF", value = nil } -- if the specified token doesn't exist, we probably hit EOF
end

function parser:advance()
	local t = self.tokens[self.pos]
	self.pos = self.pos + 1
	return t
end

function parser:match(type, value)
	local t = self:peek()
	if t.type == type and (value == nil or t.value == value) then
		return self:advance()
	end
	return nil
end

function parser:expect(type, value)
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
	for i, v in stop_at do
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

function parser:parse_for()
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
		-- for x, x in x do
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
		return { kind = "GenericFor", names = names, iterators = itr, body = body }
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

function parser:serialize(node, indent)
	indent = indent or 0
	local pad = string.rep("    ", indent)
	local inner = string.rep("    ", indent + 1)

	if type(node) ~= "table" then
		return tostring(node)
	end

	if node.kind then
		local parts = {}
		for k, v in node do
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
		for i, v in node do
			table.insert(parts, inner .. self:serialize(v, indent + 1))
		end
		return "{\n" .. table.concat(parts, ",\n") .. "\n" .. pad .. "}"
	end

	return "{}"
end

return parser

end

__linker_modules["src/opcodes.lua"] = function()
local shared = __linker_shared
local OPCODES = {}
local OPNAMES = {
	-- constants / stack
	"LOAD_CONST", -- push constants[arg] onto stack
	"LOAD_LOCAL", -- push locals[arg] onto stack
	"STORE_LOCAL", -- pop stack into locals[arg]
	"LOAD_GLOBAL", -- push globals[constants[arg]] onto stack
	"LOAD_UPVALUE",
	"STORE_GLOBAL", -- pop stack into globals[constants[arg]]
	"PUSH_NIL", -- push nil
	"PUSH_TRUE", -- push true
	"PUSH_FALSE", -- push false
	"POP", -- discard top of stack
	"CALL_MULTI",

	-- arithmetic
	"ADD",
	"SUB",
	"MUL",
	"DIV",
	"MOD",
	"POW",
	"IDIV",
	"UNM", -- unary minus

	-- string
	"CONCAT", -- concat top two stack values

	-- logic
	"AND",
	"OR",
	"NOT",

	-- comparison (push true/false onto stack)
	"EQ",
	"NEQ",
	"LT",
	"LTE",
	"GT",
	"GTE",
	"LEN", -- # operator

	-- control flow
	"JUMP", -- unconditional jump to arg
	"JUMP_IF_FALSE", -- pop stack, jump to arg if false

	-- tables
	"NEW_TABLE", -- push a new empty table
	"SET_FIELD", -- table[constants[arg]] = pop()
	"GET_FIELD", -- push table[constants[arg]]
	"SET_INDEX", -- table[pop()] = pop()
	"GET_INDEX", -- push table[pop()]

	-- functions
	"CLOSURE", -- push a new function from chunk[arg]
	"CALL", -- call function with arg arguments
	"RETURN", -- return arg values from top of stack

	-- misc
	"MOVE", -- copy locals[arg1] into locals[arg2]
	"VARARG", -- push varargs onto stack
}

for i = 1, #OPNAMES do
	OPCODES[OPNAMES[i]] = i
end

return {
	CODES = OPCODES,
	NAMES = OPNAMES,
}

end

__linker_modules["src/compiler.lua"] = function()
local shared = __linker_shared
local compiler = {}
compiler.__index = compiler

local OPCODES, OPNAMES
do
	local export = __linker_require("src/opcodes.lua")
	OPCODES = export.CODES
	OPNAMES = export.NAMES
end

function compiler.new()
	local self = setmetatable({
		chunk = {
			code = {}, -- bytecode instructions
			constants = {}, -- number/string literals
			locals = {}, -- name -> register index
			num_locals = 0,
			scope_stack = {},
		},
	}, compiler)

	return self
end

function compiler:push_scope()
	table.insert(self.chunk.scope_stack, {})
end

function compiler:pop_scope()
	local scope = table.remove(self.chunk.scope_stack)
	for name, info in scope do
		self.chunk.locals[name] = info.prev
		self.chunk.num_locals -= 1
	end
end
function compiler:emit(op, ...)
	local args = { ... }
	table.insert(self.chunk.code, op)
	for i, v in args do
		table.insert(self.chunk.code, v)
	end
end

function compiler:add_constant(value)
	for i, v in self.chunk.constants do
		if v == value then
			return i - 1 -- reuse constants
		end
	end
	table.insert(self.chunk.constants, value)
	return #self.chunk.constants - 1
end

function compiler:add_local(name)
	local reg = self.chunk.num_locals
	local scope = self.chunk.scope_stack[#self.chunk.scope_stack]
	-- store previous value so we can restore it on pop
	if scope then
		scope[name] = { reg = reg, prev = self.chunk.locals[name] }
	end
	self.chunk.locals[name] = reg
	self.chunk.num_locals = self.chunk.num_locals + 1
	return reg
end
function compiler:get_local(name)
	return self.chunk.locals[name]
end

function compiler:run(node)
	if node == nil then
		error("compiler:run() called with nil node")
	end
	if node.kind == nil then
		error("compiler:run() called with node missing 'kind': " .. tostring(node))
	end

	local handler = {
		Block = function(n)
			self:block(n)
		end,
		LocalStatement = function(n)
			self:_local(n)
		end,
		Assignment = function(n)
			self:assign(n)
		end,
		IfStatement = function(n)
			self:_if(n)
		end,
		WhileStatement = function(n)
			self:_while(n)
		end,
		ReturnStatement = function(n)
			self:_return(n)
		end,
		CallStatement = function(n)
			if n.expr.kind == "MethodCall" then
				self:_method_call(n.expr)
			else
				self:call(n.expr)
			end
			-- self:emit(OPCODES.POP)
		end,
		BinaryExpr = function(n)
			self:binary(n)
		end,
		UnaryExpr = function(n)
			self:unary(n)
		end,
		Number = function(n)
			self:number(n)
		end,
		String = function(n)
			self:string(n)
		end,
		Boolean = function(n)
			self:boolean(n)
		end,
		Nil = function(n)
			self:emit(OPCODES.PUSH_NIL)
		end,
		Identifier = function(n)
			self:identifier(n)
		end,
		CallExpr = function(n)
			self:call(n)
		end,
		FieldAccess = function(n)
			self:field_access(n)
		end,
		IndexAccess = function(n)
			self:index_access(n)
		end,
		Grouped = function(n)
			self:run(n.expr)
		end,
		DoStatement = function(n)
			self:_do(n)
		end,
		LocalFunction = function(n)
			self:local_function(n)
		end,
		FunctionStatement = function(n)
			self:function_statement(n)
		end,
		Function = function(n)
			self:_function(n)
		end,
		RepeatStatement = function(n)
			self:_repeat(n)
		end,
		NumericFor = function(n)
			self:numeric_for(n)
		end,
		GenericFor = function(n)
			self:generic_for(n)
		end,
		MethodCall = function(n)
			self:method_call(n)
			-- self:emit(OPCODES.POP)
		end,
		Table = function(n)
			self:_table(n)
		end,
		Break = function(n)
			self:_break(n)
		end,
	}
	local h = handler[node.kind]
	if h then
		h(node)
	else
		error(`unknown node kind: {node.kind}`)
	end
end

function compiler:block(node)
	self:push_scope()
	for _, stmt in node.body do
		self:run(stmt)
	end
	self:pop_scope()
end

function compiler:number(node)
	local idx = self:add_constant(node.value)
	self:emit(OPCODES.LOAD_CONST, idx)
end

function compiler:string(node)
	local idx = self:add_constant(node.value)
	self:emit(OPCODES.LOAD_CONST, idx)
end

function compiler:boolean(node)
	self:emit(node.value and OPCODES.PUSH_TRUE or OPCODES.PUSH_FALSE)
end

function compiler:identifier(node)
	local reg = self:get_local(node.name)
	if reg then
		self:emit(OPCODES.LOAD_LOCAL, reg)
	else
		local idx = self:add_constant(node.name)
		self:emit(OPCODES.LOAD_GLOBAL, idx)
	end
end

function compiler:_local(node)
	-- compile values then connect names to values
	for i, name in node.names do
		local value = node.values[i]
		if value then
			self:run(value)
		else
			self:emit(OPCODES.PUSH_NIL) -- uninitialized locals default to nil
		end
		self:add_local(name)
		self:emit(OPCODES.STORE_LOCAL, self:get_local(name))
	end
end

function compiler:assign(node)
	if node.target.kind == "FieldAccess" then
		self:run(node.target.object) -- push table
		self:run(node.values[1]) -- push value
		local idx = self:add_constant(node.target.field)
		self:emit(OPCODES.SET_FIELD, idx)
	elseif node.target.kind == "IndexAccess" then
		self:run(node.target.object) -- push table
		self:run(node.target.index) -- push key
		self:run(node.values[1]) -- push value
		self:emit(OPCODES.SET_INDEX)
	else
		-- simple name assignment (existing logic)
		self:run(node.values[1])
		local reg = self:get_local(node.target.name)
		if reg then
			self:emit(OPCODES.STORE_LOCAL, reg)
		else
			local idx = self:add_constant(node.target.name)
			self:emit(OPCODES.STORE_GLOBAL, idx)
		end
	end
end

function compiler:binary(node)
	self:run(node.left)
	self:run(node.right)

	local ops = {
		["+"] = OPCODES.ADD,
		["-"] = OPCODES.SUB,
		["*"] = OPCODES.MUL,
		["/"] = OPCODES.DIV,
		["%"] = OPCODES.MOD,
		["^"] = OPCODES.POW,
		["//"] = OPCODES.IDIV,
		["=="] = OPCODES.EQ,
		["~="] = OPCODES.NEQ,
		["<"] = OPCODES.LT,
		["<="] = OPCODES.LTE,
		[">"] = OPCODES.GT,
		[">="] = OPCODES.GTE,
		["and"] = OPCODES.AND,
		["or"] = OPCODES.OR,
		[".."] = OPCODES.CONCAT,
	}
	local op = ops[node.op]
	if not op then
		error(`unknown operator: {node.op}`)
	end
	self:emit(op)
end

function compiler:unary(node)
	self:run(node.operand)
	local ops = {
		["-"] = OPCODES.UNM,
		["not"] = OPCODES.NOT,
		["#"] = OPCODES.LEN,
	}
	local op = ops[node.op]
	if not op then
		error(`unknown unary op: {node.op}`)
	end
	self:emit(op)
end

function compiler:_do(node)
	self:push_scope()
	self:run(node.body)
	self:pop_scope()
end

function compiler:_if(node)
	self:run(node.condition)
	local jump_false = #self.chunk.code + 1
	self:emit(OPCODES.JUMP_IF_FALSE, 0)

	self:push_scope()
	self:run(node.body)
	self:pop_scope()

	local jump_end = #self.chunk.code + 1
	self:emit(OPCODES.JUMP, 0)
	self.chunk.code[jump_false + 1] = #self.chunk.code + 1

	for _, ei in node.elseifs do
		self:push_scope()
		self:run(ei.body)
		self:pop_scope()
	end

	if node.else_body then
		self:push_scope()
		self:run(node.else_body)
		self:pop_scope()
	end

	self.chunk.code[jump_end + 1] = #self.chunk.code + 1
end

function compiler:_function(node)
	if node == nil then
		error("_function called with nil node")
	end
	if node.body == nil then
		error("_function called with nil body, node kind: " .. tostring(node.kind))
	end

	-- create a new compiler for the func body
	local sub = compiler.new()
	-- add params as locals in the sub compiler
	for i, param in node.params do
		sub:add_local(param)
	end
	sub:push_scope()
	sub:run(node.body)
	sub:pop_scope()
	-- store the sub chunk as a constant and emit CLOSURE
	local idx = self:add_constant(sub.chunk)
	self:emit(OPCODES.CLOSURE, idx)
end

function compiler:local_function(node)
	self:add_local(node.name)
	self:_function(node.func)
	self:emit(OPCODES.STORE_LOCAL, self:get_local(node.name))
end

function compiler:function_statement(node)
	if node.func == nil then
		error("function_statement: node.func is nil, name: " .. tostring(node.name[1]))
	end

	self:_function(node.func)

	if #node.name == 1 then
		local reg = self:get_local(node.name[1])
		if reg then
			self:emit(OPCODES.STORE_LOCAL, reg)
		else
			local idx = self:add_constant(node.name[1])
			self:emit(OPCODES.STORE_GLOBAL, idx)
		end
	else
		-- load base object, checking locals first
		local reg = self:get_local(node.name[1])
		if reg then
			self:emit(OPCODES.LOAD_LOCAL, reg)
		else
			local base_idx = self:add_constant(node.name[1])
			self:emit(OPCODES.LOAD_GLOBAL, base_idx)
		end
		-- traverse middle chain
		for i = 2, #node.name - 1 do
			local idx = self:add_constant(node.name[i])
			self:emit(OPCODES.GET_FIELD, idx)
		end
		-- store into final field
		local last_idx = self:add_constant(node.name[#node.name])
		self:emit(OPCODES.SET_FIELD, last_idx)
	end
end

function compiler:_repeat(node)
	local loop_start = #self.chunk.code + 1
	self:push_scope()
	self:run(node.body)
	self:run(node.condition) -- condition is checked at the end
	self:pop_scope()
	self:emit(OPCODES.NOT) -- repeat until condition is true
	self:emit(OPCODES.JUMP_IF_FALSE, loop_start + 1)
end

function compiler:numeric_for(node)
	self:push_scope()

	self:run(node.start)
	local i_reg = self:add_local(node.name)
	self:emit(OPCODES.STORE_LOCAL, i_reg)

	self:run(node.limit)
	local limit_reg = self:add_local("__limit__")
	self:emit(OPCODES.STORE_LOCAL, limit_reg)

	if node.step then
		self:run(node.step)
	else
		self:emit(OPCODES.LOAD_CONST, self:add_constant(1))
	end
	local step_reg = self:add_local("__step__")
	self:emit(OPCODES.STORE_LOCAL, step_reg)

	-- check step > 0 once
	self:emit(OPCODES.LOAD_LOCAL, step_reg)
	self:emit(OPCODES.LOAD_CONST, self:add_constant(0))
	self:emit(OPCODES.GT)
	local jump_neg = #self.chunk.code + 1
	self:emit(OPCODES.JUMP_IF_FALSE, 0)

	-- while i<= limit
	local pos_start = #self.chunk.code + 1
	self:emit(OPCODES.LOAD_LOCAL, i_reg)
	self:emit(OPCODES.LOAD_LOCAL, limit_reg)
	self:emit(OPCODES.LTE)
	local pos_exit = #self.chunk.code + 1
	self:emit(OPCODES.JUMP_IF_FALSE, 0)
	self:run(node.body)
	self:emit(OPCODES.LOAD_LOCAL, i_reg)
	self:emit(OPCODES.LOAD_LOCAL, step_reg)
	self:emit(OPCODES.ADD)
	self:emit(OPCODES.STORE_LOCAL, i_reg)
	self:emit(OPCODES.JUMP, pos_start)
	self.chunk.code[pos_exit + 1] = #self.chunk.code + 1

	-- jump over negative loop
	local jump_over_neg = #self.chunk.code + 1
	self:emit(OPCODES.JUMP, 0)

	-- while i >= limit
	self.chunk.code[jump_neg + 1] = #self.chunk.code + 1
	local neg_start = #self.chunk.code + 1
	self:emit(OPCODES.LOAD_LOCAL, i_reg)
	self:emit(OPCODES.LOAD_LOCAL, limit_reg)
	self:emit(OPCODES.GTE)
	local neg_exit = #self.chunk.code + 1
	self:emit(OPCODES.JUMP_IF_FALSE, 0)
	self:run(node.body)
	self:emit(OPCODES.LOAD_LOCAL, i_reg)
	self:emit(OPCODES.LOAD_LOCAL, step_reg)
	self:emit(OPCODES.ADD)
	self:emit(OPCODES.STORE_LOCAL, i_reg)
	self:emit(OPCODES.JUMP, neg_start)
	self.chunk.code[neg_exit + 1] = #self.chunk.code + 1

	self.chunk.code[jump_over_neg + 1] = #self.chunk.code + 1
	self:pop_scope()
end

function compiler:generic_for(node)
	self:push_scope()

	for _, itr in node.iterators do
		if itr.kind == "CallExpr" then
			self:run(itr.callee)
			for _, arg in itr.args do
				self:run(arg)
			end
			self:emit(OPCODES.CALL_MULTI, #itr.args, 3)
		else
			self:run(itr)
		end
	end

	local var_reg = self:add_local("__var__")
	self:emit(OPCODES.STORE_LOCAL, var_reg)

	local state_reg = self:add_local("__state__")
	self:emit(OPCODES.STORE_LOCAL, state_reg)

	local func_reg = self:add_local("__func__")
	self:emit(OPCODES.STORE_LOCAL, func_reg)

	local loop_vars = {}
	for _, name in node.names do
		local reg = self:add_local(name)
		table.insert(loop_vars, reg)
		self:emit(OPCODES.PUSH_NIL)
		self:emit(OPCODES.STORE_LOCAL, reg)
	end

	local loop_start = #self.chunk.code + 1

	self:emit(OPCODES.LOAD_LOCAL, func_reg)
	self:emit(OPCODES.LOAD_LOCAL, state_reg)
	self:emit(OPCODES.LOAD_LOCAL, var_reg)
	self:emit(OPCODES.CALL_MULTI, 2, #loop_vars)

	for i = #loop_vars, 1, -1 do
		self:emit(OPCODES.STORE_LOCAL, loop_vars[i])
	end

	self:emit(OPCODES.LOAD_LOCAL, loop_vars[1])
	self:emit(OPCODES.STORE_LOCAL, var_reg)

	self:emit(OPCODES.LOAD_LOCAL, loop_vars[1])
	local jump_out = #self.chunk.code + 1
	self:emit(OPCODES.JUMP_IF_FALSE, 0)

	self:run(node.body)
	self:emit(OPCODES.JUMP, loop_start)

	self.chunk.code[jump_out + 1] = #self.chunk.code + 1

	self:pop_scope()
end
function compiler:_method_call(node)
	self:run(node.object)

	local tmp = self:add_local("__self__")
	self:emit(OPCODES.STORE_LOCAL, tmp)

	-- get the method from the object
	self:emit(OPCODES.LOAD_LOCAL, tmp)
	local idx = self:add_constant(node.method)
	self:emit(OPCODES.GET_FIELD, idx) -- push the method

	-- push object as first argument (self)
	self:emit(OPCODES.LOAD_LOCAL, tmp)

	for _, arg in node.args do
		self:run(arg)
	end
	self:emit(OPCODES.CALL, #node.args + 1) -- +1 for implicit self

	-- clean up temp
	self.chunk.locals["__self__"] = nil
	self.chunk.num_locals -= 1
end

function compiler:_table(node)
	self:emit(OPCODES.NEW_TABLE)
	self:push_scope()
	local tbl_reg = self:add_local("__tbl__")
	self:emit(OPCODES.STORE_LOCAL, tbl_reg)

	for i, field in node.fields do
		self:emit(OPCODES.LOAD_LOCAL, tbl_reg)
		if field.kind == "NamedField" then
			self:run(field.value)
			local idx = self:add_constant(field.key)
			self:emit(OPCODES.SET_FIELD, idx)
		elseif field.kind == "IndexedField" then
			self:run(field.key)
			self:run(field.value)
			self:emit(OPCODES.SET_INDEX)
		elseif field.kind == "ValueField" then
			local idx = self:add_constant(i)
			self:emit(OPCODES.LOAD_CONST, idx)
			self:run(field.value)
			self:emit(OPCODES.SET_INDEX)
		end
	end

	self:emit(OPCODES.LOAD_LOCAL, tbl_reg)
	self:pop_scope()
end

function compiler:_while(node)
	local loop_start = #self.chunk.code + 1
	self:run(node.condition)
	local jump_false = #self.chunk.code + 1
	self:emit(OPCODES.JUMP_IF_FALSE, 0)

	self.chunk.break_jumps = {} -- collect breaks
	self:push_scope()
	self:run(node.body)
	self:pop_scope()

	self:emit(OPCODES.JUMP, loop_start)
	self.chunk.code[jump_false + 1] = #self.chunk.code + 1

	-- patch all breaks to here
	for _, jump in self.chunk.break_jumps do
		self.chunk.code[jump + 1] = #self.chunk.code + 1
	end
	self.chunk.break_jumps = nil
end

function compiler:_return(node)
	for _, v in node.values do
		self:run(v)
	end
	self:emit(OPCODES.RETURN, #node.values)
end

function compiler:call(node)
	self:run(node.callee)
	for _, arg in node.args do
		self:run(arg)
	end
	self:emit(OPCODES.CALL, #node.args)
end

function compiler:field_access(node)
	self:run(node.object)
	local idx = self:add_constant(node.field)
	self:emit(OPCODES.GET_FIELD, idx)
end

function compiler:index_access(node)
	self:run(node.object)
	self:run(node.index)
	self:emit(OPCODES.GET_INDEX)
end

function compiler:dump(copy)
	local chunk = self.chunk
	local output = ""
	output ..= "=== CHUNK DUMP ===\n"

	-- constants
	output ..= ("CONSTANTS (" .. #chunk.constants .. ")")
	for i, v in chunk.constants do
		print(string.format("  [%d] %-10s %s", i - 1, type(v), tostring(v)))
	end

	-- locals
	output ..= ("\nLOCALS (" .. chunk.num_locals .. ")")
	for name, reg in chunk.locals do
		print(string.format("  [%d] %s", reg, name))
	end

	-- bytecode
	output ..= ("\nBYTECODE (" .. #chunk.code .. " instructions)")
	local i = 1
	while i <= #chunk.code do
		local op = chunk.code[i]
		local name = OPNAMES[op] or ("UNKNOWN(" .. tostring(op) .. ")")

		-- opcodes that consume the next value as an argument
		local has_arg = {
			LOAD_CONST = true,
			LOAD_LOCAL = true,
			STORE_LOCAL = true,
			LOAD_GLOBAL = true,
			STORE_GLOBAL = true,
			JUMP = true,
			JUMP_IF_FALSE = true,
			CALL = true,
			RETURN = true,
			GET_FIELD = true,
			SET_FIELD = true,
			CLOSURE = true,
			MOVE = true,
		}

		if has_arg[name] then
			local arg = chunk.code[i + 1]
			-- if its a constant referencing op, show the value too
			local extra = ""
			if
				(name == "LOAD_CONST" or name == "LOAD_GLOBAL" or name == "STORE_GLOBAL" or name == "GET_FIELD")
				and chunk.constants[arg + 1]
			then
				extra = " ; " .. tostring(chunk.constants[arg + 1])
			end
			output ..= (string.format("  [%03d] %-20s %d%s\n", i, name, arg, extra))
			i = i + 2
		else
			output ..= (string.format("  [%03d] %-20s\n", i, name))
			i = i + 1
		end
	end

	output ..= "\n=================="

	print(output)
	if copy then
		setclipboard(output)
	end
end

return compiler

end

__linker_modules["tests/allOpcodes.lua"] = function()
local shared = __linker_shared
return [[
local a = 10
local b = 3
local add = a + b
local sub = a - b
local mul = a * b
local div = a / b
local mod = a % b
local idiv = a // b
local pow = a ^ b
local unm = -a
print(add, sub, mul, div, mod, idiv, pow, unm)

-- string concat and len
local s = "hello" .. " " .. "world"
local l = #s
print(s, l)

-- booleans and logic
local t = true
local f = false
print(t and f, t or f, not t)

-- comparisons
print(a == b, a ~= b, a < b, a <= b, a > b, a >= b)

-- nil
local n = nil
print(n)

-- if / elseif / else
if a > 5 then
	print("a > 5")
elseif a == 5 then
	print("a == 5")
else
	print("a < 5")
end

-- while
local i = 0
while i < 3 do
	print("while", i)
	i = i + 1
end

-- repeat until
local j = 0
repeat
	print("repeat", j)
	j = j + 1
until j >= 3

-- numeric for positive step
for x = 1, 3 do
	print("for+", x)
end

-- numeric for negative step
for x = 3, 1, -1 do
	print("for-", x)
end

-- tables
local tbl = {
	["key"] = "value",
	name = "carter",
	[1] = "indexed",
}
print(tbl["key"], tbl.name, tbl[1])

-- table set/get index
tbl["dynamic"] = "yes"
print(tbl["dynamic"])

-- generic for
local counts = { a = 1, b = 2, c = 3 }
for k, v in pairs(counts) do
	print("pairs", k, v)
end

-- functions
local function add2(x, y)
	return x + y
end
print(add2(10, 20))

-- closures / local function
local function outer(x)
	local function inner(y)
		return x + y
	end
	return inner(5)
end
print(outer(10))

-- do block scoping
do
	local scoped = "inside"
	print(scoped)
end

-- multiple return values
local function multi()
	return 1, 2, 3
end
local r1, r2, r3 = multi()
print(r1, r2, r3)

-- global function
function myGlobal(x)
	return x * 2
end
print(myGlobal(7))

]]

end

__linker_modules["src/vm.lua"] = function()
local shared = __linker_shared
local vm = {}
vm.__index = vm

local OPCODES, OPNAMES
do
	local export = __linker_require("src/opcodes.lua")
	OPCODES = export.CODES
	OPNAMES = export.NAMES
end

function vm.new(chunk)
	local self = setmetatable({
		chunk = chunk,
		globals = {},
	}, vm)

	return self
end

-- standard library
function vm:load_stdlib()
	-- god have mercy on my soul!!!
	self.globals["print"] = print
	self.globals["tostring"] = tostring
	self.globals["tonumber"] = tonumber
	self.globals["type"] = type
	self.globals["error"] = error
	self.globals["assert"] = assert
	self.globals["ipairs"] = ipairs
	self.globals["pairs"] = pairs
	self.globals["unpack"] = table.unpack or unpack
	self.globals["select"] = select
	self.globals["pcall"] = pcall
	self.globals["xpcall"] = xpcall
	self.globals["rawget"] = rawget
	self.globals["rawset"] = rawset
	self.globals["rawequal"] = rawequal
	self.globals["setmetatable"] = setmetatable
	self.globals["getmetatable"] = getmetatable
	self.globals["game"] = game

	self.globals["math"] = {
		floor = math.floor,
		ceil = math.ceil,
		sqrt = math.sqrt,
		abs = math.abs,
		max = math.max,
		min = math.min,
		pi = math.pi,
		huge = math.huge,
		random = math.random,
		randomseed = math.randomseed,
		sin = math.sin,
		cos = math.cos,
		tan = math.tan,
		pow = math.pow,
		log = math.log,
		exp = math.exp,
		fmod = math.fmod,
		modf = math.modf,
	}

	self.globals["string"] = {
		format = string.format,
		sub = string.sub,
		len = string.len,
		rep = string.rep,
		upper = string.upper,
		lower = string.lower,
		byte = string.byte,
		char = string.char,
		find = string.find,
		match = string.match,
		gmatch = string.gmatch,
		gsub = string.gsub,
		reverse = string.reverse,
	}

	self.globals["table"] = {
		insert = table.insert,
		remove = table.remove,
		concat = table.concat,
		sort = table.sort,
		unpack = table.unpack or unpack,
		move = table.move,
	}
end

-- create a new call frame
function vm:make_frame(chunk, args, upvalues)
	local frame = {
		chunk = chunk,
		ip = 1,
		locals = {},
		stack = {},
		top = 0,
		upvalues = upvalues or {},
	}
	if args then
		for i, v in ipairs(args) do
			frame.locals[i - 1] = v
		end
	end
	return frame
end
function vm:push(frame, value)
	frame.top = (frame.top or 0) + 1
	frame.stack[frame.top] = value
end

function vm:pop(frame)
	local val = frame.stack[frame.top]
	frame.stack[frame.top] = nil
	frame.top = frame.top - 1
	return val
end

function vm:peek_stack(frame)
	return frame.stack[frame.top]
end

function vm:execute(chunk, args, upvalues)
	local frame = self:make_frame(chunk, args, upvalues)

	while frame.ip <= #frame.chunk.code do
		local op = frame.chunk.code[frame.ip]

		-- load
		if op == OPCODES.LOAD_CONST then
			frame.ip += 1
			local idx = frame.chunk.code[frame.ip]
			self:push(frame, frame.chunk.constants[idx + 1])
		elseif op == OPCODES.LOAD_LOCAL then
			frame.ip += 1
			local reg = frame.chunk.code[frame.ip]
			self:push(frame, frame.locals[reg])
		elseif op == OPCODES.LOAD_GLOBAL then
			frame.ip += 1
			local idx = frame.chunk.code[frame.ip]
			local name = frame.chunk.constants[idx + 1]
			self:push(frame, self.globals[name])
		elseif op == OPCODES.LOAD_UPVALUE then
			frame.ip += 1
			local idx = frame.chunk.code[frame.ip]
			local name = frame.chunk.constants[idx + 1]
			self:push(frame, frame.upvalues and frame.upvalues[name] or nil)
		-- store
		elseif op == OPCODES.STORE_LOCAL then
			frame.ip += 1
			local reg = frame.chunk.code[frame.ip]
			frame.locals[reg] = self:pop(frame)
		elseif op == OPCODES.STORE_GLOBAL then
			frame.ip += 1
			local idx = frame.chunk.code[frame.ip]
			local name = frame.chunk.constants[idx + 1]
			self.globals[name] = self:pop(frame)

		-- push
		elseif op == OPCODES.PUSH_NIL then
			self:push(frame, nil)
		elseif op == OPCODES.PUSH_TRUE then
			self:push(frame, true)
		elseif op == OPCODES.PUSH_FALSE then
			self:push(frame, false)

		-- pop
		elseif op == OPCODES.POP then
			self:pop(frame)

		-- arithmetic
		elseif op == OPCODES.ADD then
			local b, a = self:pop(frame), self:pop(frame)
			self:push(frame, a + b)
		elseif op == OPCODES.SUB then
			local b, a = self:pop(frame), self:pop(frame)
			self:push(frame, a - b)
		elseif op == OPCODES.MUL then
			local b, a = self:pop(frame), self:pop(frame)
			self:push(frame, a * b)
		elseif op == OPCODES.DIV then
			local b, a = self:pop(frame), self:pop(frame)
			self:push(frame, a / b)
		elseif op == OPCODES.MOD then
			local b, a = self:pop(frame), self:pop(frame)
			self:push(frame, a % b)
		elseif op == OPCODES.IDIV then
			local b, a = self:pop(frame), self:pop(frame)
			self:push(frame, math.floor(a / b))
		elseif op == OPCODES.UNM then
			self:push(frame, -self:pop(frame))
		elseif op == OPCODES.POW then
			local b, a = self:pop(frame), self:pop(frame)
			self:push(frame, a ^ b)
		-- string
		elseif op == OPCODES.CONCAT then
			local b, a = self:pop(frame), self:pop(frame)
			self:push(frame, a .. b)
		elseif op == OPCODES.LEN then
			self:push(frame, #self:pop(frame))

		-- logic
		elseif op == OPCODES.AND then
			local b, a = self:pop(frame), self:pop(frame)
			self:push(frame, a and b)
		elseif op == OPCODES.OR then
			local b, a = self:pop(frame), self:pop(frame)
			self:push(frame, a or b)
		elseif op == OPCODES.NOT then
			self:push(frame, not self:pop(frame))

		-- cmp
		elseif op == OPCODES.EQ then
			local b, a = self:pop(frame), self:pop(frame)
			self:push(frame, a == b)
		elseif op == OPCODES.NEQ then
			local b, a = self:pop(frame), self:pop(frame)
			self:push(frame, a ~= b)
		elseif op == OPCODES.LT then
			local b, a = self:pop(frame), self:pop(frame)
			self:push(frame, a < b)
		elseif op == OPCODES.LTE then
			local b, a = self:pop(frame), self:pop(frame)
			self:push(frame, a <= b)
		elseif op == OPCODES.GT then
			local b, a = self:pop(frame), self:pop(frame)
			self:push(frame, a > b)
		elseif op == OPCODES.GTE then
			local b, a = self:pop(frame), self:pop(frame)
			self:push(frame, a >= b)

		-- control flow
		elseif op == OPCODES.JUMP then
			frame.ip += 1
			local target = frame.chunk.code[frame.ip]
			frame.ip = target
			continue
		elseif op == OPCODES.JUMP_IF_FALSE then
			frame.ip += 1
			local target = frame.chunk.code[frame.ip]
			local val = self:pop(frame)
			if not val then
				frame.ip = target
				continue
			end

		-- tables
		elseif op == OPCODES.NEW_TABLE then
			self:push(frame, {})
		elseif op == OPCODES.SET_FIELD then
			frame.ip += 1
			local idx = frame.chunk.code[frame.ip]
			local key = frame.chunk.constants[idx + 1]
			local val = self:pop(frame)
			local tbl = self:peek_stack(frame) -- keep the table on the stack
			tbl[key] = val
		elseif op == OPCODES.GET_FIELD then
			frame.ip += 1
			local idx = frame.chunk.code[frame.ip]
			local key = frame.chunk.constants[idx + 1]
			local tbl = self:pop(frame)
			self:push(frame, tbl[key])
		elseif op == OPCODES.SET_INDEX then
			local val = self:pop(frame)
			local key = self:pop(frame)
			local tbl = self:peek_stack(frame) -- keep the table on the stack
			tbl[key] = val
		elseif op == OPCODES.GET_INDEX then
			local key = self:pop(frame)
			local tbl = self:pop(frame)
			self:push(frame, tbl[key])

		-- closures
		elseif op == OPCODES.CLOSURE then
			frame.ip += 1
			local idx = frame.chunk.code[frame.ip]
			local sub_chunk = frame.chunk.constants[idx + 1]
			local f_upvalues = {}
			-- capture by name using the chunk's constants as a guide
			for name, reg in pairs(frame.chunk.locals) do
				f_upvalues[name] = frame.locals[reg]
			end
			-- also inherit any upvalues from the current frame
			if frame.upvalues then
				for k, v in pairs(frame.upvalues) do
					if f_upvalues[k] == nil then
						f_upvalues[k] = v
					end
				end
			end
			self:push(frame, {
				__type = "function",
				chunk = sub_chunk,
				upvalues = f_upvalues,
			})
		elseif op == OPCODES.CALL then
			frame.ip += 1
			local arg_count = frame.chunk.code[frame.ip]
			local f_args = {}
			for i = arg_count, 1, -1 do
				f_args[i] = self:pop(frame)
			end
			local func = self:pop(frame)
			if type(func) == "function" then
				local result = table.pack(func(table.unpack(f_args)))
				-- only push first return value for normal calls
				self:push(frame, result[1])
			elseif type(func) == "table" and func.__type == "function" then
				local result = self:execute(func.chunk, f_args, func.upvalues)
				if result then
					self:push(frame, result[1])
				else
					self:push(frame, nil)
				end
			else
				error(`attempt to call a {type(func)} value`)
			end
		elseif op == OPCODES.CALL_MULTI then
			frame.ip += 1
			local arg_count = frame.chunk.code[frame.ip]
			local expected = frame.chunk.code[frame.ip + 1] -- add expected count to opcode
			frame.ip += 1
			local f_args = {}
			for i = arg_count, 1, -1 do
				f_args[i] = self:pop(frame)
			end
			local func = self:pop(frame)
			if type(func) == "function" then
				local result = table.pack(func(table.unpack(f_args)))
				for i = 1, expected do
					self:push(frame, result[i]) -- result[i] is nil if i > result.n, which is fine
				end
			elseif type(func) == "table" and func.__type == "function" then
				local result = self:execute(func.chunk, f_args, func.upvalues) or {}
				for i = 1, expected do
					self:push(frame, result[i])
				end
			else
				error(`attempt to call a {type(func)} value`)
			end
		elseif op == OPCODES.RETURN then
			frame.ip += 1
			local count = frame.chunk.code[frame.ip]
			local results = {}
			for i = count, 1, -1 do
				results[i] = self:pop(frame)
			end
			return results
		else
			error(`unknown operation: {op} ({OPNAMES[op] or "?"}) at instruction: {frame.ip}`)
		end

		frame.ip += 1
	end
	return nil
end

function vm:run()
	return self:execute(self.chunk)
end

return vm

end

-- [[ entry point: main.lua ]]
-- Main file is built with ext/Builder.exe
local lexer = __linker_require("src/lexer.lua")
local parser = __linker_require("src/parser.lua")
local compiler = __linker_require("src/compiler.lua")
local source = __linker_require("tests/allOpcodes.lua")
local vm = __linker_require("src/vm.lua")

local tokens = lexer.new(source):run()

local parserObject = parser.new(tokens)

local ast = parserObject:run()
local compObject = compiler.new()

compObject:run(ast)
compObject:dump()
local vmObj = vm.new(compObject.chunk)
vmObj:load_stdlib()
vmObj:run()

