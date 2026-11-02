import AppKit

extension VPhoneMenuController {
    func buildNetworkMenu() -> NSMenuItem {
        let item = NSMenuItem(title: VPhoneLocalization.text("Network"), action: nil, keyEquivalent: "")
        let menu = NSMenu(title: item.title)
        menu.addItem(makeItem("Proxy…", action: #selector(showProxy)))
        item.submenu = menu
        return item
    }

    @objc func showProxy() { proxyWindowController.show() }
}
