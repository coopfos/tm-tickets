import SwiftUI

struct TicketEditorView: View {
    // MARK: - Form State
    @State private var jobNumber: String = ""
    @State private var jobName: String = ""
    @State private var ticketDate: Date = .init()
    @State private var customerName: String = ""
    @State private var projectManager: String = ""
    @State private var technician: String = ""
    @State private var workPerformed: String = ""
    @State private var materialList: String = ""
    @State private var signatureStrokes: [SignatureStroke] = []
    @State private var isSigning: Bool = false
    @State private var laborRows: [LaborRowInput] = [LaborRowInput()]
    @State private var isSaving: Bool = false
    @State private var saveResultMessage: String? = nil
    @State private var isDeleting: Bool = false
    @State private var showingDeleteConfirm: Bool = false
    @State private var ticketNumber: String = ""
    @State private var jobLookupInFlight: Bool = false
    @State private var jobValid: Bool? = nil
    @State private var jobLookupTask: Task<Void, Never>? = nil
    @State private var showingBrowseJobs: Bool = false
    @State private var suppressNextJobLookup: Bool = false
    @State private var selectedRowKeyForValidation: String? = nil
    @State private var lastSelectionJobNumber: String? = nil
    @State private var showingBrowseTechnicians: Bool = false
    #if DEBUG
    @State private var debugPMTestMessage: String? = nil
    #endif
    @Environment(\.dismiss) private var dismiss

    // Loaded draft (optional)
    private let initialDraft: ApiClient.DraftDocument?

    init(draft: ApiClient.DraftDocument? = nil) {
        self.initialDraft = draft
    }

