// MannequinRotation.swift
//
// **MannequinRotation**
// The drag-to-rotate arithmetic, kept out of the view so it can be tested.
//
// **Why this is not just inline in the gesture:**
// A `@State` write on a View that is not installed in a hierarchy goes nowhere,
// so a test that drives the gesture closure directly passes vacuously. The
// decision lives here, where it is a plain function over plain numbers.
//
// **Why rotation accumulates:**
// A DragGesture reports translation from the start of *that* drag, so assigning
// it straight to the angle snapped the body back to front-facing every time a
// new drag began — which reads as "it does not rotate" rather than as a reset.
//
import Foundation

nonisolated enum MannequinRotation {
    /// Radians per point of horizontal travel. 90 pt gives one radian, so a
    /// swipe across a phone turns the body a little over half a turn.
    static let radiansPerPoint = 1.0 / 90

    /// The live angle during a drag: what was committed, plus this drag so far.
    static func angle(committed: Double, dragWidth: Double) -> Double {
        committed + dragWidth * radiansPerPoint
    }

    /// Keeps the committed angle inside one turn so it cannot drift unbounded
    /// across a long session.
    static func normalised(_ angle: Double) -> Double {
        let turn = 2 * Double.pi
        let wrapped = angle.truncatingRemainder(dividingBy: turn)
        return wrapped < 0 ? wrapped + turn : wrapped
    }
}
