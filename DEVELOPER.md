# The ZFlash Tool

The ZFlash tool it's a project forked from the Raspberry Pi Imager that has as its main goal to provide an easy way to choose, fetch and flash EVE-OS images to removable devices.

The ZFlash tool is provided to community by Zededa Inc.


## Contributing

### Linux

#### Get dependencies

- Install the build dependencies (Debian used as an example):

```sh
sudo apt install --no-install-recommends build-essential cmake git libgnutls28-dev
```

#### Get the source

```sh
git clone --depth 1 https://github.com/zededa/zflash
```

#### Build Qt

```sh
sudo ./build-qt.sh
```

This will build and install the version of Qt preferred for ZFlash into /opt/Qt/<version>. You must use `sudo` for the installation step to complete.

#### Build the AppImage

```sh
./create_appimage.sh
./ZFlash-*.AppImage
```

### Windows

#### Get dependencies

- Get the Qt online installer from: https://www.qt.io/download-open-source
  - During installation, choose Qt 6.9 with Mingw64 64-bit toolchain.
- For building the installer, install Inno Setup scriptable install system: https://jrsoftware.org/isdl.php
- Install Visual Studio Code (or a derivative) and the Qt Extension Pack.
- It is assumed you already have a valid code signing certificate, and the Windows 10 Kit (SDK) installed.

#### Building

Building ZFlash on Windows is best done with Visual Studio Code (or a derivative).

- Open Visual Studio Code, and select 'Clone repo'. Give it the git url of this project.
- Open the CMake plugin settings, and set the following Configure Args:
  - `-DQt6_ROOT=C:\Qt\6.9.0\mingw_64` - or the equivalent path you installed Qt 6.9 to.
  - `-DMINGW64_ROOT=C:\Qt\Tools\mingw1310_64` - or the equivalent path you installed mingw64 to.
  - `-DENABLE_INNO_INSTALLER=ON` - to enable the Inno Setup installer, rather than the legacy NSIS installer.
  - `-DIMAGER_SIGNED_APP=ON` - to enable code signing for redistribution.
- In the CMake plugin tab, ensure you have selected the `MinSizeRel` variant if you intend to distribute to others.
- In the CMake plugin tab, select the 'inno_installer' target, and build it
- Your resultant installer will be located in `%WORKSPACE%\build\installer`

Signing can be tuned with:

- `-DIMAGER_SIGN_CERT_SHA1=<thumbprint>` - certificate in `Cert:\CurrentUser\My` to sign with (default: `signtool /a` picks one).
- `-DIMAGER_SIGN_TIMESTAMP_URL=<url>` - RFC 3161 timestamp server (default: `http://timestamp.digicert.com`; empty disables timestamping).

#### Self-signed builds

For test/internal builds without a commercial certificate, run from a PowerShell prompt:

```powershell
.\build-win-selfsigned.ps1 -TrustLocally
```

It creates (or reuses) a self-signed code signing certificate in `Cert:\CurrentUser\My`, exports the
public part to `certs\zflash-codesign.cer`, and builds the signed application and installer in
`src\build-w64`. See `Get-Help .\build-win-selfsigned.ps1 -Full` for options (`-TimestampUrl ""` for
offline builds, `-PfxFile` to use an existing certificate, `-SignOnly <files>` to just sign files).

Windows only trusts the result on machines where `zflash-codesign.cer` has been imported into the
`Trusted Root Certification Authorities` and `Trusted Publishers` stores. SmartScreen will still warn,
since it relies on reputation that self-signed certificates do not have.

### macOS

#### Get dependencies

- Get the Qt online installer from: https://www.qt.io/download-open-source
  - During installation, choose Qt 6.9.
- Install Visual Studio Code (or a derivative), and the Qt Extension Pack.
- It is assumed you have an Apple developer subscription, and already have a "Developer ID" code signing certificate for distribution outside the Mac Store.

#### Building

Building ZFlash on Windows is best done with Visual Studio Code (or a derivative).

- Open Visual Studio Code, and select 'Clone repo'. Give it the git url of this project.
- Open the CMake plugin settings, and set the following Configure Args:
  - `-DQt6_ROOT=/opt/Qt6/6.9.0/gcc_arm64` - or the equivalent path you installed Qt 6.9 to.
  - `-DIMAGER_SIGNED_APP=ON` - to enable code signing.
  - `-DIMAGER_SIGNING_IDENTITY=$cn` - to specify the Developer ID Certificate Common Name.
  - `-DIMAGER_NOTARIZE_APP=ON` - to enable automatic notarization for distribution to others.
  - `-DIMAGER_NOTARIZE_KEYCHAIN_PROFILE=notarytool-password` - specify the name of the keychain item containing your Apple ID credentials for notarizing.
- In the CMake plugin tab, ensure you have selected the `MinSizeRel` variant if you intend to distribute to others.
- In the CMake plugin tab, select the 'zflash' target, and build it
- Your resultant DMG will be located at `$WORKSPACE\build\ZFlash Imager-$VERSION.dmg`

## Continuous integration and releases

- `.github/workflows/build.yml` builds the Linux AppImage (x86_64), Windows installer (x64) and
  macOS DMG (universal) for every pull request. The packages are attached to the workflow run as artifacts.
- `.github/workflows/release.yml` is started manually (Actions → Release → Run workflow). It builds
  the same packages, creates the GitHub release (tag defaults to `v<version>` from `src/CMakeLists.txt`,
  created as a draft by default) and uploads the packages plus a `SHA256SUMS` file.
- To sign the Windows binaries in a release, add the repository secrets `WINDOWS_SIGNING_PFX`
  (the .pfx file, base64-encoded: `base64 -w0 sign.pfx`) and `WINDOWS_SIGNING_PFX_PASSWORD`, then
  tick "Sign the Windows binaries" when running the workflow.

## Other notes

### Custom repository

If the application is started with "--repo [your own URL]" it will use a custom image repository.
So can simply create another 'start menu shortcut' to the application with that parameter to use the application with your own images.

### License

The main code of the Imaging Utility is made available under the terms of the Apache license.
See license.txt and files in "src/dependencies" folder for more information about the various open source licenses that apply to the third-party dependencies used such as Qt, libarchive, drivelist, mountutils and libcurl.
For the embedded (netboot) build see also "embedded/legal-info" for more information about the extra system software included in that.
