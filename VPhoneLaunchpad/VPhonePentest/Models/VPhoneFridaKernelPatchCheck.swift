import Foundation

/// Static, host-side check of a VM's on-disk `PatchReceipt.plist` for the
/// four opt-in Frida kernel relaxations (JB-23b/25c/33/34). The `standard`
/// preset blocks them by default, which otherwise surfaces as a Spawn
/// EXC_CRASH or an Attach timeout against sandboxed system apps.
/// See Research/Guest/frida_server.md.
enum VPhoneFridaKernelPatchCheck {
    static let requiredPatches = [
        "kernel-exp-frida_thread_set_state_entitlement_flag",
        "kernel-exp-frida_vm_map_delete_immutable_code",
        "kernel-exp-frida_tpro_off",
        "kernel-exp-frida_syscall_filter_off",
    ]

    /// `--preset frida` enables the Frida patch set, including these four. It exists
    /// because `--preset experimental` also unblocks unrelated hv_vmm_present/
    /// identity patches that hung a disposable VM at the boot logo in testing.
    static let setupHint = "--preset frida"

    /// `nil` when the receipt is missing or unreadable (unknown state — no
    /// warning). Otherwise the subset of `requiredPatches` absent from the
    /// kernelcache component's applied-patch list.
    static func missingPatches(machineDirectory: URL?) -> [String]? {
        guard let machineDirectory,
              let data = try? Data(contentsOf: machineDirectory.appendingPathComponent("PatchReceipt.plist")),
              let receipt = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let parts = receipt["Parts"] as? [String: Any],
              let kernelcache = parts["kernelcache"] as? [String: Any],
              let applied = kernelcache["Patches"] as? [String]
        else { return nil }
        let appliedSet = Set(applied)
        return requiredPatches.filter { !appliedSet.contains($0) }
    }
}
