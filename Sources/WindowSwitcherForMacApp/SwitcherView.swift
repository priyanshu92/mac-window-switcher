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
    @Published var isDockPreview = false
    @Published var showsCloseButtons = false

    var selectedWindow: SwitchableWindow? {
        windows.indices.contains(selectedIndex) ? windows[selectedIndex] : nil
    }
}

struct SwitcherView: View {
    @Environment(\.colorScheme) private var colorScheme

    @ObservedObject var model: SwitcherViewModel
    let onSelect: (Int) -> Void
    let onHover: (Int?) -> Void
    let onClose: (Int) -> Void

    var body: some View {
        Group {
            if model.windows.isEmpty {
                emptyState
            } else if model.isDockPreview {
                HStack(spacing: DockWindowPreviewLayout.cardSpacing) {
                    ForEach(Array(model.windows.enumerated()), id: \.element.id) {
                        index,
                        window in
                        windowCard(
                            window: window,
                            index: index,
                            cardWidth: DockWindowPreviewLayout.cardWidth(
                                windowSize: window.bounds.size,
                                previewHeight: model.previewHeight
                            )
                        )
                        .overlay(alignment: .trailing) {
                            if index < model.windows.count - 1 {
                                Rectangle()
                                    .fill(
                                        colorScheme == .dark
                                            ? .white.opacity(0.10)
                                            : .black.opacity(0.10)
                                    )
                                    .frame(width: 1)
                            }
                        }
                    }
                }
                .clipShape(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .shadow(
                    color: .black.opacity(0.18),
                    radius: DockWindowPreviewLayout.shadowRadius,
                    y: 3
                )
                .padding(DockWindowPreviewLayout.panelPadding)
            } else {
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(
                            .fixed(model.cardWidth),
                            spacing: model.isDockPreview ? 8 : 12
                        ),
                        count: model.columnCount
                    ),
                    spacing: model.isDockPreview ? 8 : 12
                ) {
                    ForEach(Array(model.windows.enumerated()), id: \.element.id) { index, window in
                        windowCard(
                            window: window,
                            index: index,
                            cardWidth: model.cardWidth
                        )
                    }
                }
                .padding(18)
            }
        }

        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if !model.isDockPreview {
                backdrop
            }
        }
    }

    private func windowCard(
        window: SwitchableWindow,
        index: Int,
        cardWidth: CGFloat
    ) -> some View {
        WindowCard(
            window: window,
            isSelected: index == model.selectedIndex,
            cardWidth: cardWidth,
            previewHeight: model.previewHeight,
            showWindowTitle: model.showWindowTitles,
            isDockPreview: model.isDockPreview,
            showsCloseButton: model.showsCloseButtons,
            onHover: { hovering in
                onHover(hovering ? index : nil)
            },
            onClose: { onClose(index) }
        )
        .onTapGesture {
            onSelect(index)
        }
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
    @Environment(\.colorScheme) private var colorScheme

    let window: SwitchableWindow
    let isSelected: Bool
    let cardWidth: CGFloat
    let previewHeight: CGFloat
    let showWindowTitle: Bool
    let isDockPreview: Bool
    let showsCloseButton: Bool
    let onHover: (Bool) -> Void
    let onClose: () -> Void
    @State private var isHovered = false

    private var isHighlighted: Bool {
        isSelected || isHovered
    }

    private var dockCardBackground: Color {
        if colorScheme == .dark {
            return isHovered
                ? Color(red: 0.23, green: 0.23, blue: 0.25)
                : Color(red: 0.17, green: 0.17, blue: 0.19)
        }
        return isHovered
            ? Color(red: 0.89, green: 0.89, blue: 0.91)
            : Color(red: 0.95, green: 0.95, blue: 0.96)
    }

    private var displayedPreviewWidth: CGFloat {
        isDockPreview ? cardWidth - 16 : cardWidth
    }

    private var displayedPreviewHeight: CGFloat {
        isDockPreview ? previewHeight - 8 : previewHeight
    }

    private var captionHeight: CGFloat {
        isDockPreview ? DockWindowPreviewLayout.captionHeight : 44
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                if showsCloseButton {
                    Button(action: onClose) {
                        ZStack {
                            Circle()
                                .fill(Color(nsColor: .systemRed))
                            if isHovered {
                                Image(systemName: "xmark")
                                    .font(.system(size: 7, weight: .bold))
                                    .foregroundStyle(.black.opacity(0.58))
                            }
                        }
                        .frame(width: 14, height: 14)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close \(window.windowTitle)")
                }

                Image(nsImage: window.appIcon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)

                if showWindowTitle {
                    Text(window.windowTitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(
                            isDockPreview ? Color.primary : .white.opacity(0.92)
                        )
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: captionHeight)

            preview
                .frame(
                    width: displayedPreviewWidth,
                    height: displayedPreviewHeight
                )
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
        .clipShape(
                RoundedRectangle(
                    cornerRadius: isDockPreview ? 4 : 0,
                    style: .continuous
                )
        )
        .padding(.horizontal, isDockPreview ? 8 : 0)
        .padding(.bottom, isDockPreview ? 8 : 0)
            .frame(width: cardWidth, height: previewHeight + captionHeight)
                .background(
                    isDockPreview
                        ? dockCardBackground
                        : .black.opacity(0.28)
                )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: isDockPreview ? 0 : 16,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    !isDockPreview && isHighlighted
                        ? Color(nsColor: .controlAccentColor)
                        : isDockPreview ? .clear : .white.opacity(0.12),
                    lineWidth: !isDockPreview && isHighlighted ? 4 : 1
                )
            }
            .shadow(
                color: isDockPreview
                    ? .clear
                    : .black.opacity(isHighlighted ? 0.35 : 0.18),
                radius: isDockPreview
                    ? DockWindowPreviewLayout.shadowRadius
                    : 12,
                y: isDockPreview ? 3 : 7
            )
            .onHover {
                isHovered = $0
                onHover($0)
            }
            .accessibilityLabel("\(window.appName), \(window.windowTitle)")
    }

    @ViewBuilder
    private var preview: some View {
        if let image = window.preview {
            if WindowPreviewLayout.shouldFit(
                windowBounds: CGRect(origin: .zero, size: image.size),
                previewSize: CGSize(
                    width: displayedPreviewWidth,
                    height: displayedPreviewHeight
                )
            ) {
                ZStack(alignment: .top) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(
                            width: displayedPreviewWidth,
                            height: displayedPreviewHeight
                        )
                        .clipped()
                        .blur(radius: 14)
                        .opacity(0.5)

                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(
                            width: displayedPreviewWidth,
                            height: displayedPreviewHeight,
                            alignment: .top
                        )
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
