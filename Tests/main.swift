import Foundation
let p = PrintMetrics(pixelsWide: 3000, pixelsHigh: 4500)
let size = p.sizeCM(dpi: 300)!
assert(abs(size.width - 25.4) < 0.000001 && abs(size.height - 38.1) < 0.000001)
assert(abs(p.effectiveDPI(widthCM: 25.4, heightCM: 38.1)! - 300) < 0.000001)
assert(abs(p.effectiveDPI(widthCM: 25.4, heightCM: 50.8)! - 225) < 0.000001)
assert(p.sizeCM(dpi: 0) == nil && p.sizeCM(dpi: .infinity) == nil)
assert(p.effectiveDPI(widthCM: -1, heightCM: 20) == nil)
assert(PrintMetrics(pixelsWide: 0, pixelsHigh: 100).sizeCM(dpi: 300) == nil)
print("PASS: print dimensions, crop-to-fill limiting axis, invalid values")
