import SwiftUI
import PhotosUI

struct ContentView: View {
    @StateObject private var vm = UpscaleViewModel()
    @State private var pickerItem: PhotosPickerItem?
    @State private var batchItems: [PhotosPickerItem] = []
    @State private var showShare = false
    @State private var comparePos: CGFloat = 0.5

    private let accent = Color(red: 130/255, green: 200/255, blue: 255/255)
    private let accent2 = Color(red: 180/255, green: 160/255, blue: 250/255)
    private let bgTop = Color(red: 24/255, green: 22/255, blue: 38/255)
    private let bgBot = Color(red: 16/255, green: 15/255, blue: 28/255)
    private let card = Color(red: 38/255, green: 35/255, blue: 56/255)

    var body: some View {
        ZStack {
            LinearGradient(colors: [bgTop, bgBot], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    header
                    if vm.isBatchProcessing {
                        batchProgress
                    } else {
                        imageArea
                        if let original = vm.original, let result = vm.result {
                            SizeCompareView(before: original, after: result, accent: accent, accent2: accent2, card: card)
                        }
                        controls
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
        }
        .onAppear {
            if let screen = ProcessInfo.processInfo.environment["KUKKIRI_DEMO"] {
                vm.loadDemo(screen: screen)
            }
        }
        .onChange(of: pickerItem) { item in
            guard let item else { return }
            Task { await vm.load(item) }
        }
        .onChange(of: batchItems) { items in
            guard !items.isEmpty else { return }
            vm.runBatch(items)
            batchItems = []
        }
        .sheet(isPresented: $showShare) {
            if let url = vm.shareURL { ShareSheet(items: [url]) }
        }
        .alert("保存しました", isPresented: $vm.didSave) { Button("OK", role: .cancel) {} }
        .alert("\(vm.batchSaved)枚を写真に保存しました", isPresented: $vm.batchFinished) { Button("OK", role: .cancel) {} }
    }

    private var batchProgress: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 40)
            ProgressView(value: vm.batchTotal > 0 ? Double(vm.batchDone) / Double(vm.batchTotal) : 0)
                .progressViewStyle(.linear)
                .tint(accent)
                .frame(width: 200)
            Text("\(vm.batchDone) / \(vm.batchTotal) 枚")
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
            Text("まとめてアップスケール中…")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(RoundedRectangle(cornerRadius: 22).fill(card))
    }

