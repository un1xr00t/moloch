#!/bin/bash
# OBSIDIAN + Ollama service installer
# Run as your normal user (not root) — sudo is used only where needed

set -e

USER_NAME=$(whoami)
HOME_DIR=$HOME
APP_DIR="$HOME_DIR/obsidian-app"

echo ""
echo "  ██████╗ ██████╗ ███████╗██╗██████╗ ██╗ █████╗ ███╗   ██╗"
echo " ██╔═══██╗██╔══██╗██╔════╝██║██╔══██╗██║██╔══██╗████╗  ██║"
echo " ██║   ██║██████╔╝███████╗██║██║  ██║██║███████║██╔██╗ ██║"
echo " ██║   ██║██╔══██╗╚════██║██║██║  ██║██║██╔══██║██║╚██╗██║"
echo " ╚██████╔╝██████╔╝███████║██║██████╔╝██║██║  ██║██║ ╚████║"
echo "  ╚═════╝ ╚═════╝ ╚══════╝╚═╝╚═════╝ ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝"
echo ""
echo "  Service Installer"
echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ── 1. Create app directory ───────────────────────────────────
echo "[1/6] Creating app directory at $APP_DIR..."
mkdir -p "$APP_DIR"

# Copy files if they exist in current directory
if [ -f "./obsidian.html" ]; then
    cp -n ./obsidian.html "$APP_DIR/" 2>/dev/null || true
    echo "      Copied obsidian.html"
fi
if [ -f "./obsidian_server.py" ]; then
    cp -n ./obsidian_server.py "$APP_DIR/" 2>/dev/null || true
    echo "      Copied obsidian_server.py"
fi

# ── 2. Install Python deps ────────────────────────────────────
echo "[2/6] Installing Python dependencies..."
pip install fastapi uvicorn --quiet --break-system-packages 2>/dev/null || \
pip install fastapi uvicorn --quiet

# ── 3. Write Ollama service ───────────────────────────────────
echo "[3/6] Installing Ollama service..."

# Check if ollama service already exists (installed via official script)
if systemctl list-unit-files | grep -q "^ollama.service"; then
    echo "      Ollama service already exists — patching OLLAMA_ORIGINS..."
    # Just add the environment override
    sudo mkdir -p /etc/systemd/system/ollama.service.d
    sudo tee /etc/systemd/system/ollama.service.d/override.conf > /dev/null << EOF
[Service]
Environment="OLLAMA_ORIGINS=*"
EOF
else
    echo "      Installing fresh Ollama service..."
    sudo tee /etc/systemd/system/ollama.service > /dev/null << EOF
[Unit]
Description=Ollama Local AI Server
After=network.target

[Service]
Type=simple
User=$USER_NAME
Environment="OLLAMA_ORIGINS=*"
Environment="OLLAMA_HOST=127.0.0.1:11434"
ExecStart=/usr/local/bin/ollama serve
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
fi

# ── 4. Write OBSIDIAN service ───────────────────────────────────
echo "[4/6] Installing OBSIDIAN server service..."
PYTHON_PATH=$(which python3)

sudo tee /etc/systemd/system/obsidian-server.service > /dev/null << EOF
[Unit]
Description=OBSIDIAN AI Interface Server
After=network.target

[Service]
Type=simple
User=$USER_NAME
WorkingDirectory=$APP_DIR
ExecStart=$PYTHON_PATH $APP_DIR/obsidian_server.py
Restart=always
RestartSec=5
Environment="PYTHONUNBUFFERED=1"

[Install]
WantedBy=multi-user.target
EOF

# ── 5. Enable and start both ──────────────────────────────────
echo "[5/6] Enabling services to start on boot..."
sudo systemctl daemon-reload
sudo systemctl enable ollama.service
sudo systemctl enable obsidian-server.service

echo "[6/6] Starting services now..."
sudo systemctl restart ollama.service
sleep 2
sudo systemctl start obsidian-server.service

# ── Done ──────────────────────────────────────────────────────
echo ""
echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  DONE"
echo ""
echo "  Ollama:  http://localhost:11434"
echo "  OBSIDIAN:  http://localhost:8000"
echo ""
echo "  Useful commands:"
echo "    sudo systemctl status obsidian-server   # check status"
echo "    sudo systemctl status ollama          # check ollama"
echo "    sudo journalctl -u obsidian-server -f   # live logs"
echo "    sudo journalctl -u ollama -f          # ollama logs"
echo "    sudo systemctl restart obsidian-server  # restart"
echo ""
echo "  App files: $APP_DIR"
echo "  Data:      ~/obsidian/obsidian.db"
echo ""

# Check if services are actually running
if systemctl is-active --quiet obsidian-server; then
    echo "  [OK] OBSIDIAN server is running"
else
    echo "  [!!] OBSIDIAN server failed to start — check: sudo journalctl -u obsidian-server -n 50"
fi

if systemctl is-active --quiet ollama; then
    echo "  [OK] Ollama is running"
else
    echo "  [!!] Ollama failed to start — check: sudo journalctl -u ollama -n 50"
fi

echo ""
