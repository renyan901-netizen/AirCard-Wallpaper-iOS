import SwiftUI

struct WallpaperCatalogView: View {
    @StateObject private var model = WallpaperCatalogModel()
    @ObservedObject private var license = LicenseManager.shared
    @State private var showLicenseSheet = false

    var body: some View {
        NavigationStack {
            Group {
                if model.filteredWallpapers.isEmpty && model.isLoading {
                    ProgressView("正在加载壁纸…")
                } else if model.filteredWallpapers.isEmpty {
                    ContentUnavailableView("暂无壁纸", systemImage: "photo.on.rectangle.angled", description: Text("下拉刷新资源列表"))
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ForEach(model.filteredWallpapers) { item in
                                WallpaperCatalogCard(item: item, isDownloading: model.downloadingID == item.id) {
                                    Task { await model.download(item) }
                                }
                                .onAppear {
                                    if item.id == model.filteredWallpapers.last?.id {
                                        Task { await model.load() }
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                    .refreshable { await model.load(reset: true) }
                }
            }
            .navigationTitle("壁纸资源")
            .searchable(text: $model.searchText, prompt: "搜索壁纸")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await model.load(reset: true) } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(model.isLoading)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showLicenseSheet = true } label: {
                        Image(systemName: "key.fill")
                    }
                    .accessibilityLabel("卡密兑换")
                }
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("全部") { model.selectedTag = nil; Task { await model.load(reset: true) } }
                        ForEach(model.tags, id: \.self) { tag in
                            Button(tag) { model.selectedTag = tag; Task { await model.load(reset: true) } }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .task { await model.load(reset: true) }
            .task { await license.refresh() }
            .sheet(isPresented: $showLicenseSheet) {
                LicenseRedeemView(license: license)
            }
            .alert("提示", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
                Button("确定") { model.errorMessage = nil }
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
    }
}

private struct LicenseRedeemView: View {
    @ObservedObject var license: LicenseManager
    @Environment(\.dismiss) private var dismiss
    @State private var licenseKey = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("软件授权") {
                    Label(license.statusText, systemImage: license.isActive ? "checkmark.seal.fill" : "lock.fill")
                        .foregroundStyle(license.isActive ? .green : .secondary)

                    TextField("输入卡密", text: $licenseKey)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()

                    Button {
                        Task { await license.redeem(licenseKey) }
                    } label: {
                        HStack {
                            Spacer()
                            if license.isBusy { ProgressView() }
                            else { Text("兑换卡密") }
                            Spacer()
                        }
                    }
                    .disabled(license.isBusy || licenseKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if let error = license.lastError {
                    Section {
                        Text(error).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("卡密兑换")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}

private struct WallpaperCatalogCard: View {
    let item: RemoteWallpaper
    let isDownloading: Bool
    let download: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AsyncImage(url: item.thumbURL ?? item.imageURL) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFill()
                case .failure: Color.secondary.opacity(0.15).overlay(Image(systemName: "photo"))
                default: ProgressView()
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(0.72, contentMode: .fit)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Text(item.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)

            HStack {
                Text(item.tags.prefix(2).joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Button(action: download) {
                    if isDownloading { ProgressView().controlSize(.small) }
                    else { Image(systemName: "arrow.down.circle.fill") }
                }
                .buttonStyle(.borderless)
                .disabled(isDownloading)
                .accessibilityLabel("下载并导入")
            }
        }
        .padding(8)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
