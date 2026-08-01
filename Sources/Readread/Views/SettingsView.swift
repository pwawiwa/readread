import SwiftUI

struct SettingsView: View {
    @Environment(\.presentationMode) var presentationMode
    
    @AppStorage("sourceLanguage") private var sourceLangId: String = DictionaryService.Language.english.rawValue
    @AppStorage("targetLanguage") private var targetLangId: String = DictionaryService.Language.indonesian.rawValue
    @AppStorage("showTranslationOnSelection") private var showTranslationOnSelection: Bool = true
    @AppStorage("defaultZoomLevel") private var defaultZoomLevel: Double = 100.0
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Dictionary & Translation")) {
                    Picker("Source Language", selection: $sourceLangId) {
                        ForEach(DictionaryService.Language.allCases) { lang in
                            Text(lang.rawValue).tag(lang.rawValue)
                        }
                    }
                    
                    Picker("Target Language", selection: $targetLangId) {
                        ForEach(DictionaryService.Language.allCases) { lang in
                            Text(lang.rawValue).tag(lang.rawValue)
                        }
                    }
                    
                    Toggle("Show translation on text selection", isOn: $showTranslationOnSelection)
                }
                
                Section(header: Text("Display Settings")) {
                    VStack(alignment: .leading) {
                        Text("Default Zoom Level: \(Int(defaultZoomLevel))%")
                        Slider(value: $defaultZoomLevel, in: 50...200, step: 10)
                    }
                    
                    HStack {
                        Text("Background Color")
                        Spacer()
                        Circle()
                            .fill(Color.offWhite)
                            .frame(width: 24, height: 24)
                            .overlay(Circle().stroke(Color.gray, lineWidth: 1))
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
            .frame(width: 400, height: 400)
        }
    }
}
