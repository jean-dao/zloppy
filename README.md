# zloppy

Sloppy mode for Zig.

Tool to automatically silence compiler errors about unused variables and
unreachable code.

## Status

Still in early development, expect bugs. Can be run on the stdlib and
stage2 compiler without false positives nor bugs. There still may be some false
negatives here and there.

## Usage

`zloppy on <files>` will modify given files in place, adding statements and
comments as needed to supress errors about unused variables and unreachable
code. Can be re-applied multiple times on the same files.

Use `--experimental` to enable unused return values checks. This feature is
incomplete (only works for functions defined in the same file). It is guarded
behind a flag because it may lead to false positives with return values using
comptime features.

`zloppy off <files>` will remove all modifications previously added with `zloppy on`.

Directories will be searched recursively.

Due to technicalities, both commands will also format given files, like `zig fmt` does.

# Disclaimer

This tool is designed to facilitate development, at the cost of producing worst
code. Use with caution.
