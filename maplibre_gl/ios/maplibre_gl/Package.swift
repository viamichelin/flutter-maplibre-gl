// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "maplibre_gl",
    platforms: [
        .iOS("16.0"),
    ],
    products: [
        .library(name: "maplibre-gl", targets: ["maplibre_gl"])
    ],
    dependencies: [
        // Reuse MichelinNavigation's bundled MapLibre; keep in sync with viamichelin_navigation_ios.
        .package(url: "https://gitlab-dcadcx.michelin.net/mapping/mobile/ios-spm-mf-navigation-sdk.git", from: "6.3.3"),
    ],
    targets: [
        .target(
            name: "maplibre_gl",
            dependencies: [
                .product(name: "MichelinNavigation", package: "ios-spm-mf-navigation-sdk")
            ]
        )
    ]
)
