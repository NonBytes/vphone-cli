# Bundled native Frida client

`vphone-frida-client` links the unmodified Frida Core 17.25.2 macOS arm64
devkit. It runs as an ordinary host child with no private entitlements.
There is no Python, external Frida CLI, or Homebrew runtime dependency.

Build input:
https://github.com/frida/frida/releases/download/17.25.2/frida-core-devkit-17.25.2-macos-arm64.tar.xz

SHA-256: `b91a1dc1a59857d0d23cab91792455122187765bea0d0bd72f48355651666353`

Frida Core's license is included in COPYING (wxWindows Library Licence 3.1).
Upstream source and dependency build recipes are available at:

- https://github.com/frida/frida/tree/17.25.2
- https://github.com/frida/frida-core/tree/17.25.2
- https://github.com/frida/frida/tree/17.25.2/releng

The devkit also incorporates dependencies, including GLib, GObject, GIO and
JSON-GLib under LGPL terms. Their upstream copyright and license notices are
preserved in `frida-core.h.gz` here and `frida-core.h` in the devkit. The LGPL
text is included as COPYING.LGPL. Consult the pinned upstream dependency
recipes for their source revisions. The helper source and its unlinked object
are included here so the helper can be rebuilt/relinked with a replacement
Frida Core devkit. The object is compressed so it is not mistaken for runtime
code by bundle admission. From a directory containing a compatible devkit:

```sh
gzip -dc vphone-frida-client.o.gz > vphone-frida-client.o
xcrun --sdk macosx clang -arch arm64 -mmacosx-version-min=15.0 \
  vphone-frida-client.o libfrida-core.a -lbsm -ldl -lresolv -lm \
  -framework Foundation -framework CoreFoundation -framework AppKit \
  -framework CoreServices -o vphone-frida-client
codesign --force --sign - vphone-frida-client
```

The build is `Build/BuildFridaClient.sh`. Downloading and compilation happen
only on the build machine. The shipped helper makes only the explicit Frida
connection selected in the Session window. Token and JavaScript arrive over a
private stdin pipe; stdout contains JSON-line lifecycle and script events.
EOF detaches and unloads; the target app is left running after a successful
spawn/resume or attach. A failed spawn before resume is terminated.
