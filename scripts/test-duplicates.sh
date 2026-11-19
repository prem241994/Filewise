#!/bin/zsh
set -e
source "${0:A:h}/common.sh"
build_core "$build_dir/core"
swiftc "${swift_flags[@]}" "${core_link_flags[@]}" \
    "$project_dir"/tests/DuplicateSelectionHarness.swift -o "$build_dir/duplicate-selection-test"
"$build_dir/duplicate-selection-test"
