"""Shared Starlark rules for building GNUstep Objective-C/Objective-C++ targets with Bazel (without Apple dependencies)."""

load("@rules_cc//cc:defs.bzl", "CcInfo", "cc_binary", "cc_common", "cc_test")
load("@rules_cc//cc:find_cc_toolchain.bzl", "find_cc_toolchain", "use_cc_toolchain")
load(
    "//bazel:platforms.bzl",
    _gnustep_expand_template = "gnustep_expand_template",
    _gnustep_platform_linkopts = "gnustep_platform_linkopts",
    _gnustep_target_copts = "gnustep_target_copts",
)

def _eh_trampoline_asm_impl(ctx):
    cc_toolchain = find_cc_toolchain(ctx)
    out = ctx.actions.declare_file(ctx.attr.out)
    ctx.actions.run_shell(
        inputs = depset(
            direct = [ctx.file.src],
            transitive = [cc_toolchain.all_files],
        ),
        outputs = [out],
        command = '"{compiler}" -fPIC -S "{src}" -o - -fexceptions -fno-inline | sed "s/__gxx_personality_v0/test_eh_personality/g" > "{out}"'.format(
            compiler = cc_toolchain.compiler_executable,
            src = ctx.file.src.path,
            out = out.path,
        ),
    )
    return [DefaultInfo(files = depset([out]))]

eh_trampoline_asm = rule(
    implementation = _eh_trampoline_asm_impl,
    attrs = {
        "src": attr.label(allow_single_file = [".cc"], mandatory = True),
        "out": attr.string(mandatory = True),
    },
    toolchains = use_cc_toolchain(),
)

