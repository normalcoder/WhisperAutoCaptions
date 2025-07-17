import Foundation
import AVFoundation


public struct SimpleAligner {
    func align(segments: [CaptionSegment], to asset: AVAsset) async throws -> [CaptionSegment] { segments }
}

public actor CaptioningPipeline {
    private let transcription: [(Int64, Int64, String)]
    private let align: SimpleAligner
    private let render: MetalSubtitleRenderer
    private let export: BasicExporter

    public init(transcription: [(Int64, Int64, String)], align: SimpleAligner, render: MetalSubtitleRenderer, export: BasicExporter) {
        self.transcription = transcription
        self.align = align
        self.render = render
        self.export = export
    }

    public func process(asset: AVAsset, style: SubtitleStyle = .standard, dest: URL, progress: ((String,Double) -> Void)? = nil) async throws -> URL {
        let builder = SpeechSegmentsBuilder()
        progress?("ASR",0)
        let raw = try await builder.buildSegments(asset: asset, transcription: transcription) {
            progress?("ASR", $0*0.2)
        }
        progress?("Align",0.25)
        let aligned = try await align.align(segments: raw, to: asset)
        progress?("Render",0.35)
        let burned = try await render.burn(segments: aligned, on: asset, style: style) {
            progress?("Render",0.35+$0*0.45)
        }
        progress?("Export",0.85)
        let url = try await export.export(asset: burned, to: dest, fileType: .mp4) {
            progress?("Export",0.85+$0*0.15)
        }
        progress?("Done",1)
        return url
    }
}
