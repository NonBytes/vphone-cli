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
            "Hooks Security.framework's trust evaluation (SecTrustEvaluate, SecTrustEvaluateWithError, SecTrustGetTrustResult) so a proxy's certificate is accepted, covering most apps that pin through the system trust store. An app with its own pinning (a bundled public key check, for example) needs a script of its own."
        case .jailbreakDetectionBypass:
            "Hides the common jailbreak tells (Cydia/Sileo/Zebra/Filza/rootless paths and URL schemes, substrate/substitute/libhooker/ellekit/bash/ssh/sshd/apt paths, fork()) from the usual Objective-C and libc checks (access, stat, lstat, fopen). A detector with its own anti-Frida or anti-debugger check needs a script of its own."
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
        var hookedCount = 0;

        var hookTrustResult = function (name) {
            var addr = security ? security.findExportByName(name) : null;
            if (!addr) return;
            Interceptor.replace(addr, new NativeCallback(function (trust, result) {
                if (!result.isNull()) {
                    result.writeU32(1); // kSecTrustResultProceed
                }
                return 0; // errSecSuccess
            }, 'int', ['pointer', 'pointer']));
            hookedCount++;
            console.log('[+] ' + name + ' hooked');
        };

        hookTrustResult('SecTrustEvaluate');
        hookTrustResult('SecTrustGetTrustResult');

        var evaluateWithError = security ? security.findExportByName('SecTrustEvaluateWithError') : null;
        if (evaluateWithError) {
            Interceptor.replace(evaluateWithError, new NativeCallback(function (trust, error) {
                if (!error.isNull()) {
                    error.writePointer(ptr(0));
                }
                return 1; // true
            }, 'bool', ['pointer', 'pointer']));
            hookedCount++;
            console.log('[+] SecTrustEvaluateWithError hooked');
        }
        if (hookedCount === 0) {
            console.log('[-] No SecTrust* exports were found in Security');
        }
    })();
    """

    private static let jailbreakDetectionBypassSource = """
    // Jailbreak Detection Bypass — hides the usual tells (Cydia/Sileo/Zebra/Filza
    // paths and URL schemes, substrate/substitute/libhooker/ellekit/bash/ssh/sshd/apt
    // paths, fork()) from common Objective-C and libc checks. Does not cover an
    // app's own anti-Frida or anti-debugger checks.
    (function () {
        var suspectPattern = /Cydia|Sileo|Zebra|Filza|substrate|MobileSubstrate|libhooker|libsubstitute|ellekit|\\/var\\/jb|\\/private\\/var\\/jb|\\/bin\\/bash|\\/bin\\/su|\\/usr\\/bin\\/ssh|\\/usr\\/sbin\\/sshd|\\/etc\\/apt|\\/private\\/var\\/lib\\/apt/i;
        var suspectSchemePattern = /^(?:cydia|sileo|zbra|filza|undecimus):\\/\\//i;

        if (typeof ObjC !== 'undefined' && ObjC.available) {
            var fileExists = ObjC.classes.NSFileManager['- fileExistsAtPath:'];
            if (fileExists) {
                Interceptor.attach(fileExists.implementation, {
                    onEnter(args) {
                        this.suspect = !args[2].isNull() && suspectPattern.test(new ObjC.Object(args[2]).toString());
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
                        this.suspect = !args[2].isNull() && suspectSchemePattern.test(new ObjC.Object(args[2]).toString());
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
                            this.suspect = suspectSchemePattern.test(nsStringToJs(urlStr));
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

        var errnoAddr = Module.findGlobalExportByName('__error');
        var errnoFn = errnoAddr ? new NativeFunction(errnoAddr, 'pointer', []) : null;
        var setEnoent = function () {
            if (errnoFn) errnoFn().writeS32(2); // ENOENT
        };

        var hooked = {};
        ['access', 'stat', 'lstat', 'stat64', 'lstat64'].forEach(function (name) {
            var addr = Module.findGlobalExportByName(name);
            if (!addr) return;
            var key = addr.toString();
            if (hooked[key]) return;
            hooked[key] = true;
            Interceptor.attach(addr, {
                onEnter(args) {
                    this.suspect = !args[0].isNull() && suspectPattern.test(args[0].readUtf8String() || '');
                },
                onLeave(retval) {
                    if (this.suspect) {
                        retval.replace(-1);
                        setEnoent();
                    }
                },
            });
            console.log('[+] ' + name + '() hooked');
        });

        var fopenAddr = Module.findGlobalExportByName('fopen');
        var fcloseAddr = Module.findGlobalExportByName('fclose');
        var fcloseFn = fcloseAddr ? new NativeFunction(fcloseAddr, 'int', ['pointer']) : null;
        if (fopenAddr && !hooked[fopenAddr.toString()]) {
            hooked[fopenAddr.toString()] = true;
            Interceptor.attach(fopenAddr, {
                onEnter(args) {
                    this.suspect = !args[0].isNull() && suspectPattern.test(args[0].readUtf8String() || '');
                },
                onLeave(retval) {
                    if (this.suspect) {
                        if (!retval.isNull() && fcloseFn) fcloseFn(retval);
                        retval.replace(ptr(0));
                        setEnoent();
                    }
                },
            });
            console.log('[+] fopen() hooked');
        }

        var fork = Module.findGlobalExportByName('fork');
        if (fork) {
            Interceptor.replace(fork, new NativeCallback(function () { return -1; }, 'int', []));
            console.log('[+] fork() hooked');
        }
    })();
    """
}
