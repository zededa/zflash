<#
.SYNOPSIS
    Build ZFlash on Windows and sign it with a self-signed code signing certificate.

.DESCRIPTION
    1. Looks for a valid code signing certificate with the given subject in
       Cert:\CurrentUser\My. If none is found (or -Regenerate is given), a new
       self-signed one is created there. Alternatively, -PfxFile imports an
       existing certificate (e.g. certs\sign.pfx from gen-certs.sh).
    2. Exports the public certificate (.cer) to -CertDir, so it can be
       installed on the machines that should trust the build.
    3. Optionally trusts the certificate on this machine (-TrustLocally).
    4. Configures and builds the project with signing enabled, pointing signtool
       at the certificate by its thumbprint. The application, the installer and
       its uninstaller are all signed.

    With -SignOnly, no build is done and the given files are signed instead.

.EXAMPLE
    .\build-win-selfsigned.ps1 -TrustLocally

.EXAMPLE
    # Offline build, no timestamp server
    .\build-win-selfsigned.ps1 -TimestampUrl ""

.EXAMPLE
    # Sign already built files
    .\build-win-selfsigned.ps1 -SignOnly src\build-w64\installer\imager-1.0.0.exe
#>
[CmdletBinding()]
param(
    [string]   $Subject      = "CN=ZFlash Self-Signed Code Signing, O=Zededa Inc., L=San Jose, S=California, C=US",
    [int]      $ValidYears   = 3,
    [string]   $CertDir      = (Join-Path $PSScriptRoot "certs"),
    [switch]   $Regenerate,
    [string]   $PfxFile,
    [SecureString] $PfxPassword,
    [switch]   $ExportPfx,
    [switch]   $TrustLocally,
    # RFC 3161 timestamp server. Pass "" to skip timestamping (e.g. offline builds).
    [AllowEmptyString()]
    [string]   $TimestampUrl = "http://timestamp.digicert.com",
    [string]   $QtRoot       = "C:\Qt\6.9.1\mingw_64",
    [string]   $MingwRoot    = "C:\Qt\Tools\mingw1310_64",
    [string]   $BuildDir     = (Join-Path $PSScriptRoot "src\build-w64"),
    [string]   $Target       = "inno_installer",
    [int]      $Jobs         = 8,
    [string]   $SignTool,
    [string[]] $SignOnly
)

$ErrorActionPreference = "Stop"

function Find-SignTool {
    if ($SignTool) { return $SignTool }
    $cmd = Get-Command signtool.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $kitsRoot = (Get-ItemProperty -ErrorAction SilentlyContinue `
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows Kits\Installed Roots").KitsRoot10
    if (-not $kitsRoot) { $kitsRoot = "${env:ProgramFiles(x86)}\Windows Kits\10\" }
    $found = Get-ChildItem -Path (Join-Path $kitsRoot "bin") -Filter signtool.exe -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.Directory.Name -eq "x64" } |
        Sort-Object { $_.Directory.Parent.Name } -Descending |
        Select-Object -First 1
    if (-not $found) {
        throw "signtool.exe not found. Install the Windows 10/11 SDK or pass -SignTool <path>."
    }
    return $found.FullName
}

function Get-SigningCertificate {
    if ($PfxFile) {
        Write-Host "Importing $PfxFile into Cert:\CurrentUser\My"
        if (-not $PfxPassword) { $PfxPassword = Read-Host -AsSecureString "Password for $PfxFile" }
        $imported = Import-PfxCertificate -FilePath $PfxFile -Password $PfxPassword `
            -CertStoreLocation Cert:\CurrentUser\My -Exportable
        # A PFX may also carry CA certificates; pick the one with a private key.
        return $imported | Where-Object { $_.HasPrivateKey } | Select-Object -First 1
    }

    if (-not $Regenerate) {
        $existing = Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert |
            Where-Object { $_.Subject -eq $Subject -and $_.HasPrivateKey -and $_.NotAfter -gt (Get-Date).AddDays(1) } |
            Sort-Object NotAfter -Descending |
            Select-Object -First 1
        if ($existing) {
            Write-Host "Reusing existing certificate $($existing.Thumbprint) (expires $($existing.NotAfter))"
            return $existing
        }
    }

    Write-Host "Creating self-signed code signing certificate: $Subject"
    return New-SelfSignedCertificate `
        -Type CodeSigningCert `
        -Subject $Subject `
        -FriendlyName "ZFlash self-signed code signing" `
        -KeyAlgorithm RSA -KeyLength 3072 -HashAlgorithm SHA256 `
        -KeyUsage DigitalSignature `
        -KeyExportPolicy Exportable `
        -CertStoreLocation Cert:\CurrentUser\My `
        -NotAfter (Get-Date).AddYears($ValidYears)
}

