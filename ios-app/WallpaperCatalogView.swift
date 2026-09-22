import SwiftUI

struct WallpaperCatalogView: View {
    @StateObject private var model = WallpaperCatalogModel()

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
            .alert("提示", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
                Button("确定") { model.errorMessage = nil }
            } message: {
                Text(model.errorMessage ?? "")
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
