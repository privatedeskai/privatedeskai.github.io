#!/bin/bash
# PrivateAI Quickstart - Mac 8GB RAM
# Ollama + gemma3:4b + AnythingLLM
# privatedeskai.com | Version 1.0
# RUN: bash install-mac-8gb.sh

# --- Config ---
MODEL="gemma3:4b"
MODEL_RAM_MIN=7
INSTALL_DIR="$HOME/PrivateAI"
LOG_FILE="/tmp/privateai_install_$(date '+%Y%m%d_%H%M%S').log"

OLLAMA_PKG_URL="https://ollama.com/download/Ollama-darwin.pkg"
ANYLLM_DMG_URL="https://cdn.anythingllm.com/latest/AnythingLLMDesktop.dmg"

ANYLLM_APP="/Applications/AnythingLLM.app"

# --- Helpers ---
log()  { echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE" 2>/dev/null || true; }
s()    { echo ""; echo "[>>] $1"; log "[>>] $1"; }
ok()   { echo "[OK] $1"; log "[OK] $1"; }
warn() { echo "[!!] $1"; log "[!!] $1"; }
err()  {
    echo ""
    echo "[XX] $1"
    log "[XX] $1"
    echo ""
    echo "     Support: privatedeskai@gmail.com"
    echo "     Log: $LOG_FILE"
    echo ""
    read -r -p "Press Enter to exit..."
    exit 1
}

download_file() {
    local url="$1"
    local dest="$2"
    local label="$3"
    echo "     Downloading $label..."
    log "Downloading $label from $url"
    if [ -f "$dest" ]; then
        local existing_size
        existing_size=$(stat -f%z "$dest" 2>/dev/null || echo 0)
        if [ "$existing_size" -gt 0 ]; then
            echo "     Resuming from $(( existing_size / 1024 / 1024 )) MB..."
            curl -L -C - --progress-bar -o "$dest" "$url" || err "Download failed: $label"
            return
        fi
    fi
    curl -L --progress-bar -o "$dest" "$url" || err "Download failed: $label"
    if [ ! -f "$dest" ]; then
        err "File missing after download: $dest"
    fi
    local final_mb
    final_mb=$(( $(stat -f%z "$dest") / 1024 / 1024 ))
    ok "$label downloaded (${final_mb} MB)"
}

# ==============================================================
clear
echo "============================================================"
echo "   PrivateAI Quickstart - Mac Setup"
echo "   Model: gemma3:4b | Minimum: 8 GB RAM"
echo "   privatedeskai.com"
echo "============================================================"
echo ""
log "=== PrivateAI Install Start ==="

# ==============================================================
# STEP 1: System check
# ==============================================================
s "Step 1/5: Checking system..."

# macOS version
MACOS_VER=$(sw_vers -productVersion)
MACOS_MAJOR=$(echo "$MACOS_VER" | cut -d. -f1)
if [ "$MACOS_MAJOR" -lt 11 ]; then
    err "macOS 11 (Big Sur) or higher required. Your version: $MACOS_VER"
fi
ok "macOS: $MACOS_VER - supported."

# RAM check
RAM_BYTES=$(sysctl -n hw.memsize)
RAM_GB=$(( RAM_BYTES / 1024 / 1024 / 1024 ))
if [ "$RAM_GB" -lt "$MODEL_RAM_MIN" ]; then
    err "Not enough RAM: ${RAM_GB} GB. Minimum 8 GB required."
fi
ok "RAM: ${RAM_GB} GB - OK for this model."

# Disk space
FREE_BYTES=$(df -k "$HOME" | tail -1 | awk '{print $4}')
FREE_GB=$(( FREE_BYTES / 1024 / 1024 ))
if [ "$FREE_GB" -lt 8 ]; then
    err "Not enough disk space: ${FREE_GB} GB free. Need at least 8 GB."
fi
ok "Disk: ${FREE_GB} GB free - OK."

# Internet check
if ! curl -s --connect-timeout 10 https://ollama.com > /dev/null 2>&1; then
    err "No internet connection. Required for initial setup (~5 GB total download)."
fi
ok "Internet connection OK."

mkdir -p "$INSTALL_DIR"
ok "Install directory: $INSTALL_DIR"

# ==============================================================
# STEP 2: Install Ollama
# ==============================================================
s "Step 2/5: Installing Ollama (AI engine)..."

if command -v ollama &>/dev/null; then
    VER=$(ollama --version 2>&1 || echo "installed")
    ok "Ollama already installed: $VER"
else
    OLLAMA_PKG="$INSTALL_DIR/Ollama-darwin.pkg"
    download_file "$OLLAMA_PKG_URL" "$OLLAMA_PKG" "Ollama"

    echo "     Installing Ollama - macOS will ask for your password..."
    sudo installer -pkg "$OLLAMA_PKG" -target / || err "Ollama installation failed."
    rm -f "$OLLAMA_PKG"
    ok "Ollama installed successfully."
fi

# Start Ollama service
echo "     Starting Ollama service..."
ollama serve > /tmp/ollama_serve.log 2>&1 &
sleep 4

if ! curl -s http://localhost:11434/api/tags > /dev/null 2>&1; then
    warn "Waiting for Ollama to start..."
    sleep 8
    if ! curl -s http://localhost:11434/api/tags > /dev/null 2>&1; then
        err "Ollama failed to start. See log: /tmp/ollama_serve.log"
    fi
fi
ok "Ollama service running."

# ==============================================================
# STEP 3: Download AI model
# ==============================================================
s "Step 3/5: Downloading AI model ($MODEL, ~3.3 GB)..."
echo "     This will take 5-20 minutes. Do not close this window."
echo ""

if ollama list 2>/dev/null | grep -q "gemma3:4b"; then
    ok "Model $MODEL already downloaded."
else
    ollama pull "$MODEL" || err "Model download failed. Check internet and try again."
    ok "Model $MODEL downloaded successfully."
fi

# ==============================================================
# STEP 4: Install AnythingLLM
# ==============================================================
s "Step 4/5: Installing AnythingLLM (chat interface)..."

if [ -d "$ANYLLM_APP" ]; then
    ok "AnythingLLM already installed."
else
    ANYLLM_DMG="$INSTALL_DIR/AnythingLLMDesktop.dmg"
    download_file "$ANYLLM_DMG_URL" "$ANYLLM_DMG" "AnythingLLM"

    echo "     Mounting installer..."
    MOUNT_POINT=$(hdiutil attach "$ANYLLM_DMG" -nobrowse -quiet 2>/dev/null | \
        grep "/Volumes/" | tail -1 | sed 's/.*\/Volumes\//\/Volumes\//')

    if [ -z "$MOUNT_POINT" ]; then
        err "Failed to mount AnythingLLM installer. Try downloading manually: https://anythingllm.com"
    fi

    APP_SRC=$(find "$MOUNT_POINT" -maxdepth 1 -name "*.app" | head -1)
    if [ -z "$APP_SRC" ]; then
        hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null || true
        err "Could not find AnythingLLM app in installer"
    fi

    echo "     Copying AnythingLLM to Applications..."
    cp -R "$APP_SRC" /Applications/ || err "Failed to copy AnythingLLM to Applications"
    hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null || true
    rm -f "$ANYLLM_DMG"

    # Remove quarantine so macOS does not block launch
    xattr -rd com.apple.quarantine "$ANYLLM_APP" 2>/dev/null || true

    ok "AnythingLLM installed successfully."
fi

# ==============================================================
# STEP 5: Create startup script
# ==============================================================
s "Step 5/5: Creating startup script..."

START_SCRIPT="$INSTALL_DIR/Start-PrivateAI.sh"
cat > "$START_SCRIPT" << 'STARTSCRIPT'
#!/bin/bash
# PrivateAI Startup Script
echo "Starting PrivateAI..."
ollama serve > /tmp/ollama_serve.log 2>&1 &
sleep 3
open /Applications/AnythingLLM.app
echo "PrivateAI started."
STARTSCRIPT
chmod +x "$START_SCRIPT"
ok "Startup script created: $START_SCRIPT"

# ==============================================================
# DONE
# ==============================================================
echo ""
echo "============================================================"
echo "   Installation complete! PrivateAI is ready."
echo "============================================================"
echo ""
echo "   HOW TO START:"
echo "   Double-click AnythingLLM in your Applications folder"
echo "   OR run: bash ~/PrivateAI/Start-PrivateAI.sh"
echo ""
echo "   FIRST LAUNCH SETUP:"
echo "   1. Click Get started"
echo "   2. Click Manual setup (ignore suggested model)"
echo "   3. Select Ollama as your LLM provider"
echo "   4. Choose model: gemma3:4b"
echo "   5. Skip the email form, click arrow ->"
echo "   6. Click Open the assistant"
echo ""
echo "   Upload PDF or DOCX: paperclip icon in chat"
echo "   Works 100% offline after installation."
echo ""
echo "   Support: privatedeskai@gmail.com"
echo "   Log: $LOG_FILE"
echo ""
log "=== Installation Complete ==="

# Launch
echo "   Launching AnythingLLM..."
ollama serve > /tmp/ollama_serve.log 2>&1 &
sleep 2
open "$ANYLLM_APP" 2>/dev/null || true

read -r -p "Press Enter to finish..."
