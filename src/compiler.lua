local compiler = {}
compiler.__index = compiler

local OPCODES = require("./opcodes")
local OPNAMES = {}

for i, v in OPCODES do
	OPNAMES[v] = i
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
	for name, info in pairs(scope) do
		self.chunk.locals[name] = info.prev
		self.chunk.num_locals -= 1
	end
end
function compiler:emit(op, ...)
	local args = { ... }
	table.insert(self.chunk.code, op)
	for i, v in ipairs(args) do
		table.insert(self.chunk.code, v)
	end
end

function compiler:add_constant(value)
	for i, v in ipairs(self.chunk.constants) do
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
	self.chunk.num_locals += 1
	return reg
end
function compiler:get_local(name)
	return self.chunk.locals[name]
end

function compiler:run(node)
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
			self:call(n.expr)
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
	for _, stmt in ipairs(node.body) do
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
	for i, name in ipairs(node.names) do
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
	self:run(node.values[1])
	local reg = self:get_local(node.target.name)
	if reg then
		self:emit(OPCODES.STORE_LOCAL, reg)
	else
		local idx = self:add_constant(node.target.name)
		self:emit(OPCODES.STORE_GLOBAL, idx)
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
	self.chunk.code[jump_false + 1] = #self.chunk.code

	for _, ei in ipairs(node.elseifs) do
		self:push_scope()
		self:run(ei.body)
		self:pop_scope()
	end

	if node.else_body then
		self:push_scope()
		self:run(node.else_body)
		self:pop_scope()
	end

	self.chunk.code[jump_end + 1] = #self.chunk.code
end

