import SwiftUI

struct LoadDraftView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var ticketNumber: String = ""
    @State private var jobNumberSearch: String = ""
    @State private var isLoading: Bool = false
    @State private var isSearching: Bool = false
    @State private var errorMessage: String? = nil
    @State private var searchError: String? = nil
    @State private var results: [ApiClient.DraftListItem] = []
    var onLoaded: (ApiClient.DraftDocument?) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Enter Ticket Number")) {
                    TextField("e.g. T-1001", text: $ticketNumber)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }

                if let err = errorMessage {
                    Section {
                        Text(err).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Load Draft")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Load") { Task { await load() } }
                        .disabled(ticketNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                }
            }
            .overlay {
                if isLoading {
                    ProgressView("Loading...")
                        .padding(24)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            // New section: browse drafts by job number
            List {
                Section(header: Text("Browse by Job Number")) {
                    HStack {
                        TextField("e.g. 6014", text: $jobNumberSearch)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Search") { Task { await search() } }
                            .disabled(jobNumberSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearching)
                    }
                    if let err = searchError { Text(err).foregroundStyle(.red) }
                }
                Section {
                    ForEach(results, id: \.id) { item in
                        Button {
                            Task { await loadById(item.id) }
                        } label: {
                            VStack(alignment: .leading) {
                                Text(item.id).font(.headline.monospaced())
                                HStack(spacing: 8) {
                                    Text(item.jobNumber).font(.subheadline)
                                    Text(formatDraftDate(item.date)).font(.footnote).foregroundStyle(.secondary)
                                }
                                if let name = item.jobName, !name.isEmpty {
                                    Text(name).font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                Task { await deleteDraft(id: item.id) }
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                }
                if !isSearching && searchError == nil && !jobNumberSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && results.isEmpty {
                    Section {
                        ContentUnavailableView("No drafts found", systemImage: "doc.text.magnifyingglass", description: Text("Try a different job number or verify saved drafts."))
                    }
                }
            }
            .overlay {
                if isSearching { ProgressView().scaleEffect(1.1) }
            }
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let id = ticketNumber.trimmingCharacters(in: .whitespacesAndNewlines)
            let doc = try await ApiClient().loadDraft(id: id)
            onLoaded(doc)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

extension LoadDraftView {
    private func formatDraftDate(_ isoString: String) -> String {
        // Parse ISO8601 and display in Eastern time with HH:mm
        let parser = ISO8601DateFormatter()
        // allow parsing with/without fractional seconds
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallbackParser = ISO8601DateFormatter()
        fallbackParser.formatOptions = [.withInternetDateTime]
        var date: Date? = parser.date(from: isoString)
        if date == nil { date = fallbackParser.date(from: isoString) }
        guard let dt = date else { return isoString }

        let fmt = DateFormatter()
        fmt.timeZone = TimeZone(identifier: "America/New_York")
        fmt.locale = Locale.current
        fmt.dateFormat = "MMM d, yyyy HH:mm"
        return fmt.string(from: dt)
    }
    private func search() async {
        isSearching = true
        searchError = nil
        defer { isSearching = false }
        do {
            let jn = jobNumberSearch.trimmingCharacters(in: .whitespacesAndNewlines)
            let items = try await ApiClient().listDrafts(jobNumber: jn)
            await MainActor.run { self.results = items }
        } catch {
            await MainActor.run { self.searchError = error.localizedDescription; self.results = [] }
        }
    }
    private func loadById(_ id: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let doc = try await ApiClient().loadDraft(id: id)
            onLoaded(doc)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    private func deleteDraft(id: String) async {
        do {
            try await ApiClient().deleteDraft(id: id)
            await search()
        } catch {
            await MainActor.run { self.searchError = error.localizedDescription }
        }
    }
}
