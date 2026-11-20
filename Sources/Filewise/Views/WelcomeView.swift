import SwiftUI

/// The first-run page, shown on Home until a folder is chosen. It explains
/// what Filewise does and offers Downloads, which the sandbox can read
/// without asking, as a one-click start.
struct WelcomeView: View {
    @ObservedObject var library: Library
    @Environment(\.colorScheme) private var colorScheme

    private var downloads: URL {
        FolderAccess.homeDirectory.appendingPathComponent("Downloads", isDirectory: true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            hero
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: Theme.Spacing.l, alignment: .top)],
                      spacing: Theme.Spacing.l) { features }
            dropZone
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Hero

    private var hero: some View {
        ViewThatFits(in: .horizontal) {
            // A fixed text width makes the fit test independent of line wrapping.
            HStack(spacing: Theme.Spacing.xl) {
                heroText.frame(width: 360, alignment: .leading)
                Spacer(minLength: 0)
                WelcomeIllustration().frame(width: 240, height: 230)
                Spacer(minLength: 0)
            }
            heroText
        }
        .padding(.horizontal, 36)
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(heroBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.18), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var heroText: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("WELCOME TO FILEWISE")
                .font(.system(size: 12, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(.tint)
            Text("Find any file.\nClear the clutter.")
                .font(.system(size: 34, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
            Text("Search your files in plain words and see the duplicates, old downloads, and large files you can safely remove.")
                .font(.title3)
                .foregroundStyle(.secondary)
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
        }
    }

    private var heroBackground: some View {
        let strength = colorScheme == .dark ? 0.32 : 0.16
        return ZStack {
            LinearGradient(colors: [Color.indigo.opacity(strength), Color.blue.opacity(strength * 0.6),
                                    Color.teal.opacity(strength * 0.5)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            // Soft color glows behind the illustration.
            Circle().fill(Color.pink.opacity(strength)).frame(width: 260).blur(radius: 70)
                .offset(x: 260, y: -90)
            Circle().fill(Color.teal.opacity(strength)).frame(width: 240).blur(radius: 70)
                .offset(x: 340, y: 110)
        }
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
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 20))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Or drop any folder onto this window").font(.headline)
                Text("You can switch folders anytime from the sidebar.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.l, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                .foregroundStyle(Theme.hairline.opacity(2)))
        .accessibilityElement(children: .combine)
    }
}

/// A tinted card like the Library cards: badge, title, text, and an example row.
private struct FeatureCard<Accessory: View>: View {
    let icon: String
    let color: Color
    let title: String
    let detail: String
    @ViewBuilder let accessory: Accessory
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(LinearGradient(colors: [color.opacity(0.85), color],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: color.opacity(0.35), radius: 4, y: 2)
                .accessibilityHidden(true)
            Text(title).font(.system(size: 15, weight: .semibold)).padding(.top, Theme.Spacing.xxs)
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            accessory.padding(.top, Theme.Spacing.xxs)
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
        .background(LinearGradient(colors: [color.opacity(colorScheme == .dark ? 0.24 : 0.12),
                                            color.opacity(colorScheme == .dark ? 0.08 : 0.03)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.l, style: .continuous)
            .strokeBorder(color.opacity(0.18), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.l, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// File-type badges that fly out around a magnifying glass and then float.
private struct WelcomeIllustration: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var floating = false

    private let badges: [(category: String, x: CGFloat, y: CGFloat, angle: Double)] = [
        ("Images", -82, -58, -10), ("Documents", 0, -88, 4), ("Videos", 82, -52, 9),
        ("Music", -90, 40, 7), ("Archives", 88, 46, -8), ("Apps", 2, 88, -4),
    ]

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.accentColor.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [4, 6]))
                .frame(width: 176, height: 176)
            ForEach(Array(badges.enumerated()), id: \.offset) { index, badge in
                let color = Theme.color(for: badge.category)
                Image(systemName: Theme.icon(for: badge.category))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(LinearGradient(colors: [color.opacity(0.8), color],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .shadow(color: color.opacity(0.4), radius: 8, y: 4)
                    .rotationEffect(.degrees(badge.angle))
                    .offset(x: appeared ? badge.x : 0,
                            y: (appeared ? badge.y : 0) + (floating ? (index.isMultiple(of: 2) ? -5 : 5) : 0))
                    .scaleEffect(appeared ? 1 : 0.3)
                    .opacity(appeared ? 1 : 0)
                    .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(Double(index) * 0.06), value: appeared)
                    .animation(.easeInOut(duration: 2.2 + Double(index) * 0.25).repeatForever(autoreverses: true),
                               value: floating)
            }
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 82, height: 82)
                .background(LinearGradient(colors: [Color.accentColor.opacity(0.75), .accentColor, .indigo],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: Circle())
                .shadow(color: Color.accentColor.opacity(0.45), radius: 14, y: 6)
                .scaleEffect(appeared ? 1 : 0.6)
                .animation(.spring(response: 0.5, dampingFraction: 0.6), value: appeared)
        }
        .accessibilityHidden(true)
        .onAppear {
            if reduceMotion {
                var instant = Transaction()
                instant.disablesAnimations = true
                withTransaction(instant) { appeared = true }
            } else {
                appeared = true
                floating = true
            }
        }
    }
}