def _objc_library_impl(ctx):
    cc_toolchain = find_cc_toolchain(ctx)
    feature_configuration = cc_common.configure_features(
        ctx = ctx,
        cc_toolchain = cc_toolchain,
        requested_features = ctx.features + ["external_include_paths"],
        unsupported_features = ctx.disabled_features + [
            "use_header_modules",
            "header_modules",
            "layering_check",
            "parse_headers",
        ],
    )

    asm_srcs = []
    c_srcs = []
    m_srcs = []
    arc_m_srcs = []
    cc_srcs = []
    mm_srcs = []
    arc_mm_srcs = []
    private_hdrs = list(ctx.files.textual_hdrs)
    def _pkg_rel_path(f):
        p = f.short_path
        if p.startswith("../"):
            p = p[3:]
            slash = p.find("/")
            if slash != -1:
                p = p[slash + 1:]
        return p

    src_dirs = {}
    rel_src_dirs = {"": True, "Source": True}

    for src in ctx.files.srcs + ctx.files.non_arc_srcs + ctx.files.arc_srcs:
        if src.dirname:
            src_dirs[src.dirname] = True
        rp = _pkg_rel_path(src)
        if "/" in rp:
            rel_src_dirs[rp.rsplit("/", 1)[0]] = True

    for src in ctx.files.srcs:
        if src.extension in ["h", "hh", "hpp", "inc"]:
            private_hdrs.append(src)
        elif src.extension in ["s", "S", "asm"]:
            asm_srcs.append(src)
        elif src.extension == "c":
            c_srcs.append(src)
        elif src.extension == "m":
            wrapped = ctx.actions.declare_file(ctx.label.name + "_srcs/" + _pkg_rel_path(src) + ".c")
            ctx.actions.symlink(output = wrapped, target_file = src)
            m_srcs.append(wrapped)
        elif src.extension == "mm":
            wrapped = ctx.actions.declare_file(ctx.label.name + "_srcs/" + _pkg_rel_path(src) + ".cc")
            ctx.actions.symlink(output = wrapped, target_file = src)
            mm_srcs.append(wrapped)
        else:
            cc_srcs.append(src)

    for src in ctx.files.non_arc_srcs:
        if src.extension == "m":
            wrapped = ctx.actions.declare_file(ctx.label.name + "_srcs/" + _pkg_rel_path(src) + ".c")
            ctx.actions.symlink(output = wrapped, target_file = src)
            m_srcs.append(wrapped)
        elif src.extension == "mm":
            wrapped = ctx.actions.declare_file(ctx.label.name + "_srcs/" + _pkg_rel_path(src) + ".cc")
            ctx.actions.symlink(output = wrapped, target_file = src)
            mm_srcs.append(wrapped)
        elif src.extension == "c":
            c_srcs.append(src)
        else:
            cc_srcs.append(src)

    for src in ctx.files.arc_srcs:
        if src.extension == "m":
            wrapped = ctx.actions.declare_file(ctx.label.name + "_srcs/" + _pkg_rel_path(src) + ".c")
            ctx.actions.symlink(output = wrapped, target_file = src)
            arc_m_srcs.append(wrapped)
        elif src.extension == "mm":
            wrapped = ctx.actions.declare_file(ctx.label.name + "_srcs/" + _pkg_rel_path(src) + ".cc")
            ctx.actions.symlink(output = wrapped, target_file = src)
            arc_mm_srcs.append(wrapped)

    symlink_hdr_dirs = []
    if m_srcs or arc_m_srcs or mm_srcs or arc_mm_srcs:
        seen_hdr_symlinks = {}
        symlinked_hdrs = []
        for hdr in private_hdrs + ctx.files.hdrs:
            rel_hdr = _pkg_rel_path(hdr)
            target_rel_paths = [rel_hdr]
            if rel_hdr.startswith(".bazel/include/"):
                sub = rel_hdr[len(".bazel/include/"):]
                target_rel_paths.append(sub)
                if "/" not in sub:
                    for rdir in rel_src_dirs.keys():
                        if rdir:
                            target_rel_paths.append(rdir + "/" + sub)
            for rel_path in target_rel_paths:
                if rel_path not in seen_hdr_symlinks:
                    seen_hdr_symlinks[rel_path] = True
                    wrapped_hdr = ctx.actions.declare_file(ctx.label.name + "_srcs/" + rel_path)
                    ctx.actions.symlink(output = wrapped_hdr, target_file = hdr)
                    symlinked_hdrs.append(wrapped_hdr)
                    if wrapped_hdr.dirname and wrapped_hdr.dirname not in symlink_hdr_dirs:
                        symlink_hdr_dirs.append(wrapped_hdr.dirname)
        private_hdrs = private_hdrs + symlinked_hdrs

    dep_compilation_contexts = [dep[CcInfo].compilation_context for dep in ctx.attr.deps if CcInfo in dep]
    dep_linking_contexts = [dep[CcInfo].linking_context for dep in ctx.attr.deps if CcInfo in dep]

    ws_root = ctx.label.workspace_root
    pkg = ctx.label.package
    if ws_root and pkg:
        pkg_root = ws_root + "/" + pkg
    elif ws_root:
        pkg_root = ws_root
    else:
        pkg_root = pkg
    bin_pkg = ctx.bin_dir.path + ("/" + pkg_root if pkg_root else "")
    gen_pkg = ctx.genfiles_dir.path + ("/" + pkg_root if pkg_root else "")
    exported_include_dirs = list(symlink_hdr_dirs)
    for hdr in ctx.files.hdrs + private_hdrs:
        if hdr.dirname and "_srcs/" not in hdr.dirname and hdr.dirname not in exported_include_dirs:
            exported_include_dirs.append(hdr.dirname)
    for inc in ["."] + ctx.attr.includes:
        for base in [pkg_root, bin_pkg, gen_pkg]:
            path = base if (inc == "." or inc == "") else (base + "/" + inc if base else inc)
            if path and path not in exported_include_dirs:
                exported_include_dirs.append(path)

    include_flags = ["-iquote", ".", "-I."]
    seen_inc = {".": True}
    for d in exported_include_dirs + list(src_dirs.keys()):
        if d and d not in seen_inc:
            seen_inc[d] = True
            include_flags.append("-iquote")
            include_flags.append(d)
            include_flags.append("-I" + d)
    for cc_ctx in dep_compilation_contexts:
        for inc_depset in [cc_ctx.includes, cc_ctx.quote_includes, cc_ctx.system_includes]:
            for d in inc_depset.to_list():
                if d and d not in seen_inc:
                    seen_inc[d] = True
                    include_flags.append("-I" + d)

    objc_base_flags = [
        "-fobjc-runtime=" + ctx.attr.objc_runtime,
        "-fblocks",
        "-fexceptions",
        "-fobjc-exceptions",
        "-fno-sanitize=alignment",
        "-Wno-gnu-folding-constant",
        "-Wno-deprecated-objc-isa-usage",
        "-Wno-objc-root-class",
        "-Wno-vla",
        "-Wno-error",
    ]

    local_cc_context = cc_common.create_compilation_context(
        headers = depset(ctx.files.hdrs + private_hdrs),
        includes = depset(exported_include_dirs),
        quote_includes = depset(exported_include_dirs + list(src_dirs.keys())),
        defines = depset(ctx.attr.defines),
        local_defines = depset(ctx.attr.local_defines),
    )
    compilation_contexts = [local_cc_context]
    compilation_outputs_list = []

    safe_includes = [i for i in ctx.attr.includes if i != "." or ctx.label.package != ""]

    base_cc_context, base_outputs = cc_common.compile(
        name = ctx.label.name + "_hdrs",
        actions = ctx.actions,
        feature_configuration = feature_configuration,
        cc_toolchain = cc_toolchain,
        public_hdrs = ctx.files.hdrs,
        private_hdrs = private_hdrs,
        includes = safe_includes,
        defines = ctx.attr.defines,
        local_defines = ctx.attr.local_defines,
        compilation_contexts = [local_cc_context] + dep_compilation_contexts,
    )
    compilation_contexts.append(base_cc_context)
    compilation_outputs_list.append(base_outputs)

    common_compile_kwargs = dict(
        actions = ctx.actions,
        feature_configuration = feature_configuration,
        cc_toolchain = cc_toolchain,
        public_hdrs = ctx.files.hdrs,
        private_hdrs = private_hdrs,
        includes = safe_includes,
        defines = ctx.attr.defines,
        local_defines = ctx.attr.local_defines,
        compilation_contexts = [local_cc_context] + dep_compilation_contexts,
    )

    if asm_srcs:
        _, out = cc_common.compile(
            name = ctx.label.name + "_asm",
            srcs = asm_srcs,
            user_compile_flags = include_flags + ctx.attr.copts,
            **common_compile_kwargs
        )
        compilation_outputs_list.append(out)

    if c_srcs:
        _, out = cc_common.compile(
            name = ctx.label.name + "_c",
            srcs = c_srcs,
            user_compile_flags = include_flags + ["-Wno-vla", "-Wno-error"] + ctx.attr.copts + ctx.attr.conlyopts,
            **common_compile_kwargs
        )
        compilation_outputs_list.append(out)

    if m_srcs:
        _, out = cc_common.compile(
            name = ctx.label.name + "_m",
            srcs = m_srcs,
            user_compile_flags = ["-xobjective-c"] + include_flags + objc_base_flags + ctx.attr.copts + ctx.attr.objc_copts,
            **common_compile_kwargs
        )
        compilation_outputs_list.append(out)

    if arc_m_srcs:
        _, out = cc_common.compile(
            name = ctx.label.name + "_arc_m",
            srcs = arc_m_srcs,
            user_compile_flags = ["-xobjective-c"] + include_flags + objc_base_flags + ["-fobjc-arc"] + ctx.attr.copts + ctx.attr.objc_copts,
            **common_compile_kwargs
        )
        compilation_outputs_list.append(out)

    if cc_srcs:
        _, out = cc_common.compile(
            name = ctx.label.name + "_cc",
            srcs = cc_srcs,
            user_compile_flags = include_flags + ["-Wno-vla", "-Wno-error"] + ctx.attr.copts + ctx.attr.cxxopts,
            **common_compile_kwargs
        )
        compilation_outputs_list.append(out)

    if mm_srcs:
        _, out = cc_common.compile(
            name = ctx.label.name + "_mm",
            srcs = mm_srcs,
            user_compile_flags = ["-xobjective-c++"] + include_flags + objc_base_flags + ctx.attr.copts + ctx.attr.cxxopts + ctx.attr.objc_copts,
            **common_compile_kwargs
        )
        compilation_outputs_list.append(out)

    if arc_mm_srcs:
        _, out = cc_common.compile(
            name = ctx.label.name + "_arc_mm",
            srcs = arc_mm_srcs,
            user_compile_flags = ["-xobjective-c++"] + include_flags + objc_base_flags + ["-fobjc-arc"] + ctx.attr.copts + ctx.attr.cxxopts + ctx.attr.objc_copts,
            **common_compile_kwargs
        )
        compilation_outputs_list.append(out)

    merged_outputs = cc_common.merge_compilation_outputs(compilation_outputs = compilation_outputs_list)
    merged_compilation_context = cc_common.merge_compilation_contexts(compilation_contexts = compilation_contexts + dep_compilation_contexts)

    linking_context, linking_outputs = cc_common.create_linking_context_from_compilation_outputs(
        actions = ctx.actions,
        feature_configuration = feature_configuration,
        cc_toolchain = cc_toolchain,
        compilation_outputs = merged_outputs,
        linking_contexts = dep_linking_contexts,
        user_link_flags = ctx.attr.linkopts,
        name = ctx.label.name,
        alwayslink = ctx.attr.alwayslink,
        disallow_dynamic_library = ctx.attr.linkstatic,
    )

    files = []
    if linking_outputs.library_to_link != None:
        if linking_outputs.library_to_link.static_library != None:
            files.append(linking_outputs.library_to_link.static_library)
        if linking_outputs.library_to_link.pic_static_library != None:
            files.append(linking_outputs.library_to_link.pic_static_library)
        if linking_outputs.library_to_link.dynamic_library != None:
            files.append(linking_outputs.library_to_link.dynamic_library)

    runfiles = ctx.runfiles(files = ctx.files.data)
    for dep in ctx.attr.deps:
        runfiles = runfiles.merge(dep[DefaultInfo].default_runfiles)

    return [
        DefaultInfo(
            files = depset(files),
            runfiles = runfiles,
        ),
        CcInfo(
            compilation_context = merged_compilation_context,
            linking_context = linking_context,
        ),
    ]

