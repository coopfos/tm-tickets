//
//  ContentView.swift
//  TM Tickets
//
//  Created by Cooper Foster on 10/27/25.
//

import SwiftUI

struct ContentView: View {
    @State private var showingSettings = false
    @State private var showingLoadDraft = false
    @State private var loadedDraft: ApiClient.DraftDocument? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "ticket")
                    .font(.system(size: 56, weight: .regular))
                    .accentColor(.accentColor)
                    .accessibilityHidden(true)

                Text("TM Tickets")
                    .font(.largeTitle.weight(.semibold))

                Text("Create and submit a new service ticket.")
                    .foregroundStyle(.secondary)

                NavigationLink {
                    TicketEditorView(draft: nil)
                } label: {
                    Text("New Ticket")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal)

                Button {
                    showingLoadDraft = true
                } label: {
                    Text("Load Draft")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .padding(.horizontal)

                Spacer()
            }
            .navigationTitle("Home")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gear")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showingLoadDraft) {
                LoadDraftView { doc in
                    if let doc { self.loadedDraft = doc }
                }
            }
            .navigationDestination(isPresented: Binding(get: { loadedDraft != nil }, set: { if !$0 { loadedDraft = nil } })) {
                TicketEditorView(draft: loadedDraft)
            }
        }
    }
}

// MARK: - Model used for now
enum LaborerClass: String, CaseIterable, Identifiable, Codable {
    case foreman = "Foreman"
    case journeyman = "Journeyman"
    case apprentice = "Apprentice"

    var id: String { rawValue }
}

struct LaborEntry: Codable, CustomStringConvertible, Identifiable {
    let id = UUID()
    var role: LaborerClass
    var regularHours: Double
    var otHours: Double

    var description: String {
        "(role: \(role.rawValue), regular: \(regularHours), ot: \(otHours))"
    }
}

struct Ticket: CustomStringConvertible {
    var jobNumber: String
    var jobName: String
    var date: Date
    var customerName: String
    var technician: String
    var workPerformed: String
    var materialList: String
    var labor: [LaborEntry]
    var signature: [SignatureStroke]

    var description: String {
        let laborSummary = labor.map { $0.description }.joined(separator: ", ")
        return "Ticket(\(jobNumber), jobName: \(jobName), date: \(date), customer: \(customerName), tech: \(technician), work: \(workPerformed.count) chars, materials: \(materialList.count) chars, labor: [\(laborSummary)], signatureStrokes: \(signature.count))"
    }
}
