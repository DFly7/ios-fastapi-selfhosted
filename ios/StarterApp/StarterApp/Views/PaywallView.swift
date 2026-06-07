import RevenueCat
import SwiftUI

/// Displays available subscription packages and handles purchase + restore flows.
///
/// Present this sheet whenever you want to gate a Pro feature:
/// ```swift
/// .sheet(isPresented: $showPaywall) { PaywallView() }
/// ```
///
/// Apple App Store guidelines require a visible "Restore Purchases" button on
/// any paywall — it is included at the bottom of this view.
struct PaywallView: View {
    @Environment(PurchaseService.self) private var purchases
    @Environment(\.dismiss) private var dismiss

    @State private var purchaseError: Error?
    @State private var showError = false
    @State private var showRestoreConfirmation = false

    var body: some View {
        NavigationStack {
            Group {
                if purchases.availablePackages.isEmpty {
                    loadingOrEmptyView
                } else {
                    packageList
                }
            }
            .navigationTitle("Upgrade to Pro")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                await purchases.loadOfferings()
            }
            .alert("Something went wrong", isPresented: $showError, presenting: purchaseError) { _ in
                Button("OK", role: .cancel) {}
            } message: { error in
                Text(error.localizedDescription)
            }
            .alert("Purchases Restored", isPresented: $showRestoreConfirmation) {
                Button("OK") {
                    if purchases.isPro { dismiss() }
                }
            } message: {
                Text(
                    purchases.isPro
                        ? "Your Pro subscription has been restored."
                        : "No active subscription found for this Apple ID."
                )
            }
            // Auto-dismiss only when isPro flips to true (false → true).
            // Naming oldValue/newValue explicitly prevents accidentally dismissing
            // if a network error later flips the state back to false.
            .onChange(of: purchases.isPro) { _, newValue in
                if newValue { dismiss() }
            }
        }
    }

    // MARK: - Subviews

    private var loadingOrEmptyView: some View {
        VStack(spacing: 16) {
            if purchases.isLoading {
                ProgressView()
                Text("Loading plans…")
                    .foregroundStyle(.secondary)
            } else {
                ContentUnavailableView(
                    "Plans Unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text("Could not load subscription plans. Please try again later.")
                )
                #if DEBUG
                // Developer escape hatch: toggle Pro without a real RevenueCat key.
                // Tapping "Simulate Pro" sets isProOverride = true, which triggers
                // the .onChange(of: isPro) watcher above and auto-dismisses the sheet.
                // This block is stripped from Release builds — it never ships.
                simulateProButton
                #endif
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    #if DEBUG
    private var simulateProButton: some View {
        Button {
            purchases.isProOverride = purchases.isProOverride == true ? false : true
        } label: {
            Text(purchases.isProOverride == true ? "Revoke Simulated Pro" : "Simulate Pro (Debug)")
                .font(.footnote)
        }
        .buttonStyle(.bordered)
        .padding(.top, 8)
    }
    #endif

    private var packageList: some View {
        List {
            Section {
                ForEach(purchases.availablePackages, id: \.identifier) { package in
                    PackageRow(package: package) {
                        await buy(package)
                    }
                }
            } header: {
                featureHeader
            }

            Section {
                restoreButton
            } footer: {
                Text("Subscriptions auto-renew unless cancelled. Manage in Settings → Apple ID → Subscriptions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(purchases.isLoading)
        .overlay {
            if purchases.isLoading {
                Color.black.opacity(0.15)
                    .ignoresSafeArea()
                ProgressView()
                    .controlSize(.large)
            }
        }
    }

    private var featureHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Pro Features")
                .font(.headline)
                .foregroundStyle(.primary)
                .textCase(nil)
            Label("Unlimited access", systemImage: "checkmark.circle.fill")
            Label("Priority support", systemImage: "checkmark.circle.fill")
            Label("Early access to new features", systemImage: "checkmark.circle.fill")
        }
        .padding(.bottom, 8)
        .foregroundStyle(.secondary)
        .font(.subheadline)
    }

    /// Apple requires this button to be visible on the paywall — do not remove.
    private var restoreButton: some View {
        Button {
            Task { await restore() }
        } label: {
            HStack {
                Spacer()
                Text("Restore Purchases")
                    .font(.subheadline)
                Spacer()
            }
        }
        .disabled(purchases.isLoading)
    }

    // MARK: - Actions

    private func buy(_ package: Package) async {
        do {
            try await purchases.purchase(package)
        } catch PurchaseError.cancelled {
            // User dismissed the system sheet — no error needed.
        } catch {
            purchaseError = error
            showError = true
        }
    }

    private func restore() async {
        do {
            try await purchases.restorePurchases()
            showRestoreConfirmation = true
        } catch {
            purchaseError = error
            showError = true
        }
    }
}

// MARK: - PackageRow

private struct PackageRow: View {
    let package: Package
    let onPurchase: () async -> Void

    var body: some View {
        Button {
            Task { await onPurchase() }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(package.storeProduct.localizedTitle)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(package.storeProduct.localizedDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(package.localizedPriceString)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Previews

#Preview("Free user") {
    PaywallView()
        .environment(PurchaseService.previewFree)
}

#Preview("Loading") {
    let svc = PurchaseService.previewFree
    return PaywallView()
        .environment(svc)
}
