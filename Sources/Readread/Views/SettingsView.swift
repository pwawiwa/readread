import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

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

                Section(header: Text("Reading Room Display")) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Default Zoom Level: \(Int(defaultZoomLevel))%")
                        Slider(value: $defaultZoomLevel, in: 50...200, step: 10)
                    }

                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Reader Canvas")
                            Text("Surrounds pages in the reader. Document pages keep their original colors.")
                                .font(.caption)
                                .foregroundColor(Color.editorialSecondaryInk)
                        }
                        Spacer()
                        Circle()
                            .fill(Color.editorialCanvas)
                            .frame(width: 24, height: 24)
                            .overlay(Circle().stroke(Color.editorialRule, lineWidth: 1))
                            .accessibilityLabel("Warm reading room canvas color")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .frame(width: 440, height: 380)
        }
    }
}
