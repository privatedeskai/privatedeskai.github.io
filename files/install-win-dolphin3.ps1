# PrivateAI Quickstart - Windows 16GB RAM
# Ollama + dolphin3:8b + AnythingLLM
# privatedeskai.com | Version 1.3
# RUN: PowerShell -ExecutionPolicy Bypass -File install-win-dolphin3.ps1

#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

# --- Config ---
$MODEL       = "dolphin3:8b"
$MODEL_RAM   = 14
$INSTALL_DIR = "$env:USERPROFILE\PrivateAI"
$LOG_FILE    = "$env:TEMP\privateai_install_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$arch = $env:PROCESSOR_ARCHITECTURE
$ANYLLM_URL  = if ($arch -eq "ARM64") {
    "https://cdn.anythingllm.com/latest/AnythingLLMDesktop-Arm64.exe"
} else {
    "https://cdn.anythingllm.com/latest/AnythingLLMDesktop.exe"
}
$OLLAMA_URL  = "https://ollama.com/download/OllamaSetup.exe"
$OLLAMA_EXE  = "$env:LOCALAPPDATA\Programs\Ollama\ollama.exe"

# --- Output helpers ---
function Log { param($m) Add-Content -Path $LOG_FILE -Value "$(Get-Date -Format 's') $m" -EA SilentlyContinue }
function S   { param($m) Write-Host ""; Write-Host "[>>] $m" -ForegroundColor Cyan;   Log "[>>] $m" }
function OK  { param($m) Write-Host "[OK] $m" -ForegroundColor Green;                 Log "[OK] $m" }
function W   { param($m) Write-Host "[!!] $m" -ForegroundColor Yellow;                Log "[!!] $m" }
function ERR {
    param($m)
    Write-Host ""
    Write-Host "[XX] $m" -ForegroundColor Red
    Log "[XX] $m"
    Write-Host ""
    Write-Host "     Support: privatedeskai@gmail.com" -ForegroundColor Gray
    Write-Host "     Log: $LOG_FILE" -ForegroundColor Gray
    Read-Host "Press Enter to exit"
    exit 1
}

