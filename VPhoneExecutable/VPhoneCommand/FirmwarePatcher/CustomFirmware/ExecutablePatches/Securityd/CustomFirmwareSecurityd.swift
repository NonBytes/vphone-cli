// CustomFirmwareSecurityd.swift — make vphoned's keychain requests always
// eligible in /usr/libexec/securityd.
//
// What the problem is. On iOS 27.2+, vphoned's own keychain.add/keychain.list
// RPCs fail: `SecItemAdd` reports success but never persists a thing, and
// `SecItemCopyMatching` sees 0 Security-accessible items, no matter which
// access group is passed (`Research/Guest/keychain_inspector.md`). Creating
// and deleting the same item via Frida inside the TARGET APP's own process
// still works — only vphoned's own requests are refused.
//
// Root cause, found by pulling the guest's real `securityd` (`files.read` over
// the automation API, no shell needed) and tracing the unnamed function behind
// `serverxpc: client %@ is not eligible` / `client %@ is eligible platform
// binary` (both os_log strings in `__TEXT,__oslogstring`; the function itself
// carries no symbol in a release build, so it is found only by this xref, not
// by name):
//
//   1. The function checks the caller's codesign flags for
//      `CS_VALID | CS_PLATFORM_BINARY`. vphoned passes this — the guest's
//      jailbroken AMFI grants `CS_PLATFORM_BINARY` for its `platform-
//      application` entitlement even though vphoned is ad hoc signed.
//   2. If the caller's identifier list (the serverxpc caller's allowed
//      identifiers for this particular keychain operation) is NULL, the
//      function returns eligible unconditionally.
//   3. If it is non-NULL — vphoned's case, every time — it calls a membership
//      search, writes a one-byte result into a stack result struct at +0x18,
//      and that byte picks which log string to print. Critically, the SAME
//      byte is read again right after the log call to produce the function's
//      actual return value:
//
//          bl   <release>
//          mov  x0, x19
//          bl   <release>              ; releases the signing identifier
//          ldr  x8, [sp, #0x48]        ; reload the result struct pointer
//          ldrb w19, [x8, #0x18]       ; <- the real eligibility byte
//          add  x0, sp, #0x40
//          mov  w1, #8
//          bl   <...>
//          b    #target                ; -> `and w0, w19, #1` ; … ; `retab`
//
//      vphoned's computed identifier (`<process name>-<hash>`, the fallback
//      identity for a process with no proper Team-ID.BundleID) is never a
//      member of whatever list the search looks in, so this byte is always 0
//      and the function always returns false — for every keychain RPC
//      vphoned makes, independent of the access group it passes.
//
// The patch. Replace the `ldrb w?, [x?, #0x18]` that feeds the return value
// with `mov w?, #1` (a `MOVZ`, same four bytes, no length change, no cave).
// Located purely by the two os_log strings and the decoded instruction shapes
// around them — never a literal address — matching the kernel patcher
// guardrails in `AGENTS.md` applied to a userspace binary. The destination
// register is read from the decoded `ldrb`, not assumed to be `w19`: on a
// build where the compiler picked a different register, the patch follows it.
//
// What this does and does not affect. This disables the identifier-allowlist
// half of securityd's platform-binary eligibility gate SYSTEM-WIDE, for every
// client and every identifier list securityd checks this way — not only
// vphoned's keychain calls. The NULL-identifier-list path (already
// unconditionally eligible) is untouched. Off by default
// (`FirmwareGuestSystemPatchSet.securitydKeychainEligibility`); turn it on
// when a VM needs `keychain.add`/`.update` to actually work, and prefer the
// Keychain Inspector's "Copy In-App Frida Script" otherwise, which does not
// depend on vphoned's own keychain identity at all.
//
// Re-attestation. This project's guests enforce per-page code-signing hashes
// (TXM), so a caller that does not re-sign the whole binary afterwards MUST
// pass `reattestsCodeSignature: true`, or securityd is SIGKILLed the moment
// the patched page is paged in.

import Foundation
import VPhonePatchKit

/// Forces securityd's platform-binary eligibility check to always succeed for
/// a non-`NULL` identifier list, so vphoned's keychain RPCs stop being refused.
public enum CustomFirmwareSecuritydPatcher {
    // MARK: - Identity

    public static let component = "securityd"
    public static let patchID = "system-securityd-exp-keychain_eligibility"