    var body: some View {
        Form {
            // Job Info
            Section(header: Text("Ticket")) {
                HStack {
                    TextField("Ticket Number", text: $ticketNumber)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .disabled(true)
                    Image(systemName: "lock.fill").foregroundStyle(.secondary)
                }
            }

            Section(header: Text("Job Info")) {
                HStack(alignment: .firstTextBaseline) {
                    TextField("Job Number", text: $jobNumber)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .onChange(of: jobNumber) { _ in scheduleJobLookup() }
                    if jobLookupInFlight { ProgressView().scaleEffect(0.75) }
                    if let valid = jobValid {
                        Image(systemName: valid ? "checkmark.seal" : "xmark.octagon")
                            .foregroundStyle(valid ? .green : .red)
                    }
                    Button {
                        showingBrowseJobs = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .buttonStyle(.borderless)
                }

                TextField("Job Name", text: $jobName)
                    .textInputAutocapitalization(.words)
                    .disabled(true)

                TextField("Customer Name", text: $customerName)
                    .textInputAutocapitalization(.words)
                    .disabled(true)

                TextField("Project Manager", text: $projectManager)
                    .textInputAutocapitalization(.words)
                    .disabled(true)

                DatePicker("Date", selection: $ticketDate, displayedComponents: .date)

                HStack(alignment: .firstTextBaseline) {
                    TextField("Technician", text: $technician)
                        .textInputAutocapitalization(.words)
                        .disabled(true)
                    Button {
                        showingBrowseTechnicians = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Browse Technicians")
                }
            }

            // Work Performed
            Section(header: Text("Work Performed")) {
                TextEditor(text: $workPerformed)
                    .frame(minHeight: 140)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                    .padding(.vertical, 2)
            }

            // Materials
            Section(header: Text("Material List")) {
                TextEditor(text: $materialList)
                    .frame(minHeight: 120)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                    .padding(.vertical, 2)
            }

            // Labor
            Section(header: Text("Labor")) {
                // Header row
                HStack {
                    Text("Electrician Class").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("Regular").font(.subheadline.weight(.semibold))
                        .frame(width: 90, alignment: .trailing)
                    Text("OT").font(.subheadline.weight(.semibold))
                        .frame(width: 90, alignment: .trailing)
                }

                ForEach($laborRows) { $row in
                    HStack(spacing: 8) {
                        Picker("Class", selection: $row.role) {
                            ForEach(LaborerClass.allCases) { c in
                                Text(c.rawValue).tag(c)
                            }
                        }
                        .pickerStyle(.menu)

                        TextField("0.0", text: $row.regular)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                            .onChange(of: row.regular) { new in
                                row.regular = sanitizeHours(new)
                            }

                        TextField("0.0", text: $row.ot)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                            .onChange(of: row.ot) { new in
                                row.ot = sanitizeHours(new)
                            }

                        Button(role: .destructive) {
                            withAnimation {
                                if let idx = laborRows.firstIndex(where: { $0.id == row.id }) {
                                    laborRows.remove(at: idx)
                                }
                            }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .opacity(laborRows.count > 1 ? 1 : 0.4)
                        .disabled(laborRows.count <= 1)
                    }
                }

                Button {
                    withAnimation { laborRows.append(LaborRowInput()) }
                } label: {
                    Label("Add Row", systemImage: "plus.circle")
                }
            }

            // Signature
            Section(header: Text("Customer Signature")) {
                VStack(alignment: .leading, spacing: 12) {
                    SignatureCanvas(strokes: $signatureStrokes, isEnabled: isSigning)
                        .frame(minHeight: 240)
                        .background(Color(uiColor: .secondarySystemBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(style: StrokeStyle(lineWidth: 1))
                                .foregroundStyle(.quaternary)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    HStack(spacing: 12) {
                        Spacer()
                        Button {
                            isSigning.toggle()
                        } label: {
                            Label(isSigning ? "Done Signing" : "Sign",
                                  systemImage: isSigning ? "checkmark" : "pencil.and.outline")
                        }
                        .buttonStyle(.bordered)

                        Button(role: .destructive) {
                            signatureStrokes.removeAll()
                        } label: {
                            Label("Clear", systemImage: "xmark.circle")
                        }
                    }
                }
            }

            // Actions
            Section {
                HStack {
                    Button("Save Draft") { Task { await saveDraft() } }
                    .buttonStyle(.bordered)
                    .disabled(isSaving)

                    Spacer()

                    Button(role: .destructive) {
                        showingDeleteConfirm = true
                    } label: {
                        Text("Delete Draft")
                    }
                    .buttonStyle(.bordered)
                    .disabled(ticketNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving || isDeleting)

                    Button("Submit Ticket") {
                        submitTicket()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isFormValid)
                }
            }
        }
        .navigationTitle("New Ticket")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await initializeIfNeeded()
        }
        #if DEBUG
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                Button("Verify PM") { Task { await debugVerifyPMMapping() } }
            }
        }
        #endif
        .sheet(isPresented: $showingBrowseJobs) {
            BrowseJobsView { item in
                // Populate from selection and suppress the immediate re-lookup once
                self.suppressNextJobLookup = true
                let displayJob = item.JobNumber ?? item.RowKey
                self.jobNumber = displayJob
                self.jobName = item.Description ?? ""
                self.customerName = item.CustomerName ?? ""
                // Fetch PM name using the RowKey for accuracy
                Task {
                    if let info = try? await ApiClient().getJobInfo(for: item.RowKey) {
                        await MainActor.run { self.projectManager = info.projectManager }
                    }
                }
                self.jobValid = true
                // Store RowKey for validation while keeping the display job number
                self.selectedRowKeyForValidation = item.RowKey
                self.lastSelectionJobNumber = displayJob
            }
        }
        .sheet(isPresented: $showingBrowseTechnicians) {
            BrowseTechniciansView { item in
                self.technician = item.displayName
            }
        }
        .overlay(alignment: .center) {
            if isSaving {
                ProgressView("Saving…")
                    .padding(24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            } else if isDeleting {
                ProgressView("Deleting…")
                    .padding(24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .alert("Draft Saved", isPresented: Binding(get: {
            saveResultMessage != nil
        }, set: { newVal in
            if !newVal { saveResultMessage = nil }
        })) {
            Button("OK", role: .cancel) { saveResultMessage = nil }
        } message: {
            Text(saveResultMessage ?? "")
        }
        .alert("Delete Draft?", isPresented: $showingDeleteConfirm) {
            Button("Delete", role: .destructive) { Task { await deleteDraft() } }
            Button("Cancel", role: .cancel) { showingDeleteConfirm = false }
        } message: {
            Text("This will permanently remove this draft from storage.")
        }
        #if DEBUG
        .alert("PM Mapping Check", isPresented: Binding(get: { debugPMTestMessage != nil }, set: { if !$0 { debugPMTestMessage = nil } })) {
            Button("OK", role: .cancel) { debugPMTestMessage = nil }
        } message: {
            Text(debugPMTestMessage ?? "")
        }
        #endif
    }

    // MARK: - Helpers
    private func initializeIfNeeded() async {
        // If launched with a draft, populate fields and skip number fetch
        if let d = initialDraft {
            await MainActor.run {
                self.ticketNumber = d.id
                self.jobNumber = d.jobNumber
                self.jobName = d.jobName
                if let dt = ISO8601DateFormatter().date(from: d.date) { self.ticketDate = dt }
                self.customerName = d.customerName
                self.technician = d.technician
                self.workPerformed = d.workPerformed
                self.materialList = d.materialList
                self.laborRows = d.labor.map { LaborRowInput(role: LaborerClass(rawValue: $0.role) ?? .journeyman, regular: String($0.regularHours), ot: String($0.otHours)) }
            }
            // Attempt to load PM name for the job
            Task {
                if let info = try? await ApiClient().getJobInfo(for: d.jobNumber) {
                    await MainActor.run { self.projectManager = info.projectManager }
                }
            }
            return
        }
        // New ticket: fetch next number if empty
        if self.ticketNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            do {
                let next = try await ApiClient().getNextTicketNumber()
                await MainActor.run { self.ticketNumber = next }
            } catch {
                // Fallback to a local GUID if API fails
                await MainActor.run { self.ticketNumber = UUID().uuidString }
            }
        }
    }

    private func scheduleJobLookup() {
        // If change originated from selector, skip one lookup
        if suppressNextJobLookup {
            suppressNextJobLookup = false
            return
        }
        jobLookupTask?.cancel()
        let current = jobNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        if current.isEmpty { jobValid = nil; jobName = ""; customerName = ""; projectManager = ""; return }
        jobLookupInFlight = true
        jobLookupTask = Task {
            // Simple debounce
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            do {
                // If the current field equals the last selected display number, validate using the stored RowKey
                var keyForLookup = current
                if let selKey = selectedRowKeyForValidation, let lastDisp = lastSelectionJobNumber, current == lastDisp {
                    keyForLookup = selKey
                } else {
                    // User has changed the field since selection; validate by the typed value
                    selectedRowKeyForValidation = nil
                    lastSelectionJobNumber = nil
                }
                if let info = try await ApiClient().getJobInfo(for: keyForLookup) {
                    await MainActor.run {
                        self.jobName = info.name
                        self.customerName = info.customerName
                        self.projectManager = info.projectManager
                        self.jobValid = true
                    }
                } else {
                    await MainActor.run { self.jobValid = false; self.jobName = ""; self.customerName = ""; self.projectManager = "" }
                }
            } catch {
                await MainActor.run { self.jobValid = false }
            }
            await MainActor.run { self.jobLookupInFlight = false }
        }
    }
    private var isFormValid: Bool {
        !jobNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !jobName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !customerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !technician.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !workPerformed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !signatureStrokes.isEmpty
    }

    private func submitTicket() {
        let ticket = Ticket(
            jobNumber: jobNumber,
            jobName: jobName,
            date: ticketDate,
            customerName: customerName,
            technician: technician,
            workPerformed: workPerformed,
            materialList: materialList,
            labor: laborRows.map { $0.toEntry() },
            signature: signatureStrokes
        )
        debugPrint("Submitting ticket: \(ticket)")
    }

    private func saveDraft() async {
        isSaving = true
        defer { isSaving = false }

        // Build payload
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        // Save timestamps in Eastern Time
        iso.timeZone = TimeZone(identifier: "America/New_York")
        let payload = DraftPayload(
            id: ticketNumber.isEmpty ? nil : ticketNumber,
            jobNumber: jobNumber,
            jobName: jobName,
            date: iso.string(from: ticketDate),
            customerName: customerName,
            technician: technician,
            workPerformed: workPerformed,
            materialList: materialList,
            labor: laborRows.map {
                LaborDTO(role: $0.role.rawValue,
                         regularHours: Double($0.regular) ?? 0,
                         otHours: Double($0.ot) ?? 0)
            }
        )

        do {
            let resp = try await ApiClient().saveDraft(payload)
            saveResultMessage = "ID: \(resp.id)\nSaved at: \(resp.savedAt)"
        } catch {
            saveResultMessage = "Failed to save: \(error.localizedDescription)"
        }
    }

    private func deleteDraft() async {
        showingDeleteConfirm = false
        let id = ticketNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await ApiClient().deleteDraft(id: id)
            await MainActor.run {
                saveResultMessage = "Draft deleted."
                // Dismiss back to previous screen after a short delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { dismiss() }
            }
        } catch {
            await MainActor.run { saveResultMessage = "Delete failed: \(error.localizedDescription)" }
        }
    }

    #if DEBUG
    private func debugVerifyPMMapping() async {
        let current = jobNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !current.isEmpty else {
            await MainActor.run { self.debugPMTestMessage = "No job number entered." }
            return
        }
        var keyForLookup = current
        if let selKey = selectedRowKeyForValidation, let lastDisp = lastSelectionJobNumber, current == lastDisp {
            keyForLookup = selKey
        }
        do {
            let info = try await ApiClient().getJobInfo(for: keyForLookup)
            let pmFromAPI = info?.projectManager ?? "<nil>"
            let pmInField = self.projectManager.isEmpty ? "<empty>" : self.projectManager
            let matched = (info?.projectManager ?? "") == self.projectManager ? "YES" : "NO"
            let details = "Lookup key: \(keyForLookup)\nSelectedRowKey: \(selectedRowKeyForValidation ?? "<nil>")\nLastSelectionJob#: \(lastSelectionJobNumber ?? "<nil>")\nAPI projectManager: \(pmFromAPI)\nField projectManager: \(pmInField)\nMatch: \(matched)"
            await MainActor.run { self.debugPMTestMessage = details }
        } catch {
            await MainActor.run { self.debugPMTestMessage = "Lookup failed: \(error.localizedDescription)" }
        }
    }
    #endif
}

// MARK: - Labor helpers
private struct LaborRowInput: Identifiable {
    let id = UUID()
    var role: LaborerClass = .journeyman
    var regular: String = ""
    var ot: String = ""

    func toEntry() -> LaborEntry {
        LaborEntry(
            role: role,
            regularHours: Double(regular) ?? 0,
            otHours: Double(ot) ?? 0
        )
    }
}

private func sanitizeHours(_ input: String) -> String {
    // Digits only, allow single '.', max one fractional digit
    var result = ""
    var hasDot = false
    var fractionalCount = 0
    for ch in input {
        if ch >= "0" && ch <= "9" {
            if hasDot {
                if fractionalCount < 1 {
                    result.append(ch)
                    fractionalCount += 1
                }
            } else {
                result.append(ch)
            }
        } else if ch == "." {
            if !hasDot {
                hasDot = true
                result.append(ch)
            }
        }
    }
    if !result.isEmpty && !result.contains(".") {
        // Collapse leading zeros to a single zero
        var idx = result.startIndex
        while idx < result.endIndex && result[idx] == "0" {
            idx = result.index(after: idx)
        }
        let trimmed = result[idx...]
        result = trimmed.isEmpty ? "0" : String(trimmed)
    }
    return result
}

#Preview {
    NavigationStack {
        TicketEditorView()
    }
}
