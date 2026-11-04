import SwiftUI

/// 設定 → 主題顏色: one light theme and one dark theme. 跟隨系統 switches between them with the phone;
/// 淺色 / 深色 always use one. A choice applies right away, this page included.
struct ThemeView: View {
    @AppStorage(AppTheme.lightKey, store: AppTheme.store) private var lightThemeID = AppTheme.light.id
    @AppStorage(AppTheme.darkKey, store: AppTheme.store) private var darkThemeID = AppTheme.dark.id
    @AppStorage(AppTheme.appearanceKey, store: AppTheme.store) private var appearance = AppAppearance.system.rawValue

    private var mode: AppAppearance { AppAppearance(rawValue: appearance) ?? .system }
    private var light: AppTheme { AppTheme.lightNamed(lightThemeID) }
    private var dark: AppTheme { AppTheme.darkNamed(darkThemeID) }

    var body: some View {
        ThemedList {
            Section {
                Picker("外觀", selection: $appearance) {
                    ForEach(AppAppearance.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("外觀")
            } footer: {
                Text(mode == .system ? "跟隨手機的淺色／深色模式，各用下面選的主題。" : "一直使用\(mode.title)主題。")
            }

            if mode != .dark {
                themeSection("淺色主題", themes: AppTheme.lightThemes, selected: light) { lightThemeID = $0 }
            }
            if mode != .light {
                themeSection("深色主題", themes: AppTheme.darkThemes, selected: dark) { darkThemeID = $0 }
            }
        }
        .themedBackground()
        .navigationTitle("主題顏色")
    }

    private func themeSection(_ title: String, themes: [AppTheme], selected: AppTheme,
                              choose: @escaping (String) -> Void) -> some View {
        Section {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 12)], spacing: 12) {
                ForEach(themes) { theme in
                    Button { choose(theme.id) } label: { swatch(theme, isOn: theme.id == selected.id) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(title) \(theme.name)")
                }
            }
            .padding(.vertical, 6)
            preview(selected)
        } header: {
            Text(title)
        }
    }

    /// Drawn in the theme's own colors, so dark themes look dark even in light mode.
    private func swatch(_ theme: AppTheme, isOn: Bool) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Circle().fill(Color(hex: theme.accent)).frame(width: 24, height: 24)
                Circle().fill(Color(hex: theme.expense)).frame(width: 14, height: 14)
                Circle().fill(Color(hex: theme.income)).frame(width: 14, height: 14)
            }
            Text(theme.name).font(.caption)
                .foregroundStyle(theme.isDark ? Color.white : Color.black)
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(Color(hex: theme.surface), in: Capsule())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(hex: theme.background), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: theme.accent), lineWidth: isOn ? 3 : 0))
    }

    private func preview(_ theme: AppTheme) -> some View {
        let text: Color = theme.isDark ? .white : .black
        return VStack(spacing: 8) {
            VStack(spacing: 8) {
                HStack {
                    Text("便當").foregroundStyle(text)
                    Spacer()
                    Text("$120").foregroundStyle(Color(hex: theme.expense)).monospacedDigit()
                }
                HStack {
                    Text("薪水").foregroundStyle(text)
                    Spacer()
                    Text("$45,000").foregroundStyle(Color(hex: theme.income)).monospacedDigit()
                }
            }
            .padding(12)
            .background(Color(hex: theme.surface), in: RoundedRectangle(cornerRadius: 10))
            HStack {
                Text("食物").font(.subheadline).foregroundStyle(text)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Color(hex: theme.fill), in: RoundedRectangle(cornerRadius: 10))
                Spacer()
                Text("記一筆")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20).padding(.vertical, 8)
                    .background(Color(hex: theme.accent), in: Capsule())
            }
        }
        .padding(10)
        .background(Color(hex: theme.background), in: RoundedRectangle(cornerRadius: 14))
    }
}
