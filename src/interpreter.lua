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
		metatables = {},
	}, vm)
	return self
end

function vm:load_stdlib()
	self.globals["print"] = print

	self.globals["tonumber"] = tonumber
	self.globals["typeof"] = typeof
	self.globals["type"] = type
	self.globals["pairs"] = pairs
	self.globals["ipairs"] = ipairs
	self.globals["next"] = next
	self.globals["error"] = error
	self.globals["assert"] = assert
	self.globals["unpack"] = table.unpack or unpack
	self.globals["select"] = select
	self.globals["debug"] = debug
	self.globals["pcall"] = pcall
	self.globals["xpcall"] = xpcall
	self.globals["tostring"] = tostring
	self.globals["rawequal"] = rawequal
	self.globals["rawlen"] = rawlen
	local vm_ref = self
	self.globals["setmetatable"] = function(tbl, mt)
		vm_ref.metatables[tbl] = mt
		return tbl
	end
	self.globals["getmetatable"] = function(tbl)
		local mt = vm_ref.metatables[tbl]
		if mt ~= nil then
			local guard = rawget(mt, "__metatable")
			if guard ~= nil then
				return guard
			end
			return mt
		end

		return getmetatable(tbl)
	end
	self.globals["rawget"] = rawget
	self.globals["rawset"] = rawset
	self.globals["loadstring"] = loadstring
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

	self.globals["getrawmetatable"] = getrawmetatable
	self.globals["syn"] = syn
	self.globals["getnamecallmethod"] = getnamecallmethod
	self.globals["checkcaller"] = checkcaller

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
		local_cells = {},
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

	for name, reg in chunk.captured_locals do
		if not frame.local_cells[reg] then
			frame.local_cells[reg] = { value = frame.locals[reg] }
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
	elseif type(func) == "table" then
		local mm = self:_get_metafield(func, "__call")
		if mm then
			return self:_do_call(mm, { func, table.unpack(f_args) })
		end
		error(`attempt to call a table value`)
	elseif type(func) == "userdata" then
		local ok, result = pcall(function()
			return table.pack(func(table.unpack(f_args)))
		end)
		if ok then
			return result
		end

		local nmt = getmetatable(func)
		if nmt then
			local mm = rawget(nmt, "__call")
			if mm then
				return self:_do_call(mm, { func, table.unpack(f_args) })
			end
		end
		error(`attempt to call a userdata value`)
	else
		error(`attempt to call a {type(func)} value`)
	end
end

function vm:_get_mt(obj)
	if type(obj) == "string" then
		return { __index = string }
	end
	return self.metatables[obj]
end

function vm:_get_metafield(obj, name)
	local mt = self:_get_mt(obj)
	if mt == nil then
		return nil
	end
	return rawget(mt, name)
end

function vm:_get_index(tbl, key)
	if type(tbl) == "string" then
		return string[key]
	end

	if type(tbl) ~= "table" then
		local ok, val = pcall(function()
			return tbl[key]
		end)
		return ok and val or nil
	end

	local raw = rawget(tbl, key)
	if raw ~= nil then
		return raw
	end

	local mt = self.metatables[tbl]
	if mt == nil then
		return nil
	end

	local index = rawget(mt, "__index")
	if index == nil then
		return nil
	end

	local itype = type(index)
	if itype == "function" then
		return (self:_do_call(index, { tbl, key }))[1]
	elseif itype == "table" then
		return self:_get_index(index, key)
	end
	return nil
end