    /// The two os_log strings this patch anchors on. Both must be present, and
    /// the search that locates the patch site starts at the first one's xref —
    /// a build missing either is not the shape this patch understands.
    static let notEligibleString = "serverxpc: client %@ is not eligible"
    static let eligibleString = "client %@ is eligible platform binary"

    /// Mach-O string sections an os_log format string can live in.
    static let stringSectionNames: Set<String> = ["__oslogstring", "__cstring"]

    // MARK: - Search windows

    /// How far an ADD may sit from the ADRP it completes.
    static let maxADRPToADDInstructions = 8
    /// How far past the "not eligible" string xref to look for the `ldrb`
    /// that reads the eligibility byte.
    static let maxInstructionsToLdrb = 48
    /// How far past that `ldrb` to look for the unconditional branch to the
    /// function's return block.
    static let maxInstructionsToBranch = 8
    /// How far past the branch's target to look for the `and w0, …, #1` that
    /// confirms the `ldrb`'s register feeds the return value.
    static let maxInstructionsAfterBranchTarget = 8

    /// Where progress goes when the caller does not say.
    public static let stdoutLog: @Sendable (String) -> Void = { print($0) }

    // MARK: - Results

    public enum Outcome: String, Sendable, Equatable {
        /// The four bytes already read `mov w?, #1`. Nothing was written.
        case alreadyPatched
        /// `dryRun` was set, so the site was located and reported only.
        case wouldPatch
        /// The eligibility byte read was rewritten and its page re-attested.
        case patched
    }

    /// Where the two os_log strings were found and referenced.
    public struct Anchor: Sendable, Equatable {
        public let stringFileOffset: Int
        public let stringVMA: UInt64
        public let referenceFileOffset: Int
        public let referenceVMA: UInt64
    }

    /// The located `ldrb` this patch replaces.
    public struct Site: Sendable, Equatable {
        public let fileOffset: Int
        public let vma: UInt64
        /// The register the `ldrb` writes, e.g. `"w19"` — whatever the
        /// compiler picked, not assumed.
        public let destRegisterName: String
        public let mnemonic: String
        public let operandString: String
    }

    public struct Report: Sendable {
        public let outcome: Outcome
        public let anchor: Anchor
        public let site: Site
        public let record: PatchRecord?
        public let reattestedSlots: [CustomFirmwareSlotRehash]

        public var sitesWritten: Int { record == nil ? 0 : 1 }
    }

    // MARK: - Patching