function Download-File {
    param([string]$Url, [string]$Dest, [string]$Label)
    Write-Host "     Downloading $Label..." -ForegroundColor Gray
    $logMsg2 = "Downloading " + $Label + " from " + $Url
    Log $logMsg2
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $startByte = [long]0
    if (Test-Path $Dest) {
        $startByte = (Get-Item $Dest).Length
        if ($startByte -gt 0) { Write-Host "     Resuming from $([math]::Round($startByte/1MB,1)) MB..." -ForegroundColor Gray }
    }
    $total = [long]0
    try {
        $hr = [System.Net.HttpWebRequest]::Create($Url)
        $hr.Method = "HEAD"; $hr.Timeout = 20000; $hr.AllowAutoRedirect = $true
        $hresp = $hr.GetResponse()
        $total = $hresp.ContentLength
        $hresp.Close()
        if ($startByte -ge $total -and $total -gt 0) { OK "$Label already downloaded."; return }
    } catch {}
    $req = $null; $resp = $null; $ins = $null; $out = $null
    try {
        $req = [System.Net.HttpWebRequest]::Create($Url)
        $req.AllowAutoRedirect = $true; $req.Timeout = -1; $req.ReadWriteTimeout = 60000
        if ($startByte -gt 0) { $req.AddRange($startByte) }
        $resp = $req.GetResponse()
        $ins  = $resp.GetResponseStream()
        $mode = if ($startByte -gt 0) { [System.IO.FileMode]::Append } else { [System.IO.FileMode]::Create }
        $out  = [System.IO.File]::Open($Dest, $mode, [System.IO.FileAccess]::Write)
        $buf  = New-Object byte[] 131072
        $read = 0; $written = $startByte
        $totalMB = if ($total -gt 0) { [math]::Round($total/1MB,0) } else { "?" }
        while (($read = $ins.Read($buf, 0, $buf.Length)) -gt 0) {
            $out.Write($buf, 0, $read); $written += $read
            $elapsed = $sw.Elapsed.TotalSeconds
            $curMB   = [math]::Round($written/1MB,1)
            $speed   = if ($elapsed -gt 0) { [math]::Round($written/1MB/$elapsed,1) } else { 0 }
            if ($total -gt 0) {
                $pct = [math]::Min([int](($written/$total)*100),100)
                $eta = if ($speed -gt 0) { [math]::Round(($totalMB - $curMB)/$speed) } else { "?" }
                $etaStr = "ETA " + $eta + "s"
                Write-Progress -Activity "Downloading $Label" -Status "$curMB / $totalMB MB  |  $speed MB/s  |  $etaStr" -PercentComplete $pct
            } else {
                Write-Progress -Activity "Downloading $Label" -Status "$curMB MB  |  $speed MB/s" -PercentComplete 0
            }
        }
    } finally {
        if ($out)  { try { $out.Flush();  $out.Close()  } catch {} }
        if ($ins)  { try { $ins.Close()  } catch {} }
        if ($resp) { try { $resp.Close() } catch {} }
    }
    Write-Progress -Activity "Downloading $Label" -Completed
    # Wait up to 10 sec - antivirus may briefly lock the file after download
    $av_wait = 0
    while (-not (Test-Path $Dest) -and $av_wait -lt 10) {
        Start-Sleep -Seconds 2; $av_wait += 2
    }
    if (-not (Test-Path $Dest)) {
        ERR ("File missing after download: $Dest`n" +
             "     Possible cause: antivirus deleted the file.`n" +
             "     Add an exception for folder: $INSTALL_DIR`n" +
             "     Then run the script again.")
    }
    $finalMB = [math]::Round((Get-Item $Dest).Length/1MB,1)
    # Sanity check - file too small means antivirus truncated it
    if ($finalMB -lt 1) {
        ERR ("Downloaded file is too small ($finalMB MB) - antivirus may have blocked it.`n" +
             "     Add an exception for folder: $INSTALL_DIR`n" +
             "     Then run the script again.")
    }
    $sec = [math]::Round($sw.Elapsed.TotalSeconds)
    OK "$Label downloaded ($finalMB MB in $sec sec)"
    $secStr = "$sec" + "s"
    $logMsg = "Downloaded " + $Label + " " + $finalMB + " MB in " + $secStr
    Log $logMsg
}

# ==============================================================
Clear-Host
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "   PrivateAI Quickstart - Windows Setup"                      -ForegroundColor White
Write-Host "   Model: dolphin3:8b | Recommended: 16+ GB RAM"            -ForegroundColor Gray
Write-Host "   privatedeskai.com"                                         -ForegroundColor Gray
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Log "=== PrivateAI Install Start ==="

# ==============================================================
# STEP 1: Admin check
# ==============================================================
S "Step 1/5: Checking system..."

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { ERR "Please run PowerShell as Administrator. Right-click -> Run as Administrator." }
OK "Administrator rights confirmed."

# OS
$osVer = [System.Environment]::OSVersion.Version
$osBuild = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -EA SilentlyContinue).DisplayVersion
if ($osVer.Major -lt 10) { ERR "Windows 10 or higher required. Your version: $($osVer.ToString())" }
$osName = if ($osVer.Build -ge 22000) { "Windows 11" } else { "Windows 10" }
OK "OS: $osName (build $osBuild) - supported."

# RAM check
$ramGB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory/1GB,1)
if ($ramGB -lt 7.5) { ERR "Not enough RAM: $ramGB GB. Minimum 8 GB required." }
if ($ramGB -lt $MODEL_RAM) {
    W "RAM: $ramGB GB. This model works best with $MODEL_RAM+ GB."
    W "Performance may be slow. Consider using the 8GB version instead."
    Write-Host ""
    $cont = Read-Host "Continue anyway? (y/n)"
    if ($cont -ne "y" -and $cont -ne "Y") { exit 0 }
} else {
    OK "RAM: $ramGB GB - perfect for this model."
}