_objc_library_rule = rule(
    implementation = _objc_library_impl,
    attrs = {
        "srcs": attr.label_list(allow_files = True),
        "non_arc_srcs": attr.label_list(allow_files = True),
        "arc_srcs": attr.label_list(allow_files = True),
        "hdrs": attr.label_list(allow_files = True),
        "textual_hdrs": attr.label_list(allow_files = True),
        "includes": attr.string_list(),
        "defines": attr.string_list(),
        "local_defines": attr.string_list(),
        "copts": attr.string_list(),
        "conlyopts": attr.string_list(),
        "cxxopts": attr.string_list(),
        "objc_copts": attr.string_list(),
        "objc_runtime": attr.string(default = "gnustep-2.0"),
        "linkopts": attr.string_list(),
        "alwayslink": attr.bool(default = True),
        "linkstatic": attr.bool(default = False),
        "deps": attr.label_list(providers = [CcInfo]),
        "data": attr.label_list(allow_files = True),
    },
    toolchains = use_cc_toolchain(),
    fragments = ["cpp"],
)

def objc_library(
        name,
        srcs = [],
        non_arc_srcs = [],
        arc_srcs = [],
        hdrs = [],
        textual_hdrs = [],
        includes = [],
        defines = [],
        local_defines = [],
        copts = [],
        conlyopts = [],
        cxxopts = [],
        objc_copts = [],
        objc_runtime = "gnustep-2.0",
        linkopts = [],
        alwayslink = True,
        linkstatic = False,
        deps = [],
        data = [],
        include_default_objc_deps = False,
        **kwargs):
    """Compiles Objective-C, Objective-C++, C, C++, and ASM sources into a library without Apple dependencies."""
    _objc_library_rule(
        name = name,
        srcs = srcs,
        non_arc_srcs = non_arc_srcs,
        arc_srcs = arc_srcs,
        hdrs = hdrs,
        textual_hdrs = textual_hdrs,
        includes = includes,
        defines = defines,
        local_defines = local_defines,
        copts = copts,
        conlyopts = conlyopts,
        cxxopts = cxxopts,
        objc_copts = objc_copts,
        objc_runtime = objc_runtime,
        linkopts = linkopts,
        alwayslink = alwayslink,
        linkstatic = linkstatic,
        deps = deps,
        data = data,
        **kwargs
    )

