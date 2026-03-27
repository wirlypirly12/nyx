# nyx
a lua/luau interpreter written in luau. has its own lexer, parser, compiler, and stack based vm. source never touches the executor.

## how it works
pipeline is lexer, parser, compiler, then vm.

nested functions compile down to protos, assembled at runtime via `CLOSURE`. captured locals get turned into heap cells so closures can write to them and any other closure sharing the same cell sees the update.

## roadmap
- chunk serializer - bytecode as a binary blob
- macros - emit functions as unvirtualized native lua closures, propagate constants across functions
- compiler optimizations - dce

