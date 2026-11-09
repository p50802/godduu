# =====================================================================
#  GodDuu launcher
#  Usage (open PowerShell and paste):
#     irm https://raw.githubusercontent.com/p50802/godduu/main/run.ps1 | iex
#
#  What this script does:
#   1. Downloads GodDuu-win64.zip from GitHub Releases (version below)
#   2. Verifies its SHA-256 against the value in this script - mismatch = nothing runs
#   3. Extracts to %LOCALAPPDATA%\GodDuu\app (no install)
#   4. Starts GodDuu.exe (Windows asks for Administrator) - no desktop shortcut is created
#  Next time, if that version is already there, it starts immediately.
# =====================================================================

& {
    # ---------- config (publish.ps1 updates these 3 lines) ----------
    $Repo    = 'p50802/godduu'
    $Version = '2.2.0'
    $Sha256  = 'F442BB4526C105A4880D1997CB5F19399AA1E1A7BDC289F14E2FA7A8D513CB0F'
    # ---------------------------------------------------------------------------

    $ErrorActionPreference = 'Stop'
    $ProgressPreference    = 'SilentlyContinue'   # much faster Invoke-WebRequest on PS 5.1
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }

    function Say($msg, $color = 'Gray') { Write-Host "  $msg" -ForegroundColor $color }
    function Fail($msg) {
        Write-Host ""
        Write-Host "  [X] $msg" -ForegroundColor Red
        Write-Host ""
    }

    Write-Host ""
    Write-Host "   ____           _ ____" -ForegroundColor Cyan
    Write-Host "  / ___| ___   __| |  _ \ _   _ _   _" -ForegroundColor Cyan
    Write-Host " | |  _ / _ \ / _`` | | | | | | | | | |" -ForegroundColor Cyan
    Write-Host " | |_| | (_) | (_| | |_| | |_| | |_| |" -ForegroundColor Cyan
    Write-Host "  \____|\___/ \__,_|____/ \__,_|\__,_|  v$Version" -ForegroundColor Cyan
    Write-Host ""

    # ---------- checks ----------
    if (-not [Environment]::Is64BitOperatingSystem) { Fail "GodDuu needs 64-bit Windows."; return }
    if ($Repo -eq 'OWNER/REPO' -or $Sha256 -notmatch '^[0-9a-fA-F]{64}$') {
        Fail "This launcher is not configured yet (run publish.ps1 first)."; return
    }

    $Root    = Join-Path $env:LOCALAPPDATA 'GodDuu'
    $AppDir  = Join-Path $Root 'app'
    $Exe     = Join-Path $AppDir 'GodDuu.exe'
    $VerFile = Join-Path $AppDir 'version.txt'
    $Url     = "https://github.com/$Repo/releases/download/v$Version/GodDuu-win64.zip"

    $have = $null
    if (Test-Path $VerFile) { $have = (Get-Content $VerFile -Raw).Trim() }

    if ($have -eq $Version -and (Test-Path $Exe)) {
        Say "GodDuu v$Version is already downloaded." Green
    }
    else {
        # ---------- download ----------
        $tmpZip = Join-Path $env:TEMP ("godduu_{0}.zip" -f [guid]::NewGuid().ToString('N'))
        $tmpDir = Join-Path $env:TEMP ("godduu_{0}"     -f [guid]::NewGuid().ToString('N'))
        try {
            Say "Downloading GodDuu v$Version ..."
            Say $Url DarkGray
            Invoke-WebRequest -Uri $Url -OutFile $tmpZip -UseBasicParsing

            # ---------- verify hash ----------
            Say "Verifying SHA-256 ..."
            $got = (Get-FileHash -Path $tmpZip -Algorithm SHA256).Hash
            if ($got -ne $Sha256.ToUpper()) {
                Fail "SHA-256 mismatch! The download is not the official file. Nothing was run."
                Say "expected $($Sha256.ToUpper())" DarkGray
                Say "got      $got" DarkGray
                return
            }
            Say "SHA-256 OK" Green

            # ---------- GodDuu window must be closed so files can be replaced ----------
            $open = Get-Process -Name GodDuu -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 }
            if ($open) { Fail "Please close the GodDuu window first, then run the command again."; return }

            # ---------- extract ----------
            Say "Extracting to $AppDir ..."
            Expand-Archive -Path $tmpZip -DestinationPath $tmpDir -Force
            $src = $tmpDir
            $inner = Join-Path $tmpDir 'GodDuu'
            if (Test-Path (Join-Path $inner 'GodDuu.exe')) { $src = $inner }
            if (-not (Test-Path (Join-Path $src 'GodDuu.exe'))) { Fail "GodDuu.exe not found inside the zip."; return }

            New-Item -ItemType Directory -Path $AppDir -Force | Out-Null
            # overwrite program files - an existing WebView2 folder is kept
            Get-ChildItem -Path $src -Force | ForEach-Object {
                Copy-Item -Path $_.FullName -Destination $AppDir -Recurse -Force
            }
            Set-Content -Path $VerFile -Value $Version -Encoding ASCII
            Say "Installed GodDuu v$Version" Green
        }
        catch {
            Fail ("Download failed: " + $_.Exception.Message)
            return
        }
        finally {
            Remove-Item $tmpZip -Force -ErrorAction SilentlyContinue
            Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # ---------- WebView2 ----------
    $wvKeys = @(
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}',
        'HKLM:\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}',
        'HKCU:\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'
    )
    $hasWv = $false
    foreach ($k in $wvKeys) {
        $pv = (Get-ItemProperty -Path $k -Name pv -ErrorAction SilentlyContinue).pv
        if ($pv -and $pv -ne '0.0.0.0') { $hasWv = $true }
    }
    if (Test-Path (Join-Path $AppDir 'WebView2\msedgewebview2.exe')) { $hasWv = $true }
    if (Get-ChildItem -Path $AppDir -Filter 'Microsoft.WebView2.FixedVersionRuntime*.cab' -ErrorAction SilentlyContinue) { $hasWv = $true }

    if (-not $hasWv) {
        Write-Host ""
        Say "Microsoft Edge WebView2 Runtime was not found (needed to show the GodDuu window)." Yellow
        Say "[Y] Install it now from Microsoft (small online installer)" Yellow
        Say "[N] Skip - I will put the Fixed Version .cab into: $AppDir" Yellow
        $ans = Read-Host "  Install WebView2 now? (Y/N)"
        if ($ans -match '^[Yy]') {
            $boot = Join-Path $env:TEMP 'MicrosoftEdgeWebview2Setup.exe'
            try {
                Say "Downloading WebView2 bootstrapper from Microsoft ..."
                Invoke-WebRequest -Uri 'https://go.microsoft.com/fwlink/p/?LinkId=2124703' -OutFile $boot -UseBasicParsing
                $sig = Get-AuthenticodeSignature -FilePath $boot
                if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'Microsoft Corporation') {
                    Fail "WebView2 installer signature is not valid Microsoft - not running it."; return
                }
                Say "Installing WebView2 (this can take a minute) ..."
                Start-Process -FilePath $boot -ArgumentList '/silent', '/install' -Verb RunAs -Wait
                Say "WebView2 installed" Green
            }
            catch { Fail ("WebView2 install failed: " + $_.Exception.Message) }
            finally { Remove-Item $boot -Force -ErrorAction SilentlyContinue }
        }
    }

    # ---------- start ----------
    Say "Starting GodDuu (Windows will ask for Administrator) ..." Cyan
    try { Start-Process -FilePath $Exe -WorkingDirectory $AppDir }
    catch { Fail ("Could not start GodDuu: " + $_.Exception.Message) }
    Write-Host ""
}