    /// Patch the `securityd` at `url` in place.
    ///
    /// Idempotent: a second run finds `mov w?, #1` already in place, reports
    /// ``Outcome/alreadyPatched`` and leaves the file untouched, byte for byte.
    ///
    /// - Parameter reattestsCodeSignature: recompute the code-directory slot
    ///   hash of the page the write lands in. Off by default, matching the
    ///   other `ExecutablePatches` verbs: every shipped caller re-signs the
    ///   whole binary afterwards. A caller that does not MUST set it.
    /// - Throws: ``PatcherError/patchSiteNotFound(_:)`` when either anchor
    ///   string, its xref, or the expected instruction shape around it is
    ///   missing — each meaning the firmware moved and installation must stop
    ///   rather than guess.
    @discardableResult
    public static func patch(
        fileAt url: URL,
        dryRun: Bool = false,
        reattestsCodeSignature: Bool = false,
        log: ((String) -> Void)? = stdoutLog,
    ) throws -> Report {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw PatcherError.fileNotFound(url.path)
        }
        var data = try Data(contentsOfFileToRewrite: url)
        let report = try patch(&data, dryRun: dryRun, reattestsCodeSignature: reattestsCodeSignature, log: log)
        if !dryRun, report.sitesWritten > 0 || !report.reattestedSlots.isEmpty {
            try data.write(to: url)
        }
        return report
    }

    /// In-memory form of ``patch(fileAt:dryRun:reattestsCodeSignature:log:)``.
    @discardableResult
    public static func patch(
        _ data: inout Data,
        dryRun: Bool = false,
        reattestsCodeSignature: Bool = false,
        log: ((String) -> Void)? = stdoutLog,
    ) throws -> Report {
        if data.startIndex != 0 {
            data = Data(data)
        }

        let located = try locateSite(in: data)
        let anchor = located.anchor
        let site = located.site

        log?("  Found \"\(notEligibleString)\" at va:0x\(hex(anchor.stringVMA))")
        log?("  Found string ref at 0x\(hex(UInt64(anchor.referenceFileOffset)))")
        log?("  Found eligibility byte read at 0x\(hex(site.vma)): \(site.mnemonic) \(site.operandString)")

        let destIndex = try registerIndex(site.destRegisterName)
        guard let movz = ARM64Encoder.encodeMovzW(rd: destIndex, imm16: 1) else {
            throw PatcherError.invalidFormat("\(component): could not encode `mov \(site.destRegisterName), #1`")
        }

        guard data.count >= site.fileOffset + movz.count else {
            throw PatcherError.invalidFormat(
                "\(component): site at 0x\(hex(UInt64(site.fileOffset))) is past the end of the file",
            )
        }
        let original = Data(data[site.fileOffset ..< site.fileOffset + movz.count])

        if original == movz {
            log?("  [=] already `mov \(site.destRegisterName), #1` at 0x\(hex(site.vma)); nothing to write")
            var slots: [CustomFirmwareSlotRehash] = []
            if reattestsCodeSignature, !dryRun {
                slots = try CustomFirmwareMachOCodeSignature.reattest(&data, modifiedOffsets: [site.fileOffset])
                for slot in slots {
                    log?("    re-attested \(slot)")
                }
            }
            return Report(outcome: .alreadyPatched, anchor: anchor, site: site, record: nil, reattestedSlots: slots)
        }

        guard let decodedOriginal = ARM64Disassembler().disassembleOne(original, at: site.vma),
              decodedOriginal.mnemonic == "ldrb"
        else {
            throw PatcherError.invalidFormat(
                "\(component): bytes at 0x\(hex(site.vma)) read \(original.hex), not the `ldrb` this patch replaces",
            )
        }

        guard !dryRun else {
            log?("  [.] dry-run: would write \(original.hex) -> \(movz.hex) at 0x\(hex(UInt64(site.fileOffset)))")
            return Report(outcome: .wouldPatch, anchor: anchor, site: site, record: nil, reattestedSlots: [])
        }

        data.replaceSubrange(site.fileOffset ..< site.fileOffset + movz.count, with: movz)

        let written = Data(data[site.fileOffset ..< site.fileOffset + movz.count])
        guard written == movz else {
            throw PatcherError.patchVerificationFailed(
                "\(component): site at 0x\(hex(UInt64(site.fileOffset))) reads \(written.hex) after write",
            )
        }

        var slots: [CustomFirmwareSlotRehash] = []
        if reattestsCodeSignature {
            slots = try CustomFirmwareMachOCodeSignature.reattest(&data, modifiedOffsets: [site.fileOffset])
            for slot in slots {
                log?("    re-attested \(slot)")
            }
        }

        log?("  [+] Patched at 0x\(hex(UInt64(site.fileOffset))): mov \(site.destRegisterName), #1")

        return Report(
            outcome: .patched,
            anchor: anchor,
            site: site,
            record: PatchRecord(
                patchID: patchID,
                component: component,
                fileOffset: site.fileOffset,
                virtualAddress: site.vma,
                originalBytes: original,
                patchedBytes: movz,
                beforeDisasm: "\(decodedOriginal.mnemonic) \(decodedOriginal.operandString)",
                afterDisasm: "mov \(site.destRegisterName), #1",
                description: "securityd's platform-binary eligibility check always reports eligible",
            ),
            reattestedSlots: slots,
        )
    }

    // MARK: - Locating

    /// Find the patch site without touching the binary.
    public static func locateSite(in data: Data) throws -> (anchor: Anchor, site: Site) {
        let data = data.startIndex == 0 ? data : Data(data)
        let sections = MachOParser.parseSections(from: data)
        guard !sections.isEmpty else {
            throw PatcherError.invalidFormat("not a 64-bit Mach-O, or it carries no sections")
        }
        guard let text = sections["__TEXT,__text"] else {
            throw PatcherError.invalidFormat("__TEXT,__text not found")
        }

        guard let notEligible = findExactString(notEligibleString, in: data, sections: sections) else {
            throw PatcherError.patchSiteNotFound(
                "\(component): \"\(notEligibleString)\" not found in any string section",
            )
        }
        guard let eligible = findExactString(eligibleString, in: data, sections: sections) else {
            throw PatcherError.patchSiteNotFound(
                "\(component): \"\(eligibleString)\" not found in any string section",
            )
        }

        guard let notEligibleRef = findStringReference(in: data, text: text, targetVMA: notEligible.stringVMA) else {
            throw PatcherError.patchSiteNotFound(
                "\(component): \"\(notEligibleString)\" is present but nothing in __TEXT,__text "
                    + "forms its address (ADRP+ADD) — the eligibility check looks compiled out",
            )
        }
        // A weaker, structural sanity check that this build still carries the
        // shape this patch understands — not required to be the same function.
        guard findStringReference(in: data, text: text, targetVMA: eligible.stringVMA) != nil else {
            throw PatcherError.patchSiteNotFound(
                "\(component): \"\(eligibleString)\" is present but nothing in __TEXT,__text forms its address",
            )
        }

        let anchor = Anchor(
            stringFileOffset: notEligible.fileOffset,
            stringVMA: notEligible.stringVMA,
            referenceFileOffset: notEligibleRef.fileOffset,
            referenceVMA: notEligibleRef.vma,
        )
        let site = try findEligibilityByte(in: data, text: text, after: notEligibleRef.vma)
        return (anchor, site)
    }

    /// Scan forward from the "not eligible" string xref for `ldrb w?, [x?, #0x18]`,
    /// then confirm that register feeds the function's return value through the
    /// unconditional branch that follows it.
    static func findEligibilityByte(in data: Data, text: MachOSectionInfo, after referenceVMA: UInt64) throws -> Site {
        let disassembler = ARM64Disassembler()
        func decode(_ vma: UInt64) -> ARM64Instruction? {
            guard vma >= text.address else { return nil }
            let offset = Int(text.fileOffset) + Int(vma - text.address)
            return disassembler.disassembleOne(in: data, at: offset, address: vma)
        }

        var ldrb: ARM64Instruction?
        var cursor = referenceVMA
        for _ in 0 ..< maxInstructionsToLdrb {
            cursor += 4
            guard let instruction = decode(cursor), let operands = instruction.detail?.operands else { continue }

            let isLdrbShape = instruction.mnemonic == "ldrb"
                && operands.count == 2
                && operands[0].type == .register
                && operands[1].type == .memory
                && operands[1].mem.disp == 0x18
            // A previous run's own output: `mov w?, #1` in the same spot. Matched
            // here, not just by `original == movz` in `patch(_:)`, so a second run
            // still resolves the site (and still re-validates the branch/and
            // shape below) instead of reporting "not found".
            let isOwnOutput = instruction.mnemonic == "mov"
                && operands.count == 2
                && operands[0].type == .register
                && operands[1].type == .immediate
                && operands[1].imm == 1

            guard isLdrbShape || isOwnOutput else { continue }
            ldrb = instruction
            break
        }
        guard let ldrbInstruction = ldrb, let destReg = ldrbInstruction.detail?.operands.first?.reg.name else {
            throw PatcherError.patchSiteNotFound(
                "\(component): no `ldrb ?, [?, #0x18]` within \(maxInstructionsToLdrb) instructions "
                    + "of the \"\(notEligibleString)\" xref at 0x\(hex(referenceVMA))",
            )
        }

        var branchTargetVMA: UInt64?
        cursor = ldrbInstruction.address
        for _ in 0 ..< maxInstructionsToBranch {
            cursor += 4
            guard let instruction = decode(cursor) else { break }
            guard instruction.mnemonic == "b", let target = branchTarget(of: instruction) else { continue }
            branchTargetVMA = target
            break
        }
        guard let targetVMA = branchTargetVMA else {
            throw PatcherError.patchSiteNotFound(
                "\(component): no unconditional branch within \(maxInstructionsToBranch) instructions "
                    + "of the `ldrb` at 0x\(hex(ldrbInstruction.address))",
            )
        }

        var confirmed = false
        var probe = targetVMA
        for _ in 0 ..< maxInstructionsAfterBranchTarget {
            guard let instruction = decode(probe) else { break }
            if instruction.mnemonic == "and",
               let operands = instruction.detail?.operands,
               operands.count >= 2,
               operands[0].type == .register, operands[0].reg.name == "w0",
               operands[1].type == .register, operands[1].reg.name == destReg
            {
                confirmed = true
                break
            }
            probe += 4
        }
        guard confirmed else {
            throw PatcherError.patchSiteNotFound(
                "\(component): branch at 0x\(hex(ldrbInstruction.address + 4)) targets 0x\(hex(targetVMA)), "
                    + "which does not reach `and w0, \(destReg), #1` within "
                    + "\(maxInstructionsAfterBranchTarget) instructions — not the eligibility return path",
            )
        }

        let fileOffset = Int(text.fileOffset) + Int(ldrbInstruction.address - text.address)
        return Site(
            fileOffset: fileOffset,
            vma: ldrbInstruction.address,
            destRegisterName: destReg,
            mnemonic: ldrbInstruction.mnemonic,
            operandString: ldrbInstruction.operandString,
        )
    }

    // MARK: - String search

    /// One occurrence of an exact, NUL-terminated C string in a Mach-O's
    /// string sections.
    struct StringSite: Sendable, Equatable {
        let fileOffset: Int
        let stringVMA: UInt64
    }

    /// Find `needle` as a whole string (not a substring) in any of
    /// ``stringSectionNames``.
    static func findExactString(_ needle: String, in data: Data, sections: [String: MachOSectionInfo]) -> StringSite? {
        let pattern = Data((needle + "\0").utf8)
        for section in sections.values where stringSectionNames.contains(section.sectionName) {
            let start = Int(section.fileOffset)
            let end = start + Int(section.size)
            guard start >= 0, end <= data.count, start < end else { continue }
            guard let match = data.range(of: pattern, in: start ..< end) else { continue }
            let position = match.lowerBound - start
            guard position == 0 || data[match.lowerBound - 1] == 0 else { continue }
            return StringSite(fileOffset: match.lowerBound, stringVMA: section.address + UInt64(position))
        }
        return nil
    }

    /// The ADRP of the first ADRP+ADD pair in `__TEXT,__text` that forms
    /// `targetVMA`. The pair need not be adjacent — the compiler interleaves
    /// other setup between them — so an ADRP is remembered per destination
    /// register and matched against a later ADD that reads it. Everything is
    /// read from Capstone's decoded operands: the ADRP's immediate is already
    /// the absolute page, and the ADD's is the page offset.
    static func findStringReference(
        in data: Data,
        text: MachOSectionInfo,
        targetVMA: UInt64,
    ) -> (fileOffset: Int, vma: UInt64)? {
        let targetPage = Int64(targetVMA & ~0xFFF)
        let targetPageOffset = Int64(targetVMA & 0xFFF)
        let disassembler = ARM64Disassembler()

        var pendingADRP: [UInt32: (index: Int, fileOffset: Int, vma: UInt64, page: Int64)] = [:]
        let start = Int(text.fileOffset)
        let end = start + (Int(text.size) & ~3)
        guard start >= 0, end <= data.count else { return nil }

        for (index, offset) in stride(from: start, to: end, by: 4).enumerated() {
            let vma = text.address + UInt64(offset - start)
            guard let instruction = disassembler.disassembleOne(in: data, at: offset, address: vma),
                  let operands = instruction.detail?.operands
            else { continue }

            switch instruction.mnemonic {
            case "adrp":
                guard operands.count >= 2,
                      operands[0].type == .register,
                      operands[1].type == .immediate
                else { continue }
                pendingADRP[operands[0].reg.rawValue] = (index, offset, vma, operands[1].imm)

            case "add":
                guard operands.count >= 3,
                      operands[1].type == .register,
                      operands[2].type == .immediate,
                      let adrp = pendingADRP[operands[1].reg.rawValue],
                      adrp.page == targetPage,
                      operands[2].imm == targetPageOffset,
                      index - adrp.index <= maxADRPToADDInstructions
                else { continue }
                return (adrp.fileOffset, adrp.vma)

            default:
                continue
            }
        }
        return nil
    }

    /// The absolute address a branch jumps to, read from its last immediate
    /// operand, or `nil` when the instruction carries none.
    static func branchTarget(of instruction: ARM64Instruction) -> UInt64? {
        guard let operands = instruction.detail?.operands,
              let last = operands.last,
              last.type == .immediate,
              last.imm >= 0
        else { return nil }
        return UInt64(last.imm)
    }

    /// Parse a Capstone register name (`"w19"`) back to its index, for
    /// ``ARM64Encoder/encodeMovzW(rd:imm16:shift:)``.
    static func registerIndex(_ name: String) throws -> UInt32 {
        guard name.hasPrefix("w"), let index = UInt32(name.dropFirst()), index <= 30 else {
            throw PatcherError.invalidFormat("\(component): \"\(name)\" is not a 32-bit general register")
        }
        return index
    }

    // MARK: - Helpers

    static func hex(_ value: UInt64) -> String {
        String(value, radix: 16, uppercase: true)
    }
}
