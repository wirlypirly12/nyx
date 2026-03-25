return [[
    print("Hello, World!") -- CallStatement
    local var0,var1,var2 = "a", "b", "c" -- LocalStatement (chain)

    if (var0 and var1 and var2 and true and not false and true == true) then -- IfStatement with BinaryExpression
        print(var0..var1..var2) -- CallStatment with BinaryExpression
    end
]]
