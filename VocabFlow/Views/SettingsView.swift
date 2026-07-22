import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allCards: [FlashCard]

    @State private var apiKey = APISettings.kimiAPIKey
    @State private var selectedModel = APISettings.kimiModel
    @State private var showKey = false
    @State private var saved = false

    @State private var exportDocument: BackupDocument?
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var showImportOptions = false
    @State private var pendingImportData: Data?
    @State private var backupAlertTitle = ""
    @State private var backupAlertMessage = ""
    @State private var showBackupAlert = false

    var body: some View {
        NavigationStack {
            Form {
                apiSection
                modelSection
                saveSection
                statusSection
                importGuideSection
                backupSection
            }
            .navigationTitle("设置")
            .dismissKeyboardOnScroll()
            .keyboardDoneButton()
            .alert("已保存", isPresented: $saved) {
                Button("好", role: .cancel) {}
            }
            .alert(backupAlertTitle, isPresented: $showBackupAlert) {
                Button("好", role: .cancel) {}
            } message: {
                Text(backupAlertMessage)
            }
            .confirmationDialog("选择导入方式", isPresented: $showImportOptions, titleVisibility: .visible) {
                Button("合并导入（保留现有卡片）") {
                    performMergeImport()
                }
                Button("替换全部", role: .destructive) {
                    performReplaceImport()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("合并：同 ID 更新，新卡片追加。替换：清空现有词库后导入。")
            }
            .fileExporter(
                isPresented: $showExporter,
                document: exportDocument,
                contentType: .json,
                defaultFilename: BackupService.defaultFilename
            ) { result in
                if case .failure(let error) = result {
                    showBackupResult(title: "导出失败", message: error.localizedDescription)
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.json]
            ) { result in
                handleImportSelection(result)
            }
        }
    }

    private var apiSection: some View {
        Section {
            HStack {
                if showKey {
                    TextField("留空则使用默认 Key", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                } else {
                    SecureField("留空则使用默认 Key", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                }

                Button {
                    showKey.toggle()
                } label: {
                    Image(systemName: showKey ? "eye.slash" : "eye")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Kimi API Key")
        } footer: {
            Text("填写你自己的 Key 会优先使用；留空则自动使用内置默认 Key。")
        }
    }

    private var modelSection: some View {
        Section("模型") {
            Picker("模型", selection: $selectedModel) {
                ForEach(APISettings.availableModels, id: \.self) { model in
                    Text(model).tag(model)
                }
            }
        }
    }

    private var saveSection: some View {
        Section {
            Button("保存设置") {
                APISettings.kimiAPIKey = apiKey
                APISettings.kimiModel = selectedModel
                saved = true
            }
        }
    }

    private var statusSection: some View {
        Section("当前状态") {
            Label {
                Text(APISettings.keySourceDescription)
            } icon: {
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)
            }

                    if APISettings.canUseKimi {
                        Text("可以正常使用 AI 制卡")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("未配置 API Key，无法制卡")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
        }
    }

    private var importGuideSection: some View {
        Group {
            Section {
                Label("Safari、备忘录", systemImage: "square.and.arrow.up")
                Label("分享面板选 VocabFlow", systemImage: "checkmark.circle")
            } header: {
                Text("支持分享导入")
            }

            Section {
                Label("Apple Books、番茄小说等", systemImage: "book.closed")
                Label("选中文字 → 点「拷贝」", systemImage: "doc.on.doc")
                Label("打开 VocabFlow → 自动填入", systemImage: "arrow.right.circle")
            } header: {
                Text("请用拷贝导入")
            } footer: {
                Text("这些 App 不使用 iOS 系统分享，第三方扩展无法出现在菜单里。这是 App 和系统的限制，不是 VocabFlow 的配置问题。拷贝后打开本 App 即可制卡。")
            }
        }
    }

    private var backupSection: some View {
        Section {
            Button {
                exportBackup()
            } label: {
                Label("导出备份", systemImage: "square.and.arrow.up")
            }

            Button {
                showImporter = true
            } label: {
                Label("导入备份", systemImage: "square.and.arrow.down")
            }
        } header: {
            Text("数据备份")
        } footer: {
            Text("导出为 JSON 文件，可通过 AirDrop、文件 App 保存或换机恢复。个人免费开发者账号不支持 iCloud，请用备份文件在多设备间同步。当前词库：\(allCards.count) 张卡片。")
        }
    }

    private var statusIcon: String {
        if APISettings.canUseKimi { "checkmark.circle.fill" }
        else { "exclamationmark.circle" }
    }

    private var statusColor: Color {
        if APISettings.canUseKimi { .green }
        else { .orange }
    }

    private func exportBackup() {
        do {
            let data = try BackupService.export(cards: allCards)
            exportDocument = BackupDocument(data: data)
            showExporter = true
        } catch {
            showBackupResult(title: "导出失败", message: error.localizedDescription)
        }
    }

    private func handleImportSelection(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            do {
                pendingImportData = try BackupDocumentSupport.readData(from: url)
                showImportOptions = true
            } catch {
                showBackupResult(title: "读取失败", message: error.localizedDescription)
            }
        case .failure(let error):
            showBackupResult(title: "导入失败", message: error.localizedDescription)
        }
    }

    private func performMergeImport() {
        guard let data = pendingImportData else { return }
        do {
            let result = try BackupService.importMerge(data: data, into: modelContext)
            showBackupResult(
                title: "导入完成",
                message: "新增 \(result.added) 张，更新 \(result.updated) 张。"
            )
        } catch {
            showBackupResult(title: "导入失败", message: error.localizedDescription)
        }
        pendingImportData = nil
    }

    private func performReplaceImport() {
        guard let data = pendingImportData else { return }
        do {
            let count = try BackupService.importReplace(data: data, into: modelContext)
            showBackupResult(title: "导入完成", message: "已替换为 \(count) 张卡片。")
        } catch {
            showBackupResult(title: "导入失败", message: error.localizedDescription)
        }
        pendingImportData = nil
    }

    private func showBackupResult(title: String, message: String) {
        backupAlertTitle = title
        backupAlertMessage = message
        showBackupAlert = true
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: FlashCard.self, inMemory: true)
}
