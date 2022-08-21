# zloppy

Sloppy mode for Zig.

Tool to automatically silence compiler errors about unused variables and
unreachable code. Incidentally format code like `zig fmt` would do.

## Status

Still in early development, expect bugs. Can be run on the stdlib and stage2
compiler (`lib/std` and `src` directories of zig repo) without false positives
nor bugs. There still may be some false negatives here and there.

## Usage

Zloppy can be used where you would use `zig fmt`. For example, it can be used
instead of `zig fmt` in the vim plugin: just replace the command line used from
`zig fmt --stdin --ast-check` to `zloppy --stdin on`.

`zloppy on <files>` will modify given files in place, adding statements and
comments as needed to supress errors about unused variables and unreachable
code. Can be re-applied multiple times on the same files.

Use `--experimental` to enable unused return values checks. This feature is
incomplete (only works for functions defined in the same file). It is guarded
behind a flag because it may lead to false positives with return values using
comptime features.

`zloppy off <files>` will remove all modifications previously added with `zloppy on`.

Directories will be searched recursively.
