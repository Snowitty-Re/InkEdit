import AppKit
import SwiftUI

/// Warm paper and mineral greens, with native dark-appearance support.
enum InkTheme {
    static let paper = Color(nsColor: paperColor)
    static let canvas = Color(nsColor: adaptive(0xF5F3ED, 0x202421))
    static let sidebar = Color(nsColor: adaptive(0xECEEE7, 0x252B26))
    static let ink = Color(nsColor: adaptive(0x303B34, 0xE5E7DE))
    static let muted = Color(nsColor: adaptive(0x70796E, 0xA7B0A3))
    static let sage = Color(nsColor: adaptive(0x526D59, 0xA2B99B))
    static let line = Color(nsColor: adaptive(0xDDE1D6, 0x3C453E))
    static let paperColor = adaptive(0xFAF9F4, 0x1C211E)

    static func editorial(_ size: CGFloat) -> Font { .custom("Songti SC", size: size) }

    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(
                srgbRed: CGFloat((value >> 16) & 255) / 255,
                green: CGFloat((value >> 8) & 255) / 255,
                blue: CGFloat(value & 255) / 255, alpha: 1)
        }
    }
}

extension View {
    func inkPanel() -> some View {
        background(InkTheme.paper).foregroundStyle(InkTheme.ink).tint(InkTheme.sage)
    }
}

enum InkAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: Self { self }
    var title: String {
        switch self {
        case .system: "跟随系统"
        case .light: "淡雅纸白"
        case .dark: "静夜墨色"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

struct InkSettingsView: View {
    @AppStorage("inkedit.appearance") private var appearance = InkAppearance.system
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 12) {
                Image("InkMark").resizable().frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text("InkEdit").font(InkTheme.editorial(26))
                    Text("让写作回归文字本身。").foregroundStyle(InkTheme.muted)
                }
            }
            Picker("界面外观", selection: $appearance) {
                ForEach(InkAppearance.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Text("云端连接按作品配置，可在作品的「云端同步」中管理。")
                .font(.callout).foregroundStyle(InkTheme.muted)
        }
        .padding(32).frame(width: 440).inkPanel()
        .preferredColorScheme(appearance.colorScheme)
    }
}
