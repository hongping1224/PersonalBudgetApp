import SwiftUI

/// List whose rows use the theme's card color instead of the system white/black.
/// (A Group passes its modifiers on to each section and row inside it.)
struct ThemedList<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        List {
            Group { content }
                .listRowBackground(Color.themeSurface)
        }
    }
}

/// Form with the theme's card color for its rows.
struct ThemedForm<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        Form {
            Group { content }
                .listRowBackground(Color.themeSurface)
        }
    }
}
