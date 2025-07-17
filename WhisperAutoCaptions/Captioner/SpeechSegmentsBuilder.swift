import Foundation
import AVFoundation

final class SpeechSegmentsBuilder {
    func buildSegments(asset: AVAsset, transcription: [(Int64, Int64, String)], progress: ((Double) -> Void)?) async throws -> [CaptionSegment] {
        var segments: [CaptionSegment] = []
        
        let pcm = try await AudioReader.pcmBuffer(from: asset)
        
        let sampleCount = pcm.frameLength
        let sampleRate = pcm.format.sampleRate
        let totalDuration = Double(sampleCount*1000) / sampleRate

        for (rawStartMs, rawEndMs, text) in transcription {
            let startFrame = AVAudioFramePosition(Double(pcm.frameLength) * Double(rawStartMs) / totalDuration)
            let endFrame = AVAudioFramePosition(Double(pcm.frameLength) * Double(rawEndMs) / totalDuration)

            let start = CMTime(value: CMTimeValue(startFrame), timescale: 16_000)
            let end = CMTime(value: CMTimeValue(endFrame), timescale: 16_000)
            segments.append(CaptionSegment(start: start, end: end, text: text))
        }

        return segments
    }
}
