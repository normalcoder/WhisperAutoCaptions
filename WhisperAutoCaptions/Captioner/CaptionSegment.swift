import Foundation
import AVFoundation

public struct CaptionSegment: Identifiable, Codable {
    public let id: UUID
    public var start: CMTime
    public var end: CMTime
    public var text: String
    public init(id: UUID = UUID(), start: CMTime, end: CMTime, text: String) {
        (self.id, self.start, self.end, self.text) = (id, start, end, text)
    }
    enum CodingKeys: String, CodingKey { case id, s, e, t }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(CMTimeGetSeconds(start), forKey: .s)
        try c.encode(CMTimeGetSeconds(end),   forKey: .e)
        try c.encode(text, forKey: .t)
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        let s = try c.decode(Double.self, forKey: .s)
        let e = try c.decode(Double.self, forKey: .e)
        text = try c.decode(String.self, forKey: .t)
        start = CMTime(seconds: s, preferredTimescale: 600)
        end = CMTime(seconds: e, preferredTimescale: 600)
    }
}
