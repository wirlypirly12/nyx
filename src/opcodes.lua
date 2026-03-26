local OPCODES = {}
local OPNAMES = {
	-- constants / stack
	"LOAD_CONST", -- push constants[arg] onto stack
	"LOAD_LOCAL", -- push locals[arg] onto stack
	"STORE_LOCAL", -- pop stack into locals[arg]
	"LOAD_GLOBAL", -- push globals[constants[arg]] onto stack
	"LOAD_UPVALUE", -- push upvalue onto stack
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
