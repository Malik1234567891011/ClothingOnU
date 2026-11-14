import SwiftUI

struct BodyPage: View {
    @Binding var profile: Profile
    var onContinue: () -> Void

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        Text("A bit about you")
                            .font(Theme.display())
                        Text("So clothes are sized to your real body, not a model's.")
                            .foregroundStyle(Theme.secondaryInk)
                    }

                    heightSection
                    buildSection
                }
                .pagePadding()
                .padding(.top, Theme.Space.m)
                .padding(.bottom, Theme.Space.l)
            }
            .scrollBounceBehavior(.basedOnSize)

            Button("Continue", action: onContinue)
                .buttonStyle(.primary)
                .pagePadding()
                .padding(.vertical, Theme.Space.m)
                .accessibilityIdentifier("body.continue")
        }
    }

    // MARK: Height

    private var heightSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack {
                Text("Height").font(.headline)
                Spacer()
                Picker("Units", selection: $profile.prefersMetric) {
                    Text("ft / in").tag(false)
                    Text("cm").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
            }

            Group {
                if profile.prefersMetric {
                    Picker("Centimetres", selection: $profile.heightCm) {
                        ForEach(Array(Height.rangeCm), id: \.self) { Text("\($0) cm").tag($0) }
                    }
                } else {
                    HStack(spacing: 0) {
                        Picker("Feet", selection: feet) {
                            ForEach(4...7, id: \.self) { Text("\($0) ft").tag($0) }
                        }
                        Picker("Inches", selection: inches) {
                            ForEach(0...11, id: \.self) { Text("\($0) in").tag($0) }
                        }
                    }
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 140)
            .background(Theme.surface, in: .rect(cornerRadius: Theme.Radius.m))
        }
    }

    private var feet: Binding<Int> {
        Binding(
            get: { Height.feetInches(cm: profile.heightCm).feet },
            set: { setHeight(feet: $0, inches: Height.feetInches(cm: profile.heightCm).inches) }
        )
    }

    private var inches: Binding<Int> {
        Binding(
            get: { Height.feetInches(cm: profile.heightCm).inches },
            set: { setHeight(feet: Height.feetInches(cm: profile.heightCm).feet, inches: $0) }
        )
    }

    private func setHeight(feet: Int, inches: Int) {
        let cm = Height.cm(feet: feet, inches: inches)
        profile.heightCm = min(max(cm, Height.rangeCm.lowerBound), Height.rangeCm.upperBound)
    }

    // MARK: Build

    private var buildSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("How would you describe your build?").font(.headline)
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(Build.allCases) { build in
                    BuildCard(build: build, selected: profile.build == build) {
                        withAnimation(.spring(duration: 0.25)) { profile.build = build }
                    }
                }
            }
            Text("Your photos matter most; this just helps when they're unclear.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryInk)
        }
    }
}

private struct BuildCard: View {
    let build: Build
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(build.title).font(.subheadline.weight(.semibold))
                    Spacer(minLength: 0)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? Theme.ink : Theme.hairline)
                }
                Text(build.detail)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryInk)
                    .lineLimit(2, reservesSpace: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: .rect(cornerRadius: Theme.Radius.m))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.m)
                    .strokeBorder(selected ? Theme.ink : Theme.hairline, lineWidth: selected ? 2 : 1)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.ink)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("build.\(build.rawValue)")
        .sensoryFeedback(.selection, trigger: selected)
    }
}
