import AppKit
#if canImport(VPhonePentestKit)
import VPhonePentestKit
#endif

// MARK: - Features Menu

/// Host sensor controls, with the motion panels grouped in their own submenu.
extension VPhoneMenuController {
    @objc func showFridaTools() { fridaToolsWindowController.show() }

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
        for section in [buildLocationSubmenu(), buildBatterySubmenu(), buildCameraSubmenu()] {
            if menu.numberOfItems > 0 {
                menu.addItem(NSMenuItem.separator())
            }
            menu.addItem(NSMenuItem.sectionHeader(title: section.title))
            // Move, not copy: the controller keeps references to these items.
            let items = section.submenu?.items ?? []
            section.submenu?.removeAllItems()
            for child in items {
                menu.addItem(child)
            }
        }
        menu.addItem(NSMenuItem.separator())
        menu.addItem(buildMotionSensorsMenu())
        menu.addItem(makeItem("Frida Tools…", action: #selector(showFridaTools)))
        let pentestItem = makeItem("Pentest Tools…", action: #selector(showPentestTools))
        pentestItem.isEnabled = machineDirectory != nil
        menu.addItem(pentestItem)
        item.submenu = menu
        return item
    }
}
