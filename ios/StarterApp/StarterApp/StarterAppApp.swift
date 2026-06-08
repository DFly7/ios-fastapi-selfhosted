//
//  StarterAppApp.swift
//  StarterApp
//
//  Created by Darragh Flynn on 30/03/2026.
//

import OSLog
import PostHog
import RevenueCat
import SwiftUI

@main
struct StarterAppApp: App {
    @State private var authService: AuthService
    @State private var purchaseService = PurchaseService()

    init() {
        Self.configurePostHogIfNeeded()
        Self.configureRevenueCat()

        _authService = State(
            initialValue: AuthService(backendURL: APIConfig.backendURL)
        )
        let posthogOn = APIConfig.isPostHogConfigured
        AppLog.general.info(
            "App init — Backend=\(APIConfig.backendURL, privacy: .public), PostHog=\(posthogOn, privacy: .public)"
        )
    }

    private static func configureRevenueCat() {
        Purchases.configure(withAPIKey: APIConfig.revenueCatAPIKey)
        #if DEBUG
        Purchases.logLevel = .debug
        #endif
        AppLog.purchases.info("RevenueCat configured")
    }

    private static func configurePostHogIfNeeded() {
        guard APIConfig.isPostHogConfigured,
              let apiKey = Bundle.main.infoDictionary?["PostHogAPIKey"] as? String,
              !apiKey.isEmpty
        else {
            return
        }
        let hostString = (Bundle.main.infoDictionary?["PostHogHost"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let host = (hostString?.isEmpty == false ? hostString : nil) ?? "https://us.i.posthog.com"
        let config = PostHogConfig(apiKey: apiKey, host: host)
        PostHogSDK.shared.setup(config)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(authService)
                .environment(purchaseService)
                // Sync RevenueCat identity whenever the authenticated user changes.
                // Fires on sign-in, sign-out, and the initial session check.
                // Runs before any purchase UI can be shown so RC never writes
                // an entitlement to an anonymous device ID.
                .task(id: authService.userId) {
                    if let id = authService.userId {
                        await purchaseService.identify(userId: id.uuidString)
                    } else {
                        await purchaseService.reset()
                    }
                }
                .onOpenURL { url in
                    let scheme = url.scheme ?? "nil"
                    let host = url.host ?? "nil"
                    AppLog.general.info(
                        "Open URL scheme=\(scheme, privacy: .public) host=\(host, privacy: .public)"
                    )
                }
        }
    }
}