def objc_binary(
        name,
        srcs = [],
        non_arc_srcs = [],
        arc_srcs = [],
        hdrs = [],
        textual_hdrs = [],
        includes = [],
        defines = [],
        local_defines = [],
        copts = [],
        conlyopts = [],
        cxxopts = [],
        objc_copts = [],
        objc_runtime = "gnustep-2.0",
        linkopts = [],
        linkstatic = True,
        deps = [],
        data = [],
        **kwargs):
    """Builds an executable binary from Objective-C/C/C++ sources using GNUstep libobjc2."""
    lib_name = name + "_objclib"
    objc_library(
        name = lib_name,
        srcs = srcs,
        non_arc_srcs = non_arc_srcs,
        arc_srcs = arc_srcs,
        hdrs = hdrs,
        textual_hdrs = textual_hdrs,
        includes = includes,
        defines = defines,
        local_defines = local_defines,
        copts = copts,
        conlyopts = conlyopts,
        cxxopts = cxxopts,
        objc_copts = objc_copts,
        objc_runtime = objc_runtime,
        deps = deps,
        data = data,
        testonly = kwargs.get("testonly", False),
        visibility = ["//visibility:private"],
    )
    cc_binary(
        name = name,
        deps = [":" + lib_name],
        linkopts = _gnustep_platform_linkopts() + linkopts,
        linkstatic = linkstatic,
        data = data,
        **kwargs
    )

