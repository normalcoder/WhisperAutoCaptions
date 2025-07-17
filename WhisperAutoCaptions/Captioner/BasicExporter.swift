import Foundation
import AVFoundation

public struct BasicExporter {
    func export(asset: AVAsset, to url: URL, fileType: AVFileType, progress: ((Double)->Void)?) async throws -> URL {
        let exp = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1280x720)!
        exp.outputURL = url
        exp.outputFileType = fileType
        await withCheckedContinuation { c in
            exp.exportAsynchronously { c.resume() }
            Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { t in
                progress?(Double(exp.progress))
                if exp.status != .exporting { t.invalidate() }
            }
        }
        if exp.status == .failed { throw exp.error! }
        return url
    }
}
