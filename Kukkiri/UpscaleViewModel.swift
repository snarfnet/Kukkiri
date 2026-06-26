import SwiftUI
import PhotosUI

/// 出力サイズのプリセット。入力長辺の上限で実質の出力解像度（×4）が決まる。
enum OutputMode: String, CaseIterable, Identifiable {
    case tshirt
    case print

    var id: String { rawValue }
    var title: String { self == .tshirt ? "Tシャツ用" : "印刷用" }
    var note: String { self == .tshirt ? "最大4096px・軽快" : "最大6144px・高精細" }
    var icon: String { self == .tshirt ? "tshirt" : "printer" }

    /// 入力長辺の上限。これ×4が出力長辺の上限になる。
    /// tshirt: 1024×4=4096px(~50MB) / print: 1536×4=6144px(~113MB)
    var maxInputLongSide: CGFloat { self == .tshirt ? 1024 : 1536 }
}

@MainActor
final class UpscaleViewModel: ObservableObject {
    @Published var original: UIImage?
    @Published var result: UIImage?
    @Published var isProcessing = false
    @Published var progress: Double = 0
    @Published var errorText: String?
    @Published var didSave = false
    @Published var shareURL: URL?
    @Published var outputMode: OutputMode = .tshirt

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

        let input = downscaleIfNeeded(original)

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                let engine = try self.makeEngine()
                let out = try engine.upscale(input) { p in
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

    /// 長辺が上限を超える場合のみ Lanczos 相当の高品質縮小を行う。上限は出力モードで決まる。
    private func downscaleIfNeeded(_ image: UIImage) -> UIImage {
        let cap = outputMode.maxInputLongSide
        let longSide = max(image.size.width, image.size.height)
        guard longSide > cap else { return image }
        let ratio = cap / longSide
        let newSize = CGSize(width: floor(image.size.width * ratio),
                             height: floor(image.size.height * ratio))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    private func writeTemp(_ img: UIImage) -> URL? {
        guard let data = img.jpegData(compressionQuality: 0.95) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Kukkiri.jpg")
        try? data.write(to: url, options: .atomic)
        return url
    }
}
