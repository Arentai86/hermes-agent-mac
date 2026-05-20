import AppKit
import SwiftUI

enum OpenzenBranding {
    static let website = "www.openzen.info"
    static let footerText = "developed by Openzen \(website)"
    static let background = Color(nsColor: NSColor(calibratedRed: 0.965, green: 0.972, blue: 0.982, alpha: 1))
    static let surface = Color(nsColor: .white)
    static let border = Color(nsColor: NSColor(calibratedWhite: 0.84, alpha: 1))

    static var logoImage: NSImage? {
        guard let url = Bundle.main.url(forResource: "OpenzenMark", withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
}

struct OpenzenLogoView: View {
    var width: CGFloat = 68
    var height: CGFloat = 45

    var body: some View {
        Group {
            if let image = OpenzenBranding.logoImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "bolt.circle.fill")
                    .font(.system(size: min(width, height), weight: .semibold))
                    .foregroundStyle(.primary)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(OpenzenBranding.border.opacity(0.7), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
        .accessibilityLabel("Openzen")
    }
}

struct OpenzenBrandFooter: View {
    var font: Font = .caption

    var body: some View {
        Text(OpenzenBranding.footerText)
            .font(font)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity)
            .accessibilityLabel(OpenzenBranding.footerText)
    }
}

struct OpenzenBrandedContainer<Content: View>: View {
    var logoWidth: CGFloat = 68
    var logoHeight: CGFloat = 45
    var footerFont: Font = .caption
    let content: Content

    init(
        logoWidth: CGFloat = 68,
        logoHeight: CGFloat = 45,
        footerFont: Font = .caption,
        @ViewBuilder content: () -> Content
    ) {
        self.logoWidth = logoWidth
        self.logoHeight = logoHeight
        self.footerFont = footerFont
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            OpenzenLogoView(width: logoWidth, height: logoHeight)
                .padding(.top, 12)
                .padding(.bottom, 8)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            OpenzenBrandFooter(font: footerFont)
                .padding(.horizontal, 18)
                .padding(.top, 6)
                .padding(.bottom, 10)
        }
        .background(OpenzenBranding.background.ignoresSafeArea())
        .preferredColorScheme(.light)
    }
}
