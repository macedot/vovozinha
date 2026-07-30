import SwiftUI
import PhotoDescribeKit
import StoryPromptKit
import VovoUI

/// DEBUG harness: runs `PhotoDescribeKit` alone (same Qwen pack as Story Prompt, VLM path).
@main
struct PhotoDescribeDebugApp: App {
    @State private var languageStore = LanguageStore()
    @State private var modelStore = OnDeviceMLXModelStore()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                PhotoDescribeFeatureView(
                    describer: DevicePhotoDescriber(modelStore: modelStore),
                    modelStore: modelStore
                )
                .navigationTitle("PhotoDescribe · Debug")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarColorScheme(.dark, for: .navigationBar)
                .toolbarBackground(VovoTheme.deepNight.opacity(0.9), for: .navigationBar)
            }
            .environment(languageStore)
            .preferredColorScheme(.dark)
        }
    }
}
