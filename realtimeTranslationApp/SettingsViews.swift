import SwiftUI
import SwiftData


// MARK: - SettingSheet
struct SettingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var isShowingConfirmation = false
    
    @Binding var apiKey: String
    @ObservedObject var keywordExtractor: KeywordExtractor
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        ApiKeyEditView(apiKey: $apiKey)
                    } label: {
                        Text("API Keyを編集")
                    }
                } header: {
                    Text("Google AI API Key")
                }

                
                Section {
                    Button(role: .destructive) {
                        isShowingConfirmation = true
                    } label: {
                        Text("データを削除する")
                    }
                } header: {
                    Text("単語帳と翻訳履歴を全て削除する")
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
            }
            .alert("データの削除", isPresented: $isShowingConfirmation) {
                Button("データを削除する", role: .destructive) {
                    try? modelContext.delete(model: SavedKeyword.self)
                    try? modelContext.delete(model: TranslationSession.self)
                    
                    dismiss()
                    
                    Task {
                        try? await Task.sleep(for: .seconds(0.15))
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                            apiKey = ""
                        }
                    }
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("この操作は取り消せません。\n本当に削除しますか？")
            }
        }
    }
}


// MARK: - ApiKeyEditView
struct ApiKeyEditView: View {
    @Binding var apiKey: String
    @Environment(\.dismiss) private var dismiss
    
    @State private var inputKey: String
    @State private var isShowingKey: Bool = false
    @State private var isValidating: Bool = false
    @State private var errorMessage: String?
    
    init(apiKey: Binding<String>) {
        self._apiKey = apiKey
        self._inputKey = State(initialValue: apiKey.wrappedValue)
    }
    
    var body: some View {
        Form {
            Section {
                HStack {
                    if isShowingKey {
                        TextField("API Keyを入力", text: $inputKey)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    } else {
                        SecureField("Gemini API Key", text: $inputKey)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                    
                    Button {
                        isShowingKey.toggle()
                    } label: {
                        Image(systemName: isShowingKey ? "eye.slash.fill" : "eye.fill")
                            .foregroundStyle(.secondary)
                            .contentTransition(.opacity)
                    }
                    .buttonStyle(.plain)
                }
                .disabled(isValidating)
            } header: {
                Text("Google AI API Key")
            } footer: {
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                } else {
                    Text("取得したGemini API Keyを入力してください。")
                }
            }
        }
        .navigationTitle("API Keyの編集")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(action: validateAndSave) {
                    ZStack {
                        ProgressView()
                            .opacity(isValidating ? 1 : 0)
                            .accessibilityHidden(!isValidating)
                        
                        Image(systemName: "checkmark")
                            .opacity(isValidating ? 0 : 1)
                            .accessibilityHidden(isValidating)
                    }
                }
                .buttonStyle(.glassProminent)
                .tint(.pink)
                .disabled(isValidating || inputKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .animation(.easeInOut(duration: 0.2), value: isValidating)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: errorMessage)
    }
    
    private func validateAndSave() {
        let trimmedKey = inputKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return }
        
        isValidating = true
        errorMessage = nil
        
        Task {
            let isValid = await APIKeyValidator.validate(key: trimmedKey)
            await MainActor.run {
                isValidating = false
                if isValid {
                    apiKey = trimmedKey
                    dismiss()
                } else {
                    errorMessage = "無効なAPI Keyです。入力した内容を確認してください。"
                }
            }
        }
    }
}
