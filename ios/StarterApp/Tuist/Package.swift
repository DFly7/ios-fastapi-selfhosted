// swift-tools-version: 5.9
// This file declares external SPM dependencies for Tuist.
// After editing, run: tuist install && tuist generate

import PackageDescription

#if TUIST
    import ProjectDescription

    let packageSettings = PackageSettings(
        productTypes: [
            // Use staticFramework (not framework) so that resource bundles from
            // transitive static dependencies (swift-crypto_Crypto.bundle,
            // PLCrashReporter_CrashReporter.bundle) are placed at the build
            // products root, where the Tuist-generated CpResource phase looks
            // for them. With .framework those bundles end up embedded inside the
            // dynamic framework and the copy phase fails with "No such file".
            "PostHog": .staticFramework,
            "RevenueCat": .staticFramework,
        ]
    )
#endif

let package = Package(
    name: "StarterAppPackages",
    dependencies: [
        .package(
            url: "https://github.com/PostHog/posthog-ios.git",
            from: "3.0.0"
        ),
        .package(
            url: "https://github.com/RevenueCat/purchases-ios.git",
            from: "5.0.0"
        ),
    ]
)
