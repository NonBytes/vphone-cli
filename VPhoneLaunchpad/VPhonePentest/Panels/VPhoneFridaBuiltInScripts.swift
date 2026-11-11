import Foundation

/// Ready-made Frida scripts for the two checks almost every iOS pentest
/// starts with, so a session doesn't need a script hunted down or written
/// from scratch first. Loaded the same way as a file the user chose
/// (`VPhoneFridaSessionModel.scriptSource`); neither persists past the
/// session, and neither is a substitute for a target-specific script.
enum VPhoneFridaBuiltInScript: String, CaseIterable, Identifiable {
    case sslPinningBypass
    case jailbreakDetectionBypass

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sslPinningBypass: "SSL Pinning Bypass"
        case .jailbreakDetectionBypass: "Jailbreak Detection Bypass"
        }
    }

    var summary: String {
        switch self {
        case .sslPinningBypass:
            "Hooks Security.framework's trust evaluation so a proxy's certificate is accepted, covering most apps that pin through the system trust store. An app with its own pinning (a bundled public key check, for example) needs a script of its own."
        case .jailbreakDetectionBypass:
            "Hides the common jailbreak tells (Cydia-family paths, the cydia:// scheme, su/bash/substrate paths, fork()) from the usual Objective-C and libc checks. A detector with its own anti-Frida or anti-debugger check needs a script of its own."
        }
    }

    var source: String {
        switch self {
        case .sslPinningBypass: Self.sslPinningBypassSource
        case .jailbreakDetectionBypass: Self.jailbreakDetectionBypassSource
        }
    }

    private static let sslPinningBypassSource = """
    // SSL Pinning Bypass — hooks Security.framework's trust evaluation so a
    // MITM proxy's certificate is accepted. Covers apps that pin through the
    // system trust store (SecTrust*); does not cover a pinning check an app
    // implements itself (e.g. comparing a bundled public key by hand).
    (function () {
        var security = Process.findModuleByName('Security');
        var evaluate = security ? security.findExportByName('SecTrustEvaluate') : null;
        if (evaluate) {
            Interceptor.replace(evaluate, new NativeCallback(function (trust, result) {
                if (!result.isNull()) {
                    result.writeU32(1); // kSecTrustResultProceed
                }
                return 0; // errSecSuccess
            }, 'int', ['pointer', 'pointer']));
            console.log('[+] SecTrustEvaluate hooked');
        }
        var evaluateWithError = security ? security.findExportByName('SecTrustEvaluateWithError') : null;
        if (evaluateWithError) {
            Interceptor.replace(evaluateWithError, new NativeCallback(function () {
                return 1; // true
            }, 'bool', ['pointer', 'pointer']));
            console.log('[+] SecTrustEvaluateWithError hooked');
        }
        if (!evaluate && !evaluateWithError) {
            console.log('[-] Neither SecTrustEvaluate nor SecTrustEvaluateWithError was found');
        }
    })();
    """

    private static let jailbreakDetectionBypassSource = """
    // Jailbreak Detection Bypass — hides the usual tells (Cydia-family
    // paths, the cydia:// scheme, su/bash/substrate paths, fork()) from the
    // common Objective-C and libc checks. Does not cover an app's own
    // anti-Frida or anti-debugger checks.
    (function () {
        var suspectPattern = /Cydia|Sileo|Zebra|substrate|MobileSubstrate|\\/bin\\/su|\\/usr\\/sbin\\/sshd|\\/etc\\/apt|\\/private\\/var\\/lib\\/apt/i;

        if (typeof ObjC !== 'undefined' && ObjC.available) {
            var fileExists = ObjC.classes.NSFileManager['- fileExistsAtPath:'];
            if (fileExists) {
                Interceptor.attach(fileExists.implementation, {
                    onEnter(args) {
                        this.suspect = suspectPattern.test(new ObjC.Object(args[2]).toString());
                    },
                    onLeave(retval) {
                        if (this.suspect) retval.replace(0);
                    },
                });
                console.log('[+] -[NSFileManager fileExistsAtPath:] hooked');
            }
            var canOpenURL = ObjC.classes.UIApplication['- canOpenURL:'];
            if (canOpenURL) {
                Interceptor.attach(canOpenURL.implementation, {
                    onEnter(args) {
                        this.suspect = /cydia:\\/\\//i.test(new ObjC.Object(args[2]).toString());
                    },
                    onLeave(retval) {
                        if (this.suspect) retval.replace(0);
                    },
                });
                console.log('[+] -[UIApplication canOpenURL:] hooked');
            }
        } else {
            var libobjc = Process.findModuleByName('libobjc.A.dylib');
            var getClass = libobjc ? libobjc.findExportByName('objc_getClass') : null;
            var registerName = libobjc ? libobjc.findExportByName('sel_registerName') : null;
            var getInstanceMethod = libobjc ? libobjc.findExportByName('class_getInstanceMethod') : null;
            var getImplementation = libobjc ? libobjc.findExportByName('method_getImplementation') : null;
            var msgSend = libobjc ? libobjc.findExportByName('objc_msgSend') : null;
            if (getClass && registerName && getInstanceMethod && getImplementation && msgSend) {
                var objcGetClass = new NativeFunction(getClass, 'pointer', ['pointer']);
                var selRegisterName = new NativeFunction(registerName, 'pointer', ['pointer']);
                var classGetInstanceMethod = new NativeFunction(getInstanceMethod, 'pointer', ['pointer', 'pointer']);
                var methodGetImplementation = new NativeFunction(getImplementation, 'pointer', ['pointer']);
                var objcMsgSendPtr = new NativeFunction(msgSend, 'pointer', ['pointer', 'pointer']);
                var utf8Sel = selRegisterName(Memory.allocUtf8String('UTF8String'));
                var absStrSel = selRegisterName(Memory.allocUtf8String('absoluteString'));
                var findImp = function (clsName, selName) {
                    var cls = objcGetClass(Memory.allocUtf8String(clsName));
                    if (cls.isNull()) return null;
                    var m = classGetInstanceMethod(cls, selRegisterName(Memory.allocUtf8String(selName)));
                    if (m.isNull()) return null;
                    var imp = methodGetImplementation(m);
                    return imp.isNull() ? null : imp;
                };
                var nsStringToJs = function (nsStr) {
                    if (nsStr.isNull()) return '';
                    var cstr = objcMsgSendPtr(nsStr, utf8Sel);
                    return cstr.isNull() ? '' : (cstr.readUtf8String() || '');
                };
                var fileExistsImp = findImp('NSFileManager', 'fileExistsAtPath:');
                if (fileExistsImp) {
                    Interceptor.attach(fileExistsImp, {
                        onEnter(args) {
                            this.suspect = suspectPattern.test(nsStringToJs(args[2]));
                        },
                        onLeave(retval) {
                            if (this.suspect) retval.replace(0);
                        },
                    });
                    console.log('[+] -[NSFileManager fileExistsAtPath:] hooked');
                }
                var canOpenURLImp = findImp('UIApplication', 'canOpenURL:');
                if (canOpenURLImp) {
                    Interceptor.attach(canOpenURLImp, {
                        onEnter(args) {
                            var urlStr = args[2].isNull() ? ptr(0) : objcMsgSendPtr(args[2], absStrSel);
                            this.suspect = /cydia:\\/\\//i.test(nsStringToJs(urlStr));
                        },
                        onLeave(retval) {
                            if (this.suspect) retval.replace(0);
                        },
                    });
                    console.log('[+] -[UIApplication canOpenURL:] hooked');
                }
            } else {
                console.log('[-] Objective-C runtime not available');
            }
        }

        var access = Module.findGlobalExportByName('access');
        if (access) {
            Interceptor.attach(access, {
                onEnter(args) {
                    this.suspect = !args[0].isNull() && suspectPattern.test(args[0].readUtf8String() || '');
                },
                onLeave(retval) {
                    if (this.suspect) retval.replace(-1);
                },
            });
            console.log('[+] access() hooked');
        }
        var fork = Module.findGlobalExportByName('fork');
        if (fork) {
            Interceptor.replace(fork, new NativeCallback(function () { return -1; }, 'int', []));
            console.log('[+] fork() hooked');
        }
    })();
    """
}
