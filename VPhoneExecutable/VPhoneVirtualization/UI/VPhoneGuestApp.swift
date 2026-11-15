import AppKit
import Darwin
import Foundation
import VPhoneCoreKit

/// The kit's entry point: turn parsed boot options into a running guest.
///
/// This exists so `vphone-vm`'s `main.swift` stays a parse and a call. The
/// NSApplication wiring is an implementation detail of running a guest, not
/// something an entry point should be spelling out, and keeping it here means
/// `VPhoneVirtualMachineAppDelegate` does not have to be public — which in turn keeps every
/// `NSApplicationDelegate` method it implements internal.
public enum VPhoneGuestApp {
    /// Run the guest. Returns only when the application terminates.
    ///
    /// `@MainActor` because NSApplication is: at the top of `main.swift` that
    /// isolation was implicit, and moving the code into a function loses it.
    @MainActor
    public static func run(_ boot: VPhoneBootCommand) -> Never {
        // Hold a shared lock for the lifetime of the guest. Pentest snapshots
        // take the exclusive lock before inspecting or replacing VM state.
        let directory = boot.config.deletingLastPathComponent()
        let lock = open(directory.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard lock >= 0 else {
            FileHandle.standardError.write(Data("Could not open machine directory: errno \(errno).\n".utf8))
            exit(EXIT_FAILURE)
        }
        guard flock(lock, LOCK_SH | LOCK_NB) == 0 else {
            FileHandle.standardError.write(Data("Could not lock machine directory: errno \(errno).\n".utf8))
            exit(EXIT_FAILURE)
        }
        // The first `shared` call picks the class, so this must come first.
        let app = VPhoneApplication.shared
        let delegate = VPhoneVirtualMachineAppDelegate(command: boot)
        app.delegate = delegate
        app.run()
        // NSApplication.run() does not return through here in practice: the
        // terminate path exits the process. Spelling that out keeps the caller
        // from having to invent a meaningless return value.
        exit(0)
    }
}
