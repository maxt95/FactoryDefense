import Foundation

/// Client-side prediction for smooth 60 fps FPS movement.
/// Runs at render frame rate, accumulates input, and reconciles with the
/// authoritative 20 Hz simulation each tick.
///
/// Handles: horizontal movement with acceleration, vertical jump/gravity,
/// sprint and crouch speed modifiers, and head bob.
@MainActor
public final class FPSClientPredictor {
    // Predicted position
    public private(set) var predictedX: Float
    public private(set) var predictedZ: Float
    public private(set) var predictedY: Float
    public private(set) var predictedYaw: Float
    public private(set) var predictedPitch: Float

    // Vertical physics
    public private(set) var velocityY: Float = 0
    public private(set) var isGrounded: Bool = true

    // Movement state for head bob
    public private(set) var horizontalSpeed: Float = 0
    public private(set) var distanceTraveled: Float = 0

    // Sprint/crouch state
    public private(set) var isSprinting: Bool = false
    public private(set) var isCrouching: Bool = false

    // Accumulated command delta for sim tick
    private var accumulatedDx: Float = 0
    private var accumulatedDz: Float = 0
    private var wantsJump: Bool = false
    private var wantsSprint: Bool = false
    private var wantsCrouch: Bool = false

    public init(initialX: Float = 0, initialZ: Float = 0, initialY: Float = 0,
                yaw: Float = 0, pitch: Float = 0) {
        self.predictedX = initialX
        self.predictedZ = initialZ
        self.predictedY = initialY
        self.predictedYaw = yaw
        self.predictedPitch = pitch
    }

    /// Called every render frame (~60 fps). Applies predicted movement with full physics.
    public func applyInput(
        forward: Float,
        strafe: Float,
        facing: Float,
        pitch: Float,
        jump: Bool,
        sprint: Bool,
        crouch: Bool,
        deltaTime: Float,
        moveSpeed: Float,
        sprintSpeed: Float,
        crouchSpeed: Float
    ) {
        predictedYaw = facing
        predictedPitch = max(-.pi / 2 * 0.95, min(.pi / 2 * 0.95, pitch))
        isSprinting = sprint && !crouch
        isCrouching = crouch

        // Determine effective speed
        let effectiveSpeed: Float
        if crouch {
            effectiveSpeed = crouchSpeed
        } else if sprint && (forward > 0) {
            effectiveSpeed = sprintSpeed
        } else {
            effectiveSpeed = moveSpeed
        }

        // Normalize diagonal movement
        let inputLength = sqrt(forward * forward + strafe * strafe)
        let normalizedForward = inputLength > 0.001 ? forward / inputLength : 0
        let normalizedStrafe = inputLength > 0.001 ? strafe / inputLength : 0

        // World-space horizontal movement
        let sinYaw = sin(facing)
        let cosYaw = cos(facing)
        let dx = (normalizedForward * sinYaw + normalizedStrafe * cosYaw) * effectiveSpeed * deltaTime
        let dz = (-normalizedForward * cosYaw + normalizedStrafe * sinYaw) * effectiveSpeed * deltaTime

        predictedX += dx
        predictedZ += dz
        accumulatedDx += dx
        accumulatedDz += dz

        // Track horizontal speed for head bob
        let horizontalDelta = sqrt(dx * dx + dz * dz)
        horizontalSpeed = horizontalDelta / max(deltaTime, 0.0001)
        distanceTraveled += horizontalDelta

        // Gravity / jump
        if jump && isGrounded {
            velocityY = PlayerState.jumpImpulse
            isGrounded = false
            wantsJump = true
        }

        if !isGrounded {
            velocityY += PlayerState.gravity * deltaTime
            velocityY = max(velocityY, PlayerState.terminalVelocity)
            predictedY += velocityY * deltaTime

            if predictedY <= 0 {
                predictedY = 0
                velocityY = 0
                isGrounded = true
            }
        }

        // Accumulate sprint/crouch for command
        if sprint { wantsSprint = true }
        if crouch { wantsCrouch = true }
    }

    /// Called at 20 Hz tick boundaries. Returns the accumulated movement delta
    /// to be sent as a `playerMove` command, then resets the accumulator.
    public func harvestMoveCommand() -> (dx: Float, dz: Float, facing: Float, pitch: Float, jump: Bool, sprint: Bool, crouch: Bool) {
        let result = (
            dx: accumulatedDx,
            dz: accumulatedDz,
            facing: predictedYaw,
            pitch: predictedPitch,
            jump: wantsJump,
            sprint: wantsSprint,
            crouch: wantsCrouch
        )
        accumulatedDx = 0
        accumulatedDz = 0
        wantsJump = false
        wantsSprint = false
        wantsCrouch = false
        return result
    }

    /// Called after sim tick with the authoritative player state.
    /// Snaps if error is large (> 1 cell), otherwise exponential decay toward authority.
    public func reconcile(authorityX: Float, authorityZ: Float, authorityY: Float,
                          authorityVelocityY: Float, authorityGrounded: Bool) {
        let errorX = predictedX - authorityX
        let errorZ = predictedZ - authorityZ
        let errorSq = errorX * errorX + errorZ * errorZ

        if errorSq > 1.0 {
            // Hard snap — large desync
            predictedX = authorityX
            predictedZ = authorityZ
        } else {
            // Smooth blend toward authority
            let blendFactor: Float = 0.8
            predictedX -= errorX * blendFactor
            predictedZ -= errorZ * blendFactor
        }

        // Vertical reconciliation
        let errorY = abs(predictedY - authorityY)
        if errorY > 0.5 {
            predictedY = authorityY
            velocityY = authorityVelocityY
        }
        isGrounded = authorityGrounded
    }

    /// Eye-height position for the FPS camera, including head bob.
    public var eyePosition: SIMD3<Float> {
        let baseEyeHeight = isCrouching ? PlayerState.crouchEyeHeight : PlayerState.eyeHeight

        // Head bob: sinusoidal motion based on distance traveled
        let bobAmount: Float
        if isGrounded && horizontalSpeed > 0.5 {
            let bobFrequency: Float = isSprinting ? 12.0 : 8.0
            let bobMagnitude: Float = isSprinting ? 0.06 : 0.04
            bobAmount = sin(distanceTraveled * bobFrequency) * bobMagnitude
        } else {
            bobAmount = 0
        }

        return SIMD3<Float>(predictedX, predictedY + baseEyeHeight + bobAmount, predictedZ)
    }

    /// Horizontal bob offset for the crosshair (side-to-side sway).
    public var horizontalBob: Float {
        guard isGrounded && horizontalSpeed > 0.5 else { return 0 }
        let bobFrequency: Float = isSprinting ? 6.0 : 4.0
        let bobMagnitude: Float = isSprinting ? 0.03 : 0.02
        return cos(distanceTraveled * bobFrequency) * bobMagnitude
    }
}
