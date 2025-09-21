//
//  Persistance.swift
//  FitTrack
//
//  Created by Andrei Niță on 21.09.2025.
//

import CoreData

struct PersistenceController {
    static let shared = PersistenceController()

    // For SwiftUI previews if you ever need them
    static var preview: PersistenceController = {
        let c = PersistenceController(inMemory: true)
        return c
    }()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        // ⚠️ Must match your .xcdatamodeld name
        container = NSPersistentContainer(name: "FitTrack")

        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }

        // Recommended options
        if let desc = container.persistentStoreDescriptions.first {
            desc.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            desc.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        }

        container.loadPersistentStores { _, error in
            if let error = error as NSError? {
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }
}

// MARK: - Database Export / Import
extension PersistenceController {

    /// Base URL of the SQLite store (…/FitTrack.sqlite)
    private func storeBaseURL() -> URL? {
        container.persistentStoreDescriptions.first?.url
    }

    /// All three SQLite files that make up the Core Data store (existing ones only).
    func storeFiles() -> [URL] {
        guard let baseURL = storeBaseURL() else { return [] }
        let basePath = baseURL.deletingPathExtension().path
        let fm = FileManager.default
        let candidates = [
            URL(fileURLWithPath: basePath + ".sqlite"),
            URL(fileURLWithPath: basePath + ".sqlite-wal"),
            URL(fileURLWithPath: basePath + ".sqlite-shm")
        ]
        return candidates.filter { fm.fileExists(atPath: $0.path) }
    }

    /// Export the database by copying the three SQLite files into a temporary folder.
    /// Returns the folder URL (you can pass this to a FileExporter).
    func exportDatabaseFolder() throws -> URL {
        let fm = FileManager.default

        // A stable parent temp directory just for our exports
        let base = fm.temporaryDirectory.appendingPathComponent("FitTrackExports", isDirectory: true)
        if !fm.fileExists(atPath: base.path) {
            try fm.createDirectory(at: base, withIntermediateDirectories: true)
        }

        // Child folder name is a fresh UUID so it *cannot* collide
        let tmp = base.appendingPathComponent(UUID().uuidString + ".fitdb", isDirectory: true)

        // Create the fresh folder
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)

        // Copy the three Core Data files
        for file in storeFiles() {
            let dest = tmp.appendingPathComponent(file.lastPathComponent)
            try fm.copyItem(at: file, to: dest)
        }
        return tmp
    }

    /// Import a previously exported folder (containing the sqlite/shm/wal files).
    /// This replaces the current store files and reloads the persistent store.
    func importDatabaseFolder(from folderURL: URL) throws {
        let fm = FileManager.default

        // If this URL comes from a fileImporter, it may be security-scoped.
        let needsStop = folderURL.startAccessingSecurityScopedResource()
        defer { if needsStop { folderURL.stopAccessingSecurityScopedResource() } }

        // 1) Ensure pending changes are flushed
        try container.viewContext.save()

        // 2) Remove the existing store from the coordinator
        let psc = container.persistentStoreCoordinator
        for store in psc.persistentStores {
            try psc.remove(store)
        }

        // 3) Delete current files
        for file in storeFiles() { _ = try? fm.removeItem(at: file) }

        // 4) Copy new files into the store directory
        guard let targetStoreURL = storeBaseURL() else {
            throw NSError(domain: "FitTrack", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Missing store URL"])
        }
        let targetDir = targetStoreURL.deletingLastPathComponent()
        let contents = try fm.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)

        // We expect up to three files; copy only known names
        let baseName = targetStoreURL.deletingPathExtension().lastPathComponent
        let allowedNames: Set<String> = [
            baseName + ".sqlite",
            baseName + ".sqlite-wal",
            baseName + ".sqlite-shm"
        ]

        for src in contents where allowedNames.contains(src.lastPathComponent) {
            let dest = targetDir.appendingPathComponent(src.lastPathComponent)
            try fm.copyItem(at: src, to: dest)
        }

        // 5) Reload persistent stores
        var loadError: NSError?
        container.loadPersistentStores { _, err in loadError = err as NSError? }
        if let err = loadError { throw err }

        // 6) Restore recommended context settings
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }
}