function Get-SignArgs([string] $Thumbprint) {
    $a = @("sign", "/fd", "sha256", "/sha1", $Thumbprint)
    if ($TimestampUrl) { $a += @("/tr", $TimestampUrl, "/td", "sha256") }
    return $a
}

# --- Certificate -------------------------------------------------------------

$cert = Get-SigningCertificate
if (-not $cert) { throw "No usable code signing certificate (with private key) found." }
$thumb = $cert.Thumbprint

New-Item -ItemType Directory -Force -Path $CertDir | Out-Null
$cerPath = Join-Path $CertDir "zflash-codesign.cer"
Export-Certificate -Cert $cert -FilePath $cerPath -Force | Out-Null
Write-Host "Public certificate exported to $cerPath"

if ($ExportPfx) {
    $pfxOut = Join-Path $CertDir "zflash-codesign.pfx"
    $pw = Read-Host -AsSecureString "Password to protect $pfxOut"
    Export-PfxCertificate -Cert $cert -FilePath $pfxOut -Password $pw -Force | Out-Null
    Write-Host "Certificate and private key exported to $pfxOut (keep it private!)"
}

if ($TrustLocally) {
    # Root makes the signature chain valid; TrustedPublisher suppresses the
    # "unknown publisher" prompt. Windows asks for confirmation on the Root import.
    if ($cert.Subject -ne $cert.Issuer) {
        Write-Warning "Certificate is issued by '$($cert.Issuer)'; import that CA certificate into Root instead for full trust."
    } else {
        Import-Certificate -FilePath $cerPath -CertStoreLocation Cert:\CurrentUser\Root | Out-Null
    }
    Import-Certificate -FilePath $cerPath -CertStoreLocation Cert:\CurrentUser\TrustedPublisher | Out-Null
    Write-Host "Certificate trusted for the current user."
}

# --- Sign-only mode ----------------------------------------------------------

if ($SignOnly) {
    $st = Find-SignTool
    foreach ($f in $SignOnly) {
        & $st @(Get-SignArgs $thumb) $f
        if ($LASTEXITCODE -ne 0) { throw "signtool failed on $f" }
    }
    Write-Host "Signed $($SignOnly.Count) file(s) with $thumb"
    return
}

# --- Build -------------------------------------------------------------------

$st = Find-SignTool
$env:PATH = "$MingwRoot\bin;${env:ProgramFiles}\CMake\bin;$env:PATH"
New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null

$cmakeArgs = @(
    "-S", (Join-Path $PSScriptRoot "src"),
    "-B", $BuildDir,
    "-G", "MinGW Makefiles",
    "-DQt6_ROOT=$QtRoot",
    "-DMINGW64_ROOT=$MingwRoot",
    "-DENABLE_INNO_INSTALLER=ON",
    "-DIMAGER_SIGNED_APP=ON",
    "-DSIGNTOOL=$st",
    "-DIMAGER_SIGN_CERT_SHA1=$thumb",
    "-DIMAGER_SIGN_TIMESTAMP_URL=$TimestampUrl"
)
& cmake @cmakeArgs
if ($LASTEXITCODE -ne 0) { throw "CMake configure failed" }

& cmake --build $BuildDir --target $Target -j $Jobs
if ($LASTEXITCODE -ne 0) { throw "Build failed" }

# --- Verify ------------------------------------------------------------------

$toCheck = @(Get-ChildItem (Join-Path $BuildDir "deploy\*.exe") -ErrorAction SilentlyContinue) +
           @(Get-ChildItem (Join-Path $BuildDir "installer\*.exe") -ErrorAction SilentlyContinue)
foreach ($f in $toCheck) {
    $sig = Get-AuthenticodeSignature $f.FullName
    $signer = if ($sig.SignerCertificate) { $sig.SignerCertificate.Thumbprint } else { "-" }
    Write-Host ("{0,-60} {1,-14} {2}" -f $f.Name, $sig.Status, $signer)
}
Write-Host ""
Write-Host "Done. Signed with $thumb."
Write-Host "To trust these binaries on another machine (as administrator):"
Write-Host "  Import-Certificate -FilePath zflash-codesign.cer -CertStoreLocation Cert:\LocalMachine\Root"
Write-Host "  Import-Certificate -FilePath zflash-codesign.cer -CertStoreLocation Cert:\LocalMachine\TrustedPublisher"
