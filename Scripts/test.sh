#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p build
xcrun swiftc -swift-version 5 Sources/CaffeinateSession.swift Tests/main.swift -o build/SessionTests
build/SessionTests
xcrun swiftc -swift-version 5 Sources/CaffeinateSession.swift Sources/CoffeeModel.swift Sources/ClosedLidController.swift Shared/*.swift Tests/CoffeeModel/main.swift \
    -framework AppKit -framework ServiceManagement -o build/CoffeeModelTests
build/CoffeeModelTests
xcrun swiftc -swift-version 5 Sources/ClosedLidController.swift Shared/*.swift Tests/LidGuard/main.swift -o build/LidGuardTests
build/LidGuardTests
