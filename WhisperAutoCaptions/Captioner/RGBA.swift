import Foundation
import CoreGraphics
import simd

public struct RGBA: Codable {
    public var r: Float, g: Float, b: Float, a: Float
    public init(r: Float = 1, g: Float = 1, b: Float = 1, a: Float = 1) {
        (self.r, self.g, self.b, self.a) = (r, g, b, a)
    }
    public var vec: simd_float4 { simd_float4(r, g, b, a) }
    public var cg: CGColor { CGColor(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: CGFloat(a)) }
}
