import Foundation
import ArchiveKit
import MachO

@main struct GadgetPatchTests {
    static func rejects(_ operation: () throws -> Void) { do { try operation(); fatalError("Unsafe patch accepted") } catch {} }
    static func run(_ path: String,_ args:[String]) throws {
        let process = Process(); process.executableURL = URL(fileURLWithPath:path); process.arguments=args
        process.standardOutput=FileHandle.nullDevice; process.standardError=FileHandle.nullDevice
        try process.run(); process.waitUntilExit(); precondition(process.terminationStatus == 0)
    }
    static func maliciousZip(_ url: URL, path: String, link: String? = nil) {
        let writer = archive_write_new()!; defer { archive_write_free(writer) }
        precondition(archive_write_set_format_zip(writer) == ARCHIVE_OK)
        precondition(archive_write_open_filename(writer,url.path) == ARCHIVE_OK)
        let entry = archive_entry_new()!; defer { archive_entry_free(entry) }
        archive_entry_set_pathname(entry,path); archive_entry_set_perm(entry,0o644)
        archive_entry_set_filetype(entry,UInt32(link == nil ? S_IFREG : S_IFLNK))
        if let link { archive_entry_set_symlink(entry,link) }
        archive_entry_set_size(entry,0)
        precondition(archive_write_header(writer,entry) == ARCHIVE_OK); archive_write_close(writer)
    }
    static func main() throws {
        let fixtures = URL(fileURLWithPath:CommandLine.arguments[1])
        let work = try VPhoneIPAArchive.makeWorkspace(); defer { try? FileManager.default.removeItem(at:work) }
        let app = work.appendingPathComponent("Payload/GadgetFixture.app")
        try FileManager.default.createDirectory(at:app,withIntermediateDirectories:true)
        let binary = try Data(contentsOf:fixtures.appendingPathComponent("Fixture")), gadget = try Data(contentsOf:fixtures.appendingPathComponent("FixtureGadget.dylib"))
        let images = try VPhoneGadgetMachO.slices(binary,executable:true)
        precondition(images.count == 1 && !images[0].encrypted)
        let (patched,offsets) = try VPhoneGadgetMachO.inject(binary,gadget:gadget)
        precondition(offsets.count == 1 && patched.count == binary.count)
        let injectedSlices = try VPhoneGadgetMachO.slices(patched,executable:true); precondition(injectedSlices[0].libraries.contains(VPhoneGadgetMachO.loadPath))
        let added = ((24+VPhoneGadgetMachO.loadPath.utf8.count+1+7) & ~7)
        for index in 0..<binary.count where !(16..<24).contains(index) && !(offsets[0]..<offsets[0]+added).contains(index) { precondition(binary[index] == patched[index],"Non-header bytes changed") }
        rejects { _ = try VPhoneGadgetMachO.inject(patched,gadget:gadget) }
        var noPadding = binary; noPadding[offsets[0]]=0xff
        rejects { _ = try VPhoneGadgetMachO.inject(noPadding,gadget:gadget) }
        var encrypted = binary, cursor=32, found=false
        for _ in 0..<images[0].commands {
            let cmd=try VPhoneGadgetMachO.word(encrypted,cursor), length=Int(try VPhoneGadgetMachO.word(encrypted,cursor+4))
            if cmd == LC_ENCRYPTION_INFO_64 { VPhoneGadgetMachO.put(1,into:&encrypted,at:cursor+16); found=true }
            cursor += length
        }
        precondition(found)
        rejects { _ = try VPhoneGadgetMachO.inject(encrypted,gadget:gadget) }
        rejects { _ = try VPhoneGadgetMachO.slices(Data(repeating:0,count:64),executable:true) }
        let options = VPhoneGadgetOptions(token:String(repeating:"a",count:64))
        let config=try JSONSerialization.jsonObject(with:options.config()) as! [String:Any]
        let interaction=config["interaction"] as! [String:Any]
        precondition(interaction["address"] as? String == "127.0.0.1" && interaction["port"] as? Int == 27043 && interaction["on_load"] as? String == "resume")
        let binaryURL=app.appendingPathComponent("Fixture")
        try binary.write(to:binaryURL)
        let info:[String:Any]=["CFBundleIdentifier":"com.vphone.fixture.gadget","CFBundleExecutable":"Fixture","CFBundleName":"GadgetFixture","CFBundlePackageType":"APPL","CFBundleVersion":"1","CFBundleShortVersionString":"1.0","MinimumOSVersion":"17.0","UIDeviceFamily":[1,2]]
        try PropertyListSerialization.data(fromPropertyList:info,format:.xml,options:0).write(to:app.appendingPathComponent("Info.plist"))
        try run("/usr/bin/codesign",["--force","--sign","-","--timestamp=none",app.path])
        let job=VPhoneIPAArchive(), source=try job.pack(workspace:work)
        let original=try Data(contentsOf:source)
        let destination=work.appendingPathComponent("patched.ipa")
        let result=try VPhoneGadgetPatcher.patch(source:source,gadget:fixtures.appendingPathComponent("FixtureGadget.dylib"),destination:destination,options:options,job:job,workspaceParent:work)
        let sourceAfter=try Data(contentsOf:source); precondition(sourceAfter == original)
        precondition(result.size > 0 && !String(decoding:result.report,as:UTF8.self).contains(options.token))
        let extract=try VPhoneIPAArchive.makeWorkspace(in:work)
        let unpacked=try VPhoneGadgetArchive.extract(destination,workspace:extract,job:job)
        let patchedMain=try Data(contentsOf:unpacked.appendingPathComponent("Fixture"))
        let finalSlices=try VPhoneGadgetMachO.slices(patchedMain,executable:true)
        precondition(finalSlices[0].libraries.contains(VPhoneGadgetMachO.loadPath))
        precondition(FileManager.default.fileExists(atPath:unpacked.appendingPathComponent("Frameworks/FridaGadget.config").path))
        try run("/usr/bin/codesign",["--verify","--deep","--strict",unpacked.path])
        rejects { _ = try VPhoneGadgetPatcher.patch(source:source,gadget:fixtures.appendingPathComponent("FixtureGadget.dylib"),destination:source,options:options,job:job,workspaceParent:work) }
        for (path,link) in [("../escape",nil as String?),("Payload/Evil.app/Frameworks", "/private/tmp")] {
            let archive=work.appendingPathComponent(UUID().uuidString+".ipa"); maliciousZip(archive,path:path,link:link)
            let target=try VPhoneIPAArchive.makeWorkspace(in:work)
            rejects { _ = try VPhoneGadgetArchive.extract(archive,workspace:target,job:job) }
        }
        let cancelled=VPhoneIPAArchive(); cancelled.cancel()
        rejects { _ = try VPhoneGadgetPatcher.patch(source:source,gadget:fixtures.appendingPathComponent("FixtureGadget.dylib"),destination:work.appendingPathComponent("cancelled.ipa"),options:options,job:cancelled,workspaceParent:work) }
        print("PASS: native Gadget load commands, unchanged code bytes, encryption/padding/duplicate refusal, ZIP traversal/symlink checks, ad-hoc signature verification, private output and token-free report")
    }
}
