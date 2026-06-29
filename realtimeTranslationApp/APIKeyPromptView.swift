import SwiftUI

struct APIKeyPromptView: View {
    
    @Binding var apiKey: String
    @State private var inputKey: String = ""
    @State private var isShowingKey: Bool = false
    @State private var isValidating: Bool = false
    @State private var errorMessage: String? = nil
    
    var body: some View {
        
        VStack(spacing: 24) {
            
            Spacer()
            
            Image(systemName: "key.fill")
                .font(.system(size: 60))
                .foregroundColor(.pink)
            
            Text("Gemini API Keyを設定してください")
                .font(.title3.bold())
            
            Text("Gemini API Keyを入力すると\nリアルタイム翻訳機能を利用できます")
                .multilineTextAlignment(.center)
            
            Link(destination: URL(string: "https://aistudio.google.com/app/api-keys")!) {
                Label("Google AI Studioを開く", systemImage: "arrow.up.forward.app")
            }
            .font(.subheadline)
            .foregroundColor(.secondary)
            
            VStack(alignment: .leading) {
                
                HStack {
                    
                    if isShowingKey {
                        TextField("Gemini API Key", text: $inputKey)
                            .textFieldStyle(.plain)
                    } else {
                        SecureField("Gemini API Key", text: $inputKey)
                            .textFieldStyle(.plain)
                    }
                    
                    Button {
                        isShowingKey.toggle()
                    } label: {
                        Image(systemName: isShowingKey ? "eye.slash.fill" : "eye.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(ConcentricRectangle(corners: .concentric(minimum: 16)))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.done)
                .onSubmit {
                    validateAndSave()
                }
                .disabled(isValidating)
                
                if let errorMessage = errorMessage {
                    HStack {
                        
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                            .padding(.horizontal, 4)
                            .transition(.blurReplace)
                        
                        Spacer()
                        
                    }
                }
            }
            .frame(maxWidth: 400)
            
            Spacer()
            
            Button(action: validateAndSave) {
                Group {
                    if isValidating {
                        ProgressView()
                    } else {
                    Text("保存")
                        .bold()
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .foregroundColor(isValidating || inputKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .pink : .white)
            }
            .buttonStyle(.glassProminent)
            .tint(.pink)
            .disabled(isValidating || inputKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .frame(maxWidth: 400)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .animation(.easeInOut(duration: 0.25), value: errorMessage)
        .animation(.easeInOut(duration: 0.25), value: inputKey)
        .onAppear {
            inputKey = apiKey
        }
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
                    withAnimation {
                        apiKey = trimmedKey
                    }
                } else {
                    errorMessage = "無効なAPI Keyです。入力内容を確認してください。"
                }
            }
        }
    }
}
