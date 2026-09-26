import SwiftUI

/// What's New sheet presenting recent releases with motivations and feature details.
struct WhatsNewView: View {
    let releases: [AppRelease]
    var showsArchive: Bool = false
    var onClose: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var featured: AppRelease? {
        releases.max(by: { $0.build < $1.build })
    }

    private var earlier: [AppRelease] {
        guard showsArchive, let featured else { return [] }
        return releases.filter { $0.build < featured.build }.sorted { $0.build > $1.build }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if let featured {
                            featuredBlock(featured)
                        }
                        if !earlier.isEmpty {
                            archiveSection
                        }
                    }
                    .padding(20)
                }

                continueButton
            }
            .chibiListChrome()
            .navigationTitle("What's New")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(ChibiTheme.softGlass, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        onClose()
                        dismiss()
                    }
                }
            }
            .tint(ChibiTheme.amber)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func featuredBlock(_ release: AppRelease) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(ChibiTheme.amber)
                    .frame(width: 44, height: 44)
                    .background(ChibiTheme.amber.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Version \(release.version)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ChibiTheme.amber)
                        .textCase(.uppercase)
                    Text(release.date)
                        .font(.caption2)
                        .foregroundStyle(ChibiTheme.textTertiary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(release.headline)
                    .font(ChibiTheme.heroTitleFont())
                    .foregroundStyle(ChibiTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if !release.why.isEmpty {
                    Text(release.why)
                        .font(.body)
                        .foregroundStyle(ChibiTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !release.changes.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(release.changes) { change in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: change.icon)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(ChibiTheme.amber)
                                .frame(width: 24, height: 24)

                            Text(change.text)
                                .font(.subheadline)
                                .foregroundStyle(ChibiTheme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)

                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .chibiGlassCard(cornerRadius: 16)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var archiveSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Earlier Releases")
                .font(.headline)
                .foregroundStyle(ChibiTheme.textSecondary)

            VStack(alignment: .leading, spacing: 14) {
                ForEach(earlier) { release in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("v\(release.version)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(ChibiTheme.amber)
                            Text("—")
                                .foregroundStyle(ChibiTheme.textTertiary)
                            Text(release.headline)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(ChibiTheme.textPrimary)
                        }

                        if !release.why.isEmpty {
                            Text(release.why)
                                .font(.caption)
                                .foregroundStyle(ChibiTheme.textSecondary)
                        }
                    }
                    if release.id != earlier.last?.id {
                        Divider()
                            .overlay(ChibiTheme.hairline)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .chibiGlassCard(cornerRadius: 16)
        }
    }

    private var continueButton: some View {
        Button {
            onClose()
            dismiss()
        } label: {
            Text("Continue")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .tint(ChibiTheme.amber)
        .foregroundStyle(.black)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(ChibiTheme.softGlass)
    }
}

#Preview {
    WhatsNewView(releases: APP_RELEASES, showsArchive: true) {}
}
