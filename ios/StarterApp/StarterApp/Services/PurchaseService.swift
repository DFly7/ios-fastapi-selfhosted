import Foundation
import Observation
import OSLog
import RevenueCat

/// Wraps the RevenueCat SDK; mirrors the ``AuthService`` pattern — @Observable, @MainActor,
/// environment-injected from ``StarterAppApp``.
///
/// Identity is managed externally: ``StarterAppApp`` observes ``AuthService/userId``
/// and calls ``identify(userId:)`` / ``reset()`` so the two services stay decoupled.
@Observable
@MainActor
final class PurchaseService {

    // MARK: - Published state

    private(set) var customerInfo: CustomerInfo?
    private(set) var availablePackages: [Package] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    // MARK: - Identity

    /// Logs the given Supabase user UUID into RevenueCat so entitlements follow the account,
    /// not the device. Must be called after a successful Supabase sign-in and before any
    /// purchase is initiated.
    func identify(userId: String) async {
        AppLog.purchases.info("Identifying RC user: \(userId, privacy: .private(mask: .hash))")
        do {
            let (info, _) = try await Purchases.shared.logIn(userId)
            customerInfo = info
            AppLog.purchases.info("RC identify succeeded")
        } catch {
            AppLog.purchases.error("RC identify failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Logs out the current RevenueCat user (called on Supabase sign-out).
    func reset() async {
        AppLog.purchases.info("Resetting RC identity (sign-out)")
        do {
            customerInfo = try await Purchases.shared.logOut()
        } catch {
            AppLog.purchases.error("RC logOut failed: \(error.localizedDescription, privacy: .public)")
            customerInfo = nil
        }
    }

    // MARK: - Offerings

    /// Fetches the current RC offering and caches ``availablePackages``.
    /// Safe to call multiple times; a no-op when packages are already loaded.
    func loadOfferings() async {
        guard availablePackages.isEmpty else { return }
        AppLog.purchases.info("Loading RC offerings")
        do {
            let offerings = try await Purchases.shared.offerings()
            availablePackages = offerings.current?.availablePackages ?? []
            AppLog.purchases.info("Loaded \(self.availablePackages.count) package(s)")
        } catch {
            AppLog.purchases.error("loadOfferings failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Purchase

    /// Initiates a purchase for the given package.
    ///
    /// - Throws: ``PurchaseError/cancelled`` when the user dismisses the sheet,
    ///   or ``PurchaseError/underlying`` for SDK-level failures.
    func purchase(_ package: Package) async throws {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        AppLog.purchases.info("Purchasing: \(package.identifier, privacy: .public)")
        do {
            let result = try await Purchases.shared.purchase(package: package)
            if result.userCancelled {
                AppLog.purchases.info("Purchase cancelled by user")
                throw PurchaseError.cancelled
            }
            customerInfo = result.customerInfo
            AppLog.purchases.info("Purchase succeeded")
        } catch let error as PurchaseError {
            throw error
        } catch {
            AppLog.purchases.error("Purchase failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = "Purchase failed. Please try again."
            throw PurchaseError.underlying(error)
        }
    }

    /// Restores previous purchases. Required by App Store guidelines — must be
    /// accessible from the paywall UI.
    func restorePurchases() async throws {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        AppLog.purchases.info("Restoring purchases")
        do {
            customerInfo = try await Purchases.shared.restorePurchases()
            AppLog.purchases.info("Restore succeeded")
        } catch {
            AppLog.purchases.error("Restore failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = "Restore failed. Please try again."
            throw PurchaseError.underlying(error)
        }
    }

    // MARK: - Entitlement helpers

    /// Returns `true` when the given RevenueCat entitlement identifier is active.
    ///
    /// Pass the entitlement ID configured in the RevenueCat dashboard (e.g. `"pro"`).
    func isSubscribed(to entitlement: String) -> Bool {
        customerInfo?.entitlements[entitlement]?.isActive == true
    }

    /// Convenience for the single "pro" entitlement used throughout this template.
    ///
    /// In `DEBUG` builds the `_isProOverride` flag takes precedence, acting as a master
    /// key for testing gated UI before a real RevenueCat sandbox key is configured.
    var isPro: Bool {
        #if DEBUG
        if let override = isProOverride { return override }
        #endif
        return isSubscribed(to: "pro")
    }

#if DEBUG
    /// Override `isPro` without a real RevenueCat entitlement. Set to `true` to
    /// simulate a subscribed user, `false` to force-free, or `nil` to fall back to
    /// the live SDK value. Only compiled in DEBUG builds — never ships to production.
    var isProOverride: Bool?
#endif
}

// MARK: - Errors

enum PurchaseError: LocalizedError {
    case cancelled
    case underlying(Error)

    var errorDescription: String? {
        switch self {
        case .cancelled: return "Purchase was cancelled."
        case .underlying(let err): return err.localizedDescription
        }
    }
}

// MARK: - SwiftUI Previews

extension PurchaseService {
    /// A service instance that reports the user as subscribed — for use in SwiftUI previews.
    ///
    /// `isPro` returns `true` via the `_isProOverride` debug flag. Note that
    /// `customerInfo` remains `nil` because `CustomerInfo` is an opaque RevenueCat type
    /// that cannot be instantiated outside the SDK. Any UI reading fields such as
    /// `customerInfo?.entitlements["pro"]?.expirationDate` **must** guard-let those
    /// values — production always has a real `customerInfo` after a successful login.
    @MainActor
    static var previewSubscribed: PurchaseService {
        let svc = PurchaseService()
        svc.isProOverride = true
        return svc
    }

    /// A service instance with no active entitlements.
    @MainActor
    static var previewFree: PurchaseService {
        PurchaseService()
    }
}
