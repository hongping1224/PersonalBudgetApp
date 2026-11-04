import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var context

    @State private var exportDocument: BackupDocument?
    @State private var showExporter = false
    // Kept separate from `showImporter`: the picker resets its binding before calling back,
    // so a target stored in the binding itself would already be gone.
    @State private var importTarget: ImportTarget = .backup
    @State private var showImporter = false
    @State private var pendingRestore: BackupFile?
    @State private var showRestoreConfirm = false
    @State private var message: String?
    @State private var localBackups: [URL] = []
    @AppStorage(AccountHistory.monthsKey) private var accountHistoryMonths = AccountHistory.defaultMonths

    enum ImportTarget { case backup, moze }

    /// Backups sitting in the app's own folder (Files → On My iPhone → 記帳本), restorable without the picker.
    private static var documentsFolder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    var body: some View {
        ThemedForm {
            Section("外觀") {
                NavigationLink("主題顏色") { ThemeView() }
            }

            Section("發票") {
                NavigationLink("載具") { CarrierSettingsView() }
            }

            Section {
                NavigationLink("匯率") { ExchangeRatesView() }
            } header: {
                Text("外幣")
            } footer: {
                Text("帳戶可以設定幣別，記帳時就用該帳戶的幣別。跨幣別轉帳時自己輸入轉入金額。預算、統計和淨資產用這裡的匯率換算成新台幣，台幣和外幣之間轉帳時會自動更新成那次的匯率。")
            }

            Section("分類") {
                NavigationLink("支出分類") { CategoryListView(kind: .expense) }
                NavigationLink("收入分類") { CategoryListView(kind: .income) }
            }

            Section {
                Stepper("顯示最近 \(accountHistoryMonths) 個月", value: $accountHistoryMonths, in: 1...36)
            } header: {
                Text("帳戶明細")
            } footer: {
                Text("打開帳戶時預設顯示的範圍（包含本月），可以在帳戶頁上方調整，或拉到底再載入更早的月份。")
            }

            Section {
                NavigationLink("預算規則") { BudgetRuleListView() }
            } footer: {
                Text("記帳時依分類、平日／週末和時間自動選預算；沒有符合的規則時，依過去的紀錄推測。")
            }

            Section("排序") {
                NavigationLink("預算排序") { BudgetOrderView() }
                NavigationLink("帳戶排序") { AccountOrderView() }
            }

            if !localBackups.isEmpty {
                Section {
                    ForEach(localBackups, id: \.self) { url in
                        Button {
                            handleImport(.success(url), target: .backup)
                        } label: {
                            Label("還原「\(url.deletingPathExtension().lastPathComponent)」", systemImage: "arrow.counterclockwise")
                        }
                    }
                } header: {
                    Text("App 資料夾裡的備份")
                } footer: {
                    Text("檔案 App → 我的 iPhone → 記帳本 裡的備份檔。")
                }
            }

            Section {
                Button("匯出備份（JSON）", action: exportBackup)
                Button("從備份還原") { importTarget = .backup; showImporter = true }
            } header: {
                Text("備份")
            } footer: {
                Text("資料只存在這支手機上。建議偶爾匯出備份存到 iCloud 雲碟。")
            }
            // Exporter and importer must hang off different views, or only one of them presents.
            .fileExporter(isPresented: $showExporter, document: exportDocument, contentType: .json,
                          defaultFilename: "記帳本備份-\(Date.now.formatted(.iso8601.year().month().day()))") { result in
                if case .failure(let error) = result { message = error.localizedDescription }
            }

            Section {
                Button("匯入 MOZE CSV") { importTarget = .moze; showImporter = true }
            } footer: {
                Text("在 MOZE 匯出 CSV 後選擇該檔案。紀錄會加到目前的資料裡，重複匯入會產生重複紀錄。")
            }

            Section {
                Text("「嘿 Siri，用記帳本記帳」，然後說「午餐 120」")
                Text("動作按鈕：設定 → 動作按鈕 → 捷徑 → 選「記帳本」裡的「快速記帳」或「開啟記帳畫面」")
            } header: {
                Text("Siri 與捷徑")
            }
            .font(.footnote)
        }
        .themedBackground()
        .navigationTitle("設定")
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: importTarget == .moze ? [.commaSeparatedText, .plainText] : [.json]) { result in
            handleImport(result, target: importTarget)
        }
        // `presenting:` hands the backup to the button; reading pendingRestore inside the action
        // would see nil because dismissal resets the binding first.
        .confirmationDialog("還原會刪除目前所有資料，改成備份裡的內容。", isPresented: $showRestoreConfirm,
                            titleVisibility: .visible, presenting: pendingRestore) { backup in
            Button("還原 \(backup.entries.count) 筆紀錄", role: .destructive) {
                do {
                    try backup.restore(into: context)
                    message = "已還原備份：\(backup.accounts.count) 個帳戶、\(backup.entries.count) 筆紀錄"
                } catch {
                    message = "還原失敗：\(error.localizedDescription)"
                }
                pendingRestore = nil
            }
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("好") {}
        }
        .onAppear {
            localBackups = ((try? FileManager.default.contentsOfDirectory(
                at: Self.documentsFolder, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension.lowercased() == "json" }
                .sorted { $0.lastPathComponent > $1.lastPathComponent }
            #if DEBUG
            // UI tests can't reliably drive the system file picker; this feeds a file in as if picked.
            if let path = UserDefaults.standard.string(forKey: "uitestRestorePath") {
                handleImport(.success(URL(fileURLWithPath: path)), target: .backup)
            }
            #endif
        }
    }

    private func exportBackup() {
        do {
            let data = try BackupFile.encoder.encode(try BackupFile(context: context))
            exportDocument = BackupDocument(data: data)
            showExporter = true
        } catch {
            message = "匯出失敗：\(error.localizedDescription)"
        }
    }

    private func handleImport(_ result: Result<URL, Error>, target: ImportTarget) {
        let url: URL
        switch result {
        case .success(let u): url = u
        case .failure(let error):
            present("無法開啟檔案：\(error.localizedDescription)")
            return
        }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            switch target {
            case .backup:
                pendingRestore = try BackupFile.decoder.decode(BackupFile.self, from: data)
                // When coming from the picker, wait for it to finish dismissing or the dialog is dropped.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { showRestoreConfirm = true }
            case .moze:
                guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else {
                    present("無法讀取檔案的文字編碼")
                    return
                }
                var importer = MozeImporter(context: context)
                let s = try importer.run(csv: text)
                present("匯入完成：\(s.entries) 筆收支、\(s.transfers) 筆轉帳，新增 \(s.newAccounts) 個帳戶、\(s.newCategories) 個分類、\(s.newBudgets) 個預算" + (s.skipped > 0 ? "，略過 \(s.skipped) 列" : ""))
            }
        } catch {
            present("讀取失敗：\(error.localizedDescription)")
        }
    }

    /// Shows an alert once the file picker has finished dismissing.
    private func present(_ text: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { message = text }
    }
}

