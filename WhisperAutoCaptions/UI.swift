import SwiftUI
import AVKit
import PhotosUI

struct Video {
    var originalURL: URL
    var processedURL: URL?
    
    var progress: Double? = nil
    
    var url: URL {
        processedURL ?? originalURL
    }
}

struct VideoState {
    var videos: [Video]
    var selectedIndex: Int = 0
    
    var selectionStamp = UUID()
    
    var selectedURL: URL {
        videos[selectedIndex].url
    }
}

let initialVideoState = VideoState(videos: ["feynman", "universe"].map {
    Video(originalURL: Bundle.main.url(forResource: $0, withExtension: "mp4")!)
})

struct CaptioningDemoView: View {
    @State private var videoState = initialVideoState
    
    @State private var label: String = ""
    @State private var prog: Double = 0
    
    @State private var player = AVPlayer(url: initialVideoState.selectedURL)
    
    @State private var showGrid = false
    @StateObject var whisperState = WhisperState()
    
    var body: some View {
        ZStack {
            VideoPlayer(player: player)
                .aspectRatio(9/19.5, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
                .onChange(of: videoState.selectionStamp) { _ in
                    player.pause()
                    player = AVPlayer(url: videoState.selectedURL)
                    player.play()
                }
            
            VStack(spacing: 12) {
                Button {
                    showGrid = true
                } label: {
                    Image(systemName: "square.grid.2x2")
                        .padding(16)
                }
            }
            .padding(.bottom, 24)
            .padding(.trailing, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity,
                   alignment: .bottomTrailing)
        }
        .background(Color.black)
        .sheet(isPresented: $showGrid) {
            NavigationStack {
                VideoGridView(
                    videoState: $videoState,
                    onProcess: { idx in
                        processVideo(at: idx)
                    }
                )
                .navigationTitle("Библиотека")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Close") { showGrid = false }
                    }
                }
            }
        }
    }
    
    private func processVideo(at index: Int) {
        Task {
            await MainActor.run { videoState.videos[index].progress = 0 }

            let originalUrl = videoState.videos[index].url
            let transciption = await whisperState.transcribeVideo(url: originalUrl)
            let url = try await run(url: originalUrl, transciption: transciption) { p in
                Task {
                    await MainActor.run { videoState.videos[index].progress = p }
                }
            }
            await MainActor.run {
                videoState.videos[index].processedURL = url
                videoState.videos[index].progress = nil
                
                if videoState.selectedIndex == index {
                    player.pause()
                    player = AVPlayer(url: url)
                }
            }
        }
    }
    
    private func run(
        url: URL,
        transciption: [(Int64, Int64, String)],
        progress: @escaping (Double) -> Void
    ) async throws -> URL {
        let asset = AVAsset(url: url)
        let pipeline = CaptioningPipeline(
            transcription: transciption,
            align: SimpleAligner(),
            render: try MetalSubtitleRenderer(),
            export: BasicExporter()
        )

        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")

        let out = try await pipeline.process(asset: asset, dest: dest) { lbl, p in
            withAnimation(.easeInOut(duration: 0.3)) {
                progress(p)
            }
        }
        return out
    }
}


struct VideoGridView: View {
    @Binding var videoState: VideoState
    var onProcess: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    
    @State private var pickedItem: PhotosPickerItem?
    @State private var isImporting = false
    
    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(videoState.videos.indices, id: \.self) { idx in
                    VideoCell(
                        video: videoState.videos[idx],
                        isSelected: idx == videoState.selectedIndex,
                        onSelect: {
                            videoState.selectedIndex = idx
                            videoState.selectionStamp = UUID()
                            dismiss()
                        },
                        onProcess: {
                            onProcess(idx)
                        }
                    )
                }
            }
            .padding()
        }
        .navigationTitle("Library")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                PhotosPicker(selection: $pickedItem,
                             matching: .videos,
                             photoLibrary: .shared()) {
                    Label("Add", systemImage: "plus")
                }
            }
        }
        .onChange(of: pickedItem) { newItem in
            guard let item = newItem else { return }
            Task {
                defer { pickedItem = nil }
                do {
                    if let tmpURL = try await item.loadTransferable(type: URL.self) {
                        try await importVideo(from: tmpURL)
                        return
                    }

                    guard let data = try await item.loadTransferable(type: Data.self) else { return }
                    let dst = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension("mov")
                    try data.write(to: dst, options: .atomic)
                    try await importVideo(from: dst)
                } catch {
                    print("Import error:", error)
                }
            }
        }
    }
    
    @MainActor
    private func importVideo(from src: URL) async throws {
        let dst = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(src.pathExtension)
        try FileManager.default.copyItem(at: src, to: dst)

        videoState.videos.append(Video(originalURL: dst))
        videoState.selectedIndex = videoState.videos.count - 1
    }
}

struct VideoImportSheet: UIViewControllerRepresentable {
    var onPick: (URL?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.movie])
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL?) -> Void
        init(onPick: @escaping (URL?) -> Void) { self.onPick = onPick }
        func documentPicker(_ controller: UIDocumentPickerViewController,
                            didPickDocumentsAt urls: [URL]) { onPick(urls.first) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { onPick(nil) }
    }
}

private struct VideoCell: View {
    var video: Video
    var isSelected: Bool
    var onSelect: () -> Void
    var onProcess: () -> Void
    
    @State private var player: AVPlayer?
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            VideoPlayer(player: player)
                .onAppear {
                    reloadPlayer()
                    player?.play()
                    NotificationCenter.default.addObserver(
                        forName: .AVPlayerItemDidPlayToEndTime,
                        object: player?.currentItem,
                        queue: .main
                    ) { _ in
                        player?.seek(to: .zero)
                        player?.play()
                    }
                }
                .allowsHitTesting(false)
                .aspectRatio(9/19.5, contentMode: .fill)
                .frame(height: 268)
                .clipped()
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.blue, lineWidth: 4)
                    }
                }
                .cornerRadius(12)
            
            Text(video.processedURL == nil ? "Original" : "Processed")
                .font(.caption.weight(.bold))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(8)

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button {
                        onProcess()
                    } label: {
                        Image(systemName: "captions.bubble.fill")
                            .font(.title3.weight(.bold))
                            .padding(10)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay {
                                if let p = video.progress {
                                    Circle()
                                        .trim(from: 0, to: p)
                                        .stroke(.blue, lineWidth: 4)
                                        .rotationEffect(.degrees(-90))
                                        .animation(.linear, value: p)
                                }
                            }
                    }
                    .padding(12)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .onChange(of: isSelected) { _ in syncPlayback() }
        .onChange(of: video.url) { newURL in
            player?.pause()
            player = AVPlayer(url: newURL)
            player?.isMuted = true
            player?.play()
        }
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.blue, lineWidth: 4)
            }
        }
    }
    
    
    // MARK: helpers
    private func setupPlayer() {
        reloadPlayer()
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player?.currentItem,
            queue: .main
        ) { _ in player?.seek(to: .zero) }
        syncPlayback()
    }

    private func reloadPlayer() {
        player = AVPlayer(url: video.url)
        player?.isMuted = true
    }

    private func syncPlayback() {
        if isSelected {
            player?.play()
        } else {
            player?.pause()
            player?.seek(to: .zero)
        }
    }
}
