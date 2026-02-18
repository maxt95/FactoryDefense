import Combine
import Foundation
import os

/// Continuous input state for FPS movement.
/// Mouse delta uses os_unfair_lock for thread-safe cross-thread accumulation.
@MainActor
public final class FPSInputState: ObservableObject {
    // Movement keys
    public var moveForward: Bool = false
    public var moveBack: Bool = false
    public var moveLeft: Bool = false
    public var moveRight: Bool = false

    // Action keys
    public var sprintHeld: Bool = false
    public var jumpPressed: Bool = false
    public var crouchHeld: Bool = false

    // Thread-safe mouse delta (accumulated from NSView events, consumed on main thread)
    private let lock = OSAllocatedUnfairLock(initialState: (dx: Float(0), dy: Float(0)))

    public init() {}

    /// Called from NSView mouse event handlers (may be on any thread).
    public nonisolated func accumulateMouseDelta(dx: Float, dy: Float) {
        lock.withLock { state in
            state.dx += dx
            state.dy += dy
        }
    }

    /// Called on main thread each frame to consume accumulated delta.
    public func consumeMouseDelta() -> (dx: Float, dy: Float) {
        lock.withLock { state in
            let result = (dx: state.dx, dy: state.dy)
            state.dx = 0
            state.dy = 0
            return result
        }
    }

    /// Consume the jump pressed flag (resets after read — edge-triggered).
    public func consumeJump() -> Bool {
        let wasPressed = jumpPressed
        jumpPressed = false
        return wasPressed
    }

    public var forwardAxis: Float {
        var axis: Float = 0
        if moveForward { axis += 1 }
        if moveBack { axis -= 1 }
        return axis
    }

    public var strafeAxis: Float {
        var axis: Float = 0
        if moveRight { axis += 1 }
        if moveLeft { axis -= 1 }
        return axis
    }

    /// True if any movement key is held.
    public var isMoving: Bool {
        moveForward || moveBack || moveLeft || moveRight
    }

    public func reset() {
        moveForward = false
        moveBack = false
        moveLeft = false
        moveRight = false
        sprintHeld = false
        jumpPressed = false
        crouchHeld = false
        _ = consumeMouseDelta()
    }
}
