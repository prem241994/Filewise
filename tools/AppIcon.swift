import AppKit
import SwiftUI

/// Draws the Filewise app icon: file cards fanned behind a magnifying glass on
/// an indigo-blue rounded square, in the macOS icon grid (an 824-point body
/// centered on a 1024-point canvas, leaving room for the shadow).
/// Rendered by scripts/make-icon.sh; not part of the app.
struct AppIconView: View {
    private let body824: CGFloat = 824
    private let radius: CGFloat = 185

    var body: some View {
        ZStack {
            plate
            cards
            magnifier
        }
        .frame(width: 1024, height: 1024)
    }

    // MARK: - Background

    private var plate: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return ZStack {
            shape.fill(LinearGradient(colors: [Color(red: 0.42, green: 0.45, blue: 1.0),
                                               Color(red: 0.25, green: 0.27, blue: 0.86),
                                               Color(red: 0.16, green: 0.15, blue: 0.58)],
                                      startPoint: .top, endPoint: .bottom))
            // Soft glows that echo the welcome page.
            Circle().fill(Color(red: 1.0, green: 0.45, blue: 0.70).opacity(0.45))
                .frame(width: 520).blur(radius: 120).offset(x: 260, y: -250)
            Circle().fill(Color(red: 0.25, green: 0.85, blue: 0.85).opacity(0.35))
                .frame(width: 520).blur(radius: 130).offset(x: -280, y: 300)
            // Top sheen.
            shape.fill(LinearGradient(colors: [.white.opacity(0.22), .clear],
                                      startPoint: .top, endPoint: .center))
            shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.05)],
                                              startPoint: .top, endPoint: .bottom), lineWidth: 3)
        }
        .frame(width: body824, height: body824)
        .clipShape(shape)
        .shadow(color: .black.opacity(0.35), radius: 22, y: 14)
    }

    // MARK: - File cards

    private var cards: some View {
        ZStack {
            card(accent: Color(red: 0.13, green: 0.78, blue: 0.80), symbol: "doc.text.fill")
                .rotationEffect(.degrees(-16)).offset(x: -150, y: -40)
            card(accent: Color(red: 1.0, green: 0.58, blue: 0.20), symbol: "music.note")
                .rotationEffect(.degrees(12)).offset(x: 140, y: -70)
            card(accent: Color(red: 0.98, green: 0.30, blue: 0.48), symbol: "photo.fill")
                .rotationEffect(.degrees(-2)).offset(x: -10, y: -120)
        }
        .offset(y: -10)
    }

    private func card(accent: Color, symbol: String) -> some View {
        let shape = RoundedRectangle(cornerRadius: 34, style: .continuous)
        return VStack(spacing: 0) {
            ZStack {
                accent
                Image(systemName: symbol)
                    .font(.system(size: 64, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(height: 140)
            VStack(alignment: .leading, spacing: 18) {
                Capsule().fill(Color.black.opacity(0.16)).frame(width: 170, height: 18)
                Capsule().fill(Color.black.opacity(0.10)).frame(width: 130, height: 18)
                Capsule().fill(Color.black.opacity(0.10)).frame(width: 150, height: 18)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 30)
            .padding(.top, 30)
            Spacer(minLength: 0)
        }
        .frame(width: 250, height: 320)
        .background(Color.white)
        .clipShape(shape)
        .shadow(color: .black.opacity(0.28), radius: 18, y: 10)
    }

    // MARK: - Magnifying glass

    private var magnifier: some View {
        let lens: CGFloat = 360
        let ring: CGFloat = 46
        return ZStack {
            // Handle, behind the ring, pointing to the lower right.
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.98), Color(white: 0.82)],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(width: 78, height: 230)
                .shadow(color: .black.opacity(0.3), radius: 12, y: 8)
                .offset(y: lens / 2 + 95)
                .rotationEffect(.degrees(-45))
            // Frosted glass: opaque so the lens reads at small sizes.
            Circle()
                .fill(LinearGradient(colors: [Color.white,
                                              Color(red: 0.90, green: 0.91, blue: 1.0)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: lens - ring, height: lens - ring)
            Image(systemName: "sparkle")
                .font(.system(size: 150, weight: .bold))
                .foregroundStyle(LinearGradient(colors: [Color(red: 0.45, green: 0.42, blue: 1.0),
                                                         Color(red: 0.22, green: 0.22, blue: 0.80)],
                                                startPoint: .top, endPoint: .bottom))
            Image(systemName: "sparkle")
                .font(.system(size: 46, weight: .bold))
                .foregroundStyle(Color(red: 1.0, green: 0.45, blue: 0.62))
                .offset(x: 88, y: -78)
            Circle()
                .strokeBorder(LinearGradient(colors: [.white, Color(white: 0.86)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing),
                              lineWidth: ring)
                .frame(width: lens, height: lens)
                .shadow(color: .black.opacity(0.3), radius: 16, y: 10)
        }
        .offset(x: 10, y: 70)
    }
}

@main
@MainActor
struct AppIconRenderer {
    static func main() {
        guard CommandLine.arguments.count == 2 else {
            fputs("usage: render-icon <output.png>\n", stderr)
            exit(2)
        }
        let renderer = ImageRenderer(content: AppIconView())
        renderer.scale = 1
        guard let image = renderer.cgImage else {
            fputs("render failed\n", stderr)
            exit(1)
        }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
        do {
            try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
        } catch {
            fputs("write failed: \(error)\n", stderr)
            exit(1)
        }
    }
}