def objc_test(
        name,
        srcs = [],
        non_arc_srcs = [],
        arc_srcs = [],
        hdrs = [],
        textual_hdrs = [],
        includes = [],
        defines = [],
        local_defines = [],
        copts = [],
        conlyopts = [],
        cxxopts = [],
        objc_copts = [],
        objc_runtime = "gnustep-2.0",
        linkopts = [],
        linkstatic = True,
        deps = [],
        data = [],
        **kwargs):
    """Builds a test binary from Objective-C/C/C++ sources using GNUstep libobjc2."""
    lib_name = name + "_objctestlib"
    objc_library(
        name = lib_name,
        srcs = srcs,
        non_arc_srcs = non_arc_srcs,
        arc_srcs = arc_srcs,
        hdrs = hdrs,
        textual_hdrs = textual_hdrs,
        includes = includes,
        defines = defines,
        local_defines = local_defines,
        copts = copts,
        conlyopts = conlyopts,
        cxxopts = cxxopts,
        objc_copts = objc_copts,
        objc_runtime = objc_runtime,
        deps = deps,
        data = data,
        testonly = True,
        visibility = ["//visibility:private"],
    )
    cc_test(
        name = name,
        deps = [":" + lib_name],
        linkopts = _gnustep_platform_linkopts() + linkopts,
        linkstatic = linkstatic,
        data = data,
        **kwargs
    )

# Re-export platform helpers for convenience
gnustep_target_copts = _gnustep_target_copts
gnustep_platform_linkopts = _gnustep_platform_linkopts
gnustep_expand_template = _gnustep_expand_template
