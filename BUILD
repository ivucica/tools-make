load("//bazel:platforms.bzl", "gnustep_make_sed_cmd")

package(
    default_visibility = ["//visibility:public"],
)

genrule(
    name = "gnustep-config",
    srcs = ["gnustep-config.in"],
    outs = ["gnustep-config.sh"],
    cmd = gnustep_make_sed_cmd("gnustep-config.in", executable = True),
    executable = True,
)

genrule(
    name = "openapp",
    srcs = ["openapp.in"],
    outs = ["openapp.sh"],
    cmd = gnustep_make_sed_cmd("openapp.in", executable = True),
    executable = True,
)

genrule(
    name = "opentool",
    srcs = ["opentool.in"],
    outs = ["opentool.sh"],
    cmd = gnustep_make_sed_cmd("opentool.in", executable = True),
    executable = True,
)

genrule(
    name = "gnustep_sh_gen",
    srcs = ["GNUstep.sh.in"],
    outs = ["GNUstep.sh"],
    cmd = gnustep_make_sed_cmd("GNUstep.sh.in"),
)

genrule(
    name = "gnustep_conf_gen",
    srcs = ["GNUstep.conf.in"],
    outs = ["GNUstep.conf"],
    cmd = gnustep_make_sed_cmd("GNUstep.conf.in"),
)

genrule(
    name = "config_make_gen",
    srcs = ["config.make.in"],
    outs = ["config.make"],
    cmd = gnustep_make_sed_cmd("config.make.in"),
)

genrule(
    name = "config_noarch_make_gen",
    srcs = ["config-noarch.make.in"],
    outs = ["config-noarch.make"],
    cmd = gnustep_make_sed_cmd("config-noarch.make.in"),
)

genrule(
    name = "filesystem_make_gen",
    srcs = ["filesystem.make.in"],
    outs = ["filesystem.make"],
    cmd = gnustep_make_sed_cmd("filesystem.make.in"),
)

filegroup(
    name = "makefiles",
    srcs = glob([
        "*.make",
        "*.template",
        "*.sh",
        "Instance/**/*.make",
        "Master/*.make",
        "TestFramework/*",
    ]) + [
        ":GNUstep.conf",
        ":GNUstep.sh",
        ":config.make",
        ":config-noarch.make",
        ":filesystem.make",
    ],
)

load("@rules_cc//cc:defs.bzl", "cc_library")

cc_library(
    name = "testing_h",
    textual_hdrs = [
        "TestFramework/ObjectTesting.h",
        "TestFramework/Testing.h",
    ],
    includes = ["TestFramework"],
)
