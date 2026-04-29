// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TextTransformPrimitive",
    platforms: [
        .macOS(.v13),
        .iOS(.v15),
    ],
    products: [
        .library(
            name: "TextTransformPrimitive",
            targets: ["TextTransformPrimitive"]
        ),
    ],
    dependencies: [
        .package(path: "../ReaderChromeThemePrimitive"),
    ],
    targets: [
        .target(
            name: "TextTransformPrimitive",
            dependencies: [
                .product(name: "ReaderChromeThemePrimitive", package: "ReaderChromeThemePrimitive"),
            ]
        ),
        .testTarget(
            name: "TextTransformPrimitiveTests",
            dependencies: ["TextTransformPrimitive"]
        ),
    ]
)
