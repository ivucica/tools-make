package(default_visibility = ["//visibility:public"])

exports_files([
    "objc.bzl",
    "platforms.bzl",
])

config_setting(
    name = "linux_x86_64",
    constraint_values = [
        "@platforms//os:linux",
        "@platforms//cpu:x86_64",
    ],
)

config_setting(
    name = "linux_arm64",
    constraint_values = [
        "@platforms//os:linux",
        "@platforms//cpu:aarch64",
    ],
)

config_setting(
    name = "freebsd_x86_64",
    constraint_values = [
        "@platforms//os:freebsd",
        "@platforms//cpu:x86_64",
    ],
)

config_setting(
    name = "freebsd_arm64",
    constraint_values = [
        "@platforms//os:freebsd",
        "@platforms//cpu:aarch64",
    ],
)

config_setting(
    name = "os_linux",
    constraint_values = ["@platforms//os:linux"],
)

config_setting(
    name = "os_freebsd",
    constraint_values = ["@platforms//os:freebsd"],
)

config_setting(
    name = "cpu_x86_64",
    constraint_values = ["@platforms//cpu:x86_64"],
)

config_setting(
    name = "cpu_arm64",
    constraint_values = ["@platforms//cpu:aarch64"],
)
