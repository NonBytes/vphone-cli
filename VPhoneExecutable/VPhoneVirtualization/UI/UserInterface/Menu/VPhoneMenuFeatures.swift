import AppKit
#if canImport(VPhonePentestKit)
import VPhonePentestKit
#endif

// MARK: - Features Menu

/// Host sensor controls, with the motion panels grouped in their own submenu.
extension VPhoneMenuController {
    @objc func showFridaTools() { fridaToolsWindowController.show() }

    @objc func showSnapshotManager() {
        snapshotManagerWindowController.show()
    }

    @objc func triggerQuickRollback() {
        guard let machineDirectory else { return }
        let snapshotsRoot = machineDirectory.appendingPathComponent("Snapshots", isDirectory: true)
        let fm = FileManager.default
        guard fm.fileExists(atPath: snapshotsRoot.path),
              let entries = try? fm.contentsOfDirectory(atPath: snapshotsRoot.path).filter({ !$0.hasPrefix(".") }),
              !entries.isEmpty else {
            VPhoneAlert.present(
                title: "No Snapshots Available",
                message: "No snapshots were found for this machine. Open Snapshot Manager (⌃⌘S) to inspect snapshot state.",
                style: .informational
            )
            return
        }

        var latestSnapshot: (name: String, date: Date)?
        for entry in entries {
            let plistURL = snapshotsRoot.appendingPathComponent(entry).appendingPathComponent("Snapshot.plist")
            if let data = try? Data(contentsOf: plistURL),
               let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
               let created = dict["Created"] as? Date {
                if latestSnapshot == nil || created > latestSnapshot!.date {
                    latestSnapshot = (entry, created)
                }
            }
        }

        let targetName = latestSnapshot?.name ?? entries.sorted().last!
        VPhoneAlert.present(
            title: "Rollback to '\(targetName)'?",
            message: "Reverting to snapshot '\(targetName)' requires stopping the VM to maintain SEP and APFS disk synchronization.\n\nOpen Snapshot Manager to inspect snapshots, or shut down the guest before reverting.",
            style: .warning,
            buttons: ["Open Snapshot Hub", "Shut Down Guest", "Cancel"]
        ) { [weak self] response in
            guard let self else { return }
            if response == .alertFirstButtonReturn {
                self.snapshotManagerWindowController.show()
            } else if response == .alertSecondButtonReturn {
                self.shutDownGuest()
            }
        }
    }

    /// Opens Launchpad's Pentest Tools helper for this VM directly from its
    /// own window, so using it doesn't mean switching to Launchpad first to
    /// find this machine and its Actions menu. Pentest Tools ships with
    /// Launchpad, not the Core Bundle, so this locates an installed
    /// Launchpad by bundle identifier rather than assuming a path.
    @objc func showPentestTools() {
        guard let machineDirectory else { return }
        if let existing = pentestToolsApp, !existing.isTerminated {
            existing.activate(options: [])
            return
        }
        guard let launchpad = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.vphone.launchpad") else {
            VPhoneAlert.present(
                title: "Launchpad Not Found",
                message: "Pentest Tools ships with VPhone Launchpad, not this VM. Install Launchpad to use it from here.",
                style: .warning,
            )
            return
        }
        let app = launchpad.appendingPathComponent("Contents/Helpers/VPhone Pentest.app")
        guard FileManager.default.isExecutableFile(atPath: app.appendingPathComponent("Contents/MacOS/VPhone Pentest").path) else {
            VPhoneAlert.present(
                title: "Pentest Tools Missing",
                message: "This Launchpad installation does not include Pentest Tools.",
                style: .warning,
            )
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = ["--machine-directory", machineDirectory.resolvingSymlinksInPath().path]
        configuration.createsNewApplicationInstance = true
        configuration.activates = true
        Task {
            do {
                pentestToolsApp = try await NSWorkspace.shared.openApplication(at: app, configuration: configuration)
            } catch {
                VPhoneAlert.present(title: "Unable to Open Pentest Tools", message: error.localizedDescription, style: .warning)
            }
        }
    }

    func buildFeaturesMenu() -> NSMenuItem {
        let item = NSMenuItem(title: "Features", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "Features")
        menu.autoenablesItems = false

        let fridaItem = makeItem(
            "Frida Tools…",
            action: #selector(showFridaTools),
            keyEquivalent: "f",
            modifiers: [.command, .control],
            symbol: "bolt.horizontal"
        )
        menu.addItem(fridaItem)

        let pentestItem = makeItem(
            "Pentest Tools…",
            action: #selector(showPentestTools),
            keyEquivalent: "p",
            modifiers: [.command, .control],
            symbol: "shield"
        )
        pentestItem.isEnabled = machineDirectory != nil
        menu.addItem(pentestItem)

        let snapshotItem = makeItem(
            "Snapshot Manager…",
            action: #selector(showSnapshotManager),
            keyEquivalent: "s",
            modifiers: [.command, .control],
            symbol: "camera.metering.matrix"
        )
        snapshotItem.isEnabled = machineDirectory != nil
        menu.addItem(snapshotItem)

        let rollbackItem = makeItem(
            "Rollback to Latest Snapshot…",
            action: #selector(triggerQuickRollback),
            keyEquivalent: "z",
            modifiers: [.command, .control],
            symbol: "arrow.uturn.backward"
        )
        rollbackItem.isEnabled = machineDirectory != nil
        menu.addItem(rollbackItem)
        menu.addItem(NSMenuItem.separator())

        for section in [buildLocationSubmenu(), buildBatterySubmenu(), buildCameraSubmenu()] {
            menu.addItem(NSMenuItem.sectionHeader(title: section.title))
            // Move, not copy: the controller keeps references to these items.
            let items = section.submenu?.items ?? []
            section.submenu?.removeAllItems()
            for child in items {
                menu.addItem(child)
            }
            menu.addItem(NSMenuItem.separator())
        }
        menu.addItem(buildMotionSensorsMenu())
        item.submenu = menu
        return item
    }
}
