import SwiftUI
import UIKit
import WidgetKit

/// Floating carrier barcode over the app, for the cashier's scanner; tapping outside closes it.
/// The screen goes to full brightness while it's up. Opened from the widget, it also copies the
/// number so it can be pasted into a shop's app.
struct CarrierPopup: View {
    var copyOnAppear = false
    var close: () -> Void
    @State private var copied = false
    @State private var savedBrightness: CGFloat?

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: close)
                .accessibilityLabel("關閉載具條碼")
                .accessibilityAddTraits(.isButton)
            card
                .padding(.horizontal, 16)
        }
        .onAppear {
            if copyOnAppear, let number = Carrier.number { copy(number) }
            savedBrightness = UIScreen.main.brightness
            UIScreen.main.brightness = 1
        }
        .onDisappear {
            if let savedBrightness { UIScreen.main.brightness = savedBrightness }
        }
    }

    private var card: some View {
        VStack(spacing: 16) {
            Label("手機條碼載具", systemImage: "barcode")
                .font(.subheadline.weight(.semibold)).foregroundStyle(Color.gray)
            if let number = Carrier.number {
                CarrierBarcode(number: number, fontSize: 20)
                    .frame(height: 120)
                Button { copy(number) } label: {
                    Label(copied ? "已複製載具號碼" : "複製載具號碼",
                          systemImage: copied ? "checkmark.circle.fill" : "doc.on.doc")
                        .font(.headline)
                        .padding(.horizontal, 20).padding(.vertical, 10)
                        .background(copied ? Color.green : Color.accent, in: Capsule())
                        .foregroundStyle(.white)
                }
            } else {
                Text("還沒設定載具號碼，請到 設定 → 載具 輸入。")
                    .font(.subheadline).foregroundStyle(Color.gray)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
        .environment(\.colorScheme, .light)
    }

    private func copy(_ number: String) {
        UIPasteboard.general.string = number
        copied = true
    }
}

/// 設定 → 載具: enter the number; the widget picks it up.
struct CarrierSettingsView: View {
    @State private var text = Carrier.number ?? ""

    private var normalized: String { Carrier.normalized(text) }
    private var valid: Bool { Carrier.isValid(normalized) }

    var body: some View {
        ThemedForm {
            Section {
                TextField("/ABC1234", text: $text)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
                    .accessibilityLabel("載具號碼")
                    .onChange(of: text) { _, _ in save() }
            } header: {
                Text("手機條碼")
            } footer: {
                if !text.isEmpty && !valid {
                    Text("載具號碼是「/」加 7 碼英數字，例如 /ABC1234。").foregroundStyle(.red)
                } else {
                    Text("在財政部電子發票 App 裡可以看到。存好後可以在桌面加「載具條碼」小工具，點一下就會複製號碼。")
                }
            }
            if valid {
                Section {
                    CarrierBarcode(number: normalized)
                        .frame(height: 70)
                        .padding(12)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
                    Button("顯示條碼") { AppRouter.shared.showCarrier = true }
                }
            }
        }
        .themedBackground()
        .navigationTitle("載具")
    }

    private func save() {
        let new: String? = text.isEmpty ? nil : (valid ? normalized : Carrier.number)
        guard new != Carrier.number else { return }
        Carrier.number = new
        WidgetCenter.shared.reloadAllTimelines()
    }
}
