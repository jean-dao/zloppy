# zloppy

Sloppy mode for Zig.

Tool to automatically silence compiler errors about unused variables and
unreachable code.

## Status

Still in early development, quite a few Zig construct are not yet processed,
some unused variables/unreachable code will not be properly handled.

Expect bugs.

## Usage

`zloppy on <files>` will modify given files in place, adding statements and
comments as needed to supress errors about unused variables and unreachable
code. Can be re-applied multiple times on the same files.

`zloppy off <files>` will remove all modifications previously added with `zloppy on`.

Directories will be searched recursively.

Due to technicalities, both commands will also format given files, like `zig fmt` does.

# Disclaimer

This tool is designed to facilitate development, at the cost of producing worst
code. Use with caution.
