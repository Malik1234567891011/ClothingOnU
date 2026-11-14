import SwiftUI

/// Collects the reference photos. Every photo is checked on device (Vision) before it's
/// accepted, so problems are fixed here, cheaply, instead of producing a bad model later.
struct PhotosPage: View {
    @Environment(Library.self) private var library
    var onContinue: () -> Void

    @State private var picking: PhotoRole?
    @State private var showSource = false
    @State private var issues: [PhotoRole: [BodyVision.Issue]] = [:]
    @State private var checking: Set<PhotoRole> = []

    private var canContinue: Bool {
        library.photos[.front] != nil
            && checking.isEmpty
            && !issues.values.joined().contains(where: \.isBlocking)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        Text("Your photos")
                            .font(Theme.display())
                        Text("One time only. The closer-fitting your clothes, the more accurately we can read your shape.")
                            .foregroundStyle(Theme.secondaryInk)
                    }

                    tips

                    VStack(spacing: 10) {
                        ForEach(PhotoRole.allCases) { role in
                            PhotoSlotRow(
                                role: role,
                                image: library.photo(role),
                                issues: issues[role] ?? [],
                                isChecking: checking.contains(role),
                                onTap: { picking = role; showSource = true },
                                onRemove: { library.removePhoto(role); issues[role] = nil }
                            )
                        }
                    }

                    Label("Photos stay on your phone. They're sent only to make your images and aren't stored on our servers.", systemImage: "lock.fill")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryInk)
                }
                .pagePadding()
                .padding(.top, Theme.Space.m)
                .padding(.bottom, Theme.Space.l)
            }

            Button("Create my model", action: onContinue)
                .buttonStyle(.primary)
                .disabled(!canContinue)
                .pagePadding()
                .padding(.vertical, Theme.Space.m)
                .accessibilityIdentifier("photos.continue")
        }
        .imageSource(isPresented: $showSource, title: picking.map { "\($0.title) photo" } ?? "Photo") { image in
            guard let role = picking else { return }
            Task { await accept(image, for: role) }
        }
        .task { await recheckExisting() }
    }

    private var tips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Space.s) {
                tip("tshirt", "Fitted clothes")
                tip("figure.stand", "Head to toe")
                tip("sun.max", "Good light")
                tip("square.dashed", "Plain background")
                tip("timer", "Use a timer or a friend")
            }
        }
        .scrollClipDisabled()
    }

    private func tip(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.footnote.weight(.medium))
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Theme.surface, in: .capsule)
            .overlay(Capsule().strokeBorder(Theme.hairline))
    }

    private func accept(_ image: UIImage, for role: PhotoRole) async {
        checking.insert(role)
        defer { checking.remove(role) }
        let found = await BodyVision.check(image, role: role)
        issues[role] = found
        // Blocking problems (no person, several people) aren't saved; warnings are saved but shown.
        if !found.contains(where: \.isBlocking) {
            try? library.setPhoto(image, for: role)
        }
    }

    /// Photos restored from a previous session still get their warnings shown.
    private func recheckExisting() async {
        for role in PhotoRole.allCases where issues[role] == nil {
            if let img = library.photo(role) { issues[role] = await BodyVision.check(img, role: role) }
        }
    }
}

private struct PhotoSlotRow: View {
    let role: PhotoRole
    let image: UIImage?
    let issues: [BodyVision.Issue]
    let isChecking: Bool
    let onTap: () -> Void
    let onRemove: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: Theme.Space.m) {
                preview
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(role.title).font(.headline)
                        badge
                    }
                    Text(role.instruction)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                    if isChecking {
                        Label("Checking…", systemImage: "viewfinder").font(.footnote).foregroundStyle(Theme.secondaryInk)
                    } else if let issue = issues.first {
                        Label(issue.message, systemImage: issue.isBlocking ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(issue.isBlocking ? Theme.danger : Theme.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if image != nil {
                        Label("Looks good", systemImage: "checkmark.circle.fill")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.green)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(Theme.surface, in: .rect(cornerRadius: Theme.Radius.m))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.m).strokeBorder(Theme.hairline))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.ink)
        .contextMenu {
            if image != nil { Button("Remove", systemImage: "trash", role: .destructive, action: onRemove) }
        }
        .accessibilityIdentifier("photo.\(role.rawValue)")
    }

    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.Radius.s).fill(Theme.canvas)
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: role.symbol)
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(Theme.secondaryInk)
            }
        }
        .frame(width: 64, height: role.isFullBody ? 96 : 64)
        .clipShape(.rect(cornerRadius: Theme.Radius.s))
        .overlay(alignment: .bottomTrailing) {
            if image == nil {
                Image(systemName: "plus.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Theme.canvas, Theme.ink)
                    .font(.title3)
                    .offset(x: 6, y: 6)
            }
        }
    }

    @ViewBuilder private var badge: some View {
        switch role.requirement {
        case .required:
            Text("Required").font(.caption2.weight(.bold)).foregroundStyle(Theme.canvas)
                .padding(.horizontal, 6).padding(.vertical, 2).background(Theme.ink, in: .capsule)
        case .recommended:
            Text("Recommended").font(.caption2.weight(.semibold)).foregroundStyle(Theme.ink)
                .padding(.horizontal, 6).padding(.vertical, 2).overlay(Capsule().strokeBorder(Theme.ink))
        case .optional:
            Text("Optional").font(.caption2).foregroundStyle(Theme.secondaryInk)
        }
    }
}
