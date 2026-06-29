import SwiftUI
import SwiftData

// MARK: - ExplanationsSection
struct ExplanationsSection: View {
    
    @ObservedObject var keywordExtractor: KeywordExtractor
    @Binding var currentID: UUID?
    @Binding var pillScrollID: UUID?
    @Binding var isCardsExpanded: Bool
    @Binding var isGroupExpanded: Bool
    @State var isShowPopover = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            
            HStack {
                Text("単語 & フレーズ解説")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.primary)
                Text("タッチして追加")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
                if let error = keywordExtractor.errorMessage {
                    Button(action: {
                        isShowPopover = true
                    }, label: {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                    })
                    .popover(isPresented: $isShowPopover) {
                        Text("エラー: \(error)")
                            .padding()
                            .presentationCompactAdaptation(PresentationAdaptation.popover)
                    }
                }
                if keywordExtractor.isExtracting || keywordExtractor.loadingWord != nil {
                    ProgressView().scaleEffect(0.8)
                }
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .background(Circle().fill(Color(.secondarySystemFill)))
                    .rotationEffect(.degrees(isGroupExpanded ? 90 : 0))
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isGroupExpanded.toggle()
                    isCardsExpanded = false
                }
            }
            
            if isGroupExpanded {
                VStack(spacing: 0) {
                    
                    if keywordExtractor.explanations.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "hand.point.up.left.and.text.fill")
                                .font(.system(size: 30))
                            Text("リアルタイム翻訳で表示された単語やフレーズをタッチして、解説カードを作成します。")
                                .font(.caption)
                                .multilineTextAlignment(.center)
                        }
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(40)
                        .background(Color(.secondarySystemGroupedBackground), in: .rect(corners: .concentric(minimum: 16), isUniform: true))
                        .transition(.blurReplace)
                        
                    } else {
                        VStack(spacing: 0) {
                            TopPillRow(
                                explanations: keywordExtractor.explanations,
                                currentID: $currentID,
                                pillScrollID: $pillScrollID
                            )
                            .padding(.vertical, 5)
                            
                            BottomCardRow(
                                explanations: keywordExtractor.explanations,
                                currentID: $currentID,
                                isCardsExpanded: $isCardsExpanded
                            )
                        }
                        .transition(.blurReplace)
                    }
                }
                .padding(.top, 5)
                .transition(.blurReplace.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: keywordExtractor.explanations.isEmpty)
    }
}


// MARK: - TopPillRow
struct TopPillRow: View {
    let explanations: [KeywordExplanation]
    @Binding var currentID: UUID?
    @Binding var pillScrollID: UUID?
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(explanations) { item in
                    PillButton(
                        title: item.word,
                        isSelected: currentID == item.id
                    ) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            currentID = item.id
                            pillScrollID = item.id
                        }
                    }
                    .id(item.id)
                }
                .transition(.blurReplace)
            }
            .scrollTargetLayout()
        }
        .scrollPosition(id: $pillScrollID, anchor: .center)
        .scrollTargetBehavior(.viewAligned)
        .scrollClipDisabled()
        .padding(.bottom, 8)
    }
}


// MARK: - PillButton
struct PillButton: View {
    @Environment(\.appearsActive) private var appearsActive
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .glassEffect(.regular.tint(isSelected ? .pink : Color(.secondarySystemGroupedBackground)))
        .animation(.easeOut(duration: 0.4), value: isSelected)
    }
}


// MARK: - BottomCardRow
struct BottomCardRow: View {
    let explanations: [KeywordExplanation]
    @Binding var currentID: UUID?
    @Binding var isCardsExpanded: Bool
    @Environment(\.horizontalSizeClass) private var sizeClass
    
    @Environment(\.modelContext) private var modelContext
    @Query private var savedKeywords: [SavedKeyword]
    
    private var savedWordSet: Set<String> {
        Set(savedKeywords.map { $0.word.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) })
    }
    
    var body: some View {
        let savedSet = savedWordSet
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(explanations) { item in
                    let itemWordNormalized = item.word.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                    let isSaved = savedSet.contains(itemWordNormalized)
                    KeywordCard(
                        item: item,
                        isExpanded: $isCardsExpanded,
                        isSaved: isSaved,
                        onToggleSave: {
                            toggleSave(for: item)
                        }
                    )
                    .containerRelativeFrame(
                        .horizontal,
                        count: sizeClass == .regular ? 2 : 1,
                        spacing: 12
                    )
                    .id(item.id)
                }
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .trailing),
                        removal: .opacity
                    )
                    .combined(with: .opacity)
                )
            }
            .scrollTargetLayout()
        }
        .scrollClipDisabled()
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $currentID)
    }
    
    private func toggleSave(for item: KeywordExplanation) {
        if let target = savedKeywords.first(where: { $0.word.lowercased() == item.word.lowercased() }) {
            modelContext.delete(target)
        } else {
            let newSaved = SavedKeyword(
                word: item.word,
                partOfSpeech: item.partOfSpeech,
                meaning: item.meaning,
                explanation: item.explanation,
                example: item.example,
                exampleTranslation: item.exampleTranslation
            )
            modelContext.insert(newSaved)
        }
        try? modelContext.save()
    }
}


// MARK: - KeywordCard
struct KeywordCard: View {
    let item: KeywordExplanation
    @Binding var isExpanded: Bool
    let isSaved: Bool
    let onToggleSave: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                let color = Color.partOfSpeech(item.partOfSpeech)
                Text(item.word)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(item.partOfSpeech)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .foregroundStyle(color)
                    .glassEffect(.clear.tint(color.opacity(0.2)))
                
                Spacer()
                
                Button {
                    onToggleSave()
                } label: {
                    Image(systemName: isSaved ? "star.fill" : "star")
                        .font(.title3)
                        .foregroundStyle(isSaved ? .pink : .primary)
                }
            }
            
            Divider()
            
            HStack(alignment: .center) {
                ZStack(alignment: .leading) {
                    Text(" \n ")
                        .font(.subheadline.weight(.medium))
                        .hidden()
                        .lineLimit(2, reservesSpace: true)
                        .padding(1)
                    Text(item.meaning)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(2)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    Text(item.explanation)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2, reservesSpace: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Label("例文", systemImage: "text.quote")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                        
                        ZStack(alignment: .leading) {
                            Text("\n\n\n")
                                .font(.caption)
                                .lineLimit(3, reservesSpace: true)
                                .hidden()
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.example)
                                    .font(.caption)
                                    .italic()
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                
                                Text(item.exampleTranslation)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemFill), in: .rect(corners: .concentric(minimum: 5), isUniform: true))
                }
                .transition(.opacity)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(corners: .concentric(minimum: 16), isUniform: true))
        .contentShape(.rect(corners: .concentric(minimum: 16), isUniform: true))
        .clipped()
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isExpanded.toggle()
            }
        }
    }
}
