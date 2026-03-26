local vm = {}
vm.__index = vm

local OPCODES, OPNAMES
do
	local export = require("./opcodes")
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
			for name, reg in pairs(frame.chunk.locals) do
				f_upvalues[name] = frame.locals[reg]
			end
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
			local expected = frame.chunk.code[frame.ip + 1]
			frame.ip += 1
			local f_args = {}
			for i = arg_count, 1, -1 do
				f_args[i] = self:pop(frame)
			end
			local func = self:pop(frame)
			if type(func) == "function" then
				local result = table.pack(func(table.unpack(f_args)))
				for i = 1, expected do
					self:push(frame, result[i]) -- result[i] is nil if i > result.n
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
