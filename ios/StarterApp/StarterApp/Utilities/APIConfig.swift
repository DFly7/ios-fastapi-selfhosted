//
//  Reads Backend URL, Supabase URL, and Supabase anon key from Info.plist.
//  Values are supplied by Config-Debug / Config-Release .xcconfig at build time.
//

import Foundation

enum APIConfig {
    private static let infoDictionary: [String: Any] = {
        guard let dict = Bundle.main.infoDictionary else {
            fatalError("Info.plist not found")
        }
        return dict
    }()

    static let backendURL: URL = {
        guard let urlString = infoDictionary["BackendURL"] as? String,
              !urlString.isEmpty,
              let url = URL(string: urlString) else {
            fatalError(
                "BackendURL is invalid or missing. Set BACKEND_URL in Config-Debug.xcconfig / " +
                "Config-Release.xcconfig and assign those files under the app target’s Debug / " +
                "Release configurations."
            )
        }
        return url
    }()

    static let supabaseURL: String = {
        guard let url = infoDictionary["SupabaseURL"] as? String, !url.isEmpty else {
            fatalError("SupabaseURL is invalid or missing in Info.plist")
        }
        return url
    }()

    static let supabaseAnonKey: String = {
        guard let key = infoDictionary["SupabaseAnonKey"] as? String, !key.isEmpty else {
            fatalError("SupabaseAnonKey is invalid or missing in Info.plist")
        }
        return key
    }()

    /// Custom URL scheme for OAuth / magic-link redirects (must match Supabase redirect allow list).
    ///
    /// Derived at runtime from `CFBundleURLTypes` in Info.plist, which is populated from
    /// `PRODUCT_BUNDLE_IDENTIFIER` by Project.swift. This means renaming the app bundle
    /// automatically keeps the scheme correct without any manual Swift change.
    static let authRedirectScheme: String = {
        guard
            let urlTypes = Bundle.main.infoDictionary?["CFBundleURLTypes"] as? [[String: Any]],
            let firstType = urlTypes.first,
            let schemes = firstType["CFBundleURLSchemes"] as? [String],
            let scheme = schemes.first, !scheme.isEmpty
        else {
            fatalError(
                "CFBundleURLSchemes is missing from Info.plist. " +
                "Check CFBundleURLTypes in Project.swift and regenerate the project with `tuist generate`."
            )
        }
        return scheme
    }()

    static let revenueCatAPIKey: String = {
        guard let key = infoDictionary["RevenueCatAPIKey"] as? String, !key.isEmpty else {
            fatalError(
                "RevenueCatAPIKey is invalid or missing. Set REVENUECAT_API_KEY in " +
                "Config-Debug.xcconfig / Config-Release.xcconfig and run `tuist generate`."
            )
        }
        return key
    }()

    /// True when `POSTHOG_API_KEY` is non-empty and PostHog is not explicitly turned off.
    ///
    /// Set `POSTHOG_ENABLED` to `TRUE` or `FALSE` in xcconfig. Leave `POSTHOG_API_KEY` empty to disable
    /// regardless. If the flag is missing or blank, PostHog runs when a key is present.
    static var isPostHogConfigured: Bool {
        guard let key = infoDictionary["PostHogAPIKey"] as? String, !key.isEmpty else {
            return false
        }
        if let raw = infoDictionary["PostHogEnabled"] as? String {
            let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if ["0", "NO", "FALSE", "OFF"].contains(normalized) {
                return false
            }
        }
        return true
    }
}
