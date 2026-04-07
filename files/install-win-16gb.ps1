# PrivateAI Quickstart - Windows 16GB RAM
# Ollama + Llama3.3:8b + AnythingLLM
# privatedeskai.com | Version 1.0
# RUN: PowerShell -ExecutionPolicy Bypass -File install-win-16gb.ps1

#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

# --- Config ---
$MODEL       = "qwen2.5:7b"
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
    if (-not (Test-Path $Dest)) { ERR "File missing after download: $Dest" }
    $finalMB = [math]::Round((Get-Item $Dest).Length/1MB,1)
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
Write-Host "   Model: Llama3.3:8b | Recommended: 16+ GB RAM"             -ForegroundColor Gray
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
    Start-Process -FilePath $ollamaInstaller -ArgumentList "/silent" -Wait
    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH","User")
    Start-Sleep -Seconds 5
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
if ($models -match "qwen2.5") {
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

$anyllmPath = "$env:LOCALAPPDATA\Programs\anythingllm-desktop\AnythingLLM.exe"
$anyllmAlt  = "$env:APPDATA\AnythingLLM Desktop\AnythingLLM.exe"

$anyllmInstalled = (Test-Path $anyllmPath) -or (Test-Path $anyllmAlt)

if ($anyllmInstalled) {
    OK "AnythingLLM already installed."
} else {
    $anyllmInstaller = "$INSTALL_DIR\AnythingLLMDesktop.exe"
    Download-File -Url $ANYLLM_URL -Dest $anyllmInstaller -Label "AnythingLLM"

    Write-Host ""
    Write-Host "     IMPORTANT: Windows may show a security warning." -ForegroundColor Yellow
    Write-Host "     Click 'More info' -> 'Run anyway' to continue." -ForegroundColor Yellow
    Write-Host "     Then click Next -> Install -> Finish in the installer." -ForegroundColor Yellow
    Write-Host ""
    Read-Host "Press Enter to start AnythingLLM installation"

    Start-Process -FilePath $anyllmInstaller -Wait
    Start-Sleep -Seconds 3
    Remove-Item $anyllmInstaller -Force -EA SilentlyContinue
    OK "AnythingLLM installation complete."
}

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
Write-Host "   choose qwen2.5:7b model and start chatting." -ForegroundColor Gray
Write-Host ""
Write-Host "   Upload PDF/DOCX: use the paperclip icon in chat." -ForegroundColor Gray
Write-Host "   Works 100% offline after installation." -ForegroundColor Gray
Write-Host ""
Write-Host "   Support: privatedeskai@gmail.com" -ForegroundColor Gray
Write-Host "   Log: $LOG_FILE" -ForegroundColor Gray
Write-Host ""
Log "=== Installation Complete ==="

# Launch AnythingLLM
Write-Host "   Starting AnythingLLM..." -ForegroundColor Cyan
Start-Process -FilePath $OLLAMA_EXE -ArgumentList "serve" -WindowStyle Hidden -EA SilentlyContinue
Start-Sleep -Seconds 2
if (Test-Path $anyllmPath) {
    Start-Process -FilePath $anyllmPath -EA SilentlyContinue
} elseif (Test-Path $anyllmAlt) {
    Start-Process -FilePath $anyllmAlt -EA SilentlyContinue
}

Read-Host "Press Enter to finish"
