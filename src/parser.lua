-- MIT License
-- Copyright (c) 2026 Bradley

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
	["^"] = 7,
}
local RIGHT_ASSOC = { ["^"] = true, [".."] = true }

local VALID_ATTRIBUTES = {
	unroll = { targets = { NumericFor = true }, arg = "number" },
	inline = { targets = { LocalFunction = true, FunctionStatement = true }, arg = "none" },
	cold = { targets = { LocalFunction = true, FunctionStatement = true }, arg = "none" },
	const = { targets = { LocalStatement = true, __directive = true }, arg = "none" },
	define = { targets = { __directive = true }, arg = "macro" },
	memoize = { targets = { LocalFunction = true, FunctionStatement = true }, arg = "none" },
	likely = { targets = { IfStatement = true }, arg = "none" },
	unlikely = { targets = { IfStatement = true }, arg = "none" },
}

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
	return t or { type = "EOF", value = nil }
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

function parser:parse_attributes()
	local attrs = {}
	while self:peek().type == "ATTRIBUTE" do
		local tok = self:advance()
		local name = tok.value
		local line = tok.line

		if name == "const" then
			local const_name = self:expect("IDENTIFIER").value
			self:expect("OPERATOR", "=")
			local value = self:parse_expression()
			return nil,
				{
					kind = "LocalStatement",
					names = { const_name },
					values = { value },
					attributes = { { name = "const", line = line } },
				}
		end

		if name == "define" then
			local macro_name = self:expect("IDENTIFIER").value
			local params = {}
			if self:peek().value == "(" then
				self:advance()
				if self:peek().value ~= ")" then
					table.insert(params, self:expect("IDENTIFIER").value)
					while self:match("SYMBOL", ",") do
						table.insert(params, self:expect("IDENTIFIER").value)
					end
				end
				self:expect("SYMBOL", ")")
			end
			local body_tokens = {}
			local def_line = self:peek().line
			while self:peek().type ~= "EOF" and self:peek().line == def_line do
				table.insert(body_tokens, self:advance())
			end
			return nil,
				{
					kind = "DefineDirective",
					name = macro_name,
					params = params,
					body_tokens = body_tokens,
					line = line,
				}
		end

		if not VALID_ATTRIBUTES[name] then
			local hint = ""
			for k in VALID_ATTRIBUTES do
				if k:sub(1, #name) == name or name:sub(1, #k) == k then
					hint = ` (did you mean '@{k}'?)`
					break
				end
			end
			error(`unknown attribute '@{name}' at line {line}{hint}`)
		end

		table.insert(attrs, { name = name, line = line })
	end
	return attrs, nil
end

function parser:attach_attributes(node, attrs)
	if not attrs or #attrs == 0 then
		node.attributes = {}
		return node
	end
	for _, attr in attrs do
		local info = VALID_ATTRIBUTES[attr.name]
		if not info.targets[node.kind] then
			local valid_list = {}
			for k in info.targets do
				table.insert(valid_list, k)
			end
			error(
				`'@{attr.name}' cannot be applied to '{node.kind}' at line {attr.line} `
					.. `(valid targets: {table.concat(valid_list, ", ")})`
			)
		end
	end
	node.attributes = attrs
	return node
end

function parser:parse_local()
	self:expect("KEYWORD", "local")

	if self:peek().type == "KEYWORD" and self:peek().value == "function" then
		self:advance()
		local name = self:expect("IDENTIFIER").value
		local func = self:parse_function_body()
		return { kind = "LocalFunction", name = name, func = func }
	end

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
		local stmt = self:parse_statement()
		table.insert(statements, stmt)
		self:match("SYMBOL", ";")

		if stmt.kind == "ReturnStatement" then
			break
		end
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
		local names = { name }
		while self:match("SYMBOL", ",") do
			table.insert(names, self:expect("IDENTIFIER").value)
		end
		self:expect("KEYWORD", "in")
		local itr = { self:parse_expression() }
		while self:match("SYMBOL", ",") do
			table.insert(itr, self:parse_expression())
		end

		if #itr == 1 and itr[1].kind ~= "CallExpr" and itr[1].kind ~= "MethodCall" then
			local tbl_expr = itr[1]
			itr = {
				{ kind = "Identifier", name = "next" },
				tbl_expr,
				{ kind = "Nil" },
			}
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
		table.insert(params, "self")
	end
	if self:peek().value ~= ")" then
		if self:peek().value == "..." then
			self:advance()
			table.insert(params, "...")
		else
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

	local t = self:peek()
	local stop = t.type == "EOF"
		or t.value == "end"
		or t.value == "else"
		or t.value == "elseif"
		or t.value == "until"
		or (t.type == "SYMBOL" and t.value == ";")
	if not stop then
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
		elseif t.type == "STRING" then
			self:advance()
			node = { kind = "CallExpr", callee = node, args = { { kind = "String", value = t.value } } }
		elseif t.value == "{" then
			local tbl = self:parse_table()
			node = { kind = "CallExpr", callee = node, args = { tbl } }
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

	if t.type == "OPERATOR" and t.value == "..." then
		self:advance()
		return { kind = "Identifier", name = "..." }
	end

	error(`unexpected token '{t.value}' (type={t.type}) at line {t.line}`)
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
			local key = self:advance().value
			self:advance()
			local value = self:parse_expression()
			table.insert(fields, { kind = "NamedField", key = key, value = value })
		else
			local value = self:parse_expression()
			table.insert(fields, { kind = "ValueField", value = value })
		end

		if not self:match("SYMBOL", ",") and not self:match("SYMBOL", ";") then
			break
		end
	end

	self:expect("SYMBOL", "}")
	return { kind = "Table", fields = fields }
end

function parser:parse_expression_statement()
	local expr = self:parse_postfix()

	local targets = { expr }
	while self:peek().value == "," do
		if expr.kind == "CallExpr" or expr.kind == "MethodCall" then
			break
		end
		self:advance()
		table.insert(targets, self:parse_postfix())
	end

	local op_tok = self:peek()
	if
		op_tok.value == "="
		or op_tok.value == "+="
		or op_tok.value == "-="
		or op_tok.value == "*="
		or op_tok.value == "/="
	then
		local op = self:advance().value
		local values = { self:parse_expression() }
		while self:match("SYMBOL", ",") do
			table.insert(values, self:parse_expression())
		end
		return { kind = "Assignment", targets = targets, op = op, values = values }
	end

	if expr.kind == "CallExpr" or expr.kind == "MethodCall" then
		return { kind = "CallStatement", expr = expr }
	end

	error("unexpected expression at line " .. tostring(self:peek().line))
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
	local attrs, directive = self:parse_attributes()
	if directive then
		return directive
	end

	local t = self:peek()
	local node

	if t.type == "KEYWORD" then
		if t.value == "local" then
			node = self:parse_local()
		elseif t.value == "if" then
			node = self:parse_if()
		elseif t.value == "while" then
			node = self:parse_while()
		elseif t.value == "for" then
			node = self:parse_for()
		elseif t.value == "return" then
			node = self:parse_return()
		elseif t.value == "function" then
			node = self:parse_function()
		elseif t.value == "do" then
			node = self:parse_do()
		elseif t.value == "repeat" then
			node = self:parse_repeat()
		elseif t.value == "break" then
			self:advance()
			node = { kind = "Break" }
		elseif t.value == "continue" then
			self:advance()
			node = { kind = "Continue" }
		end
	end

	if not node then
		node = self:parse_expression_statement()
	end

	return self:attach_attributes(node, attrs)
end

function parser:run()
	local statements = {}
	while self:peek().type ~= "EOF" do
		table.insert(statements, self:parse_statement())
		self:match("SYMBOL", ";")
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
