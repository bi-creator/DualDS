// DualDS — save-state slots for the running game: save, load, rename, delete.
// Copyright (C) 2026 DualDS contributors. GPL-3.0-or-later.

import SwiftData
import SwiftUI
import UIKit

struct SaveStatesView: View {
    let model: EmulatorViewModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var everyState: [SaveState]
    @State private var confirmOverwrite: Int?
    @State private var renaming: SaveState?
    @State private var newName = ""

    init(model: EmulatorViewModel) {
        self.model = model
    }

    /// This game's states (filtered in memory; see SaveStateStore.states).
    private var allStates: [SaveState] { everyState.filter { $0.gameID == model.game.id } }

    private func state(_ slot: Int) -> SaveState? { allStates.first { $0.slot == slot } }

    private func report(_ action: () throws -> Void) {
        do { try action() } catch { model.stateError = EmulatorViewModel.message(for: error) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    row(slot: SaveStateStore.quickSlot)
                } footer: {
                    Text("Save states capture the whole console at this moment. They are separate from the game's own save, which DualDS keeps automatically.")
                }
                Section("Slots") {
                    ForEach(1...SaveStateStore.manualSlots, id: \.self) { row(slot: $0) }
                }
            }
            .navigationTitle("Save States")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .overlay { if model.isWorkingOnState { ProgressView().padding().background(.regularMaterial, in: .rect(cornerRadius: 12)) } }
            .confirmationDialog("Replace this save state?", isPresented: Binding(get: { confirmOverwrite != nil }, set: { if !$0 { confirmOverwrite = nil } }),
                                titleVisibility: .visible) {
                Button("Replace", role: .destructive) {
                    if let slot = confirmOverwrite { Task { await model.saveState(slot: slot, context: context) } }
                }
            }
            .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $newName)
                Button("Save") {
                    if let s = renaming { report { try model.saveStates.rename(s, to: newName, context: context) } }
                    renaming = nil
                }
                Button("Cancel", role: .cancel) { renaming = nil }
            }
            .alert("Save States", isPresented: Binding(get: { model.stateError != nil }, set: { if !$0 { model.stateError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(model.stateError ?? "") }
        }
    }

    @ViewBuilder private func row(slot: Int) -> some View {
        let existing = state(slot)
        HStack(spacing: 12) {
            Group {
                if let data = existing?.screenshotPNG, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().interpolation(.none).scaledToFit()
                } else {
                    RoundedRectangle(cornerRadius: 4).fill(Color(.secondarySystemFill))
                        .overlay(Image(systemName: "square.dashed").foregroundStyle(.secondary))
                }
            }
            .frame(width: 44, height: 66)
            .clipShape(.rect(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 2) {
                Text(existing?.name ?? SaveStateStore.defaultName(slot: slot)).font(.headline)
                Text(existing.map { $0.createdAt.formatted(date: .abbreviated, time: .shortened) } ?? "Empty")
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("slot.\(slot).date")
            }
            Spacer()
            Button("Save") {
                if existing != nil { confirmOverwrite = slot } else { Task { await model.saveState(slot: slot, context: context) } }
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("slot.\(slot).save")
            Button("Load") {
                guard let existing else { return }
                Task { if await model.loadState(existing) { dismiss() } }
            }
            .buttonStyle(.borderedProminent)
                    .foregroundStyle(AppTheme.current.onAccent)
            .disabled(existing == nil)
            .accessibilityIdentifier("slot.\(slot).load")
        }
        .swipeActions {
            if let existing {
                Button("Delete", role: .destructive) { report { try model.saveStates.delete(existing, context: context) } }
                Button("Rename") { newName = existing.name; renaming = existing }.tint(.blue)
            }
        }
        .contextMenu {
            if let existing {
                Button("Rename", systemImage: "pencil") { newName = existing.name; renaming = existing }
                Button("Delete", systemImage: "trash", role: .destructive) { report { try model.saveStates.delete(existing, context: context) } }
            }
        }
    }
}
