-- MIT License
-- Copyright (c) 2026 Bradley

local macros = {}

local function has_attr(node, name)
	if not node.attributes then
		return false
	end
	for _, a in node.attributes do
		if a.name == name then
			return true
		end
	end
	return false
end

local function deep_copy(v)
	if type(v) ~= "table" then
		return v
	end
	local copy = {}
	for k, v in v do
		copy[k] = deep_copy(v)
	end
	return copy
end

local function substitute(node, bindings)
	if type(node) ~= "table" then
		return node
	end
	if node.kind == "Identifier" and bindings[node.name] then
		return deep_copy(bindings[node.name])
	end
	local out = {}
	for k, v in node do
		out[k] = substitute(v, bindings)
	end
	return out
end

local function expand_macro(def, args, lexer, parser)
	if #args ~= #def.params then
		error(`macro '{def.name}' expects {#def.params} args but got {#args} args`)
	end
	local bindings = {}
	for i, p in def.params do
		bindings[p] = args[i]
	end

	local stub_map = {}
	local parts = {}

	for _, tok in def.body_tokens do
		if tok.type == "IDENTIFIER" and bindings[tok.value] then
			local stub = "__macro_arg_" .. tok.value .. "__"
			stub_map[stub] = bindings[tok.value]
			table.insert(parts, stub)
		elseif tok.type == "STRING" then
			table.insert(parts, '"' .. tok.value:gsub("\\", "\\\\"):gsub('"', '\\"') .. '"')
		elseif tok.type == "NUMBER" then
			table.insert(parts, tostring(tok.value))
		else
			table.insert(parts, tostring(tok.value))
		end
	end

	local src = table.concat(parts, " ")
	local tokens = lexer.new(src):run()
	local p = parser.new(tokens)

	local ok, result = pcall(parser.parse_expression, p)
	if not ok then
		p.pos = 1
		result = p:parse_expression()
	end

	local function swap_stub(node)
		if type(node) ~= "table" then
			return node
		end
		if node.kind == "Identifier" and stub_map[node.name] then
			return deep_copy(stub_map[node.name])
		end
		local out = {}
		for k, v in node do
			out[k] = swap_stub(v)
		end
		return out
	end
	return swap_stub(result)
end

local function expand_inline(idef, args)
	if #args ~= #idef.params then
		error(`inline function '{idef.name}' expects {#idef.params} args but got {#args}`)
	end

	local param_stmts = {}
	for i, pname in idef.params do
		table.insert(param_stmts, {
			kind = "LocalStatement",
			names = { pname },
			values = { deep_copy(args[i]) },
			attributes = {},
		})
	end

	local body_stmts = {}
	for _, s in param_stmts do
		table.insert(body_stmts, s)
	end
	for _, s in idef.body.body do
		table.insert(body_stmts, deep_copy(s))
	end
	return {
		kind = "InlineCall",
		name = idef.name,
		body = { kind = "Block", body = body_stmts },
		attributes = {},
	}
end

local function expand_inline_stmt(idef, args)
	return expand_inline(idef, args)
end

local function expand_calls(node, defs, lexer, parser, inline_defs)
	if type(node) ~= "table" then
		return node
	end

	if node.kind == "CallStatement" and node.expr and node.expr.kind == "CallExpr" then
		local callee = node.expr.callee
		if callee and callee.kind == "Identifier" then
			local idef = inline_defs[callee.name]
			if idef then
				local resolved_args = {}
				for i, a in node.expr.args do
					resolved_args[i] = expand_calls(a, defs, lexer, parser, inline_defs)
				end
				return expand_inline_stmt(idef, resolved_args)
			end
			local def = defs[callee.name]
			if def then
				local resolved_args = {}
				for i, a in node.expr.args do
					resolved_args[i] = expand_calls(a, defs, lexer, parser, inline_defs)
				end
				local expanded = expand_macro(def, resolved_args, lexer, parser)
				if expanded.kind == "CallExpr" or expanded.kind == "MethodCall" then
					return { kind = "CallStatement", expr = expanded, attributes = {} }
				end
				return expanded
			end
		end
	end

	if node.kind == "CallExpr" and node.callee and node.callee.kind == "Identifier" then
		local idef = inline_defs[node.callee.name]
		if idef then
			local resolved_args = {}
			for i, a in node.args do
				resolved_args[i] = expand_calls(a, defs, lexer, parser, inline_defs)
			end
			return expand_inline(idef, resolved_args)
		end
		local def = defs[node.callee.name]
		if def then
			local resolved_args = {}
			for i, a in node.args do
				resolved_args[i] = expand_calls(a, defs, lexer, parser, inline_defs)
			end
			return expand_macro(def, resolved_args, lexer, parser)
		end
	end

	local out = {}
	for k, v in node do
		out[k] = expand_calls(v, defs, lexer, parser, inline_defs)
	end
	return out
