#!/bin/zsh
set -e
source "${0:A:h}/common.sh"
export FILEWISE_TEST_DATABASE_DIRECTORY=$(mktemp -d "${TMPDIR:-/tmp}/filewise-search-dates.XXXXXX")
trap 'rm -rf "$FILEWISE_TEST_DATABASE_DIRECTORY"' EXIT
build_core "$build_dir/core"
swiftc "${swift_flags[@]}" "${core_link_flags[@]}" \
    "$project_dir"/tests/SearchDatesHarness.swift -o "$build_dir/search-dates-test"
"$build_dir/search-dates-test"
