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

local compiler_mod = require("./compiler")
local lexer_mod = require("./lexer")
local parser_mod = require("./parser")

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
