import AppCore
import AppKit
import PlatformServices
import SwiftUI

@MainActor
final class SwitcherViewModel: ObservableObject {
    @Published var windows: [SwitchableWindow] = []
    @Published var selectedIndex = 0
    @Published var showWindowTitles = true
    @Published var columnCount = 1
    @Published var cardWidth: CGFloat = 252
    @Published var previewHeight: CGFloat = 142

    var selectedWindow: SwitchableWindow? {
        windows.indices.contains(selectedIndex) ? windows[selectedIndex] : nil
    }
}

struct SwitcherView: View {
    @ObservedObject var model: SwitcherViewModel
    let onSelect: (Int) -> Void

    var body: some View {
        Group {
            if model.windows.isEmpty {
                emptyState
            } else {
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.fixed(model.cardWidth), spacing: 12),
                        count: model.columnCount
                    ),
                    spacing: 12
                ) {
                    ForEach(Array(model.windows.enumerated()), id: \.element.id) { index, window in
                        WindowCard(
                            window: window,
                            isSelected: index == model.selectedIndex,
                            cardWidth: model.cardWidth,
                            previewHeight: model.previewHeight,
                            showWindowTitle: model.showWindowTitles
                        )
                        .onTapGesture {
                            onSelect(index)
                        }
                    }
                }
                .padding(18)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(backdrop)
    }

    private var emptyState: some View {
        Image(systemName: "rectangle.slash")
            .font(.system(size: 34, weight: .light))
            .foregroundStyle(.white.opacity(0.55))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var backdrop: some View {
        if #available(macOS 26.0, *) {
            Color.clear
                .glassEffect(
                    .regular.tint(.white.opacity(0.18)),
                    in: .rect(cornerRadius: 34)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .stroke(.white.opacity(0.52), lineWidth: 1)
                }
        } else {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .fill(.white.opacity(0.14))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .stroke(.white.opacity(0.42), lineWidth: 1)
                }
        }
    }
}

private struct WindowCard: View {
    let window: SwitchableWindow
    let isSelected: Bool
    let cardWidth: CGFloat
    let previewHeight: CGFloat
    let showWindowTitle: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Image(nsImage: window.appIcon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)

                if showWindowTitle {
                    Text(window.windowTitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 44)

            preview
                .frame(width: cardWidth, height: previewHeight)
                .clipped()
                .background(.black.opacity(0.24))
                .overlay(alignment: .topTrailing) {
                    if window.isMinimized {
                        Image(systemName: "minus")
                            .font(.system(size: 11, weight: .bold))
                            .frame(width: 24, height: 24)
                            .background(.black.opacity(0.55), in: Circle())
                            .padding(10)
                    }
                }
        }
            .frame(width: cardWidth, height: previewHeight + 44)
            .background(.black.opacity(0.28))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    isSelected
                        ? Color(nsColor: .controlAccentColor)
                        : .white.opacity(0.12),
                    lineWidth: isSelected ? 4 : 1
                )
            }
            .shadow(color: .black.opacity(isSelected ? 0.35 : 0.18), radius: 12, y: 7)
            .accessibilityLabel("\(window.appName), \(window.windowTitle)")
    }

    @ViewBuilder
    private var preview: some View {
        if let image = window.preview {
            if WindowPreviewLayout.shouldFit(
                windowBounds: CGRect(origin: .zero, size: image.size),
                previewSize: CGSize(width: cardWidth, height: previewHeight)
            ) {
                ZStack {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: cardWidth, height: previewHeight)
                        .clipped()
                        .blur(radius: 14)
                        .opacity(0.5)

                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: cardWidth, height: previewHeight)
                }
            } else {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            }
        } else {
            ZStack {
                LinearGradient(
                    colors: [.white.opacity(0.08), .white.opacity(0.02)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(nsImage: window.appIcon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 92, height: 92)
                    .opacity(0.8)
            }
        }
    }
}
