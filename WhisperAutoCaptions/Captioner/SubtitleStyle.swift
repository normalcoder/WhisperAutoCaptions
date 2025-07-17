import Foundation

public struct SubtitleStyle: Codable {
    public var fontName: String = "Helvetica-Bold"
    public var fontSize: CGFloat = 48
    public var textColor: RGBA = RGBA()
    public var backgroundColor: RGBA = RGBA(r: 0, g: 0, b: 0, a: 0.6)
    public var cornerRadius: CGFloat = 4
    public var animationDuration: TimeInterval = 0.25
    public static let standard = SubtitleStyle()
}
