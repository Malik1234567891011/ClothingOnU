import SwiftUI

/// Bottom control panel: what you're trying on, an optional note, and the one primary action.
struct OutfitPanel: View {
    @Environment(Library.self) private var library
    @Environment(Studio.self) private var studio

    @Binding var angle: ViewAngle
    var onAdd: (Slot) -> Void
    var onTryOn: () -> Void

    @FocusState private var noteFocused: Bool
    @State private var showNote = false

    private var outfit: [Garment] { library.orderedOutfit }

    /// The outfit differs from the look on screen, so "Try it on" would produce something new.
    private var outfitChanged: Bool {
        guard let look = studio.currentLook else { return true }
        return look.garments.map(\.file) != outfit.map(\.file) || (look.note ?? "") != library.note.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        @Bindable var library = library
        GlassEffectContainer(spacing: Theme.Space.s) {
            VStack(spacing: Theme.Space.s) {
                if let look = studio.currentLook, !studio.tryOnJob.isWorking {
                    AngleBar(angle: $angle, look: look)
                }

                if outfit.isEmpty {
                    emptyHint
                } else {
                    tray
                    if showNote {
                        noteField(text: $library.note)
                    } else if !library.note.isEmpty {
                        notePreview
                    }
                }

                actionRow
            }
            .padding(Theme.Space.s + 4)
            .glassEffect(.regular, in: .rect(cornerRadius: Theme.Radius.l + 4))
        }
        .padding(.horizontal, Theme.Space.s + 4)
        .animation(.spring(duration: 0.35), value: outfit.map(\.id))
        .animation(.spring(duration: 0.35), value: showNote)
    }

    private var emptyHint: some View {
        HStack(spacing: Theme.Space.s) {
            Image(systemName: "hand.tap")
            Text("Tap a **+** on your body, then pick a screenshot of what you want to try.")
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    private var tray: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(outfit) { g in
                    TrayItem(garment: g, image: library.garmentImage(g),
                             onTap: { onAdd(g.slot) },
                             onRemove: { library.removeGarment(g.slot) })
                        // Locked while rendering: the render is using these files.
                        .disabled(studio.tryOnJob.isWorking)
                }
                if outfit.count < Slot.allCases.count {
                    Menu {
                        ForEach(Slot.allCases.filter { library.outfit[$0] == nil }) { slot in
                            Button(slot.title, systemImage: slot.symbol) { onAdd(slot) }
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.title3.weight(.medium))
                            .frame(width: 52, height: 52)
                            .background(Theme.hairline.opacity(0.5), in: .rect(cornerRadius: Theme.Radius.s))
                    }
                    .accessibilityLabel("Add another item")
                    .disabled(studio.tryOnJob.isWorking)
                }
            }
            .padding(.vertical, 2)
        }
    }

    /// Collapsed note: one line, tap to edit. Keeps the photo as big as possible.
    private var notePreview: some View {
        Button {
            showNote = true
            noteFocused = true
        } label: {
            Label("“\(library.note)”", systemImage: "text.bubble")
                .font(.footnote)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Styling note: \(library.note). Tap to edit.")
    }

    private func noteField(text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("e.g. leave the jacket unzipped", text: text, axis: .vertical)
                .lineLimit(1...3)
                .focused($noteFocused)
                .submitLabel(.done)
                .onChange(of: text.wrappedValue) { _, new in
                    if new.count > 300 { text.wrappedValue = String(new.prefix(300)) }
                    if new.contains("\n") { text.wrappedValue = new.replacingOccurrences(of: "\n", with: " "); noteFocused = false }
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(Theme.surface.opacity(0.7), in: .rect(cornerRadius: Theme.Radius.s))
                .accessibilityIdentifier("note.field")
            let suggestions = Array(Set(outfit.flatMap(\.slot.suggestions))).sorted()
            if !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(suggestions, id: \.self) { s in
                            Button(s) { append(s, to: text) }
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Theme.surface.opacity(0.7), in: .capsule)
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private func append(_ suggestion: String, to text: Binding<String>) {
        let current = text.wrappedValue.trimmingCharacters(in: .whitespaces)
        guard !current.localizedCaseInsensitiveContains(suggestion) else { return }
        text.wrappedValue = current.isEmpty ? suggestion : "\(current), \(suggestion.lowercased())"
    }

    private var actionRow: some View {
        HStack(spacing: Theme.Space.s) {
            if !outfit.isEmpty {
                Button {
                    showNote.toggle()
                    noteFocused = showNote
                } label: {
                    Image(systemName: library.note.isEmpty ? "text.bubble" : "text.bubble.fill")
                        .font(.title3)
                        .frame(width: 52, height: 52)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel("Add a styling note")
                .accessibilityIdentifier("note.toggle")
            }
            Button {
                showNote = false
                noteFocused = false
                onTryOn()
            } label: {
                Label(tryOnTitle, systemImage: "sparkles")
                    .font(.headline)
                    .foregroundStyle(Theme.canvas)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .tint(Theme.ink)
            .disabled(!studio.canTryOn || !outfitChanged)
            .accessibilityIdentifier("tryon.button")
        }
    }

    private var tryOnTitle: String {
        if studio.tryOnJob.isWorking { return "Trying it on…" }
        if studio.currentLook != nil && !outfitChanged { return "On you" }
        return studio.currentLook == nil ? "Try it on" : "Update look"
    }
}

private struct TrayItem: View {
    let garment: Garment
    let image: UIImage?
    let onTap: () -> Void
    let onRemove: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                if let image { Thumb(image: image, size: 52) }
            }
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.7))
                    .font(.system(size: 18))
            }
            .offset(x: 6, y: -6)
            .accessibilityLabel("Remove \(garment.slot.title.lowercased())")
        }
        .overlay(alignment: .bottom) {
            Text(garment.slot.title)
                .font(.system(size: 9, weight: .bold))
                .padding(.horizontal, 4).padding(.vertical, 1)
                .background(.ultraThinMaterial, in: .capsule)
                .offset(y: 6)
        }
        .padding(.vertical, 6)
        .accessibilityLabel("\(garment.slot.title). Tap to change.")
    }
}

/// Front · ¾ · Side · Back. Tapping an angle that isn't rendered yet starts the turnaround.
private struct AngleBar: View {
    @Environment(Studio.self) private var studio
    @Binding var angle: ViewAngle
    let look: Look

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Studio.turnaround) { a in
                let ready = look.images[a] != nil
                let state = studio.angleState(a, for: look)
                Button {
                    angle = a
                    if !ready { studio.renderMissingAngles() }
                } label: {
                    HStack(spacing: 4) {
                        if state.isWorking { ProgressView().controlSize(.mini) }
                        else if state.error != nil { Image(systemName: "exclamationmark.circle") }
                        Text(a.title)
                    }
                    .font(.subheadline.weight(angle == a ? .semibold : .regular))
                    .foregroundStyle(ready || state.isWorking ? Theme.ink : Theme.secondaryInk)
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .background(angle == a ? Theme.surface.opacity(0.9) : .clear, in: .capsule)
                    .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("angle.\(a.rawValue)")
            }
        }
        .padding(3)
        .background(Theme.hairline.opacity(0.35), in: .capsule)
        .sensoryFeedback(.selection, trigger: angle)
        .animation(.spring(duration: 0.25), value: angle)
    }
}