struct CategoryListView: View {
    let kind: EntryKind
    @Environment(\.modelContext) private var context
    @Query(sort: \EntryCategory.sortOrder) private var all: [EntryCategory]
    @State private var editing: EntryCategory?
    @State private var creating = false

    private var categories: [EntryCategory] { all.filter { $0.kind == kind } }

    var body: some View {
        ThemedList {
            ForEach(categories) { c in
                Button { editing = c } label: {
                    HStack(spacing: 12) {
                        SymbolBadge(symbol: c.symbol, color: Color(hex: c.colorHex), size: 36)
                        Text(c.name)
                        Spacer()
                        Text("\(c.entries?.count ?? 0) 筆").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .tint(.primary)
            }
            .onMove { from, to in
                var items = categories
                items.move(fromOffsets: from, toOffset: to)
                for (i, c) in items.enumerated() { c.sortOrder = i }
                try? context.save()
            }
        }
        .themedBackground()
        .navigationTitle("\(kind.title)分類")
        .toolbar {
            EditButton()
            Button { creating = true } label: { Image(systemName: "plus") }
        }
        .sheet(item: $editing) { CategoryEditor(category: $0, kind: kind) }
        .sheet(isPresented: $creating) { CategoryEditor(category: nil, kind: kind) }
    }
}

struct CategoryEditor: View {
    let category: EntryCategory?
    let kind: EntryKind

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var all: [EntryCategory]

    @State private var name = ""
    @State private var symbol = "tag"
    @State private var colorHex = Palette.colors[0]
    @State private var confirmDelete = false
    @State private var mergeTarget: EntryCategory?

    private var mergeTargets: [EntryCategory] {
        all.filter { $0.kind == kind && $0.id != category?.id }.sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        NavigationStack {
            ThemedForm {
                Section {
                    HStack {
                        Spacer()
                        SymbolBadge(symbol: symbol, color: Color(hex: colorHex), size: 64)
                        Spacer()
                    }
                    TextField("名稱", text: $name)
                }
                Section("顏色") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(Palette.colors, id: \.self) { hex in
                            Circle().fill(Color(hex: hex)).frame(width: 34, height: 34)
                                .overlay(Circle().stroke(Color.primary, lineWidth: hex == colorHex ? 3 : 0).padding(-3))
                                .onTapGesture { colorHex = hex }
                        }
                    }
                    .padding(.vertical, 6)
                }
                Section {
                    SymbolPicker(symbol: $symbol, color: Color(hex: colorHex))
                }
                if let category {
                    if !mergeTargets.isEmpty {
                        Section {
                            Menu {
                                ForEach(mergeTargets) { c in
                                    Button(c.name) { mergeTarget = c }
                                }
                            } label: {
                                Label("合併到其他分類…", systemImage: "arrow.triangle.merge")
                            }
                        } footer: {
                            Text("把這個分類的紀錄全部移到另一個分類，然後刪除這個分類。")
                        }
                    }
                    Section {
                        Button("刪除分類", role: .destructive) { confirmDelete = true }
                    } footer: {
                        if let n = category.entries?.count, n > 0 {
                            Text("有 \(n) 筆紀錄使用這個分類，刪除後會變成「未分類」。")
                        }
                    }
                }
            }
            .themedBackground()
            .navigationTitle(category == nil ? "新增分類" : "編輯分類")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存", action: save).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("刪除「\(name)」？", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("刪除", role: .destructive) {
                    if let category { context.delete(category); try? context.save() }
                    dismiss()
                }
            }
            .confirmationDialog("合併分類", isPresented: Binding(get: { mergeTarget != nil },
                                                             set: { if !$0 { mergeTarget = nil } }),
                                titleVisibility: .visible, presenting: mergeTarget) { target in
                Button("合併到「\(target.name)」", role: .destructive) {
                    if let category { CategoryMerge.merge(category, into: target, context: context) }
                    dismiss()
                }
            } message: { target in
                Text("「\(name)」的 \(category?.entries?.count ?? 0) 筆紀錄會移到「\(target.name)」。")
            }
            .onAppear {
                if let category {
                    name = category.name
                    symbol = category.symbol
                    colorHex = category.colorHex
                }
            }
        }
    }

    private func save() {
        let target = category ?? {
            let c = EntryCategory(name: "", symbol: symbol, colorHex: colorHex, kind: kind,
                                  sortOrder: (all.map(\.sortOrder).max() ?? 0) + 1)
            context.insert(c)
            return c
        }()
        target.name = name.trimmingCharacters(in: .whitespaces)
        target.symbol = symbol
        target.colorHex = colorHex
        try? context.save()
        dismiss()
    }
}

enum CategoryMerge {
    /// Moves every entry of `source` to `target`, then deletes `source`.
    static func merge(_ source: EntryCategory, into target: EntryCategory, context: ModelContext) {
        for e in source.entries ?? [] { e.category = target }
        target.useCount += source.useCount
        context.delete(source)
        try? context.save()
    }
}
