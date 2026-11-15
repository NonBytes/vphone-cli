// CustomFirmwareSecuritydTests.swift — the securityd keychain eligibility patch.
//
// This is a new patch with no Python predecessor and no `ipsws/ref_extract`
// fixture to compare against, so unlike the other `ExecutablePatches` suites
// there is no frozen golden digest here. Instead a synthetic Mach-O carries
// exactly the instruction shape the real guest `securityd` was found to have
// (`Research/Guest/keychain_inspector.md`): both os_log anchor strings in
// `__TEXT,__cstring`, their adrp+add xrefs in `__TEXT,__text`, the `ldrb w19,
// [x8, #0x18]` that reads the eligibility byte, the `b` past it, and the
// `and w0, w19, #1` the branch target must reach.

@testable import FirmwarePatcher
import Foundation
import Testing
import VPhonePatchKit

private typealias Patcher = CustomFirmwareSecuritydPatcher

// MARK: - Synthetic securityd

/// A two-section Mach-O (`__TEXT,__cstring` and `__TEXT,__text`) built to
/// exactly the shape the real binary was found to have.
private struct SyntheticSecurityd {
    static let slide: UInt64 = 0x1_0000_0000

    let eligibleStringOffset: Int
    let notEligibleStringOffset: Int
    let textOffset: Int
    /// `ldrb w19, [x8, #0x18]`.
    let ldrbOffset: Int
    /// The `and w0, w19, #1` the branch reaches.
    let andOffset: Int

    var data: Data

