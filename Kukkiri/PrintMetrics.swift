import Foundation

struct PrintMetrics {
    let pixelsWide: Int
    let pixelsHigh: Int
    func sizeCM(dpi: Double) -> (width: Double, height: Double)? {
        guard pixelsWide > 0, pixelsHigh > 0, dpi.isFinite, dpi > 0 else { return nil }
        return (Double(pixelsWide) / dpi * 2.54, Double(pixelsHigh) / dpi * 2.54)
    }
    func effectiveDPI(widthCM: Double, heightCM: Double) -> Double? {
        guard pixelsWide > 0, pixelsHigh > 0, widthCM.isFinite, heightCM.isFinite,
              widthCM > 0, heightCM > 0 else { return nil }
        return min(Double(pixelsWide) / widthCM * 2.54, Double(pixelsHigh) / heightCM * 2.54)
    }
}
