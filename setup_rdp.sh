#!/bin/bash
# ============================================================
# setup_rdp.sh — Ubuntu XFCE + noVNC web desktop (HTTP)
# Works fully automated for Azure Custom Script Extension
# Includes 16 GB swap, Chrome, XFCE, and auto-start services
# ============================================================

set -e
export HOME=/home/azureuser
cd $HOME

echo "🧩 Starting Ubuntu desktop setup..."

# ------------------------------------------------------------
# 1️⃣ Update system
# ------------------------------------------------------------
echo "🧩 Updating system packages..."
sudo apt update -y && sudo apt upgrade -y

# ------------------------------------------------------------
# 2️⃣ Create 16 GB Swap file
# ------------------------------------------------------------
echo "🌿 Creating 16 GB swap file..."
if [ ! -f /swapfile ]; then
  sudo fallocate -l 16G /swapfile || sudo dd if=/dev/zero of=/swapfile bs=1M count=16384
  sudo chmod 600 /swapfile
  sudo mkswap /swapfile
  sudo swapon /swapfile
  echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
  echo 'vm.swappiness=10' | sudo tee /etc/sysctl.d/99-swappiness.conf
  sudo sysctl -p /etc/sysctl.d/99-swappiness.conf
fi

# ------------------------------------------------------------
# 3️⃣ Install XFCE Desktop + VNC + noVNC
# ------------------------------------------------------------
echo "🖥️ Installing XFCE, xrdp, and noVNC..."
sudo apt install -y xfce4 xfce4-goodies tightvncserver novnc websockify python3-numpy curl wget unzip net-tools

# ------------------------------------------------------------
# 4️⃣ Set up VNC password (non-interactive)
# ------------------------------------------------------------
echo "🔐 Configuring VNC password..."
sudo mkdir -p /home/azureuser/.vnc
echo "chrome123" | vncpasswd -f | sudo tee /home/azureuser/.vnc/passwd >/dev/null
sudo chmod 600 /home/azureuser/.vnc/passwd
sudo chown -R azureuser:azureuser /home/azureuser/.vnc

# ------------------------------------------------------------
# 5️⃣ Create VNC systemd service
# ------------------------------------------------------------
echo "⚙️ Creating VNC systemd service..."
cat <<EOF | sudo tee /etc/systemd/system/vncserver.service
[Unit]
Description=VNC Server for azureuser
After=syslog.target network.target

[Service]
Type=forking
User=azureuser
PAMName=login
PIDFile=/home/azureuser/.vnc/%H:1.pid
ExecStart=/usr/bin/vncserver :1 -geometry 1280x800 -depth 24
ExecStop=/usr/bin/vncserver -kill :1
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# ------------------------------------------------------------
# 6️⃣ Install Google Chrome
# ------------------------------------------------------------
echo "🌐 Installing Google Chrome..."
cd /home/azureuser
wget -q https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
sudo apt install -y ./google-chrome-stable_current_amd64.deb || true
rm -f google-chrome-stable_current_amd64.deb

# ------------------------------------------------------------
# 7️⃣ Create Chrome desktop shortcut
# ------------------------------------------------------------
echo "🖱️ Creating Chrome desktop shortcut..."
mkdir -p /home/azureuser/Desktop
cat <<EOF > /home/azureuser/Desktop/chrome.desktop
[Desktop Entry]
Version=1.0
Type=Application
Name=Google Chrome
Exec=/usr/bin/google-chrome-stable
Icon=google-chrome
Categories=Network;WebBrowser;
Terminal=false
EOF
chmod +x /home/azureuser/Desktop/chrome.desktop
sudo chown -R azureuser:azureuser /home/azureuser/Desktop

# ------------------------------------------------------------
# 8️⃣ Generate self-signed certificate for noVNC (optional SSL)
# ------------------------------------------------------------
echo "🔐 Generating self-signed certificate..."
sudo mkdir -p /etc/ssl/novnc
sudo openssl req -x509 -nodes -newkey rsa:2048 \
  -keyout /etc/ssl/novnc/self.pem \
  -out /etc/ssl/novnc/self.pem \
  -days 365 \
  -subj "/CN=localhost"

# ------------------------------------------------------------
# 9️⃣ Create noVNC systemd service
# ------------------------------------------------------------
echo "🌍 Creating noVNC service..."
cat <<EOF | sudo tee /etc/systemd/system/novnc.service
[Unit]
Description=noVNC WebSocket Proxy
After=network.target vncserver.service

[Service]
Type=simple
User=azureuser
ExecStart=/usr/bin/websockify --web=/usr/share/novnc/ --cert=/etc/ssl/novnc/self.pem 6080 localhost:5901
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# ------------------------------------------------------------
# 🔟 Disable sleep/hibernate (for Azure VM resume)
# ------------------------------------------------------------
echo "💤 Disabling sleep and hibernate..."
sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target || true

# ------------------------------------------------------------
# 11️⃣ Enable and start services
# ------------------------------------------------------------
echo "🚀 Enabling and starting services..."
sudo systemctl daemon-reload
sudo systemctl enable vncserver novnc
sudo systemctl restart vncserver || true
sudo systemctl restart novnc || true

# ------------------------------------------------------------
# ✅ Done
# ------------------------------------------------------------
echo "✅ Setup complete! Access your desktop at: http://<VM-IP>:6080/"
echo "Password: chrome123"
