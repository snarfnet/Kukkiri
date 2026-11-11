import SwiftUI
import UIKit

struct PrintPlanningView: View {
    let image: UIImage
    let isResult: Bool
    @State private var dpi = 300
    @State private var widthCM = 21.0
    @State private var heightCM = 29.7
    private var metrics: PrintMetrics {
        let w = image.cgImage?.width ?? Int(image.size.width * image.scale)
        let h = image.cgImage?.height ?? Int(image.size.height * image.scale)
        let rotated = [.left, .leftMirrored, .right, .rightMirrored].contains(image.imageOrientation)
        return PrintMetrics(pixelsWide: rotated ? h : w, pixelsHigh: rotated ? w : h)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("印刷サイズの目安", systemImage: "ruler").font(.headline)
            Text(isResult ? "拡大後の実ピクセル数で計算" : "現在の元画像で計算。拡大後に再計算します。")
                .font(.caption).foregroundStyle(.secondary)
            Text("\(metrics.pixelsWide) × \(metrics.pixelsHigh) px").monospacedDigit()
            Picker("印刷密度", selection: $dpi) {
                ForEach([150, 300, 600], id: \.self) { Text("\($0) DPI").tag($0) }
            }.pickerStyle(.segmented)
            if let size = metrics.sizeCM(dpi: Double(dpi)) {
                Text(String(format: "縦横比を保つ目安：%.1f × %.1f cm", size.width, size.height))
                    .font(.subheadline).monospacedDigit()
            }
            Menu("用途から寸法を入れる") {
                Button("A4・縦（21 × 29.7 cm）") { widthCM = 21; heightCM = 29.7 }
                Button("A3・縦（29.7 × 42 cm）") { widthCM = 29.7; heightCM = 42 }
                Button("Tシャツ前面（30 × 40 cm）") { widthCM = 30; heightCM = 40 }
                Button("正方形（20 × 20 cm）") { widthCM = 20; heightCM = 20 }
            }
            HStack {
                VStack(alignment: .leading) { Text("幅 cm"); TextField("幅", value: $widthCM, format: .number).keyboardType(.decimalPad) }
                VStack(alignment: .leading) { Text("高さ cm"); TextField("高さ", value: $heightCM, format: .number).keyboardType(.decimalPad) }
            }.textFieldStyle(.roundedBorder)
            if let effective = metrics.effectiveDPI(widthCM: widthCM, heightCM: heightCM) {
                Text(String(format: "指定範囲を余白なしで覆う場合：約%.0f DPI", effective)).font(.subheadline)
                Text(effective >= Double(dpi) ? "選んだDPIの目安を満たしています。" : "選んだDPIを下回ります。印刷寸法を小さくするか、拡大後の画像で確認してください。")
                    .font(.caption).foregroundStyle(effective >= Double(dpi) ? Color.green : Color.orange)
            } else { Text("幅と高さに0より大きい数値を入れてください。").font(.caption) }
            Text("縦横比が異なる場合は切り抜きが必要です。この計算で画像やDPIメタデータは変更しません。拡大しても元画像の細部や印刷品質を保証するものではありません。")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(16).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
    }
}
