import Foundation
import AVFoundation
import MetalKit

public final class MetalSubtitleRenderer {
    private let device: MTLDevice = MTLCreateSystemDefaultDevice()!
    private let queue: MTLCommandQueue
    private let library: MTLLibrary
    init() throws {
        queue = device.makeCommandQueue()!
        library = try device.makeDefaultLibrary(bundle: .main)
    }

    func burn(segments: [CaptionSegment],
              on asset: AVAsset,
              style: SubtitleStyle,
              progress: ((Double)->Void)?) async throws -> AVAsset
    {
        // 1. Atlas + composition
        let atlas = try GlyphAtlas(fontName: style.fontName,
                                   size: style.fontSize,
                                   device: device)

        let comp = AVMutableComposition()
        let vTrackSrc = try await asset.firstTrack(mediaType: .video)
        let timeRange = CMTimeRange(start: .zero, duration: asset.duration)
        
        let transform = vTrackSrc.preferredTransform

        // Video
        let vTrackDst = comp.addMutableTrack(withMediaType: .video,
                                             preferredTrackID: kCMPersistentTrackID_Invalid)!
        try vTrackDst.insertTimeRange(timeRange, of: vTrackSrc, at: .zero)
        
        vTrackDst.preferredTransform = transform

        // Audio
        if let aTrackSrc = try? await asset.firstTrack(mediaType: .audio) {
            let aTrackDst = comp.addMutableTrack(withMediaType: .audio,
                                                 preferredTrackID: kCMPersistentTrackID_Invalid)!
            try aTrackDst.insertTimeRange(timeRange, of: aTrackSrc, at: .zero)
        }

        // 2. Videcomposer
        let layerInstr = AVMutableVideoCompositionLayerInstruction(assetTrack: vTrackDst)
        layerInstr.setTransform(transform, at: .zero)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange        = timeRange
        instruction.layerInstructions = [layerInstr]

        let videoComp = AVMutableVideoComposition()
        videoComp.instructions            = [instruction]
        videoComp.frameDuration           = CMTime(value: 1, timescale: 30)
        let natural = vTrackSrc.naturalSize
        let isPortrait = abs(transform.b) == 1 || abs(transform.c) == 1
        videoComp.renderSize = isPortrait
            ? CGSize(width: natural.height, height: natural.width)
            : natural
        videoComp.customVideoCompositorClass = SubtitleCompositor.self

        SubtitleCompositor.configure(device: device,
                                     queue: queue,
                                     library: library,
                                     atlas: atlas,
                                     style: style,
                                     segments: segments,
                                     transform: transform)

        // 3. Export
        let exp = AVAssetExportSession(asset: comp,
                                       presetName: AVAssetExportPresetHighestQuality)!
        exp.videoComposition = videoComp
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")
        exp.outputURL = url
        exp.outputFileType = .mov

        await withCheckedContinuation { cont in
            exp.exportAsynchronously { cont.resume() }
            Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { t in
                progress?(Double(exp.progress))
                if exp.status != .exporting { t.invalidate() }
            }
        }
        if exp.status == .failed { throw exp.error! }

        return AVAsset(url: url)
    }
}
