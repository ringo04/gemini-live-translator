import SwiftUI
import SwiftData


// MARK: - SavedContentSheet
struct SavedContentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = 0
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("表示切り替え", selection: $selectedTab) {
                    Text("単語帳").tag(0)
                    Text("翻訳履歴").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()
                
                if selectedTab == 0 {
                    SavedKeywordsListView()
                } else {
                    TranslationHistoryListView()
                }
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("保存")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
                ToolbarItem(placement: .cancellationAction) { EditButton() }
            }
        }
    }
}


// MARK: - SavedKeywordsListView
struct SavedKeywordsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedKeyword.savedAt, order: .reverse) private var savedKeywords: [SavedKeyword]
    
    @State private var searchText = ""
    
    private var filteredKeywords: [SavedKeyword] {
        if searchText.isEmpty {
            return savedKeywords
        }
        return savedKeywords.filter { keyword in
            keyword.word.localizedStandardContains(searchText) ||
            keyword.meaning.localizedStandardContains(searchText) ||
            keyword.partOfSpeech.localizedStandardContains(searchText)
        }
    }
    
    var body: some View {
        ZStack {
            if filteredKeywords.isEmpty {
                if searchText.isEmpty {
                    ContentUnavailableView(
                        "保存された単語はありません",
                        systemImage: "star.slash",
                        description: Text("解説カードの星マークをタップすると、ここに保存されます。")
                    )
                } else {
                    ContentUnavailableView.search(text: searchText)
                }
            } else {
                List {
                    ForEach(filteredKeywords) { keyword in
                        NavigationLink(destination: KeywordDetailView(keyword: keyword)) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(keyword.partOfSpeech)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(Color.partOfSpeech(keyword.partOfSpeech))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .glassEffect(.clear.tint(Color.partOfSpeech(keyword.partOfSpeech).opacity(0.2)))
                                
                                Text(keyword.word)
                                    .font(.headline)
                                
                                Text(keyword.meaning)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .onDelete(perform: deleteKeywords)
                }
            }
        }
        .ignoresSafeArea(edges: [.bottom])
        .animation(.easeInOut(duration: 0.3), value: filteredKeywords)
        .searchable(text: $searchText, prompt: "単語を検索")
    }
    private func deleteKeywords(at offsets: IndexSet) {
        let keywordsToDelete = offsets.map { filteredKeywords[$0] }
        keywordsToDelete.forEach { modelContext.delete($0) }
    }
}


// MARK: - KeywordDetailView
struct KeywordDetailView: View {
    let keyword: SavedKeyword
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                
                VStack(alignment: .leading, spacing: 12) {
                    Text(keyword.partOfSpeech)
                        .bold()
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .glassEffect(.clear.tint(Color.partOfSpeech(keyword.partOfSpeech).opacity(0.2)))
                        .foregroundStyle(Color.partOfSpeech(keyword.partOfSpeech))
                    Text(keyword.word)
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(.primary)
                    
                    Text(keyword.meaning)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.primary)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 4)
                
                VStack(alignment: .leading, spacing: 10) {
                    Label("解説", systemImage: "doc.text.magnifyingglass")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.primary.opacity(0.5))
                    
                    Text(keyword.explanation)
                        .font(.body)
                        .lineSpacing(8)
                        .foregroundStyle(.primary)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground), in: .rect(corners: .concentric(minimum: 16), isUniform: true))
                HStack(spacing: 16) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.partOfSpeech(keyword.partOfSpeech).opacity(0.6))
                        .frame(width: 4)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Label("例文", systemImage: "text.quote")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        Text(keyword.example)
                            .font(.body)
                            .italic()
                            .lineSpacing(4)
                            .foregroundStyle(.primary)
                        
                        Text(keyword.exampleTranslation)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(24)
            .containerShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("単語")
        .navigationBarTitleDisplayMode(.inline)
    }
}


// MARK: - TranslationHistoryListView
struct TranslationHistoryListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TranslationSession.date, order: .reverse) private var sessions: [TranslationSession]
    
    @State private var searchText = ""
    
    private var filteredSessions: [TranslationSession] {
        if searchText.isEmpty {
            return sessions
        }
        return sessions.filter { session in
            session.translatedText.localizedStandardContains(searchText) ||
            session.originalText.localizedStandardContains(searchText) ||
            session.targetLanguage.localizedName.localizedStandardContains(searchText)
        }
    }
    
    var body: some View {
        ZStack {
            if sessions.isEmpty {
                ContentUnavailableView(
                    "翻訳履歴はありません",
                    systemImage: "text.page.slash",
                    description: Text("翻訳を行うと、ここに履歴が保存されます。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredSessions.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                List {
                    ForEach(filteredSessions) { session in
                        NavigationLink(destination: TranslationSessionDetailView(session: session)) {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(session.date.formatted(date: .numeric, time: .shortened))
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                    Text(session.targetLanguage.localizedName)
                                        .font(.caption2.weight(.bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .foregroundStyle(.pink)
                                        .glassEffect(.clear.tint(.pink.opacity(0.2)))
                                    Spacer()
                                }
                                
                                Text(session.translatedText)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(2, reservesSpace: true)
                                    .foregroundStyle(.primary)
                                
                                Text(session.originalText)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .onDelete(perform: deleteSessions)
                }
            }
        }
        .ignoresSafeArea(edges: [.bottom])
        .animation(.easeInOut(duration: 0.3), value: filteredSessions)
        .searchable(text: $searchText, placement: .toolbar, prompt: "翻訳履歴を検索")
    }
    
    private func deleteSessions(at offsets: IndexSet) {
        for index in offsets {
            let session = filteredSessions[index]
            modelContext.delete(session)
        }
    }
}


// MARK: - TranslationSessionDetailView
struct TranslationSessionDetailView: View {
    let session: TranslationSession
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                
                HStack(spacing: 10) {
                    Label("音声入力", systemImage: "mic.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    
                    Image(systemName: "arrow.right")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.pink.opacity(0.4))
                    
                    Text(session.targetLanguage.localizedName)
                        .font(.footnote.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .foregroundStyle(.pink)
                        .glassEffect(.clear.tint(.pink.opacity(0.2)))
                    
                    Spacer()
                }
                
                VStack(alignment: .leading, spacing: 10) {
                    Label("音声入力", systemImage: "mic.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    
                    Text(session.originalText)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(16)
                .background(Color(.secondarySystemGroupedBackground), in: .rect(corners: .concentric(minimum: 16), isUniform: true))
                
                Image(systemName: "arrow.down")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.pink.opacity(0.4))
                
                VStack(alignment: .leading, spacing: 10) {
                    Label("翻訳結果", systemImage: "translate")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.pink)
                    
                    Text(session.translatedText)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(16)
                .background(.pink.opacity(0.07), in: .rect(corners: .concentric(minimum: 16), isUniform: true))
                
                .background {
                    ZStack {
                        Color(.white)
                        Color(.pink.opacity(0.08))
                    }
                }
                .clipShape(.rect(corners: .concentric(minimum: 16), isUniform: true))
            }
            .padding(20)
            .containerShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        }
        .ignoresSafeArea(edges: [.bottom])
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(
            session.date.formatted(.dateTime.year().month().day().hour().minute())
        )
        .navigationBarTitleDisplayMode(.large)
    }
}

