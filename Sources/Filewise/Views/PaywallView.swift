import FilewiseCore
import SwiftUI

/// The unlock sheet, shown when a cleanup action is used before the trial
/// starts or after it ends. It names what the user was about to clean up and
/// keeps the free parts clear. Before the trial it offers to start it, with
/// the terms App Review requires shown first.
struct PaywallView: View {
    @ObservedObject var store: Store
    let request: PaywallRequest
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private var offersTrial: Bool { store.status == .notStarted }

    private var title: String {
        if request.trialEnded { return "Your free trial has ended" }
        if offersTrial {
            return request.bytes > 0 ? "Start your free trial to clean up \(Theme.bytes(request.bytes))"
                                     : "Start your free trial"
        }
        return request.bytes > 0 ? "Unlock Filewise to clean up \(Theme.bytes(request.bytes))" : "Unlock Filewise"
    }

    private var subtitle: String {
        if request.trialEnded {
            let offer = request.bytes > 0
                ? "Unlock Filewise to clean up the \(Theme.bytes(request.bytes)) it found."
                : "Unlock Filewise once to keep cleaning up."
            return offer + " Searching and browsing stay free."
        }
        if offersTrial { return store.trialTerms }
        return switch store.status {
        case .trial(let days):
            "Your free trial has \(Theme.count(days, "day")) left. Unlock now to keep cleaning up after it ends."
        case .unlocked:
            "Filewise is unlocked. Thank you!"
        default:
            "Your 7-day free trial has ended. Searching and browsing stay free; cleaning up needs a one-time purchase."
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                benefit("trash", .red, "Move suggestions to the Trash", "Duplicates, old downloads, large files, and more.")
                benefit("checklist", .orange, "Select extra copies in one click", "Keep the oldest, newest, or the copy in a folder you choose.")
                benefit("arrow.uturn.backward.circle", .blue, "Undo always stays free", "Files you moved can be restored, unlocked or not.")
                benefit("checkmark.seal", .green, "Pay once", "No subscription and no account.")
            }
            .padding(.horizontal, 32)
            .padding(.vertical, Theme.Spacing.xl)

            if let error = store.purchaseError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 32)
                    .padding(.bottom, Theme.Spacing.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()
            buttons
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.vertical, Theme.Spacing.l)
        }
        .frame(width: 460)
        .onChange(of: store.status) { _, status in
            if status == .unlocked { dismiss() }
        }
    }

    private var header: some View {
        VStack(spacing: Theme.Spacing.m) {
            Image(systemName: "sparkles")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 60, height: 60)
                .background(LinearGradient(colors: [.orange, .pink], startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: Color.pink.opacity(0.35), radius: 10, y: 4)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 32)
        .padding(.top, 28)
        .padding(.bottom, Theme.Spacing.l)
        .frame(maxWidth: .infinity)
        .background(LinearGradient(colors: [Color.orange.opacity(colorScheme == .dark ? 0.22 : 0.12),
                                            Color.pink.opacity(colorScheme == .dark ? 0.10 : 0.04)],
                                   startPoint: .top, endPoint: .bottom))
    }

    private func benefit(_ icon: String, _ color: Color, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(Theme.tint(color), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var buttons: some View {
        VStack(spacing: Theme.Spacing.m) {
            if offersTrial {
                Button {
                    Task { await store.startTrial() }
                } label: {
                    Text("Start \(License.trialDays)-Day Free Trial").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(store.isPurchasing)
            }
            purchaseRow
        }
        .controlSize(.large)
    }

    private var purchaseRow: some View {
        HStack(spacing: Theme.Spacing.m) {
            Button("Restore Purchase") { Task { await store.restore() } }
                .disabled(store.isPurchasing)
            Spacer()
            Button("Not Now") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button {
                Task { await store.purchase() }
            } label: {
                HStack(spacing: Theme.Spacing.s) {
                    if store.isPurchasing { ProgressView().controlSize(.small) }
                    Text(store.priceText.isEmpty ? "Unlock" : "Unlock for \(store.priceText)")
                }
                .padding(.horizontal, Theme.Spacing.xs)
            }
            .buttonStyle(.borderedProminent)
            .tint(offersTrial ? .secondary : .accentColor)
            .disabled(store.isPurchasing || store.status == .unlocked)
            .keyboardShortcut(offersTrial ? nil : .defaultAction)
        }
    }
}