# Disk
$freeGB = [math]::Round((Get-PSDrive C).Free/1GB,1)
if ($freeGB -lt 10) { ERR "Not enough disk space: $freeGB GB free. Need at least 10 GB." }
OK "Disk: $freeGB GB free - OK."

# Internet
try {
    $null = Invoke-WebRequest -Uri "https://ollama.com" -UseBasicParsing -TimeoutSec 10
    OK "Internet connection OK."
} catch { ERR "No internet connection. Required for initial setup (~7 GB total download)." }

# Create install dir
New-Item -ItemType Directory -Force -Path $INSTALL_DIR | Out-Null
OK "Install directory: $INSTALL_DIR"

# ==============================================================
# STEP 2: Install Ollama
# ==============================================================
S "Step 2/5: Installing Ollama (AI engine)..."

$ollamaInstalled = $false
if (Test-Path $OLLAMA_EXE) {
    try {
        $ver = & $OLLAMA_EXE --version 2>&1
        OK "Ollama already installed: $ver"
        $ollamaInstalled = $true
    } catch {}
}

if (-not $ollamaInstalled) {
    $ollamaInstaller = "$INSTALL_DIR\OllamaSetup.exe"
    Download-File -Url $OLLAMA_URL -Dest $ollamaInstaller -Label "Ollama"
    Write-Host "     Installing Ollama silently..." -ForegroundColor Gray
    $ollamaProc = Start-Process -FilePath $ollamaInstaller -ArgumentList "/silent" -PassThru
    # Wait up to 120 sec for ollama.exe to appear (ARM64 installer may not exit cleanly)
    $waited = 0
    while (-not (Test-Path $OLLAMA_EXE) -and $waited -lt 120) {
        Start-Sleep -Seconds 3
        $waited += 3
        Write-Host "     Waiting for Ollama... ($waited sec)" -ForegroundColor Gray
    }
    try { if (-not $ollamaProc.HasExited) { $ollamaProc.Kill() } } catch {}
    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH","User")
    Start-Sleep -Seconds 2
    if (Test-Path $OLLAMA_EXE) {
        OK "Ollama installed successfully."
    } else {
        ERR "Ollama installation failed. Try downloading manually: https://ollama.com/download"
    }
    Remove-Item $ollamaInstaller -Force -EA SilentlyContinue
}

# Start Ollama service
Write-Host "     Starting Ollama service..." -ForegroundColor Gray
Start-Process -FilePath $OLLAMA_EXE -ArgumentList "serve" -WindowStyle Hidden -EA SilentlyContinue
Start-Sleep -Seconds 3

# ==============================================================
# STEP 3: Download AI model
# ==============================================================
S "Step 3/5: Downloading AI model ($MODEL, ~5 GB)..."
Write-Host "     This will take 10-30 minutes depending on your internet speed." -ForegroundColor Gray
Write-Host "     Do not close this window." -ForegroundColor Yellow
Write-Host ""

# Check if model already exists
$models = & $OLLAMA_EXE list 2>&1
if ($models -match "dolphin3") {
    OK "Model $MODEL already downloaded."
} else {
    try {
        & $OLLAMA_EXE pull $MODEL
        if ($LASTEXITCODE -ne 0) { ERR "Model download failed. Check your internet connection and try again." }
        OK "Model $MODEL downloaded successfully."
    } catch {
        ERR "Model download failed: $_"
    }
}

# ==============================================================
# STEP 4: Install AnythingLLM
# ==============================================================
S "Step 4/5: Installing AnythingLLM (chat interface)..."

