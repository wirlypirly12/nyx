local compiler = {}
compiler.__index = compiler

local OPCODES, OPNAMES
do
	local export = require("./opcodes")
	OPCODES = export.CODES
	OPNAMES = export.NAMES
end

local BINARY_OPS
local UNARY_OPS

BINARY_OPS = {
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
	[".."] = OPCODES.CONCAT,
}
UNARY_OPS = {
	["-"] = OPCODES.UNM,
	["not"] = OPCODES.NOT,
	["#"] = OPCODES.LEN,
}

function compiler.new(parent)
	local self = setmetatable({
		parent = parent,
		chunk = {
			code = {},
			constants = {},
			constant_index = {},
			locals = {},
			num_locals = 0,
			scope_stack = {},
			upvalue_names = {},
			captured_locals = {},
		},
		break_stack = {},
		continue_stack = {},
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
	for _, v in args do
		table.insert(self.chunk.code, v)
	end
end

function compiler:add_constant(value)
	local idx = self.chunk.constant_index[value]
	if idx ~= nil then
		return idx
	end
	table.insert(self.chunk.constants, value)
	idx = #self.chunk.constants - 1
	self.chunk.constant_index[value] = idx
	return idx
end

function compiler:add_local(name)
	local reg = self.chunk.num_locals
	local scope = self.chunk.scope_stack[#self.chunk.scope_stack]
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

function compiler:_mark_captured(name, stop)
	local q = self
	while q do
		local reg = q:get_local(name)
		if reg ~= nil then
			q.chunk.captured_locals[name] = reg
		end
		if q == stop then
			break
		end
		q = q.parent
	end
end

function compiler:push_loop()
	table.insert(self.break_stack, {})
	table.insert(self.continue_stack, {})
end

function compiler:pop_loop()
	table.remove(self.continue_stack)
	return table.remove(self.break_stack)
end

function compiler:emit_break()
	local list = self.break_stack[#self.break_stack]
	if not list then
		error("break outside loop")
	end
	local site = #self.chunk.code + 1
	self:emit(OPCODES.JUMP, 0)
	table.insert(list, site)
end

function compiler:emit_continue()
	local list = self.continue_stack[#self.continue_stack]
	if not list then
		error("continue outside loop")
	end
	local site = #self.chunk.code + 1
	self:emit(OPCODES.JUMP, 0)
	table.insert(list, site)
end

function compiler:patch_breaks(breaks)
	local here = #self.chunk.code + 1
	for _, site in breaks do
		self.chunk.code[site + 1] = here
	end
end

function compiler:patch_continues(target)
	for _, site in self.continue_stack[#self.continue_stack] do
		self.chunk.code[site + 1] = target
	end
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
				self:method_call(n.expr, false)
			else
				self:call(n.expr, false)
			end
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
			self:call(n, true)
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
			self:method_call(n, true)
		end,
		Table = function(n)
			self:_table(n)
		end,
		Break = function(n)
			self:_break(n)
		end,
		Continue = function(n)
			self:emit_continue()
		end,
		UnrolledFor = function(n)
			self:unrolled_for(n)
		end,
		InlineCall = function(n)
			self:inline_call(n)
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
	if node.name == "..." then
		self:emit(OPCODES.VARARG)
		return
	end
	local reg = self:get_local(node.name)
	if reg ~= nil then
		self:emit(OPCODES.LOAD_LOCAL, reg)
		return
	end

	local p = self.parent
	while p do
		if p:get_local(node.name) ~= nil then
			self.chunk.upvalue_names[node.name] = true

			self.parent:_mark_captured(node.name, p)
			local idx = self:add_constant(node.name)
			self:emit(OPCODES.LOAD_UPVALUE, idx)
			return
		end
		p = p.parent
	end

	local idx = self:add_constant(node.name)
	self:emit(OPCODES.LOAD_GLOBAL, idx)
end

function compiler:_local(node)
	local num_names = #node.names

	if #node.values == 1 and (node.values[1].kind == "CallExpr" or node.values[1].kind == "MethodCall") then
		local call = node.values[1]

		local regs = {}
		for i, name in node.names do
			local reg = self:add_local(name)
			regs[i] = reg
			self:emit(OPCODES.PUSH_NIL)
			self:emit(OPCODES.STORE_LOCAL, reg)
		end

		if call.kind == "CallExpr" then
			self:run(call.callee)
			for _, arg in call.args do
				self:run(arg)
			end
			self:emit(OPCODES.CALL_MULTI, #call.args, num_names)
		else
			self:push_scope()
			self:run(call.object)
			local tmp = self:add_local("__self__")
			self:emit(OPCODES.STORE_LOCAL, tmp)
			self:emit(OPCODES.LOAD_LOCAL, tmp)
			local idx = self:add_constant(call.method)
			self:emit(OPCODES.GET_FIELD, idx)
			self:emit(OPCODES.LOAD_LOCAL, tmp)
			for _, arg in call.args do
				self:run(arg)
			end
			self:emit(OPCODES.CALL_MULTI, #call.args + 1, num_names)
			self:pop_scope()
		end

		for i = num_names, 1, -1 do
			self:emit(OPCODES.STORE_LOCAL, regs[i])
		end
		return
	end

	for i, name in node.names do
		local value = node.values[i]
		if value then
			if value.kind == "Identifier" and value.name == "..." then
				self:emit(OPCODES.VARARG_FIRST)
			else
				self:run(value)
			end
		else
			self:emit(OPCODES.PUSH_NIL)
		end
		self:add_local(name)
		self:emit(OPCODES.STORE_LOCAL, self:get_local(name))
	end
end

function compiler:assign(node)
	local targets = node.targets or { node.target }

	if node.op ~= "=" then
		local op_map = { ["+="] = "+", ["-="] = "-", ["*="] = "*", ["/="] = "/" }
		local bin_op = op_map[node.op]
		if not bin_op then
			error(`unknown assignment operator: {node.op}`)
		end
		local bin_ops = { ["+"] = OPCODES.ADD, ["-"] = OPCODES.SUB, ["*"] = OPCODES.MUL, ["/"] = OPCODES.DIV }
		local target = targets[1]

		if target.kind == "FieldAccess" then
			self:run(target.object)
			local idx = self:add_constant(target.field)
			self:emit(OPCODES.GET_FIELD, idx)
		elseif target.kind == "IndexAccess" then
			self:run(target.object)
			self:run(target.index)
			self:emit(OPCODES.GET_INDEX)
		else
			local reg = self:get_local(target.name)
			if reg ~= nil then
				self:emit(OPCODES.LOAD_LOCAL, reg)
			else
				local idx = self:add_constant(target.name)
				self:emit(OPCODES.LOAD_GLOBAL, idx)
			end
		end
		self:run(node.values[1])
		self:emit(bin_ops[bin_op])

		self:_store_target(target)
		return
	end

	local num_targets = #targets
	if num_targets > 1 and #node.values == 1 then
		local rhs = node.values[1]
		if rhs.kind == "CallExpr" or rhs.kind == "MethodCall" then
			if rhs.kind == "CallExpr" then
				self:run(rhs.callee)
				for _, arg in rhs.args do
					self:run(arg)
				end
				self:emit(OPCODES.CALL_MULTI, #rhs.args, num_targets)
			else
				self:push_scope()
				self:run(rhs.object)
				local tmp = self:add_local("__stmp__")
				self:emit(OPCODES.STORE_LOCAL, tmp)
				self:emit(OPCODES.LOAD_LOCAL, tmp)
				local idx = self:add_constant(rhs.method)
				self:emit(OPCODES.GET_FIELD, idx)
				self:emit(OPCODES.LOAD_LOCAL, tmp)
				for _, arg in rhs.args do
					self:run(arg)
				end
				self:emit(OPCODES.CALL_MULTI, #rhs.args + 1, num_targets)
				self:pop_scope()
			end

			for i = num_targets, 1, -1 do
				self:_store_target(targets[i])
			end
			return
		end
	end

	for i = 1, num_targets do
		local value = node.values[i]
		if value then
			self:run(value)
		else
			self:emit(OPCODES.PUSH_NIL)
		end
	end

	for i = num_targets, 1, -1 do
		self:_store_target(targets[i])
	end
end

function compiler:_store_target(target)
	if target.kind == "FieldAccess" then
		self:push_scope()
		local tmp = self:add_local("__stmp__")
		self:emit(OPCODES.STORE_LOCAL, tmp)
		self:run(target.object)
		self:emit(OPCODES.LOAD_LOCAL, tmp)
		local idx = self:add_constant(target.field)
		self:emit(OPCODES.SET_FIELD, idx)

		self:emit(OPCODES.POP)
		self:pop_scope()
	elseif target.kind == "IndexAccess" then
		self:push_scope()
		local tmp = self:add_local("__stmp__")
		self:emit(OPCODES.STORE_LOCAL, tmp)
		self:run(target.object)
		self:run(target.index)
		self:emit(OPCODES.LOAD_LOCAL, tmp)
		self:emit(OPCODES.SET_INDEX)

		self:emit(OPCODES.POP)
		self:pop_scope()
	else
		local reg = self:get_local(target.name)
		if reg ~= nil then
			self:emit(OPCODES.STORE_LOCAL, reg)
		else
			local found_at = nil
			local p = self.parent
			while p do
				if p:get_local(target.name) ~= nil then
					found_at = p
					break
				end
				p = p.parent
			end
			if found_at then
				self.parent:_mark_captured(target.name, found_at)

				self.chunk.upvalue_names[target.name] = true
				local idx = self:add_constant(target.name)
				self:emit(OPCODES.STORE_UPVALUE, idx)
			else
				local idx = self:add_constant(target.name)
				self:emit(OPCODES.STORE_GLOBAL, idx)
			end
		end
	end
end

function compiler:binary(node)
	if node.op == "and" then
		self:run(node.left)
		local skip = #self.chunk.code + 1
		self:emit(OPCODES.JUMP_IF_FALSE_KEEP, 0)
		self:emit(OPCODES.POP)
		self:run(node.right)
		self.chunk.code[skip + 1] = #self.chunk.code + 1
		return
	end

	if node.op == "or" then
		self:run(node.left)
		local skip = #self.chunk.code + 1
		self:emit(OPCODES.JUMP_IF_TRUE_KEEP, 0)
		self:emit(OPCODES.POP)
		self:run(node.right)
		self.chunk.code[skip + 1] = #self.chunk.code + 1
		return
	end

	self:run(node.left)
	self:run(node.right)

	local op = BINARY_OPS[node.op]
	if not op then
		error(`unknown operator: {node.op}`)
	end
	self:emit(op)
end

function compiler:unary(node)
	self:run(node.operand)
	local op = UNARY_OPS[node.op]
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
	local end_jumps = {}

	self:run(node.condition)
	local jump_false = #self.chunk.code + 1
	self:emit(OPCODES.JUMP_IF_FALSE, 0)

	self:push_scope()
	self:run(node.body)
	self:pop_scope()

	local j = #self.chunk.code + 1
	self:emit(OPCODES.JUMP, 0)
	table.insert(end_jumps, j)
	self.chunk.code[jump_false + 1] = #self.chunk.code + 1

	for _, ei in node.elseifs do
		self:run(ei.condition)
		local ei_jf = #self.chunk.code + 1
		self:emit(OPCODES.JUMP_IF_FALSE, 0)

		self:push_scope()
		self:run(ei.body)
		self:pop_scope()

		local ej = #self.chunk.code + 1
		self:emit(OPCODES.JUMP, 0)
		table.insert(end_jumps, ej)
		self.chunk.code[ei_jf + 1] = #self.chunk.code + 1
	end

	if node.else_body then
		self:push_scope()
		self:run(node.else_body)
		self:pop_scope()
	end

	local here = #self.chunk.code + 1
	for _, site in end_jumps do
		self.chunk.code[site + 1] = here
	end
end

function compiler:_function(node)
	local sub = compiler.new(self)
	sub.chunk.num_params = 0
	for _, param in node.params do
		if param == "..." then
			break
		end
		sub:add_local(param)
		sub.chunk.num_params += 1
	end
	sub:push_scope()
	sub:run(node.body)
	sub:pop_scope()
	local idx = self:add_constant(sub.chunk)
	self:emit(OPCODES.CLOSURE, idx)
end

function compiler:local_function(node)
	self:add_local(node.name)
	local reg = self:get_local(node.name)
	self:emit(OPCODES.PUSH_NIL)
	self:emit(OPCODES.STORE_LOCAL, reg)
	self:_function(node.func)
	self:emit(OPCODES.STORE_LOCAL, reg)
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
		self:push_scope()
		local fn_tmp = self:add_local("__fn_tmp__")
		self:emit(OPCODES.STORE_LOCAL, fn_tmp)

		local reg = self:get_local(node.name[1])
		if reg then
			self:emit(OPCODES.LOAD_LOCAL, reg)
		else
			local base_idx = self:add_constant(node.name[1])
			self:emit(OPCODES.LOAD_GLOBAL, base_idx)
		end
		for i = 2, #node.name - 1 do
			local idx = self:add_constant(node.name[i])
			self:emit(OPCODES.GET_FIELD, idx)
		end
		self:emit(OPCODES.LOAD_LOCAL, fn_tmp)
		local last_idx = self:add_constant(node.name[#node.name])
		self:emit(OPCODES.SET_FIELD, last_idx)
		self:emit(OPCODES.POP)
		self:pop_scope()
	end
end

function compiler:_repeat(node)
	self:push_loop()
	local loop_start = #self.chunk.code + 1
	self:push_scope()
	for _, stmt in node.body.body do
		self:run(stmt)
	end
	local continue_target = #self.chunk.code + 1
	self:patch_continues(continue_target)
	self:run(node.condition)
	local breaks = self:pop_loop()
	self:emit(OPCODES.JUMP_IF_FALSE, loop_start)
	self:pop_scope()
	self:patch_breaks(breaks)
end

function compiler:numeric_for(node)
	self:push_scope()
	self:push_loop()

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

	self:emit(OPCODES.LOAD_LOCAL, step_reg)
	self:emit(OPCODES.LOAD_CONST, self:add_constant(0))
	self:emit(OPCODES.GT)
	local jump_neg = #self.chunk.code + 1
	self:emit(OPCODES.JUMP_IF_FALSE, 0)

	local pos_start = #self.chunk.code + 1
	self:emit(OPCODES.LOAD_LOCAL, i_reg)
	self:emit(OPCODES.LOAD_LOCAL, limit_reg)
	self:emit(OPCODES.LTE)
	local pos_exit = #self.chunk.code + 1
	self:emit(OPCODES.JUMP_IF_FALSE, 0)
	self:run(node.body)
	local pos_continue = #self.chunk.code + 1
	self:patch_continues(pos_continue)
	self:emit(OPCODES.LOAD_LOCAL, i_reg)
	self:emit(OPCODES.LOAD_LOCAL, step_reg)
	self:emit(OPCODES.ADD)
	self:emit(OPCODES.STORE_LOCAL, i_reg)
	self:emit(OPCODES.JUMP, pos_start)
	self.chunk.code[pos_exit + 1] = #self.chunk.code + 1

	local jump_over_neg = #self.chunk.code + 1
	self:emit(OPCODES.JUMP, 0)

	self.chunk.code[jump_neg + 1] = #self.chunk.code + 1
	self.continue_stack[#self.continue_stack] = {}
	local neg_start = #self.chunk.code + 1
	self:emit(OPCODES.LOAD_LOCAL, i_reg)
	self:emit(OPCODES.LOAD_LOCAL, limit_reg)
	self:emit(OPCODES.GTE)
	local neg_exit = #self.chunk.code + 1
	self:emit(OPCODES.JUMP_IF_FALSE, 0)
	self:run(node.body)
	local neg_continue = #self.chunk.code + 1
	self:patch_continues(neg_continue)
	self:emit(OPCODES.LOAD_LOCAL, i_reg)
	self:emit(OPCODES.LOAD_LOCAL, step_reg)
	self:emit(OPCODES.ADD)
	self:emit(OPCODES.STORE_LOCAL, i_reg)
	self:emit(OPCODES.JUMP, neg_start)
	self.chunk.code[neg_exit + 1] = #self.chunk.code + 1

	self.chunk.code[jump_over_neg + 1] = #self.chunk.code + 1

	local breaks = self:pop_loop()
	self:pop_scope()
	self:patch_breaks(breaks)
end

function compiler:generic_for(node)
	self:push_scope()
	self:push_loop()

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

	local func_reg = self:add_local("__func__")
	self:emit(OPCODES.PUSH_NIL)
	self:emit(OPCODES.STORE_LOCAL, func_reg)
	local state_reg = self:add_local("__state__")
	self:emit(OPCODES.PUSH_NIL)
	self:emit(OPCODES.STORE_LOCAL, state_reg)
	local var_reg = self:add_local("__var__")
	self:emit(OPCODES.PUSH_NIL)
	self:emit(OPCODES.STORE_LOCAL, var_reg)

	self:emit(OPCODES.STORE_LOCAL, var_reg)
	self:emit(OPCODES.STORE_LOCAL, state_reg)
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

	self:patch_continues(loop_start)
	self:emit(OPCODES.JUMP, loop_start)
	self.chunk.code[jump_out + 1] = #self.chunk.code + 1

	local breaks = self:pop_loop()
	self:pop_scope()
	self:patch_breaks(breaks)
end

function compiler:method_call(node, push_result)
	self:push_scope()

	self:run(node.object)
	local tmp = self:add_local("__self__")
	self:emit(OPCODES.STORE_LOCAL, tmp)

	self:emit(OPCODES.LOAD_LOCAL, tmp)
	local idx = self:add_constant(node.method)
	self:emit(OPCODES.GET_FIELD, idx)

	self:emit(OPCODES.LOAD_LOCAL, tmp)

	for _, arg in node.args do
		self:run(arg)
	end

	if push_result then
		self:emit(OPCODES.CALL, #node.args + 1)
	else
		self:emit(OPCODES.CALL_VOID, #node.args + 1)
	end

	self:pop_scope()
end

function compiler:_table(node)
	self:emit(OPCODES.NEW_TABLE)
	self:push_scope()
	local tbl_reg = self:add_local("__tbl__")
	self:emit(OPCODES.STORE_LOCAL, tbl_reg)

	local array_idx = 1
	for _, field in node.fields do
		if field.kind == "NamedField" then
			self:emit(OPCODES.LOAD_LOCAL, tbl_reg)
			self:run(field.value)
			local idx = self:add_constant(field.key)
			self:emit(OPCODES.SET_FIELD, idx)
			self:emit(OPCODES.POP)
		elseif field.kind == "IndexedField" then
			self:emit(OPCODES.LOAD_LOCAL, tbl_reg)
			self:run(field.key)
			self:run(field.value)
			self:emit(OPCODES.SET_INDEX)
			self:emit(OPCODES.POP)
		elseif field.kind == "ValueField" then
			if field.value.kind == "Identifier" and field.value.name == "..." then
				self:emit(OPCODES.LOAD_LOCAL, tbl_reg)
				self:emit(OPCODES.LOAD_CONST, self:add_constant(array_idx))
				self:emit(OPCODES.VARARG)
				self:emit(OPCODES.SET_VARARG_TABLE)
			else
				self:emit(OPCODES.LOAD_LOCAL, tbl_reg)
				self:emit(OPCODES.LOAD_CONST, self:add_constant(array_idx))
				self:run(field.value)
				self:emit(OPCODES.SET_INDEX)
				array_idx += 1
			end
		end
	end

	self:emit(OPCODES.LOAD_LOCAL, tbl_reg)
	self:pop_scope()
end

function compiler:_while(node)
	self:push_loop()
	local loop_start = #self.chunk.code + 1
	self:run(node.condition)
	local jump_false = #self.chunk.code + 1
	self:emit(OPCODES.JUMP_IF_FALSE, 0)

	self:push_scope()
	self:run(node.body)
	self:pop_scope()

	self:patch_continues(loop_start)
	self:emit(OPCODES.JUMP, loop_start)
	self.chunk.code[jump_false + 1] = #self.chunk.code + 1

	local breaks = self:pop_loop()
	self:patch_breaks(breaks)
end

function compiler:_return(node)
	for _, v in node.values do
		self:run(v)
	end
	self:emit(OPCODES.RETURN, #node.values)
end

function compiler:call(node, push_result)
	self:run(node.callee)
	for _, arg in node.args do
		self:run(arg)
	end
	if push_result then
		self:emit(OPCODES.CALL, #node.args)
	else
		self:emit(OPCODES.CALL_VOID, #node.args)
	end
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

function compiler:unrolled_for(node)
	for _, iter in node.iterations do
		self:push_scope()

		local i_reg = self:add_local(node.name)
		local const_idx = self:add_constant(iter.i_value)
		self:emit(OPCODES.LOAD_CONST, const_idx)
		self:emit(OPCODES.STORE_LOCAL, i_reg)

		self:push_loop()
		self:run(iter.body)

		self:patch_continues(#self.chunk.code + 1)

		local iter_breaks = self:pop_loop()

		if self.break_stack[#self.break_stack] then
			for _, site in iter_breaks do
				table.insert(self.break_stack[#self.break_stack], site)
			end
		else
			for _, site in iter_breaks do
				table.insert(iter_breaks, site)
			end
		end

		self:pop_scope()
	end
end

function compiler:inline_call(node)
	self:push_scope()
	self:run(node.body)
	self:pop_scope()
end

function compiler:_break(node)
	self:emit_break()
end

function compiler:dump(copy)
	local chunk = self.chunk
	local output = ""
	output ..= "=== CHUNK DUMP ===\n"

	output ..= ("CONSTANTS (" .. #chunk.constants .. ")\n")
	for i, v in chunk.constants do
		if type(v) == "table" then
			print(string.format("  [%d] %-10s <chunk>", i - 1, "chunk"))
		else
			print(string.format("  [%d] %-10s %s", i - 1, type(v), tostring(v)))
		end
	end

	output ..= ("\nLOCALS (" .. chunk.num_locals .. ")\n")
	for name, reg in chunk.locals do
		print(string.format("  [%d] %s", reg, name))
	end

	output ..= ("\nBYTECODE (" .. #chunk.code .. " instructions)\n")
	local i = 1
	while i <= #chunk.code do
		local op = chunk.code[i]
		local name = OPNAMES[op] or ("UNKNOWN(" .. tostring(op) .. ")")

		local has_arg = {
			LOAD_CONST = true,
			LOAD_LOCAL = true,
			STORE_LOCAL = true,
			LOAD_GLOBAL = true,
			STORE_GLOBAL = true,
			LOAD_UPVALUE = true,
			STORE_UPVALUE = true,
			JUMP = true,
			JUMP_IF_FALSE = true,
			JUMP_IF_FALSE_KEEP = true,
			JUMP_IF_TRUE_KEEP = true,
			CALL = true,
			CALL_VOID = true,
			RETURN = true,
			GET_FIELD = true,
			SET_FIELD = true,
			CLOSURE = true,
			MOVE = true,
		}
		local has_two_args = { CALL_MULTI = true }

		if has_two_args[name] then
			local a1, a2 = chunk.code[i + 1], chunk.code[i + 2]
			output ..= string.format("  [%03d] %-24s %d %d\n", i, name, a1, a2)
			i += 3
		elseif has_arg[name] then
			local arg = chunk.code[i + 1]
			local extra = ""
			if
				(
					name == "LOAD_CONST"
					or name == "LOAD_GLOBAL"
					or name == "STORE_GLOBAL"
					or name == "GET_FIELD"
					or name == "LOAD_UPVALUE"
					or name == "STORE_UPVALUE"
				)
				and chunk.constants[arg + 1]
				and type(chunk.constants[arg + 1]) ~= "table"
			then
				extra = " ; " .. tostring(chunk.constants[arg + 1])
			end
			output ..= string.format("  [%03d] %-24s %d%s\n", i, name, arg, extra)
			i += 2
		else
			output ..= string.format("  [%03d] %-24s\n", i, name)
			i += 1
		end
	end

	output ..= "\n=================="
	print(output)
	if copy then
		pcall(setclipboard, output)
	end
end

return compiler
