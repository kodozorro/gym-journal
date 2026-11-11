// swift-tools-version: 5.9
// Общая логика «Журнала тренировок» для iPhone и Apple Watch: журнал, план, очередь записей,
// обмен с таблицей. Только Foundation, без экранов: логика проверяется командой `swift test`.

import PackageDescription

let package = Package(
    name: "GymJournalCore",
    platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v13)],
    products: [
        .library(name: "GymJournalCore", targets: ["GymJournalCore"]),
    ],
    targets: [
        .target(name: "GymJournalCore", resources: [.process("Resources")]),
        .testTarget(
            name: "GymJournalCoreTests",
            dependencies: ["GymJournalCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