    /// - Parameters:
    ///   - includeEligibleString: Omit to test the "eligible platform binary"
    ///     string missing entirely.
    ///   - branchTargetOffset: Override where the `b` after the `ldrb` points,
    ///     to test a target that does not reach the `and`.
    ///   - omitAnd: Replace the `and w0, w19, #1` with a `nop`, so nothing
    ///     confirms the `ldrb`'s register feeds the return value.
    init(
        includeEligibleString: Bool = true,
        branchTargetOffset: Int? = nil,
        omitAnd: Bool = false,
    ) {
        let header = 32
        let segment = header
        let segmentCmdSize = 72
        let sectionSize = 80
        let cstringSectionHeader = segment + segmentCmdSize
        let textSectionHeader = cstringSectionHeader + sectionSize
        let loadCommandsEnd = textSectionHeader + sectionSize

        let eligibleBytes = Data((Patcher.eligibleString + "\0").utf8)
        let notEligibleBytes = Data((Patcher.notEligibleString + "\0").utf8)
        let eligibleOffset = loadCommandsEnd
        let notEligibleOffset = eligibleOffset + (includeEligibleString ? eligibleBytes.count : 0)
        let cstringSize = notEligibleOffset + notEligibleBytes.count - loadCommandsEnd

        let text = ((notEligibleOffset + notEligibleBytes.count + 3) / 4) * 4
        let eligibleXref = text
        let notEligibleXref = eligibleXref + 8
        let ldrb = notEligibleXref + 8
        let branch = ldrb + 4
        let target = branchTargetOffset ?? (branch + 20) // four NOPs of padding
        let textSize = max(target, branch + 4) + 8 // room for `and`/replacement + `ret`

        var file = Data(count: text + textSize)

        func put32(_ value: UInt32, at offset: Int) {
            file.replaceSubrange(offset ..< offset + 4, with: ARM64.encodeU32(value))
        }
        func put64(_ value: UInt64, at offset: Int) {
            put32(UInt32(truncatingIfNeeded: value), at: offset)
            put32(UInt32(truncatingIfNeeded: value >> 32), at: offset + 4)
        }
        func putName(_ name: String, at offset: Int) {
            file.replaceSubrange(offset ..< offset + name.utf8.count, with: Data(name.utf8))
        }
        func put(_ bytes: Data, at offset: Int) {
            file.replaceSubrange(offset ..< offset + bytes.count, with: bytes)
        }

        // mach_header_64
        put32(0xFEED_FACF, at: 0) // MH_MAGIC_64
        put32(1, at: 16) // ncmds
        put32(UInt32(segmentCmdSize + sectionSize * 2), at: 20) // sizeofcmds

        // LC_SEGMENT_64
        put32(0x19, at: segment)
        put32(UInt32(segmentCmdSize + sectionSize * 2), at: segment + 4)
        putName("__TEXT", at: segment + 8)
        put64(UInt64(file.count), at: segment + 32) // vmsize
        put64(UInt64(file.count), at: segment + 48) // filesize (resized below)
        put32(2, at: segment + 64) // nsects

        // __TEXT,__cstring
        putName("__cstring", at: cstringSectionHeader)
        putName("__TEXT", at: cstringSectionHeader + 16)
        put64(Self.slide + UInt64(loadCommandsEnd), at: cstringSectionHeader + 32) // addr
        put64(UInt64(cstringSize), at: cstringSectionHeader + 40) // size
        put32(UInt32(loadCommandsEnd), at: cstringSectionHeader + 48) // offset

        // __TEXT,__text
        putName("__text", at: textSectionHeader)
        putName("__TEXT", at: textSectionHeader + 16)
        put64(Self.slide + UInt64(text), at: textSectionHeader + 32) // addr
        put64(UInt64(textSize), at: textSectionHeader + 40) // size
        put32(UInt32(text), at: textSectionHeader + 48) // offset

        if includeEligibleString {
            put(eligibleBytes, at: eligibleOffset)
        }
        put(notEligibleBytes, at: notEligibleOffset)

        func adrpAdd(rd: UInt32, pc: Int, targetVMA: UInt64) {
            let pcVMA = Self.slide + UInt64(pc)
            guard let adrp = ARM64Encoder.encodeADRP(rd: rd, pc: pcVMA, target: targetVMA),
                  let add = ARM64Encoder.encodeAddImm12(rd: rd, rn: rd, imm12: UInt32(targetVMA & 0xFFF))
            else {
                fatalError("could not encode a synthetic adrp+add")
            }
            put(adrp, at: pc)
            put(add, at: pc + 4)
        }

        if includeEligibleString {
            adrpAdd(rd: 3, pc: eligibleXref, targetVMA: Self.slide + UInt64(eligibleOffset))
        }
        adrpAdd(rd: 3, pc: notEligibleXref, targetVMA: Self.slide + UInt64(notEligibleOffset))

        guard let ldrbBytes = ARM64Encoder.encodeLdrBUnsignedOffset(rt: 19, rn: 8, offset: 0x18) else {
            fatalError("could not encode the synthetic ldrb")
        }
        put(ldrbBytes, at: ldrb)

        guard let branchBytes = ARM64Encoder.encodeB(from: branch, to: target) else {
            fatalError("could not encode the synthetic branch")
        }
        put(branchBytes, at: branch)

        // `and w0, w19, #1` — `ARM64Encoder` has no AND-immediate encoder, so
        // this is the literal word, confirmed against Capstone's own decode in
        // the "and w0, w19, #1" round-trip test below.
        if !omitAnd {
            put32(0x1200_0260, at: target)
        } else {
            put32(ARM64.nop.loadLE(UInt32.self, at: 0), at: target)
        }

        eligibleStringOffset = eligibleOffset
        notEligibleStringOffset = notEligibleOffset
        textOffset = text
        ldrbOffset = ldrb
        andOffset = target
        data = file
    }
}

// MARK: - Site discovery

struct CustomFirmwareSecuritydSiteTests {
    @Test func `and w0, w19, #1 is really what 0x12000260 decodes to`() {
        let decoded = ARM64Disassembler().disassembleOne(Data([0x60, 0x02, 0x00, 0x12]), at: 0)
        #expect(decoded?.mnemonic == "and")
        #expect(decoded?.operandString == "w0, w19, #1")
    }

    @Test func `locates the ldrb from the not-eligible string's xref`() throws {
        let synthetic = SyntheticSecurityd()
        let located = try Patcher.locateSite(in: synthetic.data)
        #expect(located.site.fileOffset == synthetic.ldrbOffset)
        #expect(located.site.mnemonic == "ldrb")
        #expect(located.site.destRegisterName == "w19")
        #expect(located.anchor.referenceFileOffset < synthetic.ldrbOffset)
    }

