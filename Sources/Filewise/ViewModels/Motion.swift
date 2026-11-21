import AppKit
import SwiftUI

/// The app's shared motion: one gentle spring for state changes, skipped when
/// the user has turned on Reduce Motion.
@MainActor
enum Motion {
    static let spring = Animation.spring(duration: 0.4, bounce: 0.12)

    static var reduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// Runs `changes` inside the app's spring when `animated` is true and
    /// Reduce Motion is off; otherwise applies them immediately.
    static func animate(_ animated: Bool = true, _ changes: () -> Void) {
        if animated && !reduced {
            withAnimation(spring, changes)
        } else {
            changes()
        }
    }
}

extension View {
    /// Animates changes to `value` with the app's spring, or not at all when
    /// Reduce Motion is on.
    func motion<V: Equatable>(_ animation: Animation = Motion.spring, value: V) -> some View {
        modifier(MotionModifier(animation: animation, value: value))
    }
}

private struct MotionModifier<V: Equatable>: ViewModifier {
    let animation: Animation
    let value: V
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}