# Find AnythingLLM via registry - works on any Windows regardless of install folder
function Find-AnythingLLM {
    $regRoots = @(
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    foreach ($root in $regRoots) {
        $entries = Get-ItemProperty $root -EA SilentlyContinue
        foreach ($entry in $entries) {
            if ($entry -and ($entry.PSObject.Properties['DisplayName']) -and $entry.DisplayName -like "*AnythingLLM*") {
                if ($entry.PSObject.Properties['InstallLocation'] -and $entry.InstallLocation) {
                    $exe = Join-Path $entry.InstallLocation "AnythingLLM.exe"
                    if (Test-Path $exe) { return $exe }
                }
            }
        }
    }
    $known = @(
        "$env:LOCALAPPDATA\Programs\AnythingLLM\AnythingLLM.exe",
        "$env:LOCALAPPDATA\Programs\anythingllm-desktop\AnythingLLM.exe",
        "$env:APPDATA\AnythingLLM Desktop\AnythingLLM.exe"
    )
    foreach ($p in $known) { if (Test-Path $p) { return $p } }
    $found = Get-ChildItem "$env:LOCALAPPDATA\Programs" -Recurse -Filter "AnythingLLM.exe" -EA SilentlyContinue | Select-Object -First 1
    if ($found) { return $found.FullName }
    return $null
}

$anyllmPath = Find-AnythingLLM
$anyllmInstalled = $null -ne $anyllmPath

if ($anyllmInstalled) {
    OK "AnythingLLM already installed: $anyllmPath"
} else {
    $anyllmInstaller = "$INSTALL_DIR\AnythingLLMDesktop.exe"
    Download-File -Url $ANYLLM_URL -Dest $anyllmInstaller -Label "AnythingLLM"

    Write-Host "     Closing AnythingLLM if running..." -ForegroundColor Gray
    Get-Process | Where-Object { $_.Name -like "*AnythingLLM*" -or $_.Name -like "*anythingllm*" } | ForEach-Object {
        try { $_.Kill(); Start-Sleep -Seconds 1 } catch {}
    }
    Start-Sleep -Seconds 2

    Write-Host "     Installing AnythingLLM..." -ForegroundColor Gray
    Write-Host "     If a security warning appears: click More info -> Run anyway" -ForegroundColor Yellow
    $anyllmProc = Start-Process -FilePath $anyllmInstaller -PassThru
    $waited = 0
    $detectedPath = $null
    while ($waited -lt 300) {
        Start-Sleep -Seconds 3
        $waited += 3
        Write-Host "     Waiting for AnythingLLM... ($waited sec)" -ForegroundColor Gray
        $detectedPath = Find-AnythingLLM
        if ($detectedPath) { break }
    }
    try { if (-not $anyllmProc.HasExited) { $anyllmProc.Kill() } } catch {}
    Start-Sleep -Seconds 2
    Remove-Item $anyllmInstaller -Force -EA SilentlyContinue
    if ($detectedPath) {
        $anyllmPath = $detectedPath
        OK "AnythingLLM installed: $anyllmPath"
    } else {
        ERR "AnythingLLM not found after installation. Please contact support: privatedeskai@gmail.com"
    }
}

# Confirm final path
$confirmedPath = Find-AnythingLLM
if ($confirmedPath) {
    $anyllmPath = $confirmedPath
    OK "AnythingLLM path confirmed: $anyllmPath"
} else {
    ERR "AnythingLLM not found. Please contact support: privatedeskai@gmail.com"
}

# Extract backend.7z - always extract fresh to ensure completeness
$anyllmDir = Split-Path $anyllmPath
$backendArchive = Join-Path $anyllmDir "resources\backend.7z"
$backendDir = Join-Path $anyllmDir "resources\backend"
$7zExe = Join-Path $anyllmDir "resources\static\7za.exe"

if (Test-Path $backendArchive) {
    if (Test-Path $7zExe) {
        Write-Host "     Extracting backend files..." -ForegroundColor Gray
        # Clean partial extraction if exists (keep only Ghostscript files)
        if (Test-Path $backendDir) {
            $serverJs = Join-Path $backendDir "server.js"
            if (-not (Test-Path $serverJs)) {
                Write-Host "     Removing incomplete backend folder..." -ForegroundColor Gray
                Remove-Item $backendDir -Recurse -Force -EA SilentlyContinue
            }
        }
        if (-not (Test-Path (Join-Path $backendDir "server.js"))) {
            & $7zExe x $backendArchive -o"$backendDir" -y 2>&1 | Out-Null
            Start-Sleep -Seconds 2
        }
        if (Test-Path (Join-Path $backendDir "server.js")) {
            OK "Backend extracted successfully."
        } else {
            W "Backend extraction may be incomplete. App will attempt to recover on launch."
        }
    } else {
        W "7za.exe not found at: $7zExe - skipping backend extraction."
    }
} else {
    OK "No backend archive found - skipping extraction."
}

# ==============================================================
# Write AnythingLLM config - set Ollama as provider before first launch
# ==============================================================
$anyllmStorage = "$env:APPDATA\anythingllm-desktop\storage"
New-Item -ItemType Directory -Force -Path $anyllmStorage | Out-Null
$envFile = "$anyllmStorage\.env"
$envContent = @"
LLM_PROVIDER=ollama
OLLAMA_BASE_PATH=http://127.0.0.1:11434
OLLAMA_MODEL_PREF=dolphin3:8b
OLLAMA_MODEL_TOKEN_LIMIT=4096
EMBEDDING_ENGINE=native
VECTOR_DB=lancedb
"@
Set-Content -Path $envFile -Value $envContent -Encoding UTF8
OK "AnythingLLM configured: Ollama provider, model dolphin3:8b"

# ==============================================================
# STEP 5: Create startup script and shortcut
# ==============================================================
S "Step 5/5: Creating startup script..."

# Startup BAT - launches Ollama + AnythingLLM
$startBat = "$INSTALL_DIR\Start-PrivateAI.bat"
$batContent = "@echo off`r`n"
$batContent += "title PrivateAI - Starting...`r`n"
$batContent += "echo Starting PrivateAI...`r`n"
$batContent += "start `"`" `"$OLLAMA_EXE`" serve`r`n"
$batContent += "timeout /t 3 /nobreak >nul`r`n"
$batContent += "start `"`" `"$anyllmPath`"`r`n"
$batContent += "exit`r`n"
Set-Content -Path $startBat -Value $batContent -Encoding ASCII
OK "Startup script created: Start-PrivateAI.bat"

# Desktop shortcut
try {
    $wsh  = New-Object -ComObject WScript.Shell
    $link = $wsh.CreateShortcut("$([Environment]::GetFolderPath('Desktop'))\PrivateAI.lnk")
    $link.TargetPath       = $startBat
    $link.WorkingDirectory = $INSTALL_DIR
    $link.Description      = "PrivateAI - Your private AI assistant"
    $link.Save()
    OK "Desktop shortcut created: PrivateAI"
} catch {
    W "Could not create desktop shortcut: $($_.Exception.Message)"
}

# ==============================================================
# DONE
# ==============================================================
Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "   Installation complete! PrivateAI is ready."               -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "   HOW TO START:" -ForegroundColor Cyan
Write-Host "   Double-click [PrivateAI] shortcut on your Desktop" -ForegroundColor White
Write-Host ""
Write-Host "   First launch takes 1-2 minutes to initialize." -ForegroundColor Gray
Write-Host "   In AnythingLLM: select Ollama as provider," -ForegroundColor Gray
Write-Host "   choose dolphin3:8b model and start chatting." -ForegroundColor Gray
Write-Host ""
Write-Host "   Upload PDF/DOCX: use the paperclip icon in chat." -ForegroundColor Gray
Write-Host "   Works 100% offline after installation." -ForegroundColor Gray
Write-Host ""
Write-Host "   Support: privatedeskai@gmail.com" -ForegroundColor Gray
Write-Host "   Log: $LOG_FILE" -ForegroundColor Gray
Write-Host ""
Log "=== Installation Complete ==="

# Launch Ollama + AnythingLLM in separate processes (no logs in this window)
Write-Host "   Starting PrivateAI..." -ForegroundColor Cyan
Start-Process -FilePath $OLLAMA_EXE -ArgumentList "serve" -WindowStyle Hidden -EA SilentlyContinue
Start-Sleep -Seconds 2
if (Test-Path $anyllmPath) {
    Start-Process -FilePath $anyllmPath -WindowStyle Normal -EA SilentlyContinue
    Write-Host "   AnythingLLM launched." -ForegroundColor Green
} else {
    W "Could not launch AnythingLLM. Please start it manually from Desktop shortcut."
}
Start-Sleep -Seconds 1

# Installation complete - window closes automatically
