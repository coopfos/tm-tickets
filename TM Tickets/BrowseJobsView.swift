import SwiftUI

struct BrowseJobsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var search: String = ""
    @State private var isLoading: Bool = false
    @State private var items: [ApiClient.JobItem] = []
    @State private var errorMessage: String? = nil
    var onSelect: (ApiClient.JobItem) -> Void

    var body: some View {
        NavigationStack {
            List {
                if let err = errorMessage { Text(err).foregroundStyle(.red) }
                ForEach(items, id: \.RowKey) { it in
                    Button {
                        onSelect(it)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading) {
                            Text((it.Description?.isEmpty == false) ? "\(it.displayJobNumber) - \(it.Description!)" : it.displayJobNumber)
                                .font(.headline)
                            if let cust = it.CustomerName, !cust.isEmpty {
                                Text(cust).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Browse Jobs")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .searchable(text: $search, prompt: "Filter by job number")
            .onChange(of: search) { _ in Task { await load() } }
            .task { await load() }
            .overlay {
                if isLoading { ProgressView().scaleEffect(1.2) }
                else if items.isEmpty && errorMessage == nil {
                    ContentUnavailableView("No jobs", systemImage: "doc.text.magnifyingglass", description: Text("Try a different prefix"))
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
            let res = try await ApiClient().listJobs(prefix: prefix.isEmpty ? nil : prefix)
            await MainActor.run { self.items = res }
        } catch {
            await MainActor.run { self.errorMessage = error.localizedDescription; self.items = [] }
        }
    }
}
