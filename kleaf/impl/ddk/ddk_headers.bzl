# Copyright (C) 2022 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

load("@bazel_skylib//lib:paths.bzl", "paths")

DdkHeadersInfo = provider(fields = {
    "files": "A [depset](https://bazel.build/rules/lib/depset) including all header files",
    "includes": "A [depset](https://bazel.build/rules/lib/depset) containing the `includes` attribute of the rule",
})

def get_include_depset(label, deps, includes):
    """Returns a depset containing include directories from the list of dependencies and direct includes.

    Args:
        label: Label of this target
        deps: A list of depended targets. If [`DdkHeadersInfo`](#DdkHeadersInfo) is in the target,
          their `includes` are included in the returned depset.
        includes: A list of local include directories included in the returned depset.
    """
    for include_dir in includes:
        if paths.normalize(include_dir) != include_dir:
            fail(
                "{}: include directory {} is not normalized to {}".format(
                    label,
                    include_dir,
                    paths.normalize(include_dir),
                ),
            )
        if paths.is_absolute(include_dir):
            fail("{}: Absolute directories not allowed in includes: {}".format(label, include_dir))
        if include_dir == ".." or include_dir.startswith("../"):
            fail("{}: Invalid include directory: {}".format(label, include_dir))

    transitive_includes = []
    for dep in deps:
        if DdkHeadersInfo in dep:
            transitive_includes.append(dep[DdkHeadersInfo].includes)

    return depset(
        [paths.normalize(paths.join(label.package, d)) for d in includes],
        transitive = transitive_includes,
    )

def get_headers_depset(deps):
    """Returns a depset containing headers from the list of dependencies

    Args:
        deps: A list of depended targets. If [`DdkHeadersInfo`](#DdkHeadersInfo) is in the target,
          `target[DdkHeadersInfo].files` are included in the returned depset. Otherwise
          the default output files are included in the returned depset.
    """
    transitive_deps = []

    for dep in deps:
        if DdkHeadersInfo in dep:
            transitive_deps.append(dep[DdkHeadersInfo].files)
        else:
            transitive_deps.append(dep.files)

    return depset(transitive = transitive_deps)

def ddk_headers_common_impl(label, hdrs, includes):
    """Common implementation for rules that returns `DdkHeadersInfo`.

    Args:
        label: Label of this target.
        hdrs: The list of exported headers, e.g. [`ddk_headers.hdrs`](#ddk_headers-hdrs)
        includes: The list of exported include directories, e.g. [`ddk_headers.includes`](#ddk_headers-includes)
    """

    return DdkHeadersInfo(
        files = get_headers_depset(hdrs),
        includes = get_include_depset(label, hdrs, includes),
    )

def _ddk_headers_impl(ctx):
    ddk_headers_info = ddk_headers_common_impl(ctx.label, ctx.attr.hdrs, ctx.attr.includes)
    return [
        DefaultInfo(files = ddk_headers_info.files),
        ddk_headers_info,
    ]

ddk_headers = rule(
    implementation = _ddk_headers_impl,
    doc = """A rule that exports a list of header files to be used in DDK.

Example:

```
ddk_headers(
   name = "headers",
   hdrs = ["include/module.h"]
   includes = ["include"],
)
```

`ddk_headers` can be chained; that is, a `ddk_headers` target can re-export
another `ddk_headers` target. For example:

```
ddk_headers(
   name = "foo",
   hdrs = ["include_foo/foo.h"],
   includes = ["include_foo"],
)
ddk_headers(
   name = "headers",
   hdrs = [":foo", "include/module.h"],
   includes = ["include"],
)
```
""",
    attrs = {
        "hdrs": attr.label_list(allow_files = [".h"], doc = """One of the following:

- Local header files to be exported. You may also need to set the `includes` attribute.
- Other `ddk_headers` targets to be re-exported.
"""),
        "includes": attr.string_list(
            doc = """A list of directories, relative to the current package, that are re-exported as include directories.

[`ddk_module`](#ddk_module) with `deps` including this target automatically
adds the given include directory in the generated `Kbuild` files.

You still need to add the actual header files to `hdrs`.
""",
        ),
    },
)
