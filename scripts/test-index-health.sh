#!/bin/zsh
set -e
source "${0:A:h}/common.sh"
filewise_test_db_dir=$(mktemp -d "${TMPDIR:-/tmp}/filewise-health-test.XXXXXX")
trap 'rm -rf "$filewise_test_db_dir"' EXIT
build_core "$build_dir/core"
swiftc "${swift_flags[@]}" "${core_link_flags[@]}" \
    "$project_dir"/tests/IndexHealthHarness.swift -o "$build_dir/index-health-test"
FILEWISE_TEST_DATABASE_DIRECTORY="$filewise_test_db_dir/migration" "$build_dir/index-health-test" migration
FILEWISE_TEST_DATABASE_DIRECTORY="$filewise_test_db_dir/corrupt" "$build_dir/index-health-test" corrupt