function vm:_set_index(tbl, key, val)
	local mt = self.metatables[tbl]
	if mt ~= nil and rawget(tbl, key) == nil then
		local ni = rawget(mt, "__newindex")
		if ni ~= nil then
			if type(ni) == "function" then
				self:_do_call(ni, { tbl, key, val })
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
	if type(a) == "number" and type(b) == "number" then
		return native(a, b)
	end

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

	local code = frame.chunk.code
	local code_len = #code
	local constants = frame.chunk.constants
	local locals = frame.locals
	local local_cells = frame.local_cells
	local upvalue_cells_l = frame.upvalue_cells
	local captured_locals = frame.chunk.captured_locals
	local stack = frame.stack
	local ip = frame.ip
	local top = frame.top
	local varargs = frame.varargs
	local globals = self.globals
	local vmself = self

	local OP_LOAD_CONST = OPCODES.LOAD_CONST
	local OP_LOAD_LOCAL = OPCODES.LOAD_LOCAL
	local OP_STORE_LOCAL = OPCODES.STORE_LOCAL
	local OP_LOAD_GLOBAL = OPCODES.LOAD_GLOBAL
	local OP_STORE_GLOBAL = OPCODES.STORE_GLOBAL
	local OP_LOAD_UPVALUE = OPCODES.LOAD_UPVALUE
	local OP_STORE_UPVALUE = OPCODES.STORE_UPVALUE
	local OP_PUSH_NIL = OPCODES.PUSH_NIL
	local OP_PUSH_TRUE = OPCODES.PUSH_TRUE
	local OP_PUSH_FALSE = OPCODES.PUSH_FALSE
	local OP_POP = OPCODES.POP
	local OP_CALL_MULTI = OPCODES.CALL_MULTI
	local OP_ADD = OPCODES.ADD
	local OP_SUB = OPCODES.SUB
	local OP_MUL = OPCODES.MUL
	local OP_DIV = OPCODES.DIV
	local OP_MOD = OPCODES.MOD
	local OP_POW = OPCODES.POW
	local OP_IDIV = OPCODES.IDIV
	local OP_UNM = OPCODES.UNM
	local OP_CONCAT = OPCODES.CONCAT
	local OP_AND = OPCODES.AND
	local OP_OR = OPCODES.OR
	local OP_NOT = OPCODES.NOT
	local OP_EQ = OPCODES.EQ
	local OP_NEQ = OPCODES.NEQ
	local OP_LT = OPCODES.LT
	local OP_LTE = OPCODES.LTE
	local OP_GT = OPCODES.GT
	local OP_GTE = OPCODES.GTE
	local OP_LEN = OPCODES.LEN
	local OP_JUMP = OPCODES.JUMP
	local OP_JUMP_IF_FALSE = OPCODES.JUMP_IF_FALSE
	local OP_JUMP_IF_FALSE_KEEP = OPCODES.JUMP_IF_FALSE_KEEP
	local OP_JUMP_IF_TRUE_KEEP = OPCODES.JUMP_IF_TRUE_KEEP
	local OP_NEW_TABLE = OPCODES.NEW_TABLE
	local OP_SET_FIELD = OPCODES.SET_FIELD
	local OP_GET_FIELD = OPCODES.GET_FIELD
	local OP_SET_INDEX = OPCODES.SET_INDEX
	local OP_GET_INDEX = OPCODES.GET_INDEX
	local OP_CLOSURE = OPCODES.CLOSURE
	local OP_CALL = OPCODES.CALL
	local OP_CALL_VOID = OPCODES.CALL_VOID
	local OP_RETURN = OPCODES.RETURN
	local OP_MOVE = OPCODES.MOVE
	local OP_VARARG = OPCODES.VARARG
	local OP_SET_VARARG_TABLE = OPCODES.SET_VARARG_TABLE
	local OP_VARARG_FIRST = OPCODES.VARARG_FIRST

	local math_floor = math.floor
	local tbl_insert = table.insert

	while ip <= code_len do
		local op = code[ip]

		if op == OP_LOAD_CONST then
			ip += 1
			top += 1
			stack[top] = constants[code[ip] + 1]
		elseif op == OP_LOAD_LOCAL then
			ip += 1
			local reg = code[ip]
			if local_cells and local_cells[reg] then
				top += 1
				stack[top] = local_cells[reg].value
			else
				top += 1
				stack[top] = locals[reg]
			end
		elseif op == OP_STORE_LOCAL then
			ip += 1
			local reg = code[ip]
			local val = stack[top]
			stack[top] = nil
			top -= 1
			locals[reg] = val
			if local_cells and local_cells[reg] then
				local_cells[reg].value = val
			end
		elseif op == OP_LOAD_GLOBAL then
			ip += 1
			top += 1
			stack[top] = globals[constants[code[ip] + 1]]
		elseif op == OP_STORE_GLOBAL then
			ip += 1
			globals[constants[code[ip] + 1]] = stack[top]
			stack[top] = nil
			top -= 1
		elseif op == OP_LOAD_UPVALUE then
			ip += 1
			local cell = upvalue_cells_l[constants[code[ip] + 1]]
			top += 1
			stack[top] = cell and cell.value or nil
		elseif op == OP_STORE_UPVALUE then
			ip += 1
			local name = constants[code[ip] + 1]
			local cell = upvalue_cells_l[name]
			local val = stack[top]
			stack[top] = nil
			top -= 1
			if cell then
				cell.value = val
			else
				upvalue_cells_l[name] = { value = val }
			end
		elseif op == OP_PUSH_NIL then
			top += 1
			stack[top] = nil
		elseif op == OP_PUSH_TRUE then
			top += 1
			stack[top] = true
		elseif op == OP_PUSH_FALSE then
			top += 1
			stack[top] = false
		elseif op == OP_POP then
			stack[top] = nil
			top -= 1
		elseif op == OP_ADD then
			local b = stack[top]
			stack[top] = nil
			top -= 1
			local a = stack[top]
			stack[top] = nil
			top -= 1
			local ta, tb = type(a), type(b)
			if ta == "number" and tb == "number" then
				top += 1
				stack[top] = a + b
			else
				frame.ip = ip
				frame.top = top
				top += 1
				stack[top] = vmself:_arith(a, b, "__add", function(x, y)
					return x + y
				end)
			end
		elseif op == OP_SUB then
			local b = stack[top]
			stack[top] = nil
			top -= 1
			local a = stack[top]
			stack[top] = nil
			top -= 1
			local ta, tb = type(a), type(b)
			if ta == "number" and tb == "number" then
				top += 1
				stack[top] = a - b
			else
				frame.ip = ip
				frame.top = top
				top += 1
				stack[top] = vmself:_arith(a, b, "__sub", function(x, y)
					return x - y
				end)
			end
		elseif op == OP_MUL then
			local b = stack[top]
			stack[top] = nil
			top -= 1
			local a = stack[top]
			stack[top] = nil
			top -= 1
			local ta, tb = type(a), type(b)
			if ta == "number" and tb == "number" then
				top += 1
				stack[top] = a * b
			else
				frame.ip = ip
				frame.top = top
				top += 1
				stack[top] = vmself:_arith(a, b, "__mul", function(x, y)
					return x * y
				end)
			end
		elseif op == OP_DIV then
			local b = stack[top]
			stack[top] = nil
			top -= 1
			local a = stack[top]
			stack[top] = nil
			top -= 1
			local ta, tb = type(a), type(b)
			if ta == "number" and tb == "number" then
				top += 1
				stack[top] = a / b
			else
				frame.ip = ip
				frame.top = top
				top += 1
				stack[top] = vmself:_arith(a, b, "__div", function(x, y)
					return x / y
				end)
			end
		elseif op == OP_MOD then
			local b = stack[top]
			stack[top] = nil
			top -= 1
			local a = stack[top]
			stack[top] = nil
			top -= 1
			local ta, tb = type(a), type(b)
			if ta == "number" and tb == "number" then
				top += 1
				stack[top] = a % b
			else
				frame.ip = ip
				frame.top = top
				top += 1
				stack[top] = vmself:_arith(a, b, "__mod", function(x, y)
					return x % y
				end)
			end
		elseif op == OP_POW then
			local b = stack[top]
			stack[top] = nil
			top -= 1
			local a = stack[top]
			stack[top] = nil
			top -= 1
			local ta, tb = type(a), type(b)
			if ta == "number" and tb == "number" then
				top += 1
				stack[top] = a ^ b
			else
				frame.ip = ip
				frame.top = top
				top += 1
				stack[top] = vmself:_arith(a, b, "__pow", function(x, y)
					return x ^ y
				end)
			end
		elseif op == OP_IDIV then
			local b = stack[top]
			stack[top] = nil
			top -= 1
			local a = stack[top]
			stack[top] = nil
			top -= 1
			local ta, tb = type(a), type(b)
			if ta == "number" and tb == "number" then
				top += 1
				stack[top] = math_floor(a / b)
			else
				frame.ip = ip
				frame.top = top
				top += 1
				stack[top] = vmself:_arith(a, b, "__idiv", function(x, y)
					return math_floor(x / y)
				end)
			end
		elseif op == OP_UNM then
			local a = stack[top]
			stack[top] = nil
			top -= 1
			if type(a) == "number" then
				top += 1
				stack[top] = -a
			else
				frame.ip = ip
				frame.top = top
				top += 1
				stack[top] = vmself:_unary(a, "__unm", function(x)
					return -x
				end)
			end
		elseif op == OP_CONCAT then
			local b = stack[top]
			stack[top] = nil
			top -= 1
			local a = stack[top]
			stack[top] = nil
			top -= 1
			frame.ip = ip
			frame.top = top
			top += 1
			stack[top] = vmself:_concat(a, b)
		elseif op == OP_LEN then
			local a = stack[top]
			stack[top] = nil
			top -= 1
			frame.ip = ip
			frame.top = top
			top += 1
			stack[top] = vmself:_len(a)
		elseif op == OP_AND then
			local b = stack[top]
			stack[top] = nil
			top -= 1
			local a = stack[top]
			stack[top] = nil
			top -= 1
			top += 1
			stack[top] = a and b
		elseif op == OP_OR then
			local b = stack[top]
			stack[top] = nil
			top -= 1
			local a = stack[top]
			stack[top] = nil
			top -= 1
			top += 1
			stack[top] = a or b
		elseif op == OP_NOT then
			stack[top] = not stack[top]
		elseif op == OP_EQ then
			local b = stack[top]
			stack[top] = nil
			top -= 1
			local a = stack[top]
			stack[top] = nil
			top -= 1
			frame.ip = ip
			frame.top = top
			top += 1
			stack[top] = vmself:_eq(a, b)
		elseif op == OP_NEQ then
			local b = stack[top]
			stack[top] = nil
			top -= 1
			local a = stack[top]
			stack[top] = nil
			top -= 1
			frame.ip = ip
			frame.top = top
			top += 1
			stack[top] = not vmself:_eq(a, b)
		elseif op == OP_LT then
			local b = stack[top]
			stack[top] = nil
			top -= 1
			local a = stack[top]
			stack[top] = nil
			top -= 1
			local ta, tb = type(a), type(b)
			if ta == "number" and tb == "number" then
				top += 1
				stack[top] = a < b
			elseif ta == "string" and tb == "string" then
				top += 1
				stack[top] = a < b
			else
				frame.ip = ip
				frame.top = top
				top += 1
				stack[top] = vmself:_lt(a, b)
			end
		elseif op == OP_LTE then
			local b = stack[top]
			stack[top] = nil
			top -= 1
			local a = stack[top]
			stack[top] = nil
			top -= 1
			local ta, tb = type(a), type(b)
			if ta == "number" and tb == "number" then
				top += 1
				stack[top] = a <= b
			elseif ta == "string" and tb == "string" then
				top += 1
				stack[top] = a <= b
			else
				frame.ip = ip
				frame.top = top
				top += 1
				stack[top] = vmself:_le(a, b)
			end
		elseif op == OP_GT then
			local b = stack[top]
			stack[top] = nil
			top -= 1
			local a = stack[top]
			stack[top] = nil
			top -= 1
			local ta, tb = type(a), type(b)
			if ta == "number" and tb == "number" then
				top += 1
				stack[top] = a > b
			elseif ta == "string" and tb == "string" then
				top += 1
				stack[top] = a > b
			else
				frame.ip = ip
				frame.top = top
				top += 1
				stack[top] = vmself:_lt(b, a)
			end
		elseif op == OP_GTE then
			local b = stack[top]
			stack[top] = nil
			top -= 1
			local a = stack[top]
			stack[top] = nil
			top -= 1
			local ta, tb = type(a), type(b)
			if ta == "number" and tb == "number" then
				top += 1
				stack[top] = a >= b
			elseif ta == "string" and tb == "string" then
				top += 1
				stack[top] = a >= b
			else
				frame.ip = ip
				frame.top = top
				top += 1
				stack[top] = vmself:_le(b, a)
			end
		elseif op == OP_JUMP then
			ip = code[ip + 1] - 1
		elseif op == OP_JUMP_IF_FALSE then
			local target = code[ip + 1]
			local v = stack[top]
			stack[top] = nil
			top -= 1
			if not v then
				ip = target - 1
			else
				ip += 1
			end
		elseif op == OP_JUMP_IF_FALSE_KEEP then
			local target = code[ip + 1]
			if not stack[top] then
				ip = target - 1
			else
				ip += 1
			end
		elseif op == OP_JUMP_IF_TRUE_KEEP then
			local target = code[ip + 1]
			if stack[top] then
				ip = target - 1
			else
				ip += 1
			end
		elseif op == OP_NEW_TABLE then
			top += 1
			stack[top] = {}
		elseif op == OP_SET_FIELD then
			ip += 1
			local key = constants[code[ip] + 1]
			local val = stack[top]
			stack[top] = nil
			top -= 1
			local tbl = stack[top]
			if type(tbl) ~= "table" then
				error(`attempt to index '{type(tbl)}' value`)
			end
			frame.ip = ip
			frame.top = top
			vmself:_set_index(tbl, key, val)
		elseif op == OP_GET_FIELD then
			ip += 1
			local key = constants[code[ip] + 1]
			local tbl = stack[top]
			stack[top] = nil
			top -= 1
			if tbl == nil then
				error(`attempt to index a nil value (field '{key}')`)
			end
			local ttbl = type(tbl)
			if ttbl ~= "table" and ttbl ~= "string" then
				error(`attempt to index '{ttbl}' value`)
			end
			frame.ip = ip
			frame.top = top
			top += 1
			stack[top] = vmself:_get_index(tbl, key)
		elseif op == OP_SET_INDEX then
			local val = stack[top]
			stack[top] = nil
			top -= 1
			local key = stack[top]
			stack[top] = nil
			top -= 1
			local tbl = stack[top]
			frame.ip = ip
			frame.top = top
			vmself:_set_index(tbl, key, val)
		elseif op == OP_GET_INDEX then
			local key = stack[top]
			stack[top] = nil
			top -= 1
			local tbl = stack[top]
			stack[top] = nil
			top -= 1
			if tbl == nil then
				error(`attempt to index a nil value`)
			end
			frame.ip = ip
			frame.top = top
			top += 1
			stack[top] = vmself:_get_index(tbl, key)
		elseif op == OP_VARARG then
			for _, v in varargs do
				top += 1
				stack[top] = v
			end
			top += 1
			stack[top] = { __vararg_count = #varargs }
		elseif op == OP_VARARG_FIRST then
			top += 1
			stack[top] = varargs[1]
		elseif op == OP_SET_VARARG_TABLE then
			local sentinel = stack[top]
			stack[top] = nil
			top -= 1
			local count = sentinel.__vararg_count
			local values = {}
			for i = count, 1, -1 do
				values[i] = stack[top]
				stack[top] = nil
				top -= 1
			end
			local offset = stack[top]
			stack[top] = nil
			top -= 1
			local tbl = stack[top]
			for i, v in values do
				tbl[offset + i - 1] = v
			end
		elseif op == OP_CLOSURE then
			ip += 1
			local sub_chunk = constants[code[ip] + 1]
			local new_cells = {}
			for name, _ in sub_chunk.upvalue_names do
				if upvalue_cells_l[name] then
					new_cells[name] = upvalue_cells_l[name]
				else
					local reg = captured_locals[name]
					if reg ~= nil then
						if local_cells and local_cells[reg] then
							new_cells[name] = local_cells[reg]
						else
							local cell = { value = locals[reg] }
							if not local_cells then
								local_cells = {}
								frame.local_cells = local_cells
							end
							local_cells[reg] = cell
							new_cells[name] = cell
						end
					else
						new_cells[name] = { value = globals[name] }
					end
				end
			end
			local sub = sub_chunk
			top += 1
			stack[top] = function(...)
				local res = vmself:execute(sub, { ... }, new_cells)
				return table.unpack(res or {})
			end
		elseif op == OP_CALL then
			ip += 1
			local arg_count = code[ip]

			local f_args = {}
			local top_val = stack[top]
			if type(top_val) == "table" and top_val.__vararg_count then
				stack[top] = nil
				top -= 1
				local vc = top_val.__vararg_count
				local vbuf = {}
				for i = vc, 1, -1 do
					vbuf[i] = stack[top]
					stack[top] = nil
					top -= 1
				end
				local nc = arg_count - 1
				for i = nc, 1, -1 do
					f_args[i] = stack[top]
					stack[top] = nil
					top -= 1
				end
				for _, v in vbuf do
					tbl_insert(f_args, v)
				end
			else
				for i = arg_count, 1, -1 do
					f_args[i] = stack[top]
					stack[top] = nil
					top -= 1
				end
			end
			local func = stack[top]
			stack[top] = nil
			top -= 1
			frame.ip = ip
			frame.top = top
			local results = vmself:_do_call(func, f_args)
			top += 1
			stack[top] = results[1]
		elseif op == OP_CALL_VOID then
			ip += 1
			local arg_count = code[ip]
			local f_args = {}
			local top_val = stack[top]
			if type(top_val) == "table" and top_val.__vararg_count then
				stack[top] = nil
				top -= 1
				local vc = top_val.__vararg_count
				local vbuf = {}
				for i = vc, 1, -1 do
					vbuf[i] = stack[top]
					stack[top] = nil
					top -= 1
				end
				local nc = arg_count - 1
				for i = nc, 1, -1 do
					f_args[i] = stack[top]
					stack[top] = nil
					top -= 1
				end
				for _, v in vbuf do
					tbl_insert(f_args, v)
				end
			else
				for i = arg_count, 1, -1 do
					f_args[i] = stack[top]
					stack[top] = nil
					top -= 1
				end
			end
			local func = stack[top]
			stack[top] = nil
			top -= 1
			frame.ip = ip
			frame.top = top
			vmself:_do_call(func, f_args)
		elseif op == OP_CALL_MULTI then
			ip += 1
			local arg_count = code[ip]
			ip += 1
			local expected = code[ip]
			local f_args = {}
			local top_val = stack[top]
			if type(top_val) == "table" and top_val.__vararg_count then
				stack[top] = nil
				top -= 1
				local vc = top_val.__vararg_count
				local vbuf = {}
				for i = vc, 1, -1 do
					vbuf[i] = stack[top]
					stack[top] = nil
					top -= 1
				end
				local nc = arg_count - 1
				for i = nc, 1, -1 do
					f_args[i] = stack[top]
					stack[top] = nil
					top -= 1
				end
				for _, v in vbuf do
					tbl_insert(f_args, v)
				end
			else
				for i = arg_count, 1, -1 do
					f_args[i] = stack[top]
					stack[top] = nil
					top -= 1
				end
			end
			local func = stack[top]
			stack[top] = nil
			top -= 1
			frame.ip = ip
			frame.top = top
			local results = vmself:_do_call(func, f_args)
			for i = 1, expected do
				top += 1
				stack[top] = results[i]
			end
		elseif op == OP_RETURN then
			ip += 1
			local count = code[ip]
			local results = {}
			for i = count, 1, -1 do
				results[i] = stack[top]
				stack[top] = nil
				top -= 1
			end
			frame.ip = ip
			frame.top = top
			return results
		elseif op == OP_MOVE then
		else
			error(`unknown opcode: {op} ({OPNAMES[op] or "?"}) at ip={ip}`)
		end

		ip += 1
	end

	frame.ip = ip
	frame.top = top
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

local compiler_mod = require("./compiler")
local lexer_mod = require("./lexer")
local parser_mod = require("./parser")
local macros = require("./macros")

function vm:runSource(source, debug)
	debug = debug or {}

	local startLex = os.clock()
	local tokens = lexer_mod.new(source):run()
	local endLex = os.clock()

	local ast = parser_mod.new(tokens):run()

	local endAst = os.clock()

	ast = macros.expand(ast, lexer_mod, parser_mod)

	local endMacros = os.clock()

	local comp = compiler_mod.new()

	comp:run(ast)

	local endComp = os.clock()

	local instance = vm.new(comp.chunk)
	instance:load_stdlib()
	instance:load_roblox_env()

	instance.globals["_G"] = instance.globals
	local succ, err = pcall(instance.run, instance)

	local endRan = os.clock()
	if not succ then
		if debug then
			error(err)
		end
		error(err, 2)
	end
	if debug.b == true then
		comp:dump(false)
	end
	if debug.m == true then
		print(
			string.format(
				"took %.0f [lexing: %.0f] [parsing: %.0f] [compilation: %.0f] [execution: %.0f] (microseconds)",
				(endRan - startLex) * 1000000,
				(endAst - endLex) * 1000000,
				(endMacros - endAst) * 1000000,
				(endComp - endMacros) * 1000000,
				(endRan - endComp) * 1000000
			)
		)
	end
end

return vm
