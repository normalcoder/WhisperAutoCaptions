import AVFoundation

extension AVAsset {
    func firstTrack(mediaType: AVMediaType) async throws -> AVAssetTrack {
        if #available(iOS 16, macOS 13, *) {
            let tracks = try await loadTracks(withMediaType: mediaType)
            guard let t = tracks.first else { throw NSError(domain: "NoTrack", code: -1) }
            return t
        } else {
            let tracks = self.tracks(withMediaType: mediaType)
            guard let t = tracks.first else { throw NSError(domain: "NoTrack", code: -1) }
            return t
        }
    }
}
