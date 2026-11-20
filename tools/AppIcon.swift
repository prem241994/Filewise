import AppKit
import SwiftUI

/// Draws the Filewise app icon: a friendly owl ("wise") wearing round glasses,
/// on an indigo rounded square, in the macOS icon grid (an 824-point body
/// centered on a 1024-point canvas, leaving room for the shadow).
/// Rendered by scripts/make-icon.sh; not part of the app.
struct AppIconView: View {
    var body: some View {
        ZStack {
            plate
            owl.offset(y: 34)
            sparkles
        }
        .frame(width: 1024, height: 1024)
    }

    // MARK: - Palette

    private static func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }
    private let indigo = rgb(0.20, 0.16, 0.58)
    private let feather = LinearGradient(colors: [rgb(1.0, 0.70, 0.30), rgb(0.97, 0.47, 0.20)],
                                         startPoint: .top, endPoint: .bottom)
    private let darkFeather = LinearGradient(colors: [rgb(0.93, 0.48, 0.18), rgb(0.80, 0.33, 0.14)],
                                             startPoint: .top, endPoint: .bottom)
    private let cream = rgb(1.0, 0.90, 0.74)
    private let amber = rgb(0.98, 0.66, 0.16)

    // MARK: - Background

    private var plate: some View {
        let shape = RoundedRectangle(cornerRadius: 185, style: .continuous)
        return ZStack {
            shape.fill(LinearGradient(colors: [Self.rgb(0.42, 0.36, 1.0), Self.rgb(0.28, 0.22, 0.82),
                                               Self.rgb(0.17, 0.13, 0.52)],
                                      startPoint: .top, endPoint: .bottom))
            Circle().fill(Self.rgb(1.0, 0.45, 0.72).opacity(0.40))
                .frame(width: 520).blur(radius: 120).offset(x: 280, y: -280)
            Circle().fill(Self.rgb(0.25, 0.85, 0.90).opacity(0.30))
                .frame(width: 520).blur(radius: 130).offset(x: -300, y: 320)
            shape.fill(LinearGradient(colors: [.white.opacity(0.22), .clear], startPoint: .top, endPoint: .center))
            shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.05)],
                                              startPoint: .top, endPoint: .bottom), lineWidth: 3)
        }
        .frame(width: 824, height: 824)
        .clipShape(shape)
        .shadow(color: .black.opacity(0.35), radius: 22, y: 14)
    }

    // MARK: - Owl

    private var owl: some View {
        ZStack {
            // Ear tufts, angled outward, behind the head.
            ForEach([-1.0, 1.0], id: \.self) { side in
                Tuft()
                    .fill(darkFeather)
                    .frame(width: 120, height: 150)
                    .rotationEffect(.degrees(side * 28))
                    .offset(x: side * 175, y: -238)
            }
            // Body.
            Ellipse()
                .fill(feather)
                .frame(width: 520, height: 580)
                .shadow(color: .black.opacity(0.28), radius: 20, y: 12)
            // Wings.
            ForEach([-1.0, 1.0], id: \.self) { side in
                Ellipse()
                    .fill(darkFeather)
                    .frame(width: 150, height: 300)
                    .rotationEffect(.degrees(side * -14))
                    .offset(x: side * 232, y: 92)
            }
            belly
            face
            feet
        }
    }

    private var belly: some View {
        ZStack {
            Ellipse().fill(cream).frame(width: 300, height: 250)
            // Feather marks: two rows of small arcs.
            ForEach(0..<5, id: \.self) { index in
                let row = index < 3 ? 0 : 1
                let column = row == 0 ? Double(index) - 1 : Double(index - 3) - 0.5
                FeatherMark()
                    .stroke(Self.rgb(0.93, 0.55, 0.25).opacity(0.38), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .frame(width: 56, height: 26)
                    .offset(x: column * 74, y: row == 0 ? -30 : 34)
            }
        }
        .offset(y: 152)
    }

    private var face: some View {
        ZStack {
            // Facial disc: two soft circles that meet in a V between the eyes.
            ForEach([-1.0, 1.0], id: \.self) { side in
                Circle().fill(cream).frame(width: 262, height: 262).offset(x: side * 108, y: -84)
            }
            // Glasses: two lenses and a bridge.
            ForEach([-1.0, 1.0], id: \.self) { side in
                eye(side: side).offset(x: side * 112, y: -86)
            }
            Capsule().fill(indigo).frame(width: 46, height: 20).offset(y: -96)
            // Beak.
            Beak()
                .fill(LinearGradient(colors: [amber, Self.rgb(0.90, 0.48, 0.10)], startPoint: .top, endPoint: .bottom))
                .frame(width: 66, height: 70)
                .offset(y: 20)
        }
    }

    private func eye(side: Double) -> some View {
        ZStack {
            Circle().fill(Color.white).frame(width: 186, height: 186)
            Circle().fill(Self.rgb(0.16, 0.13, 0.38)).frame(width: 86, height: 86).offset(x: side * -12, y: 8)
            Circle().fill(Color.white).frame(width: 28, height: 28).offset(x: side * -26, y: -8)
            Circle().strokeBorder(indigo, lineWidth: 24).frame(width: 212, height: 212)
            // A shine on the frame, upper left.
            Circle()
                .trim(from: 0.56, to: 0.68)
                .stroke(Color.white.opacity(0.75), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .frame(width: 200, height: 200)
        }
    }

    private var feet: some View {
        HStack(spacing: 70) {
            ForEach(0..<2, id: \.self) { _ in
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { _ in
                        Capsule().fill(amber).frame(width: 22, height: 44)
                    }
                }
            }
        }
        .offset(y: 290)
    }

    private var sparkles: some View {
        ZStack {
            Image(systemName: "sparkle")
                .font(.system(size: 82, weight: .bold))
                .foregroundStyle(.white)
                .offset(x: 290, y: 170)
            Image(systemName: "sparkle")
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(.white.opacity(0.85))
                .offset(x: 238, y: 262)
            Image(systemName: "sparkle")
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(.white.opacity(0.7))
                .offset(x: -300, y: -250)
        }
    }
}

/// An ear tuft: a leaf shape with a rounded base and a soft point.
private struct Tuft: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.midX, y: rect.minY))
            p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY),
                           control: CGPoint(x: rect.maxX, y: rect.midY * 0.8))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.minY),
                           control: CGPoint(x: rect.minX, y: rect.midY * 0.8))
        }
    }
}

/// A downward arc, like a feather's edge.
private struct FeatherMark: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.midX, y: rect.maxY * 1.6))
        }
    }
}

/// A small rounded beak pointing down.
private struct Beak: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.15))
            p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.15),
                           control: CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.1))
            p.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.maxY),
                           control: CGPoint(x: rect.maxX * 0.85, y: rect.height * 0.6))
            p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.15),
                           control: CGPoint(x: rect.width * 0.15, y: rect.height * 0.6))
        }
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