    // MARK: header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(LinearGradient(colors: [accent, accent2], startPoint: .leading, endPoint: .trailing))
            Text("アップスケール")
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
            Spacer()
            Text("4×")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(.black)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(accent))
        }
    }

    // MARK: image area

    private var imageArea: some View {
        Group {
            if vm.result == nil {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    imageContent
                }
                .buttonStyle(.plain)
                .disabled(vm.isProcessing)
            } else {
                imageContent
            }
        }
    }

    private var imageContent: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22).fill(card)

            if let result = vm.result, let original = vm.original {
                CompareView(before: original, after: result, pos: $comparePos)
                    .clipShape(RoundedRectangle(cornerRadius: 22))
            } else if let original = vm.original {
                Image(uiImage: original)
                    .resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 22))
            } else {
                placeholder
            }

            if vm.isProcessing {
                ZStack {
                    RoundedRectangle(cornerRadius: 22).fill(.black.opacity(0.55))
                    VStack(spacing: 14) {
                        ProgressView(value: vm.progress)
                            .progressViewStyle(.linear)
                            .tint(accent)
                            .frame(width: 180)
                        Text("\(Int(vm.progress * 100))%  アップスケール中…")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 420)
        .overlay(alignment: .bottom) {
            if let original = vm.original, vm.result == nil, !vm.isProcessing {
                let p = px(original)
                Text("\(p.w) × \(p.h) px")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(.black.opacity(0.55)))
                    .padding(.bottom, 12)
            }
        }
    }

    private func px(_ img: UIImage) -> (w: Int, h: Int) {
        if let cg = img.cgImage { return (cg.width, cg.height) }
        return (Int(img.size.width * img.scale), Int(img.size.height * img.scale))
    }

    private var placeholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 46))
                .foregroundColor(.white.opacity(0.35))
            Text("写真を選んでください")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.5))
        }
    }

    // MARK: controls

    private var controls: some View {
        VStack(spacing: 12) {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                label("photo", vm.original == nil ? "写真を選ぶ" : "別の写真", filled: true)
            }

            if vm.result == nil && !vm.isProcessing {
                subjectPicker
                modePicker
                if vm.original != nil {
                    Button { vm.run() } label: {
                        label("wand.and.stars", "アップスケールする", filled: true)
                    }
                }
                PhotosPicker(selection: $batchItems, maxSelectionCount: 20, matching: .images) {
                    label("square.stack.3d.up", "まとめて変換（複数枚）", filled: false)
                }
            }

            if vm.result != nil {
                HStack(spacing: 12) {
                    Button { vm.save() } label: { label("square.and.arrow.down", "保存", filled: false) }
                    Button { showShare = true } label: { label("square.and.arrow.up", "共有", filled: false) }
                }
                Button { vm.reset() } label: {
                    label("chevron.left", "戻る", filled: false)
                }
            }

            if let err = vm.errorText {
                Text(err).font(.system(size: 12)).foregroundColor(.red.opacity(0.8))
            }
        }
    }

    private var subjectPicker: some View {
        HStack(spacing: 10) {
            ForEach(SubjectMode.allCases) { mode in
                modeCard(icon: mode.icon, title: mode.title, note: mode.note,
                         selected: vm.subjectMode == mode) { vm.subjectMode = mode }
            }
        }
    }

    private var modePicker: some View {
        HStack(spacing: 10) {
            ForEach(OutputMode.allCases) { mode in
                modeCard(icon: mode.icon, title: mode.title, note: mode.note,
                         selected: vm.outputMode == mode) { vm.outputMode = mode }
            }
        }
    }

    private func modeCard(icon: String, title: String, note: String,
                          selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                    Text(title).font(.system(size: 15, weight: .bold, design: .rounded))
                }
                Text(note)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(selected ? .black.opacity(0.7) : .white.opacity(0.5))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundColor(selected ? .black : .white)
            .background(
                Group {
                    if selected {
                        LinearGradient(colors: [accent, accent2], startPoint: .leading, endPoint: .trailing)
                    } else {
                        Color.white.opacity(0.08)
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private func label(_ icon: String, _ text: String, filled: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
            Text(text).font(.system(size: 16, weight: .bold, design: .rounded))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .foregroundColor(filled ? .black : .white)
        .background(
            Group {
                if filled {
                    LinearGradient(colors: [accent, accent2], startPoint: .leading, endPoint: .trailing)
                } else {
                    Color.white.opacity(0.10)
                }
            }
        )
        .clipShape(Capsule())
    }
}

// MARK: - サイズ比較（入れ子図）

struct SizeCompareView: View {
    let before: UIImage
    let after: UIImage
    let accent: Color
    let accent2: Color
    let card: Color

    private func px(_ img: UIImage) -> (w: Int, h: Int) {
        if let cg = img.cgImage { return (cg.width, cg.height) }
        return (Int(img.size.width * img.scale), Int(img.size.height * img.scale))
    }

    var body: some View {
        let b = px(before)
        let a = px(after)
        let ratio = b.w > 0 ? Double(a.w) / Double(b.w) : 1
        let ratioText = abs(ratio - ratio.rounded()) < 0.05
            ? "×\(Int(ratio.rounded()))"
            : String(format: "×%.1f", ratio)

        return HStack(spacing: 14) {
            diagram(bw: b.w, bh: b.h, aw: a.w, ah: a.h)
                .frame(width: 120, height: 96)

            VStack(alignment: .leading, spacing: 8) {
                Text(ratioText)
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: [accent, accent2], startPoint: .leading, endPoint: .trailing))
                VStack(alignment: .leading, spacing: 2) {
                    dimRow("元", "\(b.w)×\(b.h)", .white.opacity(0.45))
                    dimRow("アップ", "\(a.w)×\(a.h)", accent)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 18).fill(card))
    }

    private func dimRow(_ label: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(color)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.85))
        }
    }

    private func diagram(bw: Int, bh: Int, aw: Int, ah: Int) -> some View {
        // 大きい方を外枠、小さい方を内側に実寸比で描く（出力が縮む場合も崩れない）
        let afterBigger = aw >= bw
        let big = afterBigger ? (w: aw, h: ah) : (w: bw, h: bh)
        let small = afterBigger ? (w: bw, h: bh) : (w: aw, h: ah)
        let bigIsAfter = afterBigger

        return GeometryReader { geo in
            let maxW = geo.size.width
            let maxH = geo.size.height
            let aspect = big.h > 0 ? CGFloat(big.w) / CGFloat(big.h) : 1
            var rw = maxW
            var rh = rw / aspect
            if rh > maxH { rh = maxH; rw = rh * aspect }
            let scale = big.w > 0 ? CGFloat(small.w) / CGFloat(big.w) : 1

            let outerColor = bigIsAfter ? accent : Color.white.opacity(0.6)
            let innerColor = bigIsAfter ? Color.white.opacity(0.6) : accent

            return ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(outerColor.opacity(0.14))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(outerColor, lineWidth: 2))
                    .frame(width: rw, height: rh)
                RoundedRectangle(cornerRadius: 3)
                    .fill(innerColor.opacity(0.30))
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(innerColor, lineWidth: 1))
                    .frame(width: rw * scale, height: rh * scale)
            }
            .frame(width: maxW, height: maxH, alignment: .bottomLeading)
        }
    }
}

