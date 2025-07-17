import Foundation
import AVFoundation

enum AudioReader {
    static func pcmBuffer(from asset: AVAsset) async throws -> AVAudioPCMBuffer {
        let track = try await asset.firstTrack(mediaType: .audio)
        let reader = try AVAssetReader(asset: asset)
        let out = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000,
            AVLinearPCMBitDepthKey: 16,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ])
        reader.add(out)
        reader.startReading()
        let fmt = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!
        let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: 8192 * 400)!
        while reader.status == .reading, let s = out.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(s) else { continue }
            let len = CMBlockBufferGetDataLength(block)
            var tmp = [UInt8](repeating: 0, count: len)
            CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: len, destination: &tmp)
            let frames = UInt32(len / 2)
            memcpy(buf.int16ChannelData![0] + Int(buf.frameLength), tmp, len)
            buf.frameLength += frames
        }
        if reader.status == .failed { throw reader.error! }
        return buf
    }
}
