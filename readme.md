# nyx
a lua/luau interpreter written in luau. has its own lexer, parser, compiler, and stack-based vm. source never touches the host executor.

nyx is being used as the base for a separate obfuscator project that runs on top of it.

## how it works
pipeline is lexer, parser, compiler, then vm.

nested functions compile down to protos, spun up at runtime via `CLOSURE`. captured locals get turned into heap cells so closures can write back to them and any other closure sharing the same cell sees the update.

## roadmap
- chunk serializer - bytecode as a binary blob
- macros - emit functions as real native lua closures, inline, unroll, propagate constants across call boundaries
- compiler optimizations - constant folding, dce, register coalescing