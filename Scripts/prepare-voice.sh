#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
vendor=build/vendor
mkdir -p "$vendor"
fetch() {
    local_file=$1
    expected=$2
    source_url=$3
    if [ -f "$local_file" ] && [ "$(shasum -a 256 "$local_file" | cut -d ' ' -f 1)" = "$expected" ]; then return; fi
    staging=$(mktemp "$vendor/download.XXXXXX")
    trap 'rm -f "$staging"' EXIT
    curl --fail --show-error --location --retry 2 --output "$staging" "$source_url"
    actual=$(shasum -a 256 "$staging" | cut -d ' ' -f 1)
    if [ "$actual" != "$expected" ]; then echo "Integrity check failed for $local_file" >&2; exit 1; fi
    mv -f "$staging" "$local_file"
    trap - EXIT
}
archive="$vendor/whisper.cpp-1.7.5.zip"
fetch "$archive" a8e38fdbe85fae2c968914f4bd2671467671ca07aa003a5daea379891f064dc6 \
    'https://github.com/ggml-org/whisper.cpp/archive/refs/tags/v1.7.5.zip'
fetch "$vendor/ggml-base.en-q5_1.bin" 4baf70dd0d7c4247ba2b81fafd9c01005ac77c2f9ef064e00dcf195d0e2fdd2f \
    'https://huggingface.co/ggerganov/whisper.cpp/resolve/c521a4b02f422512d734391fdf08bb08c0862f68/ggml-base.en-q5_1.bin?download=true'
unzip -oq "$archive" 'whisper.cpp-1.7.5/ggml/*' 'whisper.cpp-1.7.5/src/*' 'whisper.cpp-1.7.5/include/*' 'whisper.cpp-1.7.5/examples/grammar-parser.*' -d "$vendor"
patch -s -d "$vendor/whisper.cpp-1.7.5" -p1 < Scripts/complete-grammar.patch
