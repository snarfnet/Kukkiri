import SwiftUI
import PhotosUI

struct ContentView: View {
    @StateObject private var vm = UpscaleViewModel()
    @State private var pickerItem: PhotosPickerItem?
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

            VStack(spacing: 16) {
                header
                imageArea
                controls
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .onChange(of: pickerItem) { item in
            guard let item else { return }
            Task { await vm.load(item) }
        }
        .sheet(isPresented: $showShare) {
            if let url = vm.shareURL { ShareSheet(items: [url]) }
        }
        .alert("保存しました", isPresented: $vm.didSave) { Button("OK", role: .cancel) {} }
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

            if vm.original != nil && vm.result == nil && !vm.isProcessing {
                modePicker
                Button { vm.run() } label: {
                    label("wand.and.stars", "アップスケールする", filled: true)
                }
            }

            if vm.result != nil {
                HStack(spacing: 12) {
                    Button { vm.save() } label: { label("square.and.arrow.down", "保存", filled: false) }
                    Button { showShare = true } label: { label("square.and.arrow.up", "共有", filled: false) }
                }
            }

            if let err = vm.errorText {
                Text(err).font(.system(size: 12)).foregroundColor(.red.opacity(0.8))
            }
        }
    }

    private var modePicker: some View {
        HStack(spacing: 10) {
            ForEach(OutputMode.allCases) { mode in
                let selected = vm.outputMode == mode
                Button { vm.outputMode = mode } label: {
                    VStack(spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: mode.icon)
                            Text(mode.title).font(.system(size: 15, weight: .bold, design: .rounded))
                        }
                        Text(mode.note)
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
        }
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

// MARK: - Before/After スライダー

struct CompareView: View {
    let before: UIImage
    let after: UIImage
    @Binding var pos: CGFloat

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
            .overlay(alignment: .topLeading) { tag("元", .black.opacity(0.5)) }
            .overlay(alignment: .topTrailing) { tag("アップ", .blue.opacity(0.6)) }
        }
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
