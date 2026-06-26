import SwiftUI
import PhotosUI

@MainActor
final class UpscaleViewModel: ObservableObject {
    @Published var original: UIImage?
    @Published var result: UIImage?
    @Published var isProcessing = false
    @Published var progress: Double = 0
    @Published var errorText: String?
    @Published var didSave = false
    @Published var shareURL: URL?

    private var engine: UpscaleEngine?

    func load(_ item: PhotosPickerItem) async {
        errorText = nil
        result = nil
        shareURL = nil
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let img = UIImage(data: data) else { return }
            original = img
        } catch {
            errorText = "画像を読み込めませんでした"
        }
    }

    func run() {
        guard let original else { return }
        isProcessing = true
        progress = 0
        errorText = nil

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                let engine = try self.makeEngine()
                let out = try engine.upscale(original) { p in
                    Task { @MainActor in self.progress = p }
                }
                await MainActor.run {
                    self.result = out
                    self.shareURL = self.writeTemp(out)
                    self.isProcessing = false
                }
            } catch {
                await MainActor.run {
                    self.errorText = "処理に失敗しました"
                    self.isProcessing = false
                }
            }
        }
    }

    func save() {
        guard let result else { return }
        UIImageWriteToSavedPhotosAlbum(result, nil, nil, nil)
        didSave = true
    }

    private nonisolated func makeEngine() throws -> UpscaleEngine {
        try UpscaleEngine()
    }

    private func writeTemp(_ img: UIImage) -> URL? {
        guard let data = img.jpegData(compressionQuality: 0.95) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Kukkiri.jpg")
        try? data.write(to: url, options: .atomic)
        return url
    }
}
