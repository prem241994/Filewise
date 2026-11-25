#!/bin/zsh
set -e
source "${0:A:h}/common.sh"
filewise_test_db_dir=$(mktemp -d "${TMPDIR:-/tmp}/filewise-image-text-index.XXXXXX")
trap 'rm -rf "$filewise_test_db_dir"' EXIT
build_core "$build_dir/core"
swiftc "${swift_flags[@]}" "${app_frameworks[@]}" "${core_link_flags[@]}" \
    "${view_model_sources[@]}" "$project_dir"/tests/ImageTextHarness.swift -o "$build_dir/image-text-test"
FILEWISE_TEST_DATABASE_DIRECTORY="$filewise_test_db_dir" "$build_dir/image-text-test"
