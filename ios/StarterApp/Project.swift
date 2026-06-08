import ProjectDescription

let project = Project(
    name: "StarterApp",
    settings: .settings(
        configurations: [
            .debug(name: "Debug", xcconfig: "Config-Debug.xcconfig"),
            .release(name: "Release", xcconfig: "Config-Release.xcconfig"),
        ]
    ),
    targets: [
        .target(
            name: "StarterApp",
            destinations: .iOS,
            product: .app,
            // Resolved at build time from Config-Debug/Release.xcconfig
            bundleId: "$(PRODUCT_BUNDLE_IDENTIFIER)",
            deploymentTargets: .iOS("17.0"),
            infoPlist: .extendingDefault(with: [
                // Declare standard HTTPS-only encryption so TestFlight build processing
                // skips the manual compliance questionnaire and goes straight to testers.
                // This app uses TLS via Apple's Network.framework only — no custom crypto.
                // If you add your own encryption layer, change this to true and complete
                // the encryption compliance form in App Store Connect.
                "ITSAppUsesNonExemptEncryption": .boolean(false),
                // Allow plain HTTP to loopback in all builds. Production URLs use HTTPS;
                // this only matters for local device testing against a tunnel or Simulator.
                "NSAppTransportSecurity": .dictionary([
                    "NSAllowsLocalNetworking": .boolean(true),
                ]),
                // Runtime URLs and keys — values injected from xcconfig
                "BackendURL": "$(BACKEND_URL)",
                "PostHogAPIKey": "$(POSTHOG_API_KEY)",
                "PostHogHost": "$(POSTHOG_HOST)",
                "PostHogEnabled": "$(POSTHOG_ENABLED)",
                "RevenueCatAPIKey": "$(REVENUECAT_API_KEY)",
                // Auth redirect scheme.
                // Uses PRODUCT_BUNDLE_IDENTIFIER so renaming the app bundle
                // automatically keeps the scheme in sync. APIConfig reads this
                // at runtime from CFBundleURLTypes — no hardcoded value in Swift.
                "CFBundleURLTypes": .array([
                    .dictionary([
                        "CFBundleTypeRole": "Editor",
                        "CFBundleURLName": "$(PRODUCT_BUNDLE_IDENTIFIER)",
                        "CFBundleURLSchemes": .array(["$(PRODUCT_BUNDLE_IDENTIFIER)"]),
                    ]),
                ]),
                "UIApplicationSceneManifest": .dictionary([
                    "UIApplicationSupportsMultipleScenes": .boolean(false),
                ]),
                "UILaunchScreen": .dictionary([:]),
                "UISupportsIndirectInputEvents": .boolean(true),
                "UISupportedInterfaceOrientations": .array([
                    "UIInterfaceOrientationPortrait",
                    "UIInterfaceOrientationLandscapeLeft",
                    "UIInterfaceOrientationLandscapeRight",
                ]),
                "UISupportedInterfaceOrientations~iPad": .array([
                    "UIInterfaceOrientationPortrait",
                    "UIInterfaceOrientationPortraitUpsideDown",
                    "UIInterfaceOrientationLandscapeLeft",
                    "UIInterfaceOrientationLandscapeRight",
                ]),
            ]),
            sources: ["StarterApp/**/*.swift"],
            resources: [
                "StarterApp/Assets.xcassets",
                "StarterApp/PrivacyInfo.xcprivacy",
            ],
            entitlements: .file(path: "StarterApp.entitlements"),
            dependencies: [
                .external(name: "PostHog"),
                .external(name: "RevenueCat"),
            ],
            settings: .settings(
                base: [
                    "DEVELOPMENT_TEAM": "$(DEVELOPMENT_TEAM)",
                    "CODE_SIGN_STYLE": "Automatic",
                    "MARKETING_VERSION": "1.0",
                    "CURRENT_PROJECT_VERSION": "1",
                    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
                    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
                    "ENABLE_PREVIEWS": "YES",
                    "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"],
                    "STRING_CATALOG_GENERATE_SYMBOLS": "YES",
                    "SWIFT_APPROACHABLE_CONCURRENCY": "YES",
                    "SWIFT_DEFAULT_ACTOR_ISOLATION": "MainActor",
                    "SWIFT_EMIT_LOC_STRINGS": "YES",
                    "SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY": "YES",
                    "SWIFT_VERSION": "5.0",
                ]
            )
        ),
        .target(
            name: "StarterAppTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "com.example.StarterAppTests",
            deploymentTargets: .iOS("17.0"),
            sources: ["StarterAppTests/**/*.swift"],
            dependencies: [
                .target(name: "StarterApp"),
            ],
            settings: .settings(
                base: [
                    "CODE_SIGNING_ALLOWED": "NO",
                    "BUNDLE_LOADER": "$(TEST_HOST)",
                    "SWIFT_APPROACHABLE_CONCURRENCY": "YES",
                    "SWIFT_VERSION": "5.0",
                    "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/StarterApp.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/StarterApp",
                ]
            )
        ),
        .target(
            name: "StarterAppUITests",
            destinations: .iOS,
            product: .uiTests,
            bundleId: "com.example.StarterAppUITests",
            deploymentTargets: .iOS("17.0"),
            sources: ["StarterAppUITests/**/*.swift"],
            dependencies: [
                .target(name: "StarterApp"),
            ],
            settings: .settings(
                base: [
                    "CODE_SIGNING_ALLOWED": "NO",
                    "SWIFT_APPROACHABLE_CONCURRENCY": "YES",
                    "SWIFT_VERSION": "5.0",
                    "TEST_TARGET_NAME": "StarterApp",
                ]
            )
        ),
    ],
    schemes: [
        .scheme(
            name: "StarterApp",
            buildAction: .buildAction(targets: [.target("StarterApp")]),
            testAction: .targets([
                .testableTarget(target: .target("StarterAppTests")),
                .testableTarget(target: .target("StarterAppUITests")),
            ]),
            runAction: .runAction(
                configuration: .debug,
                executable: .target("StarterApp"),
                options: .options(storeKitConfigurationPath: "SupportingFiles/Products.storekit")
            )
        ),
    ],
    additionalFiles: [
        .glob(pattern: "SupportingFiles/**"),
    ]
)
