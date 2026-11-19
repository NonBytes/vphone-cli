import AppKit
#if canImport(VPhonePentestKit)
import VPhonePentestKit
#endif

extension VPhoneMenuController {
    func buildNetworkMenu() -> NSMenuItem {
        let item = NSMenuItem(title: VPhoneLocalization.text("Network"), action: nil, keyEquivalent: "")
        let menu = NSMenu(title: item.title)
        menu.addItem(makeItem("Auto Proxy Assistant (Burp / mitmproxy)…", action: #selector(showProxyAssistant), symbol: "bolt.shield"))
        menu.addItem(makeItem("Manual Proxy Settings…", action: #selector(showProxy)))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(makeItem("Diagnostics & PCAP…", action: #selector(showNetworkDiagnostics)))
        item.submenu = menu
        return item
    }

    @objc func showProxyAssistant() {
        if !openInPentestTools(toolID: "net.proxy") { proxyAssistantWindowController.show() }
    }
    @objc func showProxy() { proxyWindowController.show() }
    @objc func showNetworkDiagnostics() {
        if !openInPentestTools(toolID: "net.diagnostics") { networkDiagnosticsWindowController.show() }
    }
}