function compiler:_function(node)
	-- create a new compiler for the func body
	local sub = compiler.new()
	-- add params as locals in the sub compiler
	for i, param in ipairs(node.params) do
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
	self:_function(node.func)
	-- function a.b.c() end
	if #node.name == 1 then
		local idx = self:add_constant(node.name[1])
		self:emit(OPCODES.STORE_GLOBAL, idx)
	else
		-- load base then set fields
		local base_idx = self:add_constant(node.name[1])
		self:emit(OPCODES.LOAD_GLOBAL, base_idx)
		for i = 2, #node.name - 1 do
			local idx = self:add_constant(node.name[i])
			self:emit(OPCODES.GET_FIELD, idx)
		end
		local last_idx = self:add_constant(node.name[#node.name])
		self:emit(OPCODES.SET_FIELD, last_idx)
	end
end

function compiler:_repeat(node)
	local loop_start = #self.chunk.code
	self:push_scope()
	self:run(node.body)
	self:run(node.condition) -- condition is checked at the end
	self:pop_scope()
	self:emit(OPCODES.NOT) -- repeat until condition is true
	self:emit(OPCODES.JUMP_IF_FALSE, loop_start)
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
	local pos_start = #self.chunk.code
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
	self.chunk.code[pos_exit + 1] = #self.chunk.code

	-- jump over negative loop
	local jump_over_neg = #self.chunk.code + 1
	self:emit(OPCODES.JUMP, 0)

	-- while i >= limit
	self.chunk.code[jump_neg + 1] = #self.chunk.code
	local neg_start = #self.chunk.code
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
	self.chunk.code[neg_exit + 1] = #self.chunk.code

	self.chunk.code[jump_over_neg + 1] = #self.chunk.code
	self:pop_scope()
end

function compiler:generic_for(node)
	self:push_scope()

	for _, itr in ipairs(node.iterators) do
		self:run(itr)
	end

	local var_reg = self:add_local("__var__")
	self:emit(OPCODES.STORE_LOCAL, var_reg)

	local state_reg = self:add_local("__state__")
	self:emit(OPCODES.STORE_LOCAL, state_reg)

	local func_reg = self:add_local("__func__")
	self:emit(OPCODES.STORE_LOCAL, func_reg)

	local loop_vars = {}
	for _, name in ipairs(node.names) do
		local reg = self:add_local(name)
		table.insert(loop_vars, reg)
		self:emit(OPCODES.PUSH_NIL)
		self:emit(OPCODES.STORE_LOCAL, reg)
	end

	local loop_start = #self.chunk.code

	self:emit(OPCODES.LOAD_LOCAL, func_reg)
	self:emit(OPCODES.LOAD_LOCAL, state_reg)
	self:emit(OPCODES.LOAD_LOCAL, var_reg)
	self:emit(OPCODES.CALL, 2)

	for _, reg in ipairs(loop_vars) do
		self:emit(OPCODES.STORE_LOCAL, reg)
	end

	self:emit(OPCODES.LOAD_LOCAL, loop_vars[1])
	self:emit(OPCODES.STORE_LOCAL, var_reg)

	self:emit(OPCODES.LOAD_LOCAL, var_reg)
	self:emit(OPCODES.PUSH_NIL)
	self:emit(OPCODES.EQ)

	local jump_continue = #self.chunk.code + 1
	self:emit(OPCODES.JUMP_IF_FALSE, 0)

	local jump_exit = #self.chunk.code + 1
	self:emit(OPCODES.JUMP, 0)

	self.chunk.code[jump_continue + 1] = #self.chunk.code

	self:run(node.body)
	self:emit(OPCODES.JUMP, loop_start)

	self.chunk.code[jump_exit + 1] = #self.chunk.code

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

	for _, arg in ipairs(node.args) do
		self:run(arg)
	end
	self:emit(OPCODES.CALL, #node.args + 1) -- +1 for implicit self

	-- clean up temp
	self.chunk.locals["__self__"] = nil
	self.chunk.num_locals -= 1
end

function compiler:_table(node)
	self:emit(OPCODES.NEW_TABLE)
	for i, field in ipairs(node.fields) do
		if field.kind == "NamedField" then
			-- {key = value}
			self:run(field.value)
			local idx = self:add_constant(field.key)
			self:emit(OPCODES.SET_FIELD, idx)
		elseif field.kind == "IndexedField" then
			-- {[expr] = value}
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
end

function compiler:_while(node)
	local loop_start = #self.chunk.code
	self:run(node.condition)
	local jump_false = #self.chunk.code + 1
	self:emit(OPCODES.JUMP_IF_FALSE, 0)

	self.chunk.break_jumps = {} -- collect breaks
	self:push_scope()
	self:run(node.body)
	self:pop_scope()

	self:emit(OPCODES.JUMP, loop_start)
	self.chunk.code[jump_false + 1] = #self.chunk.code

	-- patch all breaks to here
	for _, jump in ipairs(self.chunk.break_jumps) do
		self.chunk.code[jump + 1] = #self.chunk.code
	end
	self.chunk.break_jumps = nil
end

function compiler:_return(node)
	for _, v in ipairs(node.values) do
		self:run(v)
	end
	self:emit(OPCODES.RETURN, #node.values)
end

function compiler:call(node)
	self:run(node.callee)
	for _, arg in ipairs(node.args) do
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

function compiler:dump()
	local chunk = self.chunk
	print("=== CHUNK DUMP ===\n")

	-- constants
	print("CONSTANTS (" .. #chunk.constants .. ")")
	for i, v in ipairs(chunk.constants) do
		print(string.format("  [%d] %-10s %s", i - 1, type(v), tostring(v)))
	end

	-- locals
	print("\nLOCALS (" .. chunk.num_locals .. ")")
	for name, reg in pairs(chunk.locals) do
		print(string.format("  [%d] %s", reg, name))
	end

	-- bytecode
	print("\nBYTECODE (" .. #chunk.code .. " instructions)")
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
			-- if its a constant-referencing op, show the value too
			local extra = ""
			if
				(name == "LOAD_CONST" or name == "LOAD_GLOBAL" or name == "STORE_GLOBAL" or name == "GET_FIELD")
				and chunk.constants[arg + 1]
			then
				extra = " ; " .. tostring(chunk.constants[arg + 1])
			end
			print(string.format("  [%03d] %-20s %d%s", i, name, arg, extra))
			i = i + 2
		else
			print(string.format("  [%03d] %-20s", i, name))
			i = i + 1
		end
	end

	print("\n==================")
end

return compiler
