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

/// 被写体の種類。写真とイラスト・ロゴで最適なモデルを切り替える。
enum SubjectMode: String, CaseIterable, Identifiable {
    case photo
    case illust

    var id: String { rawValue }
    var title: String { self == .photo ? "写真" : "イラスト・ロゴ" }
    var note: String { self == .photo ? "人物・風景に" : "絵・ロゴ・アニメに" }
    var icon: String { self == .photo ? "person.crop.square" : "paintbrush.pointed" }
    var modelName: String { self == .photo ? "realesrgan4x" : "realesrgan_anime4x" }
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
    @Published var subjectMode: SubjectMode = .photo

    @Published var isBatchProcessing = false
    @Published var batchTotal = 0
    @Published var batchDone = 0
    @Published var batchSaved = 0
    @Published var batchFinished = false

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
        let modelName = subjectMode.modelName

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                let engine = try self.makeEngine(modelName: modelName)
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

    private nonisolated func makeEngine(modelName: String) throws -> UpscaleEngine {
        try UpscaleEngine(modelName: modelName)
    }

    /// 長辺が上限を超える場合のみ Lanczos 相当の高品質縮小を行う。上限は出力モードで決まる。
    private func downscaleIfNeeded(_ image: UIImage) -> UIImage {
        Self.downscale(image, cap: outputMode.maxInputLongSide)
    }

    nonisolated private static func downscale(_ image: UIImage, cap: CGFloat) -> UIImage {
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

    /// 複数枚をまとめてアップスケールし、各結果を写真ライブラリに保存する。
    func runBatch(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        isBatchProcessing = true
        batchTotal = items.count
        batchDone = 0
        batchSaved = 0
        batchFinished = false
        errorText = nil
        let modelName = subjectMode.modelName
        let cap = outputMode.maxInputLongSide

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                let engine = try self.makeEngine(modelName: modelName)
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let img = UIImage(data: data) {
                        let input = Self.downscale(img, cap: cap)
                        if let out = try? engine.upscale(input, progress: { _ in }) {
                            await MainActor.run {
                                UIImageWriteToSavedPhotosAlbum(out, nil, nil, nil)
                                self.batchSaved += 1
                            }
                        }
                    }
                    await MainActor.run { self.batchDone += 1 }
                }
                await MainActor.run {
                    self.isBatchProcessing = false
                    self.batchFinished = true
                }
            } catch {
                await MainActor.run {
                    self.errorText = "一括処理に失敗しました"
                    self.isBatchProcessing = false
                }
            }
        }
    }

    private func writeTemp(_ img: UIImage) -> URL? {
        guard let data = img.jpegData(compressionQuality: 0.95) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Kukkiri.jpg")
        try? data.write(to: url, options: .atomic)
        return url
    }
}
