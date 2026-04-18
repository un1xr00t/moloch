# OBSIDIAN // Unrestricted Local AI Interface

<img width="1486" height="1022" alt="image" src="https://github.com/user-attachments/assets/04c37e36-3a53-4c10-8868-b2d1e1a6903b" />


> A single-file, self-hosted AI interface that connects to [Ollama](https://ollama.com) for fully local, private, unrestricted AI. No cloud. No API keys. No filters. Your hardware, your models, your data.

---

## Features

- Single `obsidian.html` file — no build step, no framework
- Projects system with persistent memory, file attachments, and custom system instructions
- Auto artifact panel for code — detects complete files, shows syntax-highlighted split view
- AI memory extraction — automatically pulls key facts from conversations every 4 exchanges
- Full chat history with session management
- FastAPI + SQLite backend (`obsidian_server.py`) for persistence across devices
- Works fully offline (no internet required once models are pulled)
- Multi-device support via SSH reverse tunnel

---

## Stack

| Component | Tech |
|-----------|------|
| Frontend | Vanilla HTML/CSS/JS, single file |
| Backend | Python, FastAPI, SQLite |
| AI Runtime | Ollama |
| Fonts | JetBrains Mono |
| Markdown | marked.js (cdnjs) |
| Syntax highlighting | highlight.js (cdnjs) |

---

## Quick Start (Single Machine)

### 1. Install Ollama

```bash
curl -fsSL https://ollama.com/install.sh | sh
```

### 2. Pull a model

```bash
ollama pull qwen2.5-coder:14b
```

### 3. Clone the repo

```bash
git clone https://github.com/un1xr00t/obsidian.git
cd obsidian
```

### 4. Install Python dependencies

```bash
pip install fastapi uvicorn
```

### 5. Run the server

```bash
python3 obsidian_server.py
```

Open `http://localhost:8000` in your browser. Done.

---

## Model Recommendations by Hardware

OBSIDIAN works with any model Ollama supports. Here's a general guide:

### Low-end (8–16GB VRAM or RAM-only)
```bash
ollama pull qwen2.5-coder:7b
ollama pull mistral:7b
ollama pull dolphin-mistral        # uncensored
```

### Mid-range (16–24GB VRAM)
```bash
ollama pull qwen2.5-coder:14b
ollama pull huihui_ai/qwen2.5-coder-abliterate:14b   # uncensored version
ollama pull deepseek-r1:14b
```

### High-end (24–48GB+ VRAM)
```bash
ollama pull qwen2.5-coder:32b
ollama pull deepseek-r1:70b
ollama pull huihui_ai/deepseek-r1-abliterated:70b-llama-distill-q8_0   # uncensored
ollama pull dolphin-mixtral:8x22b
```

> **Quantization tip:** If a model doesn't fit in VRAM, try a quantized version. `Q5_K_M` is the best quality/size tradeoff. `Q4_K_M` for tighter fits. `Q8_0` if you have headroom.

---

## Auto-Install (Linux / systemd)

The included `install_services.sh` sets up Ollama and OBSIDIAN as systemd services that start on boot.

```bash
chmod +x install_services.sh
./install_services.sh
```

This will:
- Copy `obsidian.html` and `obsidian_server.py` to `~/obsidian-app/`
- Install Python dependencies
- Create and enable `ollama.service` (or patch existing)
- Create and enable `obsidian-server.service`
- Start both services immediately

### Useful commands after install

```bash
sudo systemctl status obsidian-server
sudo systemctl status ollama
sudo journalctl -u obsidian-server -f    # live logs
sudo journalctl -u ollama -f
sudo systemctl restart obsidian-server
```

---

## macOS Setup

### Ollama
Download from [ollama.com](https://ollama.com) or:
```bash
brew install ollama
brew services start ollama
```

### obsidian_server.py (via tmux — recommended)

```bash
# Create a venv and install deps
python3 -m venv ~/obsidian-venv
~/obsidian-venv/bin/pip install fastapi uvicorn

# Start in a persistent tmux session
brew install tmux
tmux new-session -d -s obsidian '~/obsidian-venv/bin/python3 ~/obsidian-app/obsidian_server.py'
```

Add to `~/.zshrc` for auto-start on login:
```bash
# OBSIDIAN server auto-start
if ! lsof -ti :8000 > /dev/null 2>&1; then
  tmux new-session -d -s obsidian "~/obsidian-venv/bin/python3 ~/obsidian-app/obsidian_server.py" 2>/dev/null
fi
```

Verify everything is running:
```bash
curl http://localhost:8000/health   # OBSIDIAN server
curl http://localhost:11434         # Ollama
```

---

## Multi-Device Setup (VPS + SSH Tunnel)

This setup lets you access OBSIDIAN from any browser (phone, tablet, remote machine) while keeping all AI inference on your local hardware.

### Architecture

```
[Your Machine] ──autossh──▶ [VPS] ──nginx──▶ [Browser anywhere]
  Ollama :11434                 :11434 (tunneled)
  obsidian_server :8000           nginx serves obsidian.html
```

### VPS Requirements

Any cheap Linux VPS works (1GB RAM, 1 vCPU is enough — it's just a proxy).
- Ubuntu 22.04 or 24.04 recommended
- A domain name pointed at your VPS IP

### VPS Setup

```bash
# SSH into your VPS
ssh user@your-vps-ip

# Install nginx
apt update && apt install -y nginx certbot python3-certbot-nginx ufw fail2ban

# Configure UFW
ufw allow ssh
ufw allow 80
ufw allow 443
ufw enable

# Configure nginx — create /etc/nginx/sites-available/obsidian
cat > /etc/nginx/sites-available/obsidian << 'EOF'
server {
    listen 80;
    server_name your.domain.com;

    # Serve the UI
    location / {
        root /var/www/obsidian;
        index obsidian.html;
        try_files $uri $uri/ /obsidian.html;
    }

    # Proxy Ollama API (tunneled from local machine)
    location /api/ {
        proxy_pass http://127.0.0.1:11434/api/;
        proxy_http_version 1.1;
        proxy_set_header Connection '';
        chunked_transfer_encoding on;
        proxy_buffering off;
        proxy_read_timeout 300s;
    }
}
EOF

ln -s /etc/nginx/sites-available/obsidian /etc/nginx/sites-enabled/
nginx -t && systemctl reload nginx

# Get SSL cert
certbot --nginx -d your.domain.com

# Create web root and copy obsidian.html
mkdir -p /var/www/obsidian
# (scp obsidian.html here from your local machine)
```

### SSH Tunnel (Linux — systemd)

Install autossh:
```bash
sudo apt install autossh    # or: brew install autossh on macOS
```

Create the tunnel service on your **local machine**:

```bash
sudo tee /etc/systemd/system/obsidian-tunnel.service > /dev/null << EOF
[Unit]
Description=OBSIDIAN SSH Reverse Tunnel
After=network.target

[Service]
Type=simple
User=$USER
ExecStart=/usr/bin/autossh -M 0 -N \
  -o "ServerAliveInterval=30" \
  -o "ServerAliveCountMax=3" \
  -o "ExitOnForwardFailure=yes" \
  -o "StrictHostKeyChecking=no" \
  -R 11434:localhost:11434 \
  -i ~/.ssh/your_vps_key \
  user@your-vps-ip
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable obsidian-tunnel
sudo systemctl start obsidian-tunnel
```

### SSH Tunnel (macOS — launchd)

```bash
cat > ~/Library/LaunchAgents/com.obsidian.tunnel.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.obsidian.tunnel</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/ssh</string>
        <string>-N</string>
        <string>-o</string><string>ServerAliveInterval=30</string>
        <string>-o</string><string>ExitOnForwardFailure=yes</string>
        <string>-R</string><string>11434:localhost:11434</string>
        <string>-i</string><string>/Users/YOU/.ssh/your_vps_key</string>
        <string>user@your-vps-ip</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/obsidian-tunnel.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/obsidian-tunnel.err</string>
</dict>
</plist>
EOF

launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.obsidian.tunnel.plist
```

### Deploy updated obsidian.html to VPS

```bash
scp ~/obsidian-app/obsidian.html user@your-vps-ip:/var/www/obsidian/obsidian.html
```

No service restart needed — nginx serves it as a static file.

---

## Data & Privacy

- All chat history and project data is stored locally in SQLite (`~/obsidian/obsidian.db`)
- Nothing is sent to any external service
- Ollama runs entirely on your hardware
- The VPS only acts as a reverse proxy — it never sees your data, only tunneled API calls between your browser and your machine

---

## VPS Hardening

If you're setting up a VPS for remote access, the included `vps-harden.sh` handles everything in one shot:

```bash
# Run as root on a fresh Ubuntu 22.04/24.04 VPS
chmod +x vps-harden.sh
./vps-harden.sh your.domain.com your@email.com
```

This sets up:
- **nginx** — serves `obsidian.html` and proxies `/api/` to Ollama (via tunnel)
- **SSL** — certbot + Let's Encrypt, auto-redirect HTTP to HTTPS
- **UFW** — firewall, allows only SSH/80/443
- **fail2ban** — SSH brute force protection
- **SSH hardening** — disables password auth, root key-only

After running, copy `obsidian.html` to `/var/www/obsidian/obsidian.html` and set up the SSH tunnel from your local machine (see Multi-Device Setup above).

---

## File Structure

```
obsidian/
├── obsidian.html          # The entire frontend (single file)
├── obsidian_server.py     # FastAPI backend + SQLite persistence
├── install_services.sh  # Linux systemd auto-installer (local machine)
├── vps-harden.sh        # VPS hardening + nginx setup (run on VPS as root)
└── README.md
```

---

## License

MIT