// MARK: - Before/After スライダー

struct CompareView: View {
    let before: UIImage
    let after: UIImage
    @Binding var pos: CGFloat
    @State private var loupePoint: CGPoint?

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Image(uiImage: after).resizable().scaledToFit()
                Image(uiImage: before).resizable().scaledToFit()
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: w * pos)
                    }
                // ハンドル
                Rectangle().fill(.white).frame(width: 2)
                    .position(x: w * pos, y: geo.size.height / 2)
                Circle().fill(.white).frame(width: 28, height: 28)
                    .overlay(Image(systemName: "arrow.left.and.right").font(.system(size: 12, weight: .bold)).foregroundColor(.black))
                    .position(x: w * pos, y: geo.size.height / 2)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture().onChanged { v in
                pos = min(max(v.location.x / w, 0), 1)
            })
            // ルーペ: 長押しドラッグでなぞった部分を等倍拡大
            .gesture(LongPressGesture(minimumDuration: 0.15).sequenced(before: DragGesture(minimumDistance: 0))
                .onChanged { value in
                    if case .second(true, let drag?) = value { loupePoint = drag.location }
                }
                .onEnded { _ in loupePoint = nil })
            .overlay(alignment: .topLeading) { tag("元", .black.opacity(0.5)) }
            .overlay(alignment: .topTrailing) { tag("アップ", .blue.opacity(0.6)) }
            .overlay { if let p = loupePoint { loupe(geo: geo, p: p) } }
        }
    }

    private func loupe(geo: GeometryProxy, p: CGPoint) -> some View {
        let size: CGFloat = 130
        let zoom: CGFloat = 3
        let cx = min(max(p.x, size / 2), geo.size.width - size / 2)
        let cy = max(p.y - size / 2 - 30, size / 2)
        return Image(uiImage: after)
            .resizable().scaledToFit()
            .frame(width: geo.size.width, height: geo.size.height)
            .scaleEffect(zoom)
            .offset(x: (geo.size.width / 2 - p.x) * zoom,
                    y: (geo.size.height / 2 - p.y) * zoom)
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().stroke(.white, lineWidth: 3))
            .overlay(Circle().stroke(.black.opacity(0.25), lineWidth: 1))
            .shadow(radius: 8)
            .position(x: cx, y: cy)
            .allowsHitTesting(false)
    }

    private func tag(_ t: String, _ c: Color) -> some View {
        Text(t).font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundColor(.white).padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(c)).padding(8)
    }
}

// MARK: - Share

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

#Preview { ContentView() }
