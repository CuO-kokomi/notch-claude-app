import SwiftUI

struct WidgetDescriptor: Identifiable {
    let id: String
    let displayName: String
    let iconName: String
    let viewBuilder: @MainActor (WidgetEnvironment, Alignment) -> AnyView
}
