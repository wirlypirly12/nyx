--!nolint
-- [[ linker bundled output ]]
-- built   : 2026-03-26 19:21:32
-- entry   : main.lua
-- inlined : 5 module(s) + entry

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

__linker_modules["src/opcodes.lua"] = function()
local shared = __linker_shared
local OPCODES = {}
local OPNAMES = {

	"LOAD_CONST",
	"LOAD_LOCAL",
	"STORE_LOCAL",
	"LOAD_GLOBAL",
	"LOAD_UPVALUE",
	"STORE_UPVALUE",
	"STORE_GLOBAL",
	"PUSH_NIL",
	"PUSH_TRUE",
	"PUSH_FALSE",
	"POP",
	"CALL_MULTI",

	"ADD",
	"SUB",
	"MUL",
	"DIV",
	"MOD",
	"POW",
	"IDIV",
	"UNM",

	"CONCAT",

	"AND",
	"OR",
	"NOT",

	"EQ",
	"NEQ",
	"LT",
	"LTE",
	"GT",
	"GTE",
	"LEN",

	"JUMP",
	"JUMP_IF_FALSE",
	"JUMP_IF_FALSE_KEEP",
	"JUMP_IF_TRUE_KEEP",

	"NEW_TABLE",
	"SET_FIELD",
	"GET_FIELD",
	"SET_INDEX",
	"GET_INDEX",

	"CLOSURE",
	"CALL",
	"CALL_VOID",
	"RETURN",

	"MOVE",
	"VARARG",
	"SET_VARARG_TABLE",
	"VARARG_FIRST",
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

function compiler.new(parent)
	local self = setmetatable({
		parent = parent,
		chunk = {
			code = {},
			constants = {},
			locals = {},
			num_locals = 0,
			scope_stack = {},
			upvalue_names = {},
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
	for i, v in self.chunk.constants do
		if v == value then
			return i - 1
		end
	end
	table.insert(self.chunk.constants, value)
	return #self.chunk.constants - 1
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
			local is_upval = false
			local p = self.parent
			while p do
				if p:get_local(target.name) ~= nil then
					is_upval = true
					break
				end
				p = p.parent
			end
			if is_upval then
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
	local ops = { ["-"] = OPCODES.UNM, ["not"] = OPCODES.NOT, ["#"] = OPCODES.LEN }
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
		elseif field.kind == "IndexedField" then
			self:emit(OPCODES.LOAD_LOCAL, tbl_reg)
			self:run(field.key)
			self:run(field.value)
			self:emit(OPCODES.SET_INDEX)
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
	["break"] = true,
	["continue"] = true,
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
		self.char = self.source:sub(self.pos, self.pos)
		if self.char == "\n" then
			self.line = self.line + 1
			self.column = 1
		else
			self.column = self.column + 1
		end
	else
		self.char = nil
	end
end

function lexer:peek(offset)
	offset = offset or 1
	local peek_at = self.pos + offset
	if peek_at <= #self.source then
		return self.source:sub(peek_at, peek_at)
	end
	return nil
end

function lexer:skip_whitespace()
	while self.char and self.char:match("%s") do
		self:advance()
	end
end

function lexer:skip_comment()
	if self.char == "-" and self:peek() == "-" then
		self:advance()
		self:advance()

		if self.char == "[" then
			local level = 0
			local i = 1
			while self:peek(i) == "=" do
				level = level + 1
				i = i + 1
			end

			if self:peek(i) == "[" then
				self:advance()
				for _ = 1, level do
					self:advance()
				end
				self:advance()

				while self.char do
					if self.char == "]" then
						local close_level = 0
						local j = 1
						while self:peek(j) == "=" do
							close_level = close_level + 1
							j = j + 1
						end
						if close_level == level and self:peek(j) == "]" then
							self:advance()
							for _ = 1, level do
								self:advance()
							end
							self:advance()
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

function lexer:long_string()
	local level = 0
	local i = 1
	while self:peek(i) == "=" do
		level = level + 1
		i = i + 1
	end
	if self:peek(i) ~= "[" then
		return false
	end

	self:advance()
	for _ = 1, level do
		self:advance()
	end
	self:advance()

	if self.char == "\n" then
		self:advance()
	end

	local result = {}
	while self.char do
		if self.char == "]" then
			local close_level = 0
			local j = 1
			while self:peek(j) == "=" do
				close_level = close_level + 1
				j = j + 1
			end
			if close_level == level and self:peek(j) == "]" then
				self:advance()
				for _ = 1, level do
					self:advance()
				end
				self:advance()
				self:emit(TOKEN_TYPES.STRING, table.concat(result))
				return true
			end
		end
		table.insert(result, self.char)
		self:advance()
	end
	error(`unended long string, expected ]{string.rep("=", level)}]`)
end

function lexer:string()
	local escapes = {
		n = "\n",
		t = "\t",
		r = "\r",
		["\\"] = "\\",
		['"'] = '"',
		["'"] = "'",
		["0"] = "\0",
		a = "\a",
		b = "\b",
		f = "\f",
		v = "\v",
	}

	local quote = self.char
	self:advance()
	local result = {}
	while self.char and self.char ~= quote do
		if self.char == "\\" then
			self:advance()
			local escaped = escapes[self.char]
			if escaped then
				table.insert(result, escaped)
			elseif self.char and self.char:match("%d") then
				local num_str = self.char
				self:advance()
				if self.char and self.char:match("%d") then
					num_str ..= self.char
					self:advance()
					if self.char and self.char:match("%d") then
						num_str ..= self.char
						self:advance()
					end
				end
				table.insert(result, string.char(tonumber(num_str)))
				continue
			else
				error(`illegal escape sequence: \\{self.char}`)
			end
		else
			table.insert(result, self.char)
		end
		self:advance()
	end
	if not self.char then
		error("unfinished string (missing closing quote)")
	end
	self:advance()
	self:emit(TOKEN_TYPES.STRING, table.concat(result))
end

function lexer:number()
	local result = {}

	if self.char == "0" and (self:peek() == "x" or self:peek() == "X") then
		table.insert(result, self.char)
		self:advance()
		table.insert(result, self.char)
		self:advance()
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
		if self.char == "." and self:peek() and self:peek():match("%d") then
			table.insert(result, ".")
			self:advance()
			while self.char and self.char:match("%d") do
				table.insert(result, self.char)
				self:advance()
			end
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
	local p2 = self:peek(2)

	if c == "." and p == "." and p2 == "." then
		self:advance()
		self:advance()
		self:advance()
		self:emit(TOKEN_TYPES.OPERATOR, "...")
		return
	end

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

		["+="] = true,
		["-="] = true,
		["*="] = true,
		["/="] = true,
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
		error(`unexpected character: '{self.char}' at line {self.line} col {self.column}`)
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
		elseif self.char == "[" and (self:peek() == "[" or self:peek() == "=") then
			if not self:long_string() then
				self:symbol()
			end
		elseif self.char:match("%d") then
			self:number()
		elseif self.char == "." and self:peek() and self:peek():match("%d") then
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
			return { kind = "Break" }
		elseif t.value == "continue" then
			self:advance()
			return { kind = "Continue" }
		end
	end
	return self:parse_expression_statement()
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

function vm:load_stdlib()
	self.globals["print"] = print
	self.globals["tostring"] = tostring
	self.globals["tonumber"] = tonumber
	self.globals["type"] = type
	self.globals["typeof"] = typeof or type
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
	self.globals["rawlen"] = rawlen
	self.globals["setmetatable"] = setmetatable
	self.globals["getmetatable"] = getmetatable
	self.globals["next"] = next
	self.globals["load"] = load
	self.globals["loadstring"] = loadstring or load
	self.globals["collectgarbage"] = collectgarbage
	self.globals["warn"] = warn or print

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
		asin = math.asin,
		acos = math.acos,
		atan = math.atan,
		atan2 = math.atan2,
		log = math.log,
		exp = math.exp,
		fmod = math.fmod,
		modf = math.modf,
		pow = math.pow,
		rad = math.rad,
		deg = math.deg,

		round = math.round or function(n)
			return math.floor(n + 0.5)
		end,
		clamp = math.clamp or function(n, lo, hi)
			return math.max(lo, math.min(hi, n))
		end,
		sign = math.sign or function(n)
			return n > 0 and 1 or n < 0 and -1 or 0
		end,
		noise = math.noise,
		map = math.map,
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
		split = string.split or function(s, sep)
			local result = {}
			local pattern = "([^" .. sep .. "]*)" .. sep .. "?"
			for part in s:gmatch("[^" .. sep .. "]+") do
				table.insert(result, part)
			end
			return result
		end,
	}

	self.globals["table"] = {
		insert = table.insert,
		remove = table.remove,
		concat = table.concat,
		sort = table.sort,
		unpack = table.unpack or unpack,
		move = table.move,
		pack = table.pack or function(...)
			return { n = select("#", ...), ... }
		end,
		find = table.find or function(t, val, init)
			for i = init or 1, #t do
				if t[i] == val then
					return i
				end
			end
			return nil
		end,
		freeze = table.freeze or function(t)
			return t
		end,
		clear = table.clear or function(t)
			for k in next, t do
				rawset(t, k, nil)
			end
		end,
		create = table.create or function(n, val)
			local t = {}
			for i = 1, n do
				t[i] = val
			end
			return t
		end,
	}

	self.globals["os"] = {
		time = os.time,
		clock = os.clock,
		date = os.date,
		difftime = os.difftime,
	}
end

function vm:load_roblox_env()
	self.globals["game"] = game
	self.globals["workspace"] = workspace
	self.globals["script"] = script
	self.globals["_G"] = self.globals

	local vm_globals = self.globals
	self.globals["getgenv"] = function()
		return vm_globals
	end

	self.globals["Instance"] = Instance
	self.globals["Vector3"] = Vector3
	self.globals["Vector2"] = Vector2
	self.globals["CFrame"] = CFrame
	self.globals["Color3"] = Color3
	self.globals["UDim"] = UDim
	self.globals["UDim2"] = UDim2
	self.globals["Rect"] = Rect
	self.globals["Ray"] = Ray
	self.globals["TweenInfo"] = TweenInfo
	self.globals["NumberSequence"] = NumberSequence
	self.globals["NumberSequenceKeypoint"] = NumberSequenceKeypoint
	self.globals["ColorSequence"] = ColorSequence
	self.globals["ColorSequenceKeypoint"] = ColorSequenceKeypoint
	self.globals["BrickColor"] = BrickColor
	self.globals["Axes"] = Axes
	self.globals["Faces"] = Faces
	self.globals["Region3"] = Region3
	self.globals["Enum"] = Enum
	self.globals["Random"] = Random

	self.globals["task"] = task
	self.globals["wait"] = task.wait
	self.globals["spawn"] = task.spawn
	self.globals["delay"] = task.delay
	self.globals["tick"] = tick
	self.globals["time"] = time
	self.globals["os"] = {
		time = os.time,
		clock = os.clock,
		date = os.date,
		difftime = os.difftime,
	}

	self.globals["game"] = game
	self.globals["require"] = require

	self.globals["cloneref"] = cloneref
	self.globals["sethiddenproperty"] = sethiddenproperty
	self.globals["set_hidden_property"] = set_hidden_property
	self.globals["set_hidden_prop"] = set_hidden_prop
	self.globals["gethiddenproperty"] = gethiddenproperty
	self.globals["get_hidden_property"] = get_hidden_property
	self.globals["get_hidden_prop"] = get_hidden_prop
	self.globals["queue_on_teleport"] = queue_on_teleport
	self.globals["syn"] = syn
	self.globals["fluxus"] = fluxus
	self.globals["request"] = request
	self.globals["http_request"] = http_request
	self.globals["http"] = http
	self.globals["setclipboard"] = setclipboard
	self.globals["toclipboard"] = toclipboard
	self.globals["set_clipboard"] = set_clipboard
	self.globals["Clipboard"] = Clipboard
	self.globals["firetouchinterest"] = firetouchinterest
	self.globals["writefile"] = writefile
	self.globals["readfile"] = readfile
	self.globals["isfile"] = isfile
	self.globals["makefolder"] = makefolder
	self.globals["isfolder"] = isfolder
	self.globals["getcustomasset"] = getcustomasset
	self.globals["getsynasset"] = getsynasset
	self.globals["hookfunction"] = hookfunction
	self.globals["hookmetamethod"] = hookmetamethod
	self.globals["getnamecallmethod"] = getnamecallmethod
	self.globals["get_namecall_method"] = get_namecall_method
	self.globals["checkcaller"] = checkcaller
	self.globals["newcclosure"] = newcclosure
	self.globals["getgc"] = getgc
	self.globals["get_gc_objects"] = get_gc_objects
	self.globals["setthreadidentity"] = setthreadidentity
	self.globals["syn_context_set"] = syn_context_set
	self.globals["setthreadcontext"] = setthreadcontext
	self.globals["replicatesignal"] = replicatesignal
	self.globals["getconnections"] = getconnections
	self.globals["get_signal_cons"] = get_signal_cons

	self.globals["string"].split = string.split or self.globals["string"].split
end

function vm:make_frame(chunk, args, upvalue_cells)
	local frame = {
		chunk = chunk,
		ip = 1,
		locals = {},
		stack = {},
		top = 0,

		upvalue_cells = upvalue_cells or {},
		varargs = {},
	}
	if args then
		local num_params = chunk.num_params or 0
		for i, v in args do
			if i <= num_params then
				frame.locals[i - 1] = v
			else
				table.insert(frame.varargs, v)
			end
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

function vm:_do_call(func, f_args)
	if type(func) == "function" then
		return table.pack(func(table.unpack(f_args)))
	elseif type(func) == "table" and func.__type == "function" then
		local res = self:execute(func.chunk, f_args, func.upvalue_cells)
		return res or {}
	elseif type(func) == "table" or type(func) == "userdata" then
		local mt = getmetatable(func)
		if mt then
			local mm = rawget(mt, "__call")
			if mm then
				local args2 = { func, table.unpack(f_args) }
				return self:_do_call(mm, args2)
			end
		end
		error(`attempt to call a {type(func)} value`)
	else
		error(`attempt to call a {type(func)} value`)
	end
end

local STRING_METATABLE = { __index = string }

function vm:_get_metafield(obj, name)
	local mt
	if type(obj) == "string" then
		mt = STRING_METATABLE
	else
		mt = getmetatable(obj)
	end
	if mt == nil then
		return nil
	end
	return rawget(mt, name)
end

function vm:_get_index(tbl, key)
	local raw
	if type(tbl) == "string" then
		return string[key]
	end
	raw = rawget(tbl, key)
	if raw ~= nil then
		return raw
	end

	local mt = getmetatable(tbl)
	if mt == nil then
		return nil
	end
	local index = rawget(mt, "__index")
	if index == nil then
		return nil
	end
	if type(index) == "function" then
		local res = table.pack(index(tbl, key))
		return res[1]
	elseif type(index) == "table" or type(index) == "userdata" then
		return self:_get_index(index, key)
	end
	return nil
end

function vm:_set_index(tbl, key, val)
	local mt = getmetatable(tbl)
	if mt and rawget(tbl, key) == nil then
		local ni = rawget(mt, "__newindex")
		if ni then
			if type(ni) == "function" then
				ni(tbl, key, val)
				return
			elseif type(ni) == "table" then
				self:_set_index(ni, key, val)
				return
			end
		end
	end
	rawset(tbl, key, val)
end

function vm:_arith(a, b, mm_name, native)
	local ok, result = pcall(native, a, b)
	if ok then
		return result
	end

	local mm = self:_get_metafield(a, mm_name) or self:_get_metafield(b, mm_name)
	if mm then
		return (self:_do_call(mm, { a, b }))[1]
	end
	error(`attempt to perform arithmetic`)
end

function vm:_unary(a, mm_name, native)
	local ok, result = pcall(native, a)
	if ok then
		return result
	end
	local mm = self:_get_metafield(a, mm_name)
	if mm then
		return (self:_do_call(mm, { a, a }))[1]
	end
	error(`attempt to perform arithmetic on a {type(a)} value`)
end

function vm:_concat(a, b)
	if (type(a) == "string" or type(a) == "number") and (type(b) == "string" or type(b) == "number") then
		return tostring(a) .. tostring(b)
	end
	local mm = self:_get_metafield(a, "__concat") or self:_get_metafield(b, "__concat")
	if mm then
		return (self:_do_call(mm, { a, b }))[1]
	end
	error(`attempt to concatenate a {type(a)} value`)
end

function vm:_len(a)
	if type(a) == "string" or type(a) == "table" then
		local mm = self:_get_metafield(a, "__len")
		if mm then
			return (self:_do_call(mm, { a }))[1]
		end
		return #a
	end
	error(`attempt to get length of a {type(a)} value`)
end

function vm:_eq(a, b)
	if a == b then
		return true
	end

	local mm_a = self:_get_metafield(a, "__eq")
	local mm_b = self:_get_metafield(b, "__eq")
	if mm_a and mm_a == mm_b then
		return (self:_do_call(mm_a, { a, b }))[1] and true or false
	end
	return false
end

function vm:_lt(a, b)
	if type(a) == "number" and type(b) == "number" then
		return a < b
	end
	if type(a) == "string" and type(b) == "string" then
		return a < b
	end
	local mm = self:_get_metafield(a, "__lt") or self:_get_metafield(b, "__lt")
	if mm then
		return (self:_do_call(mm, { a, b }))[1] and true or false
	end
	error(`attempt to compare {type(a)} with {type(b)}`)
end

function vm:_le(a, b)
	if type(a) == "number" and type(b) == "number" then
		return a <= b
	end
	if type(a) == "string" and type(b) == "string" then
		return a <= b
	end
	local mm = self:_get_metafield(a, "__le") or self:_get_metafield(b, "__le")
	if mm then
		return (self:_do_call(mm, { a, b }))[1] and true or false
	end

	return not self:_lt(b, a)
end

function vm:execute(chunk, args, upvalue_cells)
	local frame = self:make_frame(chunk, args, upvalue_cells)

	while frame.ip <= #frame.chunk.code do
		local op = frame.chunk.code[frame.ip]

		if op == OPCODES.LOAD_CONST then
			frame.ip += 1
			self:push(frame, frame.chunk.constants[frame.chunk.code[frame.ip] + 1])
		elseif op == OPCODES.LOAD_LOCAL then
			frame.ip += 1
			self:push(frame, frame.locals[frame.chunk.code[frame.ip]])
		elseif op == OPCODES.STORE_LOCAL then
			frame.ip += 1
			local reg = frame.chunk.code[frame.ip]
			local val = self:pop(frame)
			frame.locals[reg] = val

			if frame.local_cells and frame.local_cells[reg] then
				frame.local_cells[reg].value = val
			end
		elseif op == OPCODES.LOAD_GLOBAL then
			frame.ip += 1
			local name = frame.chunk.constants[frame.chunk.code[frame.ip] + 1]
			self:push(frame, self.globals[name])
		elseif op == OPCODES.STORE_GLOBAL then
			frame.ip += 1
			local name = frame.chunk.constants[frame.chunk.code[frame.ip] + 1]
			self.globals[name] = self:pop(frame)
		elseif op == OPCODES.LOAD_UPVALUE then
			frame.ip += 1
			local name = frame.chunk.constants[frame.chunk.code[frame.ip] + 1]
			local cell = frame.upvalue_cells[name]
			self:push(frame, cell and cell.value or nil)
		elseif op == OPCODES.STORE_UPVALUE then
			frame.ip += 1
			local name = frame.chunk.constants[frame.chunk.code[frame.ip] + 1]
			local cell = frame.upvalue_cells[name]
			if cell then
				cell.value = self:pop(frame)
			else
				frame.upvalue_cells[name] = { value = self:pop(frame) }
			end
		elseif op == OPCODES.PUSH_NIL then
			self:push(frame, nil)
		elseif op == OPCODES.PUSH_TRUE then
			self:push(frame, true)
		elseif op == OPCODES.PUSH_FALSE then
			self:push(frame, false)
		elseif op == OPCODES.POP then
			self:pop(frame)
		elseif op == OPCODES.ADD then
			local b, a = self:pop(frame), self:pop(frame)
			self:push(
				frame,
				self:_arith(a, b, "__add", function(x, y)
					return x + y
				end)
			)
		elseif op == OPCODES.SUB then
			local b, a = self:pop(frame), self:pop(frame)
			self:push(
				frame,
				self:_arith(a, b, "__sub", function(x, y)
					return x - y
				end)
			)
		elseif op == OPCODES.MUL then
			local b, a = self:pop(frame), self:pop(frame)
			self:push(
				frame,
				self:_arith(a, b, "__mul", function(x, y)
					return x * y
				end)
			)
		elseif op == OPCODES.DIV then
			local b, a = self:pop(frame), self:pop(frame)
			self:push(
				frame,
				self:_arith(a, b, "__div", function(x, y)
					return x / y
				end)
			)
		elseif op == OPCODES.MOD then
			local b, a = self:pop(frame), self:pop(frame)
			self:push(
				frame,
				self:_arith(a, b, "__mod", function(x, y)
					return x % y
				end)
			)
		elseif op == OPCODES.IDIV then
			local b, a = self:pop(frame), self:pop(frame)
			self:push(
				frame,
				self:_arith(a, b, "__idiv", function(x, y)
					return math.floor(x / y)
				end)
			)
		elseif op == OPCODES.POW then
			local b, a = self:pop(frame), self:pop(frame)
			self:push(
				frame,
				self:_arith(a, b, "__pow", function(x, y)
					return x ^ y
				end)
			)
		elseif op == OPCODES.UNM then
			local a = self:pop(frame)
			self:push(
				frame,
				self:_unary(a, "__unm", function(x)
					return -x
				end)
			)
		elseif op == OPCODES.CONCAT then
			local b, a = self:pop(frame), self:pop(frame)
			self:push(frame, self:_concat(a, b))
		elseif op == OPCODES.LEN then
			local a = self:pop(frame)
			self:push(frame, self:_len(a))
		elseif op == OPCODES.AND then
			local b, a = self:pop(frame), self:pop(frame)
			self:push(frame, a and b)
		elseif op == OPCODES.OR then
			local b, a = self:pop(frame), self:pop(frame)
			self:push(frame, a or b)
		elseif op == OPCODES.NOT then
			self:push(frame, not self:pop(frame))
		elseif op == OPCODES.EQ then
			local b, a = self:pop(frame), self:pop(frame)
			self:push(frame, self:_eq(a, b))
		elseif op == OPCODES.NEQ then
			local b, a = self:pop(frame), self:pop(frame)
			self:push(frame, not self:_eq(a, b))
		elseif op == OPCODES.LT then
			local b, a = self:pop(frame), self:pop(frame)
			self:push(frame, self:_lt(a, b))
		elseif op == OPCODES.LTE then
			local b, a = self:pop(frame), self:pop(frame)
			self:push(frame, self:_le(a, b))
		elseif op == OPCODES.GT then
			local b, a = self:pop(frame), self:pop(frame)
			self:push(frame, self:_lt(b, a))
		elseif op == OPCODES.GTE then
			local b, a = self:pop(frame), self:pop(frame)
			self:push(frame, self:_le(b, a))
		elseif op == OPCODES.JUMP then
			frame.ip += 1
			frame.ip = frame.chunk.code[frame.ip]
			continue
		elseif op == OPCODES.JUMP_IF_FALSE then
			frame.ip += 1
			local target = frame.chunk.code[frame.ip]
			if not self:pop(frame) then
				frame.ip = target
				continue
			end
		elseif op == OPCODES.JUMP_IF_FALSE_KEEP then
			frame.ip += 1
			local target = frame.chunk.code[frame.ip]
			if not self:peek_stack(frame) then
				frame.ip = target
				continue
			end
		elseif op == OPCODES.JUMP_IF_TRUE_KEEP then
			frame.ip += 1
			local target = frame.chunk.code[frame.ip]
			if self:peek_stack(frame) then
				frame.ip = target
				continue
			end
		elseif op == OPCODES.NEW_TABLE then
			self:push(frame, {})
		elseif op == OPCODES.SET_FIELD then
			frame.ip += 1
			local key = frame.chunk.constants[frame.chunk.code[frame.ip] + 1]
			local val = self:pop(frame)
			local tbl = self:peek_stack(frame)
			self:_set_index(tbl, key, val)
		elseif op == OPCODES.GET_FIELD then
			frame.ip += 1
			local key = frame.chunk.constants[frame.chunk.code[frame.ip] + 1]
			local tbl = self:pop(frame)
			if tbl == nil then
				error(`attempt to index a nil value (field '{key}')`)
			end
			self:push(frame, self:_get_index(tbl, key))
		elseif op == OPCODES.SET_INDEX then
			local val = self:pop(frame)
			local key = self:pop(frame)
			local tbl = self:peek_stack(frame)
			self:_set_index(tbl, key, val)
		elseif op == OPCODES.GET_INDEX then
			local key = self:pop(frame)
			local tbl = self:pop(frame)
			if tbl == nil then
				error(`attempt to index a nil value`)
			end
			self:push(frame, self:_get_index(tbl, key))
		elseif op == OPCODES.VARARG then
			for _, v in frame.varargs do
				self:push(frame, v)
			end
			self:push(frame, { __vararg_count = #frame.varargs })
		elseif op == OPCODES.VARARG_FIRST then
			self:push(frame, frame.varargs[1])
		elseif op == OPCODES.SET_VARARG_TABLE then
			local sentinel = self:pop(frame)
			local count = sentinel.__vararg_count
			local values = {}
			for i = count, 1, -1 do
				values[i] = self:pop(frame)
			end
			local offset = self:pop(frame)
			local tbl = self:peek_stack(frame)
			for i, v in values do
				tbl[offset + i - 1] = v
			end
		elseif op == OPCODES.CLOSURE then
			frame.ip += 1
			local sub_chunk = frame.chunk.constants[frame.chunk.code[frame.ip] + 1]

			local new_cells = {}

			for name, _ in sub_chunk.upvalue_names do
				if frame.upvalue_cells[name] then
					new_cells[name] = frame.upvalue_cells[name]
				else
					local reg = frame.chunk.locals[name]
					if reg ~= nil then
						if frame.local_cells and frame.local_cells[reg] then
							new_cells[name] = frame.local_cells[reg]
						else
							local cell = { value = frame.locals[reg] }
							if not frame.local_cells then
								frame.local_cells = {}
							end
							frame.local_cells[reg] = cell
							new_cells[name] = cell
						end
					else
						new_cells[name] = { value = self.globals[name] }
					end
				end
			end

			self:push(frame, {
				__type = "function",
				chunk = sub_chunk,
				upvalue_cells = new_cells,
			})
		elseif op == OPCODES.CALL then
			frame.ip += 1
			local arg_count = frame.chunk.code[frame.ip]
			local f_args = self:_collect_args(frame, arg_count)
			local func = self:pop(frame)
			local results = self:_do_call(func, f_args)
			self:push(frame, results[1])
		elseif op == OPCODES.CALL_VOID then
			frame.ip += 1
			local arg_count = frame.chunk.code[frame.ip]
			local f_args = self:_collect_args(frame, arg_count)
			local func = self:pop(frame)
			self:_do_call(func, f_args)
		elseif op == OPCODES.CALL_MULTI then
			frame.ip += 1
			local arg_count = frame.chunk.code[frame.ip]
			frame.ip += 1
			local expected = frame.chunk.code[frame.ip]
			local f_args = self:_collect_args(frame, arg_count)
			local func = self:pop(frame)
			local results = self:_do_call(func, f_args)
			for i = 1, expected do
				self:push(frame, results[i])
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
			error(`unknown opcode: {op} ({OPNAMES[op] or "?"}) at ip={frame.ip}`)
		end

		frame.ip += 1
	end

	return nil
end

function vm:_collect_args(frame, arg_count)
	local f_args = {}
	local top = self:peek_stack(frame)

	if type(top) == "table" and top.__vararg_count then
		self:pop(frame)
		local vararg_count = top.__vararg_count
		local varargs = {}
		for i = vararg_count, 1, -1 do
			varargs[i] = self:pop(frame)
		end
		local normal_count = arg_count - 1
		for i = normal_count, 1, -1 do
			f_args[i] = self:pop(frame)
		end
		for _, v in varargs do
			table.insert(f_args, v)
		end
	else
		for i = arg_count, 1, -1 do
			f_args[i] = self:pop(frame)
		end
	end

	return f_args
end

local _orig_push = vm.push
local _orig_pop = vm.pop

function vm:run()
	return self:execute(self.chunk)
end

local compiler_mod = __linker_require("src/compiler.lua")
local lexer_mod = __linker_require("src/lexer.lua")
local parser_mod = __linker_require("src/parser.lua")

function vm:runSource(source)
	local tokens = lexer_mod.new(source):run()
	local ast = parser_mod.new(tokens):run()
	local comp = compiler_mod.new()
	comp:run(ast)

	local instance = vm.new(comp.chunk)
	instance:load_stdlib()
	instance:load_roblox_env()

	instance.globals["_G"] = instance.globals
	instance:run()
end

return vm

end

-- [[ entry point: main.lua ]]
local vm = __linker_require("src/vm.lua")

vm:runSource([[
    print("VM Running!")
]])

getgenv().vm = vm

