#!/bin/zsh
set -e
source "${0:A:h}/common.sh"
build_core "$build_dir/core"
swiftc "${swift_flags[@]}" "${core_link_flags[@]}" \
    "$project_dir"/tests/LicenseHarness.swift -o "$build_dir/license-test"
"$build_dir/license-test"
