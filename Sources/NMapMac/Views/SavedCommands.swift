import SwiftUI
import NMapMacCore

/// Menu of built-in scan types and the user's saved commands, plus saving and
/// deleting. Picking one fills the Command field; the command can then be
/// edited freely and saved under a new name.
struct SavedCommandsMenu: View {
    @Bindable var session: ScanSession
    @State private var confirmDelete: SavedCommand?

    var body: some View {
        Menu {
            Section("Scan Types") {
                ForEach(session.commands.builtIn) { item(for: $0) }
            }
            if !session.commands.custom.isEmpty {
                Section("My Commands") {
                    ForEach(session.commands.custom) { item(for: $0) }
                }
            }
            Divider()
            Button("Save Current Command…") { session.isSavingCommand = true }
            if !session.commands.custom.isEmpty {
                Menu("Delete Saved Command") {
                    ForEach(session.commands.custom) { saved in
                        Button(saved.name) { confirmDelete = saved }
                    }
                }
            }
        } label: {
            Text(menuTitle)
        }
        .frame(width: 200)
        .help("Pick a scan type or one of your saved commands. Edit the command below and choose Save Current Command… to keep it.")
        .confirmationDialog("Delete “\(confirmDelete?.name ?? "")”?",
                            isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } })) {
            Button("Delete", role: .destructive) {
                if let saved = confirmDelete {
                    do {
                        try session.commands.delete(named: saved.name)
                    } catch {
                        session.alert = AlertInfo(title: "Can't delete command", message: error.localizedDescription)
                    }
                }
                confirmDelete = nil
            }
        }
    }

    private var menuTitle: String {
        if let current = session.currentSavedCommand { return current.name }
        if let last = session.lastUsedCommandName { return "\(last) (modified)" }
        return "Custom command"
    }

    private func item(for saved: SavedCommand) -> some View {
        Button {
            session.use(saved)
        } label: {
            if session.currentSavedCommand?.name == saved.name {
                Label(saved.name, systemImage: "checkmark")
            } else {
                Text(saved.name)
            }
        }
    }
}

/// Asks for a name and saves the current command (without targets).
struct SaveCommandSheet: View {
    @Bindable var session: ScanSession
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var note = ""
    @State private var error: String?

    private var commandWithoutTargets: String {
        var options = NmapOptions(commandLine: session.command)
        options.targets = []
        return options.commandLine
    }

    private var overwrites: Bool {
        session.commands.custom.contains { $0.name == name.trimmingCharacters(in: .whitespaces) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Save Current Command").font(.title3.bold())
            Text(commandWithoutTargets)
                .font(.body.monospaced())
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            Text("Targets aren't saved — pick them each time you scan.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Form {
                TextField("Name", text: $name, prompt: Text("e.g. Web servers"))
                TextField("Note", text: $note, prompt: Text("Optional: what this command is for"))
            }

            if let error {
                Text(error).foregroundStyle(.red)
            } else if overwrites {
                Text("This replaces your saved command with the same name.")
                    .foregroundStyle(.orange)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(overwrites ? "Replace" : "Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear {
            // Editing one of your own commands? Offer to update it in place.
            let candidate = session.currentSavedCommand?.name ?? session.lastUsedCommandName
            if let candidate, !session.commands.isBuiltIn(candidate),
               let saved = session.commands.command(named: candidate) {
                name = saved.name
                note = saved.description
            }
        }
    }

    private func save() {
        do {
            try session.commands.save(name: name, command: session.command, description: note)
            session.lastUsedCommandName = name.trimmingCharacters(in: .whitespaces)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
