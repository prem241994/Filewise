#!/bin/zsh
set -e
source "${0:A:h}/common.sh"
filewise_test_db_dir=$(mktemp -d "${TMPDIR:-/tmp}/filewise-benchmark-index.XXXXXX")
trap 'rm -rf "$filewise_test_db_dir"' EXIT
# Optimized, in its own directory so it never replaces the debug library.
build_core "$build_dir/core-release" -O
swiftc -O "${swift_flags[@]}" "${app_frameworks[@]}" "${core_link_flags[@]}" \
    "${view_model_sources[@]}" "$project_dir"/tests/ScanBenchmark.swift -o "$build_dir/scan-benchmark"
FILEWISE_TEST_DATABASE_DIRECTORY="$filewise_test_db_dir" "$build_dir/scan-benchmark"
