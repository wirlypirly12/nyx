return [[
local a = 10
local b = 3
local add = a + b
local sub = a - b
local mul = a * b
local div = a / b
local mod = a % b
local idiv = a // b
local pow = a ^ b
local unm = -a
print(add, sub, mul, div, mod, idiv, pow, unm)

-- string concat and len
local s = "hello" .. " " .. "world"
local l = #s
print(s, l)

-- booleans and logic
local t = true
local f = false
print(t and f, t or f, not t)

-- comparisons
print(a == b, a ~= b, a < b, a <= b, a > b, a >= b)

-- nil
local n = nil
print(n)

-- if / elseif / else
if a > 5 then
	print("a > 5")
elseif a == 5 then
	print("a == 5")
else
	print("a < 5")
end

-- while
local i = 0
while i < 3 do
	print("while", i)
	i = i + 1
end

-- repeat until
local j = 0
repeat
	print("repeat", j)
	j = j + 1
until j >= 3

-- numeric for positive step
for x = 1, 3 do
	print("for+", x)
end

-- numeric for negative step
for x = 3, 1, -1 do
	print("for-", x)
end

-- tables
local tbl = {
	["key"] = "value",
	name = "carter",
	[1] = "indexed",
}
print(tbl["key"], tbl.name, tbl[1])

-- table set/get index
tbl["dynamic"] = "yes"
print(tbl["dynamic"])

-- generic for
local counts = { a = 1, b = 2, c = 3 }
for k, v in pairs(counts) do
	print("pairs", k, v)
end

-- functions
local function add2(x, y)
	return x + y
end
print(add2(10, 20))

-- closures / local function
local function outer(x)
	local function inner(y)
		return x + y
	end
	return inner(5)
end
print(outer(10))

-- do block scoping
do
	local scoped = "inside"
	print(scoped)
end

-- multiple return values
local function multi()
	return 1, 2, 3
end
local r1, r2, r3 = multi()
print(r1, r2, r3)

-- global function
function myGlobal(x)
	return x * 2
end
print(myGlobal(7))

]]
