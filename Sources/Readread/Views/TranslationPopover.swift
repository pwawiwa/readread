import SwiftUI

struct TranslationPopover: View {
    let selectedText: String
    let selectionRect: CGRect
    @Binding var isPresented: Bool
    
    @EnvironmentObject var dictionaryServiceWrapper: DictionaryServiceWrapper
    @AppStorage("sourceLanguage") private var sourceLangId: String = DictionaryService.Language.english.rawValue
    @AppStorage("targetLanguage") private var targetLangId: String = DictionaryService.Language.indonesian.rawValue
    
    @State private var selectedMode: Mode = .translate
    
    enum Mode: String, CaseIterable {
        case define = "Define"
        case translate = "Translate"
    }
    
    var sourceLanguage: DictionaryService.Language { DictionaryService.Language(rawValue: sourceLangId) ?? .english }
    var targetLanguage: DictionaryService.Language { DictionaryService.Language(rawValue: targetLangId) ?? .indonesian }
    
    var translationResult: DictionaryService.TranslationResult? {
        let cleanText = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanText.isEmpty { return nil }
        
        if selectedMode == .define {
            return dictionaryServiceWrapper.service.define(word: cleanText, language: sourceLanguage)
        } else {
            return dictionaryServiceWrapper.service.translate(word: cleanText, from: sourceLanguage, to: targetLanguage)
        }
    }
    
    var body: some View {
        GeometryReader { geo in
            let popoverWidth: CGFloat = 360
            let popoverHeight: CGFloat = min(260, geo.size.height * 0.4)
            
            let rawX = selectionRect.origin.x
            let rawY = selectionRect.origin.y
            
            let posX = clamp(rawX, min: popoverWidth/2 + 20, max: max(popoverWidth/2 + 20, geo.size.width - popoverWidth/2 - 20))
            
            let preferredY = (rawY - popoverHeight/2 - 30 > 60) ? (rawY - popoverHeight/2 - 20) : (rawY + popoverHeight/2 + 30)
            let posY = clamp(preferredY, min: popoverHeight/2 + 20, max: max(popoverHeight/2 + 20, geo.size.height - popoverHeight/2 - 20))
            
            VStack(alignment: .leading, spacing: 10) {
                // Header bar
                HStack(spacing: 8) {
                    Picker("", selection: $selectedMode) {
                        ForEach(Mode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .labelsHidden()
                    .frame(width: 140)
                    
                    Spacer()
                    
                    if selectedMode == .translate {
                        Button(action: {
                            let temp = sourceLangId
                            sourceLangId = targetLangId
                            targetLangId = temp
                        }) {
                            HStack(spacing: 4) {
                                Text(sourceLanguage.rawValue.prefix(2).uppercased())
                                    .font(.caption2.bold())
                                Image(systemName: "arrow.left.arrow.right")
                                    .font(.system(size: 9))
                                Text(targetLanguage.rawValue.prefix(2).uppercased())
                                    .font(.caption2.bold())
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentBrown.opacity(0.2))
                            .foregroundColor(.accentBrown)
                            .cornerRadius(6)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 16))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                Divider()
                
                // Selected Sentence & Translation Scrollable View
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(selectedText)
                            .font(.headline)
                            .foregroundColor(.primary)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                        
                        Divider()
                        
                        if let result = translationResult {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(result.translations, id: \.self) { translation in
                                    HStack(alignment: .top, spacing: 6) {
                                        Text("•")
                                            .foregroundColor(.accentBrown)
                                            .bold()
                                        Text(translation)
                                            .font(.body)
                                            .foregroundColor(.primary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                        } else {
                            Text("No translation found.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .italic()
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding(14)
            .frame(width: popoverWidth, height: popoverHeight)
            .background(Color(nsColor: .windowBackgroundColor))
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.primary.opacity(0.15), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.3), radius: 12, x: 0, y: 6)
            .position(x: posX, y: posY)
        }
    }
    
    private func clamp(_ val: CGFloat, min minVal: CGFloat, max maxVal: CGFloat) -> CGFloat {
        if maxVal < minVal { return minVal }
        return Swift.min(Swift.max(val, minVal), maxVal)
    }
}
