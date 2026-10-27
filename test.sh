#!/bin/bash
# Testleri derler ve çalıştırır. Xcode kuruluysa düz `swift test` de yeterlidir.
set -euo pipefail
cd "$(dirname "$0")"

# Gizlilik koruması: uygulama ağa çıkmaz ve Keychain'e erişmez.
if grep -rnE 'URLSession|URLRequest|NSURLConnection|import Network|import Security|SecItem' Sources; then
    echo "✘ Kaynak kodda ağ veya Keychain erişimi bulundu (yukarıda). Uygulama hiçbir veriyi dışarı göndermemeli." >&2
    exit 1
fi

swift build --build-tests
BIN_DIR="$(swift build --show-bin-path)"
BUNDLE="$BIN_DIR/ClaudeUsageBarPackageTests.xctest/Contents/MacOS/ClaudeUsageBarPackageTests"

CLT_DEV=/Library/Developer/CommandLineTools/Library/Developer
if [[ -d "$CLT_DEV/Frameworks/Testing.framework" ]] && ! xcode-select -p | grep -q Xcode.app; then
    RUNNER="$BIN_DIR/swift-testing-runner"
    if [[ ! -x "$RUNNER" || Scripts/TestRunner.swift -nt "$RUNNER" ]]; then
        swiftc -parse-as-library -F "$CLT_DEV/Frameworks" \
            -Xlinker -rpath -Xlinker "$CLT_DEV/Frameworks" \
            -Xlinker -rpath -Xlinker "$CLT_DEV/usr/lib" \
            Scripts/TestRunner.swift -o "$RUNNER"
    fi
    exec "$RUNNER" "$BUNDLE"
else
    exec swift test "$@"
fi
