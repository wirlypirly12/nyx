return [==[
    local identifer = "this is a string!"

    local keyword = print

    keyword(identifer)

    if true then
        --[[
            This is inside a comment!!!
        ]]
    end

    local m = "h" .. "i"
    local isHi = m == "hi"
]==]
