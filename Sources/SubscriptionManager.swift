import StoreKit

/// Auto-renewable subscription with a 1-week free trial (introductory offer configured in App Store Connect).
@MainActor
final class SubscriptionManager: ObservableObject {
    static let productIDs = ["com.yourcompany.goalpilot.monthly", "com.yourcompany.goalpilot.yearly"]
    @Published var products: [Product] = []
    @Published var isSubscribed = false
    @Published var inTrial = false
    @Published var loaded = false
    @Published var testBypass = false   // only reachable in TESTBUILD
    @Published var error: String?
    private var updates: Task<Void, Never>?

    init() {
        updates = Task { [weak self] in
            for await _ in Transaction.updates { await self?.refresh() }
        }
    }
    deinit { updates?.cancel() }

    func load() async {
        products = ((try? await Product.products(for: Self.productIDs)) ?? []).sorted { $0.price < $1.price }
        await refresh()
        loaded = true
    }

    func refresh() async {
        var active = false, trial = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, t.revocationDate == nil {
                active = true
                if t.offerType == .introductory { trial = true }
            }
        }
        isSubscribed = active; inTrial = trial
    }

    func purchase(_ p: Product) async {
        do {
            if case .success(let r) = try await p.purchase(), case .verified(let t) = r {
                await t.finish(); await refresh()
            }
        } catch { self.error = error.localizedDescription }
    }

    func restore() async { try? await AppStore.sync(); await refresh() }

    func trialText(_ p: Product) -> String {
        p.subscription?.introductoryOffer?.paymentMode == .freeTrial ? "Start 7-day free trial" : "Subscribe"
    }
}
