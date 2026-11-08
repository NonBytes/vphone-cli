import Foundation
import Darwin

final class GadgetFixtureServer:@unchecked Sendable {
    let fd:Int32, path:String, usb:Bool
    let lock=NSLock()
    var methods:[String]=[]
    var existing=false, wrongID=false, launchPID=4242
    init(path:String,usb:Bool=false) throws {
        self.path=path; self.usb=usb
        fd=socket(AF_UNIX,SOCK_STREAM,0)
        var address=sockaddr_un(); address.sun_family=sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of:&address.sun_path) {$0.copyBytes(from:Array(path.utf8)+[0])}
        let bound=withUnsafePointer(to:&address) {p in p.withMemoryRebound(to:sockaddr.self,capacity:1) {bind(fd,$0,socklen_t(MemoryLayout<sockaddr_un>.size))}}
        precondition(bound==0 && listen(fd,8)==0)
        Thread { [self] in
            while true {
                let peer=accept(fd,nil,nil); if peer<0 {return}
                _=fcntl(peer,F_SETNOSIGPIPE,1)
                do {
                    if usb {try serveUSB(peer)} else {try serveRPC(peer)}
                } catch {}
                close(peer)
            }
        }.start()
    }
    func stop() {shutdown(fd,SHUT_RDWR); close(fd); unlink(path)}
    func snapshot()->[String] {lock.withLock {methods}}
    func serveRPC(_ peer:Int32) throws {
        var data=Data(), byte:UInt8=0
        while read(peer,&byte,1)==1 && byte != 10 {data.append(byte)}
        let request=try JSONSerialization.jsonObject(with:data) as! [String:Any]
        let method=request["method"] as? String ?? request["t"] as? String ?? ""
        let result:[String:Any]=lock.withLock {
            methods.append(method)
            switch method {
            case "apps.list":return ["apps":existing ? [["bundle_id":"com.vphone.fixture.gadget"]] : []]
            case "push":
                let url=URL(fileURLWithPath:request["local"] as! String)
                precondition((try? Data(contentsOf:url))==Data("IPA-FIXTURE".utf8),"Must push verified private copy")
                return [:]
            case "apps.install":existing=true; return ["bundle_id":wrongID ? "wrong.app" : "com.vphone.fixture.gadget","msg":"Installed"]
            case "apps.launch":return ["pid":launchPID]
            default:return [:]
            }
        }
        let reply=try JSONSerialization.data(withJSONObject:["ok":true,"result":result])
        try VPhoneGadgetUSB.write(reply,fd:peer)
    }
    func packet(_ fields:[String:Any],fd:Int32) throws {
        let body=try PropertyListSerialization.data(fromPropertyList:fields,format:.xml,options:0)
        var data=Data()
        for word in [UInt32(body.count+16),1,8,1] {var value=word.littleEndian; withUnsafeBytes(of:&value){data.append(contentsOf:$0)}}
        data.append(body)
        for start in stride(from:0,to:data.count,by:7) {try VPhoneGadgetUSB.write(data.subdata(in:start..<min(start+7,data.count)),fd:fd)}
    }
    func serveUSB(_ peer:Int32) throws {
        let head=try VPhoneGadgetUSB.read(16,fd:peer)
        let length=head.prefix(4).reversed().reduce(UInt32(0)){($0<<8)|UInt32($1)}
        guard (16...65536).contains(length) else {return}
        let body=try VPhoneGadgetUSB.read(Int(length)-16,fd:peer)
        let request=try PropertyListSerialization.propertyList(from:body,format:nil) as! [String:Any]
        if request["MessageType"] as? String == "ListDevices" {
            try packet(["DeviceList":[
                ["DeviceID":77,"Properties":["SerialNumber":"0000FE01-AAAAAAAAAAAAAAAA","ConnectionType":"USB"]],
                ["DeviceID":42,"Properties":["SerialNumber":"0000FE01-1234567890ABCDEF","ConnectionType":"USB"]]
            ]],fd:peer)
        } else {
            precondition(request["DeviceID"] as? Int==42,"Must never select first device")
            precondition(request["PortNumber"] as? Int==41833,"Port must be network byte order")
            try packet(["MessageType":"Result","Number":0],fd:peer)
            let message=try VPhoneGadgetUSB.read(5,fd:peer)
            try VPhoneGadgetUSB.write(message,fd:peer)
        }
    }
}
@main struct GadgetDeploymentTests {
    static func rejects(_ body:() throws -> Void) {do {try body(); fatalError("Unsafe USB selection accepted")} catch {}}
    @MainActor static func main() async throws {
        let work=try VPhoneIPAArchive.makeWorkspace()
        defer {try? FileManager.default.removeItem(at:work)}
        // Short socket paths remain below sockaddr_un.sun_path's bound.
        let root=URL(fileURLWithPath:"/private/tmp/gadget-flow-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        let dirs=try ["one","two"].map {name in let url=root.appendingPathComponent(name); try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true); return url}
        let servers=try dirs.map {try GadgetFixtureServer(path:$0.appendingPathComponent("vphone.sock").path)}
        defer {servers.forEach {$0.stop()}}
        let machines=["one","two"].map {VPhoneGadgetMachine(json:["name":$0,"libraryRoot":root.path,"udid":"0000FE01-1234567890ABCDEF","state":"running"])!}
        let file=work.appendingPathComponent("fixture.ipa"), bytes=Data("IPA-FIXTURE".utf8)
        try bytes.write(to:file)
        let artifact=VPhoneGadgetArtifact(file:file,result:.init(bundleID:"com.vphone.fixture.gadget",size:Int64(bytes.count),sha256:VPhoneEvidencePackage.hash(bytes),report:Data()),options:.init(token:String(repeating:"a",count:64)))
        let model=VPhoneGadgetDeployment(directory:dirs[0]); model.listMachines={machines}
        model.reset(artifact); await model.refresh()
        precondition(model.selectedID==machines[0].id && !model.installed && !model.launched)
        await model.launch(); precondition(servers[0].snapshot().isEmpty,"No automatic launch")
        await model.install(); precondition(model.installed && !model.launched)
        precondition(!servers[0].snapshot().contains("apps.launch"))
        let pushes=servers[0].snapshot().filter {$0=="push"}.count
        await model.install(); precondition(model.error != nil && servers[0].snapshot().filter {$0=="push"}.count==pushes,"Updating requires explicit opt-in")
        await model.launch(); precondition(model.launched)
        var handed=false
        model.route="custom"; model.customEndpoint="127.0.0.1:27043"
        model.openSession={control,endpoint,token,relay in
            precondition(control.machineDirectory.path==machines[0].directory.path && endpoint=="127.0.0.1:27043" && token==artifact.options.token && relay==nil)
            handed=true; return true
        }
        await model.handoff(); precondition(handed)
        model.select(machines[1].id); precondition(!model.installed && !model.launched && !model.allowUpdate && model.route=="usb" && model.customEndpoint.isEmpty)
        await model.launch(); precondition(servers[1].snapshot().isEmpty)
        try Data("changed".utf8).write(to:file)
        await model.install(); precondition(model.error != nil && servers[1].snapshot().isEmpty,"Changed IPA must fail before guest side effects")
        try bytes.write(to:file)
        servers[1].lock.withLock {servers[1].wrongID=true}
        await model.install(); precondition(!model.installed && model.error != nil)
        await model.launch(); precondition(!servers[1].snapshot().contains("apps.launch"))
        model.reset(); precondition(model.artifact==nil && !model.installed && !model.launched)
        let udid="0000FE01-1234567890ABCDEF"
        rejects {_=try VPhoneGadgetUSB.device(["DeviceList":[]],udid:udid)}
        let network:[String:Any]=["DeviceID":42,"Properties":["SerialNumber":udid,"ConnectionType":"Network"]]
        rejects {_=try VPhoneGadgetUSB.device(["DeviceList":[network]],udid:udid)}
        let device:[String:Any]=["DeviceID":42,"Properties":["SerialNumber":udid,"ConnectionType":"USB"]]
        rejects {_=try VPhoneGadgetUSB.device(["DeviceList":[device,device]],udid:udid)}
        let usb=try GadgetFixtureServer(path:root.appendingPathComponent("usb.sock").path,usb:true); defer {usb.stop()}
        let fd=try await Task.detached {try VPhoneGadgetUSB.connect(udid:udid,port:27043,path:usb.path,allowUserPeer:true)}.value
        try VPhoneGadgetUSB.write(Data("hello".utf8),fd:fd)
        let echo=try VPhoneGadgetUSB.read(5,fd:fd); precondition(echo==Data("hello".utf8)); close(fd)
        let relay=try VPhoneFridaPortRelay {onData,onClose in
            let fd=try await Task.detached {try VPhoneGadgetUSB.connect(udid:udid,port:27043,path:usb.path,allowUserPeer:true)}.value
            return VPhoneGadgetUSBChannel(fd:fd,onData:onData,onClose:onClose)
        }
        let port=try await relay.start(); defer {relay.stop()}
        try await Task.detached {
            let fd=socket(AF_INET,SOCK_STREAM,0); defer {close(fd)}
            var address=sockaddr_in(); address.sin_family=sa_family_t(AF_INET); address.sin_port=port.bigEndian; address.sin_addr.s_addr=inet_addr("127.0.0.1")
            let result=withUnsafePointer(to:&address){p in p.withMemoryRebound(to:sockaddr.self,capacity:1){Darwin.connect(fd,$0,socklen_t(MemoryLayout<sockaddr_in>.size))}}
            precondition(result==0)
            try VPhoneGadgetUSB.write(Data("hello".utf8),fd:fd)
            let echo=try VPhoneGadgetUSB.read(5,fd:fd); precondition(echo==Data("hello".utf8))
        }.value
        print("PASS: verified IPA install, explicit launch/update, VM scope reset, token handoff, wrong-ID refusal, USB exact-device selection, fragmented plist and loopback byte relay")
    }
}
