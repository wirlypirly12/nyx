local OPCODES = {} -- built at runtime from OPNAMES
local OPNAMES = { -- every lua5.1 opcode
	"MOVE",
	"LOADBOOL",
	"LOADNIL",
	"GETUPVAL",
	"GETTABLE",
	"GETGLOBAL",
	"SETGLOBAL",
	"SETUPVAL",
	"SETTABLE",
	"NEWTABLE",
	"SELF",
	"ADD",
	"SUB",
	"MUL",
	"DIV",
	"MOD",
	"POW",
	"UNM",
	"NOT",
	"LEN",
	"CONCAT",
	"JMP",
	"EQ",
	"LE",
	"LT",
	"TEST",
	"TESTSET",
	"CALL",
	"TAILCALL",
	"RETURN",
	"FORLOOP",
	"FORPREP",
	"TFORLOOP",
	"SETLIST",
	"CLOSE",
	"CLOSURE",
	"VARARG",
}

for i = 1, #OPNAMES do
	OPCODES[OPNAMES[i]] = i
end

return OPCODES
