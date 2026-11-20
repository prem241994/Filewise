import FilewiseCore
import SwiftUI

/// The first-run page, shown on Home until a folder is chosen. It explains
/// what Filewise does and offers Downloads, which the sandbox can read
/// without asking, as a one-click start.
struct WelcomeView: View {
    @ObservedObject var library: Library
    @EnvironmentObject private var store: Store
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private var downloads: URL {
        FolderAccess.homeDirectory.appendingPathComponent("Downloads", isDirectory: true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            hero.entrance(appeared, order: 0)
            if store.status == .notStarted { trialOffer.entrance(appeared, order: 1) }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: Theme.Spacing.l, alignment: .top)],
                      spacing: Theme.Spacing.l) { features }
                .entrance(appeared, order: 2)
            dropZone.entrance(appeared, order: 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            if reduceMotion {
                var instant = Transaction()
                instant.disablesAnimations = true
                withTransaction(instant) { appeared = true }
            } else {
                appeared = true
            }
        }
    }

    // MARK: - Hero

    private var hero: some View {
        ViewThatFits(in: .horizontal) {
            // A fixed text width makes the fit test independent of line wrapping.
            HStack(spacing: Theme.Spacing.xl) {
                heroText.frame(width: 380, alignment: .leading)
                Spacer(minLength: 0)
                WelcomeIllustration().frame(width: 250, height: 250)
                Spacer(minLength: 0)
            }
            heroText
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 36)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(heroBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(
                    LinearGradient(colors: [Color.white.opacity(colorScheme == .dark ? 0.16 : 0.7),
                                            Color.accentColor.opacity(0.15)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Color.indigo.opacity(colorScheme == .dark ? 0.25 : 0.10), radius: 18, y: 8)
    }

    private var heroText: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(spacing: 5) {
                Image(systemName: "sparkles").foregroundStyle(.tint).accessibilityHidden(true)
                Text("Welcome to Filewise").foregroundStyle(.primary.opacity(0.8))
            }
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.accentColor.opacity(colorScheme == .dark ? 0.22 : 0.12), in: Capsule())
            Text("Find any file.\nClear the clutter.")
                .font(.system(size: 38, weight: .bold))
                .accessibilityLabel("Find any file. Clear the clutter.")
                .accessibilityAddTraits(.isHeader)
                .kerning(-0.6)
                .lineSpacing(-2)
                .fixedSize(horizontal: false, vertical: true)
            Text("Search your files in plain words, and see the duplicates, old downloads, and large files you can safely remove.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Theme.Spacing.m) {
                Button {
                    library.selectLocation(downloads)
                } label: {
                    Label("Scan Downloads", systemImage: "arrow.down.circle.fill")
                        .padding(.horizontal, Theme.Spacing.xs)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .accessibilityHint("Scans your Downloads folder")

                Button("Choose Folder…") { library.chooseFolder() }
                    .buttonStyle(.bordered)
            }
            .controlSize(.extraLarge)
            .padding(.top, Theme.Spacing.s)
            HStack(spacing: Theme.Spacing.m) {
                assurance("No account needed")
                assurance("Works offline")
                assurance("Undo for Trash")
            }
            .padding(.top, Theme.Spacing.xxs)
        }
    }

    private func assurance(_ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityHidden(true)
            Text(text).foregroundStyle(.secondary)
        }
        .font(.caption)
        .lineLimit(1)
        .fixedSize()
    }

    private var heroBackground: some View {
        let strength = colorScheme == .dark ? 0.34 : 0.17
        return ZStack {
            LinearGradient(colors: [Color.indigo.opacity(strength), Color.blue.opacity(strength * 0.55),
                                    Color.teal.opacity(strength * 0.5)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            // Soft color glows behind the illustration.
            Circle().fill(Color.pink.opacity(strength * 1.1)).frame(width: 280).blur(radius: 80)
                .offset(x: 280, y: -100)
            Circle().fill(Color.teal.opacity(strength)).frame(width: 260).blur(radius: 80)
                .offset(x: 360, y: 120)
            Circle().fill(Color.indigo.opacity(strength * 0.8)).frame(width: 220).blur(radius: 70)
                .offset(x: -320, y: 140)
        }
    }

    // MARK: - Trial

    /// The trial's length, what it gates, and the price, shown before it
    /// starts as App Review requires.
    private var trialOffer: some View {
        HStack(spacing: Theme.Spacing.l) {
            Image(systemName: "gift.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(LinearGradient(colors: [.orange, .pink], startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(License.trialDays)-day free trial").font(.headline).accessibilityAddTraits(.isHeader)
                Text(store.trialTerms)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Theme.Spacing.s)
            Button("Start Free Trial") { Task { await store.startTrial() } }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(store.isPurchasing)
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [Color.orange.opacity(colorScheme == .dark ? 0.20 : 0.10),
                                            Color.pink.opacity(colorScheme == .dark ? 0.08 : 0.03)],
                                   startPoint: .leading, endPoint: .trailing),
                    in: RoundedRectangle(cornerRadius: Theme.Radius.l, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.l, style: .continuous)
            .strokeBorder(Color.orange.opacity(0.2), lineWidth: 1))
    }

    // MARK: - Features

    @ViewBuilder private var features: some View {
        FeatureCard(icon: "magnifyingglass", color: .blue, title: "Find anything",
                    detail: "Type what you remember. Filewise understands dates, types, and sizes.") {
            HStack(spacing: Theme.Spacing.xs) {
                tag("pdfs from last week", .blue)
                tag("large videos", .blue)
            }
        }
        FeatureCard(icon: "sparkles", color: .orange, title: "Clean up safely",
                    detail: "Review suggestions before anything moves. Files go to the Trash, and Undo brings them back.") {
            // One row when it fits, otherwise two; a tag never wraps.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Spacing.xs) {
                    tag("Duplicates", .red); tag("Old downloads", .blue); tag("Large files", .green)
                }
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    HStack(spacing: Theme.Spacing.xs) { tag("Duplicates", .red); tag("Old downloads", .blue) }
                    tag("Large files", .green)
                }
            }
        }
        FeatureCard(icon: "lock.shield.fill", color: .green, title: "Stays on your Mac",
                    detail: "No account, no tracking, no uploads. Filewise only opens folders you choose.") {
            Label("Nothing leaves this Mac", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(.green)
        }
    }

    private func tag(_ name: String, _ color: Color) -> some View {
        Text(name)
            .font(.caption.weight(.medium))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, Theme.Spacing.s)
            .padding(.vertical, Theme.Spacing.xxs)
            .background(color.opacity(0.14), in: Capsule())
            .foregroundStyle(color)
    }

    // MARK: - Drop zone

    private var dropZone: some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 34, height: 34)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Or drop any folder onto this window").font(.headline)
                Text("You can switch folders anytime from the sidebar.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.l, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                .foregroundStyle(Color.primary.opacity(0.16)))
        .accessibilityElement(children: .combine)
    }
}

