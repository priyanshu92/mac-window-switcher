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
    @ObservedObject var model: SwitcherViewModel
    let onSelect: (Int) -> Void
    let onHover: (Int?) -> Void
    let onClose: (Int) -> Void

    var body: some View {
        Group {
            if model.windows.isEmpty {
                emptyState
            } else if model.isDockPreview {
                HStack(spacing: 8) {
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
                    }
                }
                .padding(6)
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

    private var dockOuterBorder: Color {
        colorScheme == .dark
            ? .white.opacity(0.34)
            : .black.opacity(0.30)
    }

    private var dockInnerHighlight: Color {
        colorScheme == .dark
            ? .white.opacity(0.12)
            : .white.opacity(0.88)
    }

    private var dockPreviewEdge: Color {
        colorScheme == .dark
            ? .white.opacity(0.28)
            : .black.opacity(0.24)
    }

    private var displayedPreviewWidth: CGFloat {
        isDockPreview ? cardWidth - 16 : cardWidth
    }

    private var displayedPreviewHeight: CGFloat {
        isDockPreview ? previewHeight - 8 : previewHeight
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
            .frame(height: 44)
            .background {
                if isDockPreview {
                    Color(nsColor: .windowBackgroundColor)
                }
            }

            preview
                .frame(
                    width: displayedPreviewWidth,
                    height: displayedPreviewHeight
                )
                .clipped()
                .background(.black.opacity(0.24))
                .overlay {
                    if isDockPreview {
                        Rectangle()
                            .strokeBorder(
                                dockPreviewEdge,
                                lineWidth: 1.25
                            )
                    }
                }
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
            .frame(width: cardWidth, height: previewHeight + 44)
                .background(
                    isDockPreview
                        ? Color(nsColor: .windowBackgroundColor)
                        : .black.opacity(0.28)
                )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    isHighlighted
                        ? Color(nsColor: .controlAccentColor)
                        : isDockPreview
                            ? dockOuterBorder
                            : .white.opacity(0.12),
                    lineWidth: isHighlighted ? 4 : isDockPreview ? 1.5 : 1
                )
            }
            .overlay {
                if isDockPreview, !isHighlighted {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .inset(by: 1.5)
                        .stroke(dockInnerHighlight, lineWidth: 1)
                }
            }
            .shadow(
                color: isDockPreview
                    ? .clear
                    : .black.opacity(isHighlighted ? 0.35 : 0.18),
                radius: isDockPreview ? 0 : 12,
                y: isDockPreview ? 0 : 7
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
