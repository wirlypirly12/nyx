# nyx
a lua/luau interpreter written in luau. has its own lexer, parser, compiler, and stack based vm. source never touches the executor.

## how it works
pipeline is lexer, parser, compiler, then vm.

nested functions compile down to protos, assembled at runtime via `CLOSURE`. captured locals get turned into heap cells so closures can write to them and any other closure sharing the same cell sees the update.
the vm itself is stack based with a register window per call frame. instructions are a fixed size and dispatched through a standard loop.

## installation
### single file (suggested)
store `build\nyx.lua` somewhere and require the module

### manual
clone the `src` folder and require the `src\interpreter.lua` module.

## usage
```lua
local interpreter = require("interpreter")
interpreter:runSource("print('hello world')")
```

with debug options:
```lua
interpreter:runSource(source, { b = true })  -- dump instructions
interpreter:runSource(source, { m = true })  -- show pipeline metrics (lexer, parser, compiler, vm timings)
interpreter:runSource(source, { b = true, m = true })  -- both
```

## roadmap
- chunk serializer - bytecode as a binary blob
- macros - emit functions as unvirtualized native lua closures, propagate constants across functions
- compiler optimizations - dce
- parsing fixes - full luau support
