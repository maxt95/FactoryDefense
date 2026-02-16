import Foundation
import simd

public struct PackedWhiteboxVertex {
    public var px: Float
    public var py: Float
    public var pz: Float
    public var nx: UInt16
    public var ny: UInt16
    public var nz: UInt16
    public var _pad: UInt16 = 0

    public init(position: SIMD3<Float>, normal: SIMD3<Float>) {
        self.px = position.x
        self.py = position.y
        self.pz = position.z
        self.nx = packHalf(normal.x)
        self.ny = packHalf(normal.y)
        self.nz = packHalf(normal.z)
    }

    public var position: SIMD3<Float> {
        SIMD3<Float>(px, py, pz)
    }

    public var normal: SIMD3<Float> {
        SIMD3<Float>(unpackHalf(nx), unpackHalf(ny), unpackHalf(nz))
    }
}

public struct WhiteboxPrimitiveMesh {
    public var vertices: [PackedWhiteboxVertex]
    public var indices: [UInt16]

    public init(vertices: [PackedWhiteboxVertex], indices: [UInt16]) {
        self.vertices = vertices
        self.indices = indices
    }
}

@inline(__always)
func packHalf(_ value: Float) -> UInt16 {
    Float16(value).bitPattern
}

@inline(__always)
func unpackHalf(_ value: UInt16) -> Float {
    Float(Float16(bitPattern: value))
}
