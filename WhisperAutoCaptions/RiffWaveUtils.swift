import Foundation
import AVFoundation

func decodeWaveFile(_ url: URL) throws -> [Float] {
    let data = try Data(contentsOf: url)
    let floats = stride(from: 44, to: data.count, by: 2).map {
        return data[$0..<$0 + 2].withUnsafeBytes {
            let short = Int16(littleEndian: $0.load(as: Int16.self))
            return max(-1.0, min(Float(short) / 32767.0, 1.0))
        }
    }
    return floats
}

func extractAudio(from movURL: URL, to wavURL: URL) throws {
    guard FileManager.default.fileExists(atPath: movURL.path) else {
        throw NSError(domain: "File not found", code: 404)
    }
    
    let asset = AVAsset(url: movURL)
    guard let audioTrack = asset.tracks(withMediaType: .audio).first else {
        throw NSError(domain: "No audio track found", code: 400)
    }
    
    let formatDescriptions = audioTrack.formatDescriptions
    guard let firstFormatDescription = formatDescriptions.first,
          let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(firstFormatDescription as! CMAudioFormatDescription) else {
        throw NSError(domain: "Audio format error", code: 500)
    }
    
    let sampleRate = asbd.pointee.mSampleRate
    let channelCount = asbd.pointee.mChannelsPerFrame
    
    let outputSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: 16000.0, // fixed sample rate for Whisper
        AVNumberOfChannelsKey: 1, // mono
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsNonInterleaved: false
    ]
    
    let reader = try AVAssetReader(asset: asset)
    let readerOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
    reader.add(readerOutput)
    
    let writer = try AVAssetWriter(outputURL: wavURL, fileType: .wav)
    let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: outputSettings)
    writer.add(writerInput)
    
    reader.startReading()
    writer.startWriting()
    writer.startSession(atSourceTime: CMTime.zero)
    
    let queue = DispatchQueue(label: "audio.extraction.queue")
    let group = DispatchGroup()
    group.enter()
    
    writerInput.requestMediaDataWhenReady(on: queue) {
        while writerInput.isReadyForMoreMediaData {
            if let sampleBuffer = readerOutput.copyNextSampleBuffer() {
                writerInput.append(sampleBuffer)
            } else {
                writerInput.markAsFinished()
                writer.finishWriting {
                    group.leave()
                }
                break
            }
        }
    }
    
    group.wait()
    
    if let error = reader.error {
        throw error
    }
    if let error = writer.error {
        throw error
    }
}
