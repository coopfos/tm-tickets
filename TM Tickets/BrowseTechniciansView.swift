import SwiftUI

struct BrowseTechniciansView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var search: String = ""
    @State private var isLoading: Bool = false
    @State private var items: [ApiClient.TechnicianItem] = []
    @State private var errorMessage: String? = nil
    var onSelect: (ApiClient.TechnicianItem) -> Void

    var body: some View {
        NavigationStack {
            List {
                if let err = errorMessage { Text(err).foregroundStyle(.red) }
                ForEach(items, id: \.RowKey) { it in
                    Button {
                        onSelect(it)
                        dismiss()
                    } label: {
                        Text(it.displayName).font(.headline)
                    }
                }
            }
            .navigationTitle("Browse Technicians")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .searchable(text: $search, prompt: "Filter by name")
            .onChange(of: search) { _ in Task { await load() } }
            .task { await load() }
            .overlay {
                if isLoading { ProgressView().scaleEffect(1.2) }
                else if items.isEmpty && errorMessage == nil {
                    ContentUnavailableView("No technicians", systemImage: "person.2", description: Text("Try a different prefix"))
                }
            }
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let prefix = search.trimmingCharacters(in: .whitespacesAndNewlines)
            let res = try await ApiClient().listTechnicians(prefix: prefix.isEmpty ? nil : prefix)
            await MainActor.run { self.items = res }
        } catch {
            await MainActor.run { self.errorMessage = error.localizedDescription; self.items = [] }
        }
    }
}

