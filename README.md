# zloppy

Sloppy mode for Zig 0.15.1.

Tool to automatically silence compiler errors about unused variables and
unreachable code. Incidentally format code like `zig fmt` would do.

![](demo.webp)

## Status

Still in early development, expect bugs. Can be run on the stdlib without false positives nor bugs. There still may be some false negatives here and there.

## Usage

Zloppy can be used where you would use `zig fmt`. For example, it can be used
instead of `zig fmt` in the vim plugin: just replace the command line used from
`zig fmt --stdin --ast-check` to `zloppy --stdin on`.

`zloppy on <files>` will modify given files in place, adding statements and
comments as needed to supress errors about unused variables and unreachable
code. Can be re-applied multiple times on the same files.

`zloppy off <files>` will remove all modifications previously added with `zloppy on`.

Directories will be searched recursively.