private extension View {
    /// Fades and lifts a section in, one after another.
    func entrance(_ appeared: Bool, order: Int) -> some View {
        opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 12)
            .animation(.easeOut(duration: 0.5).delay(0.08 + Double(order) * 0.1), value: appeared)
    }
}

/// A tinted card like the Library cards: badge and title, text, and an example row.
private struct FeatureCard<Accessory: View>: View {
    let icon: String
    let color: Color
    let title: String
    let detail: String
    @ViewBuilder let accessory: Accessory
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(LinearGradient(colors: [color.opacity(0.85), color],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .shadow(color: color.opacity(0.35), radius: 4, y: 2)
                    .accessibilityHidden(true)
                Text(title).font(.system(size: 15, weight: .semibold))
            }
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineSpacing(1)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Theme.Spacing.xxs)
            Spacer(minLength: Theme.Spacing.s)
            accessory
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, minHeight: 156, alignment: .topLeading)
        .background(LinearGradient(colors: [color.opacity(colorScheme == .dark ? 0.24 : 0.11),
                                            color.opacity(colorScheme == .dark ? 0.07 : 0.025)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.l, style: .continuous)
            .strokeBorder(color.opacity(0.18), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.l, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// File-type badges that spring out around a magnifying glass, then slowly
/// orbit it while a few sparkles twinkle. Still when Reduce Motion is on.
private struct WelcomeIllustration: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    private let categories = ["Images", "Documents", "Videos", "Archives", "Apps", "Music"]
    private let tilts: [Double] = [-10, 4, 9, -8, -4, 7]
    private let sparkles: [(x: CGFloat, y: CGFloat, size: CGFloat)] = [(-112, -100, 12), (116, 4, 10), (-36, 116, 9)]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let elapsed = reduceMotion ? 10 : context.date.timeIntervalSince(start)
            // One revolution every 60 seconds.
            let orbit = reduceMotion ? 0 : elapsed / 60 * 2 * .pi
            ZStack {
                Circle()
                    .strokeBorder(Color.accentColor.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [3, 6]))
                    .frame(width: 186, height: 186)
                Circle()
                    .strokeBorder(Color.accentColor.opacity(0.1), lineWidth: 1)
                    .frame(width: 132, height: 132)
                ForEach(sparkles.indices, id: \.self) { index in
                    let sparkle = sparkles[index]
                    let twinkle = reduceMotion ? 0.8 : 0.45 + 0.55 * (0.5 + 0.5 * sin(elapsed * 1.6 + Double(index) * 2))
                    Image(systemName: "sparkle")
                        .font(.system(size: sparkle.size, weight: .bold))
                        .foregroundStyle(Color.accentColor.opacity(0.7))
                        .opacity(twinkle * progress(elapsed, delay: 0.5))
                        .scaleEffect(0.8 + 0.2 * twinkle)
                        .offset(x: sparkle.x, y: sparkle.y)
                }
                ForEach(categories.indices, id: \.self) { index in
                    badge(index, elapsed: elapsed, orbit: orbit)
                }
                center(elapsed)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityHidden(true)
        .onAppear { start = Date() }
    }

    private func badge(_ index: Int, elapsed: Double, orbit: Double) -> some View {
        let category = categories[index]
        let color = Theme.color(for: category)
        let grow = easeOutBack(progress(elapsed, delay: 0.15 + Double(index) * 0.06))
        let angle = orbit + Double(index) / Double(categories.count) * 2 * .pi - .pi / 2
        let radius = 93 * grow
        let bob = reduceMotion ? 0 : 3 * sin(elapsed * 1.3 + Double(index))
        return Image(systemName: Theme.icon(for: category))
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 46, height: 46)
            .background(LinearGradient(colors: [color.opacity(0.78), color],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5))
            .shadow(color: color.opacity(0.4), radius: 8, y: 4)
            .rotationEffect(.degrees(tilts[index]))
            .scaleEffect(0.3 + 0.7 * grow)
            .opacity(min(1, progress(elapsed, delay: 0.15 + Double(index) * 0.06) * 2))
            .offset(x: radius * cos(angle), y: radius * sin(angle) + bob)
    }

    private func center(_ elapsed: Double) -> some View {
        let pulse = reduceMotion ? 0 : 0.5 + 0.5 * sin(elapsed * 1.2)
        return ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.14))
                .frame(width: 104, height: 104)
                .scaleEffect(1 + 0.06 * pulse)
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 82, height: 82)
                .background(LinearGradient(colors: [Color.accentColor.opacity(0.75), .accentColor, .indigo],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.3), lineWidth: 0.5))
                .shadow(color: Color.accentColor.opacity(0.45), radius: 14, y: 6)
        }
        .scaleEffect(0.6 + 0.4 * easeOutBack(progress(elapsed, delay: 0)))
    }

    /// 0…1 over 0.65 s, starting `delay` seconds after the page appears.
    private func progress(_ elapsed: Double, delay: Double) -> Double {
        min(1, max(0, (elapsed - delay) / 0.65))
    }

    /// Overshoots slightly before settling, like a spring.
    private func easeOutBack(_ x: Double) -> Double {
        let c1 = 1.70158, c3 = c1 + 1
        return 1 + c3 * pow(x - 1, 3) + c1 * pow(x - 1, 2)
    }
}
