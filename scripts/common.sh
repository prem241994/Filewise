# Shared build settings for the build, test, and snapshot scripts.
# Source it from zsh: `source "${0:A:h}/common.sh"`.
#
# The app is two modules: FilewiseCore (models, index, scanning, search, and
# Trash, with no UI) and the Filewise app (SwiftUI views and view models).
# Both compile in the Swift 6 language mode, with complete concurrency checks.

project_dir=${0:A:h:h}
build_dir="$project_dir/.build"
sdk_dir=${FILEWISE_SDK_PATH:-$(xcrun --sdk macosx --show-sdk-path)}
export CLANG_MODULE_CACHE_PATH="$build_dir/module-cache"
mkdir -p "$CLANG_MODULE_CACHE_PATH"

swift_flags=(
    -sdk "$sdk_dir"
    -module-cache-path "$CLANG_MODULE_CACHE_PATH"
    -target "$(uname -m)-apple-macosx14.0"
    -swift-version 6
    -parse-as-library
)
app_frameworks=(-framework SwiftUI -framework AppKit -framework QuickLook -framework QuickLookUI)

# build_core <output-dir> [extra swiftc flags…]
# Builds FilewiseCore as a static library and module in <output-dir>, and sets
# core_link_flags for compiling code that imports it.
build_core() {
    local out=$1
    shift
    mkdir -p "$out"
    swiftc "${swift_flags[@]}" "$@" \
        -module-name FilewiseCore -emit-library -static \
        -emit-module -emit-module-path "$out/FilewiseCore.swiftmodule" \
        "$project_dir"/Sources/FilewiseCore/**/*.swift \
        -o "$out/libFilewiseCore.a"
    core_link_flags=(-I "$out" -L "$out" -lFilewiseCore -lsqlite3 -framework Vision)
}

# Sources of the app's view-model layer, which the integration tests drive.
view_model_sources=("$project_dir"/Sources/Filewise/ViewModels/*.swift "$project_dir"/Sources/Filewise/Services/FolderAccess.swift)
