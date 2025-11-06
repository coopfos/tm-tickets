//
//  ContentView.swift
//  TM Tickets
//
//  Created by Cooper Foster on 10/27/25.
//

import SwiftUI

struct ContentView: View {
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
                    TicketEditorView()
                } label: {
                    Text("New Ticket")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal)

                Spacer()
            }
            .navigationTitle("Home")
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
