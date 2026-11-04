import SwiftUI

struct ProfilesView: View {
    @EnvironmentObject private var profiles: ProfileStore
    @EnvironmentObject private var library: LibraryStore
    @State private var isEditing = false
    @State private var editingID: String?
    @State private var name = ""
    @State private var validationError: String?

    var body: some View {
        List {
            Section {
                ForEach(profiles.profiles) { profile in
                    HStack(spacing: 12) {
                        Button {
                            profiles.select(profile.id)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "person.crop.circle").foregroundStyle(Design.accent)
                                Text(profile.name).foregroundStyle(.primary)
                                Spacer()
                                if profile.id == profiles.activeID {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Design.accent)
                                }
                            }.frame(minHeight: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(profile.id == profiles.activeID ? .isSelected : [])
                        Button {
                            editingID = profile.id
                            name = profile.name
                            isEditing = true
                        } label: {
                            Image(systemName: "pencil").frame(minWidth: 44, minHeight: 44)
                        }.buttonStyle(.plain).accessibilityLabel("Rename \(profile.name)")
                    }
                }
                Button {
                    editingID = nil
                    name = ""
                    isEditing = true
                } label: {
                    Label("Create profile", systemImage: "person.badge.plus").frame(minHeight: 44)
                }
            } footer: {
                Text("Each profile has its own library, reading progress and settings. Installed sources are shared. Profiles are stored on this device.")
            }
            .disabled(library.isImporting)
            if library.isImporting {
                Text("Finish or cancel the PDF import before changing profiles.")
                    .foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden).pageBackground().navigationTitle("Profiles")
        .alert(editingID == nil ? "Create profile" : "Rename profile", isPresented: $isEditing) {
            TextField("Profile name", text: $name)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                let saved: Bool
                if let id = editingID { saved = profiles.rename(id, to: name) }
                else { saved = profiles.create(name: name) }
                if !saved { validationError = "Choose a unique name between 1 and 40 characters." }
            }
        } message: {
            Text("Enter a name for this profile.")
        }
        .alert("Couldn’t save profile", isPresented: Binding(get: { validationError != nil }, set: { if !$0 { validationError = nil } })) {
            Button("Try again") { validationError = nil; isEditing = true }
            Button("Cancel", role: .cancel) { validationError = nil }
        } message: { Text(validationError ?? "") }
    }
}
