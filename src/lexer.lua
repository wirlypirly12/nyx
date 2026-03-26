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
		self.char = self.source:sub(self.pos, self.pos) -- get character at curr pos

		if self.char == "\n" then -- newline, reset the col and inc the line.
			self.line = self.line + 1
			self.column = 1
		else
			self.column = self.column + 1
		end
	else
		self.char = nil -- ran out of source to read
	end
end

function lexer:peek(offset)
	offset = offset or 1
	local peek_at = self.pos + offset

	if peek_at <= #self.source then -- ensure we are still in bounds of the source
		return self.source:sub(peek_at, peek_at)
	end
	return nil -- no more source to peek
end

function lexer:skip_whitespace()
	while self.char and self.char:match("%s") do
		self:advance()
	end
end

--
function lexer:skip_comment()
	if self.char == "-" and self:peek() == "-" then
		self:advance()
		self:advance() -- skip --

		if self.char == "[" then
			local level = 0
			local i = 1
			while self:peek(i) == "=" do
				level = level + 1
				i = i + 1
			end

			if self:peek(i) == "[" then
				self:advance() -- skip [
				for z = 1, level do
					self:advance() -- skip =
				end
				self:advance() -- skip second  [

				while self.char do
					if self.char == "]" then
						local close_level = 0
						local j = 1
						while self:peek(j) == "=" do
							close_level = close_level + 1
							j = j + 1
						end
						if close_level == level and self:peek(j) == "]" then
							self:advance() -- skip ]
							for z = 1, level do -- skip =
								self:advance()
							end
							self:advance() -- skip second ]
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

function lexer:string()
	local escapes = {
		n = "\n",
		t = "\t",
		r = "\r",
		["\\"] = "\\",
		['"'] = '"',
		["'"] = "'",
	}

	local quote = self.char -- store opening quote so we know when to stop advancing the string
	self:advance()
	local result = {}
	while self.char and self.char ~= quote do
		if self.char == "\\" then -- allow escapes to be parsed
			self:advance()
			local escaped = escapes[self.char]
			if escaped then
				table.insert(result, escaped)
			else
				error(`illegal escape: {self.char}`)
			end
		else
			table.insert(result, self.char)
		end
		self:advance()
	end
	if not self.char then -- ensure string closed
		error("illegal string! did you forget to close it?")
	end
	self:advance() -- skip closing quote
	self:emit(TOKEN_TYPES.STRING, table.concat(result))
end

function lexer:number()
	local result = {}

	if self.char == "0" and (self:peek() == "x" or self:peek() == "X") then
		table.insert(result, self.char)
		self:advance()
		table.insert(result, self.char)
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
		error(`unexpected character: {self.char} at line {self.line} col: {self.column}`)
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
		elseif self.char:match("%d") then
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
