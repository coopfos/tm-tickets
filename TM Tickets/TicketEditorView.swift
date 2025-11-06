import SwiftUI

struct TicketEditorView: View {
    // MARK: - Form State
    @State private var jobNumber: String = ""
    @State private var jobName: String = ""
    @State private var ticketDate: Date = .init()
    @State private var customerName: String = ""
    @State private var technician: String = ""
    @State private var workPerformed: String = ""
    @State private var materialList: String = ""
    @State private var signatureStrokes: [SignatureStroke] = []
    @State private var isSigning: Bool = false
    @State private var laborRows: [LaborRowInput] = [LaborRowInput()]

    var body: some View {
        Form {
            // Job Info
            Section(header: Text("Job Info")) {
                TextField("Job Number", text: $jobNumber)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()

                TextField("Job Name", text: $jobName)
                    .textInputAutocapitalization(.words)

                DatePicker("Date", selection: $ticketDate, displayedComponents: .date)

                TextField("Customer Name", text: $customerName)
                    .textInputAutocapitalization(.words)

                TextField("Technician", text: $technician)
                    .textInputAutocapitalization(.words)
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
                        Picker("Laborer", selection: $row.role) {
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
                    Button("Save Draft") {
                        // Placeholder for persistence hook
                        debugPrint("Draft saved")
                    }
                    .buttonStyle(.bordered)

                    Spacer()

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
    }

    // MARK: - Helpers
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
