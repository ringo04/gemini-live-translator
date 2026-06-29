import SwiftUI


// MARK: - Ripple
struct Ripple: View {
    
    @State private var animate = false
    
    var body: some View {
        Circle()
            .fill(Color.pink.opacity(0.35))
            .frame(width: 80, height: 80)
            .scaleEffect(animate ? 2.0 : 1.0)
            .opacity(animate ? 0 : 1)
            .onAppear {
                withAnimation(.easeOut(duration: 2)) {
                    animate = true
                }
            }
    }
}


// MARK: - Color Extension
extension Color {
    static func partOfSpeech(_ pos: String) -> Color {
        let normalized = pos.lowercased()
        if normalized.contains("noun") || normalized.contains("名詞") {
            return .blue
        } else if normalized.contains("verb") || normalized.contains("動詞") {
            return .green
        } else if normalized.contains("adj") || normalized.contains("形容") {
            return .orange
        } else if normalized.contains("idiom") || normalized.contains("phrase") || normalized.contains("慣用") {
            return .purple
        } else {
            return .cyan
        }
    }
}


// MARK: - Locale.LanguageCode Extension
extension Locale.LanguageCode {
    var localizedName: String {
        Locale.current.localizedString(forLanguageCode: self.identifier) ?? self.identifier
    }
}
