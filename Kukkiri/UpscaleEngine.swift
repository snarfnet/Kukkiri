import CoreML
import CoreImage
import UIKit
import VideoToolbox

/// Real-ESRGAN x4 を使ったオンデバイス超解像エンジン。
/// モデルは 512x512 → 2048x2048 固定なので、大きい画像はタイルに分割して処理し、
/// 各タイルにマージン（のりしろ）を持たせて継ぎ目を消す。
final class UpscaleEngine {
    enum EngineError: Error { case modelMissing, badImage, inference }

    let scale = 4
    private let tile = 512          // モデル入力サイズ
    private let margin = 32         // タイル境界の捨て幅（入力px）
    private let model: MLModel
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    init(modelName: String = "realesrgan4x") throws {
        let cfg = MLModelConfiguration()
        cfg.computeUnits = .all     // Neural Engine 優先
        guard let url = Bundle.main.url(forResource: modelName, withExtension: "mlmodelc") else {
            throw EngineError.modelMissing
        }
        model = try MLModel(contentsOf: url, configuration: cfg)
    }

    /// progress: 0.0...1.0 をメインスレッドで通知
    func upscale(_ image: UIImage, progress: @escaping (Double) -> Void) throws -> UIImage {
        guard let cg = image.normalizedCGImage() else { throw EngineError.badImage }
        let W = cg.width, H = cg.height

        // 出力キャンバス
        let outW = W * scale, outH = H * scale
        guard let outCtx = CGContext(
            data: nil, width: outW, height: outH, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw EngineError.inference }

        let core = tile - 2 * margin                 // 1タイルが寄与する有効領域（入力px）
        let xs = stride(from: 0, to: max(W, 1), by: core).map { $0 }
        let ys = stride(from: 0, to: max(H, 1), by: core).map { $0 }
        let total = Double(xs.count * ys.count)
        var done = 0.0

        for ty in ys {
            for tx in xs {
                // 有効領域 [tx, tx+core) x [ty, ty+core)
                let coreW = min(core, W - tx)
                let coreH = min(core, H - ty)
                if coreW <= 0 || coreH <= 0 { continue }

                // モデルへ渡す 512 ウィンドウ（画像内に収まるようクランプ）
                var winX = tx - margin
                var winY = ty - margin
                winX = min(max(winX, 0), max(W - tile, 0))
                winY = min(max(winY, 0), max(H - tile, 0))

                let tileBuf = try makeTilePixelBuffer(from: cg, originX: winX, originY: winY, imgW: W, imgH: H)
                let outBuf = try runModel(tileBuf)
                guard let outCG = cgImage(from: outBuf) else { throw EngineError.inference }

                // 有効領域のウィンドウ内オフセット（入力px）→出力px
                let offX = (tx - winX) * scale
                let offY = (ty - winY) * scale
                let dstW = coreW * scale
                let dstH = coreH * scale

                guard let piece = outCG.cropping(to: CGRect(x: offX, y: offY, width: dstW, height: dstH)) else { continue }
                // CoreGraphics は左下原点なので Y を反転して配置
                let drawY = outH - (ty * scale) - dstH
                outCtx.draw(piece, in: CGRect(x: tx * scale, y: drawY, width: dstW, height: dstH))

                done += 1
                let p = done / total
                DispatchQueue.main.async { progress(p) }
            }
        }

        guard let result = outCtx.makeImage() else { throw EngineError.inference }
        return UIImage(cgImage: result, scale: 1, orientation: .up)
    }

    // MARK: - Core ML

    private func runModel(_ input: CVPixelBuffer) throws -> CVPixelBuffer {
        let fv = try MLDictionaryFeatureProvider(dictionary: ["input": MLFeatureValue(pixelBuffer: input)])
        let out = try model.prediction(from: fv)
        guard let buf = out.featureValue(for: "activation_out")?.imageBufferValue else {
            throw EngineError.inference
        }
        return buf
    }

    // MARK: - Pixel buffer helpers

    /// 512x512 のタイルを画像から切り出して BGRA PixelBuffer を作る。
    /// 画像端で 512 に満たない部分はエッジを複製してパディング。
    private func makeTilePixelBuffer(from cg: CGImage, originX: Int, originY: Int, imgW: Int, imgH: Int) throws -> CVPixelBuffer {
        var pb: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        CVPixelBufferCreate(kCFAllocatorDefault, tile, tile, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pb)
        guard let buffer = pb else { throw EngineError.inference }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { throw EngineError.inference }
        let ctx = CGContext(
            data: base, width: tile, height: tile, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )
        guard let context = ctx else { throw EngineError.inference }

        // 実際に画像から取れる領域
        let availW = min(tile, imgW - originX)
        let availH = min(tile, imgH - originY)
        if let sub = cg.cropping(to: CGRect(x: originX, y: originY, width: availW, height: availH)) {
            // Y 反転配置（左下原点）
            let drawY = tile - availH
            context.draw(sub, in: CGRect(x: 0, y: drawY, width: availW, height: availH))
            // 右端・下端のパディングはエッジ列/行を引き伸ばして埋める
            if availW < tile, let edgeCol = sub.cropping(to: CGRect(x: availW - 1, y: 0, width: 1, height: availH)) {
                context.draw(edgeCol, in: CGRect(x: availW, y: drawY, width: tile - availW, height: availH))
            }
            if availH < tile {
                if let row = context.makeImage()?.cropping(to: CGRect(x: 0, y: drawY, width: tile, height: 1)) {
                    context.draw(row, in: CGRect(x: 0, y: 0, width: tile, height: tile - availH))
                }
            }
        }
        return buffer
    }

    private func cgImage(from buffer: CVPixelBuffer) -> CGImage? {
        var cg: CGImage?
        VTCreateCGImageFromCVPixelBuffer(buffer, options: nil, imageOut: &cg)
        return cg
    }
}

extension UIImage {
    /// EXIF 回転を反映し、RGBA の CGImage に正規化する。
    func normalizedCGImage() -> CGImage? {
        if imageOrientation == .up, let cg = cgImage { return cg }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let img = renderer.image { _ in draw(in: CGRect(origin: .zero, size: size)) }
        return img.cgImage
    }
}
