import Foundation
import SwiftUI
import AVFoundation
import Combine

@MainActor
class WhisperState: NSObject, ObservableObject {
    @Published var isModelLoaded = false

    private var whisperContext: WhisperContext?
    private var recordedFile: URL? = nil
    private var audioPlayer: AVAudioPlayer?
    
    private enum LoadError: Error {
        case couldNotLocateModel
    }
    
    override init() {
        super.init()
        loadModel()
    }
    
    func loadModel(path: URL? = nil, log: Bool = true) {
        do {
            let localModelUrl = Bundle.main.url(forResource: "ggml-tiny.en", withExtension: "bin")!
            whisperContext = try WhisperContext.createContext(path: localModelUrl.path())
        } catch {
            print(error.localizedDescription)
        }
    }

    private func transcribeAudio(_ url: URL) async -> [(Int64, Int64, String)] {
        guard let whisperContext else { return [] }
        
        do {
            let data = try readAudioSamples(url)
            await whisperContext.fullTranscribe(samples: data)
            let transcription = await whisperContext.getTranscription()
            return transcription
        } catch {
            print(error.localizedDescription)
            return []
        }
    }
    
    private func readAudioSamples(_ url: URL) throws -> [Float] {
        try decodeWaveFile(url)
    }
    
    func transcribeVideo(url: URL) async -> [(Int64, Int64, String)] {
        let tempFile = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("wav")
        
        try! extractAudio(from: url, to: tempFile)
        return await transcribeAudio(tempFile)
    }
    
    private func requestRecordPermission(response: @escaping (Bool) -> Void) {
#if os(macOS)
        response(true)
#else
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            response(granted)
        }
#endif
    }
    
    private func startPlayback(_ url: URL) throws {
        audioPlayer = try AVAudioPlayer(contentsOf: url)
        audioPlayer?.play()
    }
    
    private func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
    }
}


fileprivate func cpuCount() -> Int {
    ProcessInfo.processInfo.processorCount
}