end

local function is_literal(node)
	return node.kind == "Number" or node.kind == "String" or node.kind == "Boolean" or node.kind == "Nil"
end

local FOLD_ARITH = {
	["+"] = function(a, b)
		return a + b
	end,
	["-"] = function(a, b)
		return a - b
	end,
	["*"] = function(a, b)
		return a * b
	end,
	["/"] = function(a, b)
		return a / b
	end,
	["%"] = function(a, b)
		return a % b
	end,
	["^"] = function(a, b)
		return a ^ b
	end,
	["//"] = function(a, b)
		return math.floor(a / b)
	end,
}

local FOLD_CMP = {
	["=="] = function(a, b)
		return a == b
	end,
	["~="] = function(a, b)
		return a ~= b
	end,
	["<"] = function(a, b)
		return a < b
	end,
	["<="] = function(a, b)
		return a <= b
	end,
	[">"] = function(a, b)
		return a > b
	end,
	[">="] = function(a, b)
		return a >= b
	end,
}

local function fold_node(node)
	if node.kind == "BinaryExpr" then
		local l, r = node.left, node.right

		if FOLD_ARITH[node.op] and l.kind == "Number" and r.kind == "Number" then
			local ok, result = pcall(FOLD_ARITH[node.op], l.value, r.value)
			if ok then
				return { kind = "Number", value = result, attributes = {} }
			end
		end

		if node.op == ".." then
			local lv = l.kind == "String" and l.value or (l.kind == "Number" and tostring(l.value))
			local rv = r.kind == "String" and r.value or (r.kind == "Number" and tostring(r.value))
			if lv and rv then
				return { kind = "String", value = lv .. rv, attributes = {} }
			end
		end

		if FOLD_CMP[node.op] and is_literal(l) and is_literal(r) then
			local same_type = l.kind == r.kind
			local equality_op = node.op == "==" or node.op == "~="
			if same_type or equality_op then
				local lv = (l.kind == "Nil") and nil or l.value
				local rv = (r.kind == "Nil") and nil or r.value
				local ok, result = pcall(FOLD_CMP[node.op], lv, rv)
				if ok then
					return { kind = "Boolean", value = result, attributes = {} }
				end
			end
		end

		if node.op == "and" then
			if (l.kind == "Boolean" and l.value == false) or l.kind == "Nil" then
				return l
			end
			if l.kind == "Boolean" and l.value == true then
				return r
			end
		end
		if node.op == "or" then
			if (l.kind == "Boolean" and l.value == false) or l.kind == "Nil" then
				return r
			end
			if l.kind == "Boolean" and l.value == true then
				return l
			end
		end
	end

	if node.kind == "UnaryExpr" then
		local o = node.operand
		if node.op == "-" and o.kind == "Number" then
			return { kind = "Number", value = -o.value, attributes = {} }
		end
		if node.op == "not" and (o.kind == "Boolean" or o.kind == "Nil") then
			return { kind = "Boolean", value = not (o.kind ~= "Nil" and o.value), attributes = {} }
		end
		if node.op == "#" and o.kind == "String" then
			return { kind = "Number", value = #o.value, attributes = {} }
		end
	end

	return node
end

local function fold(node)
	if type(node) ~= "table" then
		return node
	end
	local out = {}
	for k, v in node do
		out[k] = fold(v)
	end
	return fold_node(out)
end

local function inline_consts(node, const_defs)
	if type(node) ~= "table" then
		return node
	end
	if node.kind == "Identifier" and const_defs[node.name] then
		return deep_copy(const_defs[node.name])
	end

	if node.kind == "Block" then
		local local_defs = {}
		for k, v in const_defs do
			local_defs[k] = v
		end
		local new_body = {}
		for _, stmt in node.body do
			if stmt.kind == "LocalStatement" then
				for _, name in stmt.names do
					local_defs[name] = nil
				end
			end
			table.insert(new_body, inline_consts(stmt, local_defs))
		end
		return { kind = "Block", body = new_body }
	end
	local out = {}
	for k, v in node do
		out[k] = inline_consts(v, const_defs)
	end
	return out
end

local function process_unroll(node)
	if node.kind ~= "NumericFor" then
		error("@unroll can only be applied to a numeric for loop")
	end

	local function as_number(expr, label)
		if expr and expr.kind == "Number" then
			return expr.value
		end
		error(`@unroll requires a constant numeric literal for '{label}' got '{expr and expr.kind or "nil"}'`)
	end
	local start = as_number(node.start, "start")
	local limit = as_number(node.limit, "limit")
	local step = node.step and as_number(node.step, "step") or 1

	if step == 0 then
		error("@unroll step cannot be 0")
	end

	local MAX_UNROLL = 1024
	local count = math.floor((limit - start) / step) + 1
	if count < 0 then
		count = 0
	end
	if count > MAX_UNROLL then
		error(`@unroll would generate {count} iterations (max {MAX_UNROLL}) use a regular for loop or reduce the limit`)
	end
	local iterations = {}
	local i_val = start
	while (step > 0 and i_val <= limit) or (step < 0 and i_val >= limit) do
		table.insert(iterations, {
			i_value = i_val,
			body = deep_copy(node.body),
		})
		i_val = i_val + step
	end

	return {
		kind = "UnrolledFor",
		name = node.name,
		iterations = iterations,
		attributes = node.attributes or {},
	}
end

local function walk(node, defs, lexer, parser, inline_defs, const_defs)
	if type(node) ~= "table" then
		return node
	end
	if node.kind == "DefineDirective" then
		defs[node.name] = node
		return nil
	end

	if node.kind == "LocalStatement" and has_attr(node, "const") then
		for i, name in node.names do
			local val_node = node.values[i]
			if not val_node then
				error(`@const '{name}' must have an initialiser`)
			end

			local folded = fold(val_node)
			if not is_literal(folded) then
				error(`@const '{name}' value must reduce to a compile-time literal (got '{folded.kind}')`)
			end
			const_defs[name] = folded
		end
		return nil
	end

	if has_attr(node, "inline") then
		local fname, func_node
		if node.kind == "LocalFunction" then
			fname = node.name
			func_node = node.func
		elseif node.kind == "FunctionStatement" and #node.name == 1 then
			fname = node.name[1]
			func_node = node.func
		end
		if fname and func_node then
			inline_defs[fname] = {
				name = fname,
				params = func_node.params,
				body = func_node.body,
			}
			return nil
		end
	end

	if has_attr(node, "memoize") then
		local fname, func_node, is_local
		if node.kind == "LocalFunction" then
			fname = node.name
			func_node = node.func
			is_local = true
		elseif node.kind == "FunctionStatement" and #node.name == 1 then
			fname = node.name[1]
			func_node = node.func
			is_local = false
		end

		if not fname or not func_node then
			error("@memoize can only be applied to a simple local or global function declaration")
		end

		local cache_name = "__memo_" .. fname .. "__"
		local params = func_node.params

		local key_expr
		if #params == 0 then
			key_expr = { kind = "String", value = "__memo_noarg__", attributes = {} }
		else
			local function tostring_call(pname)
				return {
					kind = "CallExpr",
					callee = { kind = "Identifier", name = "tostring" },
					args = { { kind = "Identifier", name = pname } },
					attributes = {},
				}
			end
			local sep = { kind = "String", value = "|", attributes = {} }
			key_expr = tostring_call(params[1])
			for i = 2, #params do
				key_expr = {
					kind = "BinaryExpr",
					op = "..",
					left = key_expr,
					right = {
						kind = "BinaryExpr",
						op = "..",
						left = sep,
						right = tostring_call(params[i]),
					},
					attributes = {},
				}
			end
		end

		local key_local = {
			kind = "LocalStatement",
			names = { "__memo_key__" },
			values = { key_expr },
			attributes = {},
		}

		local cached_local = {
			kind = "LocalStatement",
			names = { "__memo_cached__" },
			values = {
				{
					kind = "IndexAccess",
					object = { kind = "Identifier", name = cache_name },
					index = { kind = "Identifier", name = "__memo_key__" },
				},
			},
			attributes = {},
		}

		local cache_hit_if = {
			kind = "IfStatement",
			condition = {
				kind = "BinaryExpr",
				op = "~=",
				left = { kind = "Identifier", name = "__memo_cached__" },
				right = { kind = "Nil" },
				attributes = {},
			},
			body = {
				kind = "Block",
				body = {
					{
						kind = "ReturnStatement",
						values = { { kind = "Identifier", name = "__memo_cached__" } },
						attributes = {},
					},
				},
			},
			elseifs = {},
			else_body = nil,
			attributes = {},
		}

		local function rewrite_returns(block_node)
			if type(block_node) ~= "table" then
				return block_node
			end
			if block_node.kind == "Block" then
				local new_body = {}
				for _, stmt in block_node.body do
					if stmt.kind == "ReturnStatement" then
						local ret_val = stmt.values[1] or { kind = "Nil" }
						table.insert(new_body, {
							kind = "LocalStatement",
							names = { "__memo_result__" },
							values = { ret_val },
							attributes = {},
						})

						table.insert(new_body, {
							kind = "Assignment",
							targets = {
								{
									kind = "IndexAccess",
									object = { kind = "Identifier", name = cache_name },
									index = { kind = "Identifier", name = "__memo_key__" },
								},
							},
							op = "=",
							values = { { kind = "Identifier", name = "__memo_result__" } },
							attributes = {},
						})

						table.insert(new_body, {
							kind = "ReturnStatement",
							values = { { kind = "Identifier", name = "__memo_result__" } },
							attributes = {},
						})
					else
						table.insert(new_body, rewrite_returns(stmt))
					end
				end
				return { kind = "Block", body = new_body }
			end

			if
				block_node.kind == "Function"
				or block_node.kind == "LocalFunction"
				or block_node.kind == "FunctionStatement"
			then
				return block_node
			end
			local out = {}
			for k, v in block_node do
				out[k] = rewrite_returns(v)
			end
			return out
		end

		local rewritten_body = rewrite_returns(func_node.body)

		local new_body_stmts = { key_local, cached_local, cache_hit_if }
		for _, s in rewritten_body.body do
			table.insert(new_body_stmts, s)
		end

		local new_func = {
			kind = "Function",
			params = params,
			body = { kind = "Block", body = new_body_stmts },
			attributes = {},
		}

		local cache_decl = {
			kind = "LocalStatement",
			names = { cache_name },
			values = { { kind = "Table", fields = {}, attributes = {} } },
			attributes = {},
		}

		local func_decl
		if is_local then
			func_decl = {
				kind = "LocalFunction",
				name = fname,
				func = new_func,
				attributes = {},
			}
		else
			func_decl = {
				kind = "FunctionStatement",
				name = { fname },
				is_method = false,
				func = new_func,
				attributes = {},
			}
		end

		return {
			kind = "MemoizeDecl",
			cache_decl = cache_decl,
			func_decl = func_decl,
			attributes = {},
		}
	end

	if node.kind == "NumericFor" and has_attr(node, "unroll") then
		local unrolled = process_unroll(node)
		for _, itr in unrolled.iterations do
			itr.body = walk(itr.body, defs, lexer, parser, inline_defs, const_defs)
		end
		return unrolled
	end

	if node.kind == "Block" then
		local block_consts = {}
		for k, v in const_defs do
			block_consts[k] = v
		end
		local new_body = {}
		for _, stmt in node.body do
			local result = walk(stmt, defs, lexer, parser, inline_defs, block_consts)
			if result ~= nil then
				if type(result) == "table" and result.kind == "MemoizeDecl" then
					local walked_cache = walk(result.cache_decl, defs, lexer, parser, inline_defs, block_consts)
					local walked_func = walk(result.func_decl, defs, lexer, parser, inline_defs, block_consts)
					if walked_cache then
						walked_cache = inline_consts(walked_cache, block_consts)
						table.insert(new_body, walked_cache)
					end
					if walked_func then
						walked_func = inline_consts(walked_func, block_consts)
						table.insert(new_body, walked_func)
					end
				else
					result = inline_consts(result, block_consts)
					table.insert(new_body, result)
				end
			end
		end
		local expanded = {}
		for _, stmt in new_body do
			local s = expand_calls(stmt, defs, lexer, parser, inline_defs)
			table.insert(expanded, s)
		end
		return { kind = "Block", body = expanded }
	end

	local out = {}
	for k, v in node do
		if type(v) == "table" and v.kind then
			out[k] = walk(v, defs, lexer, parser, inline_defs, const_defs)
		elseif type(v) == "table" and v[1] ~= nil then
			local arr = {}
			for _, child in v do
				local r = walk(child, defs, lexer, parser, inline_defs, const_defs)
				if r ~= nil then
					table.insert(arr, r)
				end
			end
			out[k] = arr
		else
			out[k] = v
		end
	end
	return out
end

function macros.expand(ast, lexer, parser)
	local defs = {}
	local inline_defs = {}
	local const_defs = {}

	local walked = walk(ast, defs, lexer, parser, inline_defs, const_defs)

	return fold(walked)
end

return macros
