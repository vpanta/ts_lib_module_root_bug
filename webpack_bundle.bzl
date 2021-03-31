load("@build_bazel_rules_nodejs//:providers.bzl", "JSEcmaScriptModuleInfo", "JSModuleInfo", "JSNamedModuleInfo", "NpmPackageInfo", "run_node")
# TODO(vpanta): Upstream webpack_bundle so we don't need this import.
load("@build_bazel_rules_nodejs//internal/linker:link_node_modules.bzl", "MODULE_MAPPINGS_ASPECT_RESULTS_NAME", "module_mappings_aspect")

def _webpack_bundle(ctx):
    "Run the Webpack CLI"

    input_providers = []
    input_providers.extend(ctx.attr.deps)
    input_providers.extend(ctx.attr.data)

    # Collect package mappings to tell webpack for bundling.
    dep_depsets = []    
    package_map = {}
    for dep in input_providers:
        _append_deps_sources(dep_depsets, dep)
        if hasattr(dep, MODULE_MAPPINGS_ASPECT_RESULTS_NAME):
            for name, mapData in getattr(dep, MODULE_MAPPINGS_ASPECT_RESULTS_NAME).items():
                # mapData is a tuple of (type, path).
                package_map[name] = mapData[1]
    inputs = depset(transitive = dep_depsets).to_list()

    args = ctx.actions.args()

    # Add entrypoint as first argument
    js_entry = _resolve_js_input(ctx.file.entry_point, inputs)
    args.add(js_entry)

    js_config = _resolve_js_input(ctx.file.config, inputs)
    args.add_all(["--config", js_config])

    args.add_all(["--name", ctx.label])
    # Passed via env as well for logging, if wanted.
    args.add_joined("--env", ["name", ctx.label], join_with = "=")
    args.add_all(["--output-path", ctx.outputs.bundle.dirname])
    args.add_all(["--output-filename", ctx.outputs.bundle.basename])

    # Add module mappings as resolution aliases
    for name, path in package_map.items():
        args.add("--resolve-alias-alias", path)
        args.add("--resolve-alias-name", name)

    # Need to ensure we can find npm modules
    args.add("--resolve-modules", ".")
    args.add("--resolve-modules", "node_modules")

    run_node(
        ctx,
        inputs,
        [args],
        "webpack",
        outputs = [ctx.outputs.bundle],
        use_default_shell_env = True,  # use values passed via Bazel --action_env flags
        progress_message = "Bundling JavaScript %s [webpack]" % ctx.outputs.bundle.path,
    )

    outputs_depset = depset([ctx.outputs.bundle])

    return [
        DefaultInfo(files = outputs_depset),
        JSModuleInfo(sources = outputs_depset),
    ]

webpack_bundle = rule(
    implementation = _webpack_bundle,
    attrs = {
        "config": attr.label(
            allow_single_file = True,
            mandatory = True,
            doc = "The webpack config to use, as a JS or TS file. Should also be part of data, transitively.",
        ),
        "deps": attr.label_list(
            aspects = [module_mappings_aspect],
        ),
        "entry_point": attr.label(
            allow_single_file = True,
            mandatory = True,
            doc = "The entry point module, as a JS or TS file. Should also be part of deps, transitively.",
        ),
        "data": attr.label_list(
            aspects = [module_mappings_aspect],
        ),
        "webpack": attr.label(default = "@npm//webpack-cli/bin:webpack-cli", executable = True, cfg = "host"),
    },
    outputs = {
        "bundle": "%{name}.js",
    },
)

###############
### Helpers ###
###############

def _append_deps_sources(depsets, dep):
    # Supports deps with JS providers, however it prefers ts_library's
    # "es5_sources" outputs over "es6_sources" (as the latter are always .mjs
    # files no matter the actual prodmode_module for the rule).
    #
    # Preference order is:
    #   - JSModuleInfo: "es5_sources" output group
    #   - JSNamedModuleInfo: an older provider, now fallback for "es5_sources"
    #   - JSEcmaScriptModuleInfo: "es6_sources" output group
    #   - DefaultInfo: a generic output set
    if JSModuleInfo in dep:
        depsets.append(dep[JSModuleInfo].sources)
    elif JSNamedModuleInfo in dep:
        depsets.append(dep[JSNamedModuleInfo].sources)
    elif JSEcmaScriptModuleInfo in dep:
        depsets.append(dep[JSEcmaScriptModuleInfo].sources)
    elif hasattr(dep, "files"):
        depsets.append(dep.files)

    # Lastly, if this is an npm package, get its sources.
    # These deps are identified by the NpmPackageInfo provider.
    if NpmPackageInfo in dep:
        depsets.append(dep[NpmPackageInfo].sources)

def _resolve_js_input(f, inputs):
    js_extensions = ("js", "mjs")
    if f.extension in js_extensions:
        # f is JS, so we don't need to find the corresponding input.
        # If f isn't in the input, bazel will complain on its own.
        return f

    # look for corresponding js file in inputs
    f_no_ext = _strip_extension(f)
    for i in inputs:
        if i.extension in js_extensions and _strip_extension(i) == f_no_ext:
            return i
    fail("Could not find corresponding javascript entry point for %s. Add the %s.js to your deps." % (f.path, f_no_ext))

def _strip_extension(f):
    return f.short_path[:-len(f.extension) - 1]
