# Example of ts_library module output failing to link

To see the build failures when using the (`webpack_bundle` rule)[./webpack_bundle.bzl], do the following:

1. Update the (`MODULE` value in `module_type.bzl`)[./module_type.bzl] to one of `none` or `commonjs`.
2. Execute `bazel build //:bundle`

## What's going on?
As far as I can tell, when using `commonjs` or `none`, the generated output should be resolvable by Node itself.
The `tsc`-generated JavaScript in these cases requires based purely on the original import declaration. However,
the `LinkablePackageInfo` does not take into account `module_root`, so these import attempts fail to resolve
(e.g. bazel has made JS module `foo` available under `.../package_foo/src/foo`, but mapped `package_foo` to
`.../package_foo`).

Interestingly, it works fine under module-type `umd`, as `tsc` rewrites the import to account for this (e.g.
TS referencing `foo/foo` becomes JS referencing `foo/src/foo`).

