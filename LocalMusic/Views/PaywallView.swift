import SwiftUI
import StoreKit

/// Onyx × Soft Glass paywall for ChibiAudio Plus.
struct PaywallView: View {
    @Environment(PlusStore.self) private var plus
    @Environment(\.dismiss) private var dismiss

    @State private var restoreMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    hero
                    benefits
                    purchaseBlock
                    if let err = plus.lastError {
                        Text(err)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    if let restoreMessage {
                        Text(restoreMessage)
                            .font(.footnote)
                            .foregroundStyle(ChibiTheme.textSecondary)
                    }
                    legal
                }
                .padding(20)
            }
            .chibiListChrome()
            .navigationTitle("ChibiAudio Plus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(ChibiTheme.softGlass, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .tint(ChibiTheme.amber)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task {
            await plus.loadProduct()
            await plus.refreshEntitlements()
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ChibiAudio Plus")
                .font(ChibiTheme.heroTitleFont())
                .foregroundStyle(ChibiTheme.textPrimary)
            Text("\(AppBranding.appStoreSubtitle). Support the app and unlock extras. Local files, Plex, Radio Browser, and core visuals stay free.")
                .font(.body)
                .foregroundStyle(ChibiTheme.textSecondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .chibiGlassCard(cornerRadius: 20)
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: 14) {
            benefitRow(icon: "nosign", title: "Ad-free listening", detail: "No banner ads on Home, Library, Playlists, or Radio.")
            benefitRow(icon: "waveform", title: "All visualizer modes", detail: "VU, LED, spectrum, kaleidoscope, vectors, vinyl, and mixtape.")
            benefitRow(icon: "car.fill", title: "CarPlay", detail: "Apple Audio templates only — large Now Playing art, browse, and queue. No custom dash visualizers.")
            benefitRow(icon: "applewatch", title: "Apple Watch companion", detail: "Stub controls for a future Watch app — Plus unlocks the path.")
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .chibiGlassCard(cornerRadius: 20)
    }

    private func benefitRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(ChibiTheme.amber)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(ChibiTheme.textPrimary)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(ChibiTheme.textSecondary)
            }
        }
    }

    private var purchaseBlock: some View {
        VStack(spacing: 12) {
            if plus.isPlusActive {
                Label("You’re subscribed to Plus", systemImage: "checkmark.seal.fill")
                    .font(.headline)
                    .foregroundStyle(ChibiTheme.teal)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .chibiGlassCard(cornerRadius: 14)
            } else {
                Button {
                    Task {
                        if await plus.purchase() {
                            dismiss()
                        }
                    }
                } label: {
                    HStack {
                        if plus.purchaseInFlight {
                            ProgressView()
                                .tint(.black)
                        }
                        Text("Subscribe — \(plus.displayPrice)/mo")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(ChibiTheme.amber)
                .foregroundStyle(.black)
                .disabled(plus.purchaseInFlight)

                Button("Restore Purchases") {
                    Task {
                        let ok = await plus.restore()
                        restoreMessage = ok
                            ? "Plus restored. Thanks for supporting ChibiAudio."
                            : "No active Plus subscription found for this Apple ID."
                    }
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(ChibiTheme.textSecondary)
            }
        }
    }

    private var legal: some View {
        Text("Auto-renewable subscription. Cancel anytime in Settings → Apple ID → Subscriptions. Payment is charged to your Apple ID.")
            .font(.caption2)
            .foregroundStyle(ChibiTheme.textTertiary)
    }
}

#Preview {
    PaywallView()
        .environment(PlusStore())
}
