import SwiftData
import SwiftUI

struct EditEventSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let event: HeadacheEvent

    @State private var timestamp: Date
    @State private var severity: HeadacheSeverity?
    @State private var notes: String

    init(event: HeadacheEvent) {
        self.event = event
        _timestamp = State(initialValue: event.timestamp)
        _severity = State(initialValue: event.severity)
        _notes = State(initialValue: event.userNotes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(
                        "Date & Time",
                        selection: $timestamp,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.graphical)
                } header: {
                    Text("When did the headache occur?")
                }

                Section {
                    Picker("Severity", selection: $severity) {
                        Text("Not set").tag(Optional<HeadacheSeverity>.none)
                        ForEach(HeadacheSeverity.allCases, id: \.self) { s in
                            Text(s.rawValue.capitalized).tag(Optional(s))
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Severity")
                }

                Section {
                    TextEditor(text: $notes)
                        .frame(minHeight: 120)
                } header: {
                    Text("Notes")
                }
            }
            .navigationTitle("Edit Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .accessibilityIdentifier("editEventSheet")
    }

    private func save() {
        let calendar = Calendar.current

        if timestamp != event.timestamp {
            event.timestamp = timestamp
            event.timezoneIdentifier = TimeZone.current.identifier
            event.weekdayIndex = calendar.component(.weekday, from: timestamp)
            event.weekdayName = HeadacheEvent.weekdayName(from: timestamp)
            event.hourOfDay = calendar.component(.hour, from: timestamp)
            event.minuteOfHour = calendar.component(.minute, from: timestamp)
            event.partOfDayRaw = PartOfDay.from(timestamp, calendar: calendar).rawValue
        }

        event.severity = severity

        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        event.userNotes = trimmed.isEmpty ? nil : trimmed

        do {
            try modelContext.save()
        } catch {
            #if DEBUG
            print("EditEventSheet: save failed | \(error)")
            #endif
        }
    }
}