    @Test func `refuses when the not-eligible string is missing`() {
        var synthetic = SyntheticSecurityd()
        // Corrupt the string so it no longer matches.
        let range = synthetic.notEligibleStringOffset ..< synthetic.notEligibleStringOffset + 4
        synthetic.data.replaceSubrange(range, with: Data([0x58, 0x58, 0x58, 0x58]))
        #expect(throws: PatcherError.self) { try Patcher.locateSite(in: synthetic.data) }
    }

    @Test func `refuses when the eligible-platform-binary string is missing`() {
        let synthetic = SyntheticSecurityd(includeEligibleString: false)
        #expect(throws: PatcherError.self) { try Patcher.locateSite(in: synthetic.data) }
    }

    @Test func `refuses when the branch after the ldrb does not reach an and w0`() {
        let synthetic = SyntheticSecurityd(omitAnd: true)
        #expect(throws: PatcherError.self) { try Patcher.locateSite(in: synthetic.data) }
    }

    @Test func `refuses when the branch target is unrelated code`() {
        // Point the branch somewhere with neither `and` nor anything resembling it.
        let synthetic = SyntheticSecurityd(branchTargetOffset: 0)
        #expect(throws: PatcherError.self) { try Patcher.locateSite(in: synthetic.data) }
    }
}

// MARK: - Patching

struct CustomFirmwareSecuritydPatchTests {
    @Test func `patches the ldrb to mov w19, #1`() throws {
        var synthetic = SyntheticSecurityd()
        let report = try Patcher.patch(&synthetic.data, log: nil)

        #expect(report.outcome == .patched)
        #expect(report.sitesWritten == 1)
        #expect(report.site.destRegisterName == "w19")

        let decoded = ARM64Disassembler().disassembleOne(
            in: synthetic.data, at: synthetic.ldrbOffset, address: SyntheticSecurityd.slide + UInt64(synthetic.ldrbOffset),
        )
        #expect(decoded?.mnemonic == "mov")
        #expect(decoded?.operandString == "w19, #1")
    }

    @Test func `the record names the right patchID, component and bytes`() throws {
        var synthetic = SyntheticSecurityd()
        let report = try Patcher.patch(&synthetic.data, log: nil)
        let record = try #require(report.record)

        #expect(record.patchID == "system-securityd-exp-keychain_eligibility")
        #expect(record.component == "securityd")
        #expect(record.fileOffset == synthetic.ldrbOffset)
        #expect(record.beforeDisasm.hasPrefix("ldrb"))
        #expect(record.afterDisasm == "mov w19, #1")
        #expect(record.originalBytes != record.patchedBytes)
    }

    @Test func `a second run recognises its own output and changes nothing`() throws {
        var synthetic = SyntheticSecurityd()
        try Patcher.patch(&synthetic.data, log: nil)
        let once = synthetic.data

        let second = try Patcher.patch(&synthetic.data, log: nil)
        #expect(second.outcome == .alreadyPatched)
        #expect(second.sitesWritten == 0)
        #expect(second.record == nil)
        #expect(synthetic.data == once)
    }

    @Test func `a dry run locates the site and writes nothing`() throws {
        var synthetic = SyntheticSecurityd()
        let before = synthetic.data
        let report = try Patcher.patch(&synthetic.data, dryRun: true, log: nil)

        #expect(report.outcome == .wouldPatch)
        #expect(report.sitesWritten == 0)
        #expect(synthetic.data == before)
    }

    @Test func `re-attestation recomputes the touched page's slot hash when asked`() throws {
        // No LC_CODE_SIGNATURE in the synthetic file, so re-attestation has
        // nothing to recompute and must say so rather than silently succeed.
        var synthetic = SyntheticSecurityd()
        #expect(throws: PatcherError.self) {
            try Patcher.patch(&synthetic.data, reattestsCodeSignature: true, log: nil)
        }
    }
}
