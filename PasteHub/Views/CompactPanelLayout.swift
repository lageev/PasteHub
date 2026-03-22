import AppKit

enum CompactPanelLayout {
    static let width: CGFloat = 380
    static let fallbackHeight: CGFloat = 480
    static let margin: CGFloat = 10
    static let highDensityPointerRowsPerPage: Int = 10
    private static let highDensityPointerRowHeight: CGFloat = 24
    private static let highDensityPointerRowSpacing: CGFloat = 3
    private static let highDensityPointerListVerticalPadding: CGFloat = 2
    private static let highDensityPointerPanelVerticalPadding: CGFloat = 20

    private static var highDensityPointerPreferredHeight: CGFloat {
        let rows = CGFloat(highDensityPointerRowsPerPage)
        let spacing = CGFloat(max(highDensityPointerRowsPerPage - 1, 0)) * highDensityPointerRowSpacing
        return rows * highDensityPointerRowHeight
            + spacing
            + highDensityPointerListVerticalPadding
            + highDensityPointerPanelVerticalPadding
    }

    static func height(
        for screen: NSScreen?,
        size: CompactPanelSize,
        density: CompactDensity,
        position: CompactPanelPosition
    ) -> CGFloat {
        if density == .high && position == .followMouse {
            return highDensityPointerHeight(for: screen)
        }

        guard let screen else { return fallbackHeight }

        let visibleHeight = max(0, screen.visibleFrame.height - margin * 2)
        let targetHeight = screen.frame.height * size.heightRatio
        return min(targetHeight, visibleHeight)
    }

    private static func highDensityPointerHeight(for screen: NSScreen?) -> CGFloat {
        guard let screen else { return highDensityPointerPreferredHeight }
        let visibleHeight = max(0, screen.visibleFrame.height - margin * 2)
        return min(highDensityPointerPreferredHeight, visibleHeight)
    }
}
