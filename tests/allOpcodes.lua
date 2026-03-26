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

local s = "hello" .. " " .. "world"
local l = #s
print(s, l)

local t = true
local f = false
print(t and f, t or f, not t)


print(a == b, a ~= b, a < b, a <= b, a > b, a >= b)

local n = nil
print(n)

if a > 5 then
	print("a > 5")
elseif a == 5 then
	print("a == 5")
else
	print("a < 5")
end

local i = 0
while i < 3 do
	print("while", i)
	i = i + 1
end

local j = 0
repeat
	print("repeat", j)
	j = j + 1
until j >= 3

for x = 1, 3 do
	print("for+", x)
end

for x = 3, 1, -1 do
	print("for-", x)
end

local tbl = {
	["key"] = "value",
	name = "waaaa",
	[1] = "indexed",
}
print(tbl["key"], tbl.name, tbl[1])

tbl["dynamic"] = "yes"
print(tbl["dynamic"])

local counts = { a = 1, b = 2, c = 3 }
for k, v in pairs(counts) do
	print("pairs", k, v)
end


local function add2(x, y)
	return x + y
end
print(add2(10, 20))

local function outer(x)
	local function inner(y)
		return x + y
	end
	return inner(5)
end
print(outer(10))

do
	local scoped = "inside"
	print(scoped)
end

local function multi()
	return 1, 2, 3
end
local r1, r2, r3 = multi()
print(r1, r2, r3)

function myGlobal(x)
	return x * 2
end
print(myGlobal(7))

]]
