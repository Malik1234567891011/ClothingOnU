import SwiftUI

/// Every look you've tried, newest first. Tap to bring one back into the fitting room.
struct LooksSheet: View {
    @Environment(Library.self) private var library
    @Environment(Studio.self) private var studio
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        NavigationStack {
            Group {
                if library.looks.isEmpty {
                    ContentUnavailableView("No looks yet", systemImage: "hanger",
                                           description: Text("Everything you try on is saved here."))
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(library.looks) { look in
                                LookCard(look: look, isCurrent: look.id == studio.currentLookID) {
                                    studio.show(look: look.id)
                                    library.restoreOutfit(from: look)
                                    dismiss()
                                }
                                .contextMenu {
                                    if let url = library.lookURL(look, .front) {
                                        ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
                                    }
                                    Button("Delete", systemImage: "trash", role: .destructive) {
                                        if studio.currentLookID == look.id { studio.show(look: nil) }
                                        library.deleteLook(look.id)
                                    }
                                }
                            }
                        }
                        .padding(Theme.Space.m)
                    }
                }
            }
            .background(Theme.canvas.ignoresSafeArea())
            .navigationTitle("Your looks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done", role: .close) { dismiss() } }
            }
        }
    }
}

private struct LookCard: View {
    @Environment(Library.self) private var library
    let look: Look
    let isCurrent: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    Theme.studio
                    if let img = library.lookImage(look, .front) {
                        Image(uiImage: img).resizable().scaledToFill()
                    }
                }
                .aspectRatio(3 / 4, contentMode: .fit)
                .clipShape(.rect(cornerRadius: Theme.Radius.m))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.m).strokeBorder(isCurrent ? Theme.ink : .clear, lineWidth: 2))
                .overlay(alignment: .bottomTrailing) {
                    if look.images.count > 1 {
                        Label("\(look.images.count)", systemImage: "rotate.3d")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(.ultraThinMaterial, in: .capsule)
                            .padding(6)
                    }
                }
                HStack(spacing: 4) {
                    ForEach(look.garments) { g in
                        if let img = library.garmentImage(g) { Thumb(image: img, size: 26) }
                    }
                    Spacer(minLength: 0)
                }
                Text(look.createdAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryInk)
            }
        }
        .buttonStyle(.plain)
    }
}
