import SwiftUI

/// 設定 → 匯率: TWD for one unit of each currency. New entries use these; recorded entries keep
/// the rate they were saved with.
struct ExchangeRatesView: View {
    @State private var texts: [String: String] = [:]

    var body: some View {
        ThemedForm {
            Section {
                ForEach(Currency.all.filter { $0.code != Currency.base }) { c in
                    HStack {
                        Text("1 \(c.code)").monospaced()
                        Text(c.name).foregroundStyle(.secondary)
                        Spacer()
                        Text("=").foregroundStyle(.secondary)
                        TextField("0", text: binding(c.code))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                            .accessibilityLabel("\(c.code) 匯率")
                        Text("TWD").foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("只用來把外幣換算成新台幣合計（預算、統計、淨資產），不會連網。台幣和外幣之間轉帳後會更新成那次換匯的匯率，也可以自己修改。已記下的紀錄保留當時的匯率。")
            }
        }
        .themedBackground()
        .navigationTitle("匯率")
        .onAppear {
            for c in Currency.all where c.code != Currency.base {
                let rate = Currency.rate(c.code)
                // Small rates like VND need more than two decimals.
                texts[c.code] = rate >= 0.1 ? Money.plain(rate) : String(rate)
            }
        }
    }

    private func binding(_ code: String) -> Binding<String> {
        Binding(get: { texts[code] ?? "" }, set: { text in
            texts[code] = text
            if let v = Double(text.replacingOccurrences(of: ",", with: "")), v > 0 { Currency.setRate(v, for: code) }
        })
    }
}
