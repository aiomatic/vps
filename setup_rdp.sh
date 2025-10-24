#!/bin/bash
# ----------------------------------------------------------
# setup_rdp.sh — Ubuntu XFCE + noVNC web desktop (HTTPS)
# with 16 GB swap automatically configured
# ----------------------------------------------------------

set -e
export HOME=/home/azureuser
cd $HOME

echo "🔧 Updating system..."
sudo apt update -y && sudo apt upgrade -y

echo "🧩 Creating 16 GB swap file..."
if [ ! -f /swapfile ]; then
  sudo fallocate -l 16G /swapfile || sudo dd if=/dev/zero of=/swapfile bs=1M count=16384
  sudo chmod 600 /swapfile
  sudo mkswap /swapfile
  sudo swapon /swapfile
  echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
  echo 'vm.swappiness=10' | sudo tee /etc/sysctl.d/99-swappiness.conf
  sudo sysctl -p /etc/sysctl.d/99-swappiness.conf
fi

echo "🖥️ Installing desktop + tools..."
sudo apt install -y xfce4 xfce4-goodies tightvncserver novnc websockify python3-websockify wget openssl

# --- Create VNC password ---
echo "🧩 Setting VNC password..."
mkdir -p ~/.vnc
(echo "chrome123"; echo "chrome123"; echo "n") | vncpasswd
cat <<'EOF' > ~/.vnc/xstartup
#!/bin/bash
xrdb $HOME/.Xresources
startxfce4 &
EOF
chmod +x ~/.vnc/xstartup

# --- Install Google Chrome ---
echo "🌐 Installing Google Chrome..."
wget -q https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
sudo apt install -y ./google-chrome-stable_current_amd64.deb || true

# --- Create desktop shortcut ---
echo "🖱️ Creating Chrome desktop shortcut..."
mkdir -p ~/Desktop
cat <<EOF > ~/Desktop/Google-Chrome.desktop
[Desktop Entry]
Version=1.0
Name=Google Chrome
Exec=/usr/bin/google-chrome-stable
Icon=google-chrome
Type=Application
Terminal=false
Categories=Network;WebBrowser;
EOF
chmod +x ~/Desktop/Google-Chrome.desktop

# --- Create VNC systemd service ---
echo "⚙️ Creating VNC systemd service..."
sudo tee /etc/systemd/system/vncserver.service > /dev/null <<'EOF'
[Unit]
Description=VNC Server for azureuser
After=network.target

[Service]
Type=forking
User=azureuser
ExecStart=/usr/bin/vncserver :1 -geometry 1280x800 -depth 24
ExecStop=/usr/bin/vncserver -kill :1
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# --- Create self-signed SSL certificate for noVNC ---
echo "🔐 Generating self-signed certificate..."
sudo mkdir -p /usr/share/novnc
sudo openssl req -x509 -nodes -newkey rsa:2048 \
  -keyout /usr/share/novnc/self.pem \
  -out /usr/share/novnc/self.pem \
  -days 365 \
  -subj "/C=US/ST=None/L=None/O=romanempirehistory/CN=$(hostname -f)"
sudo chmod 600 /usr/share/novnc/self.pem

# --- Create noVNC systemd service (HTTPS) ---
echo "🌍 Creating noVNC service..."
sudo tee /etc/systemd/system/novnc.service > /dev/null <<'EOF'
[Unit]
Description=noVNC WebSocket proxy
After=vncserver.service
Wants=vncserver.service

[Service]
Type=simple
User=azureuser
ExecStart=/usr/share/novnc/utils/launch.sh --vnc localhost:5901 --listen 6080 --ssl-only --cert /usr/share/novnc/self.pem
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# --- Disable sleep/hibernate ---
echo "💤 Disabling sleep and hibernate..."
sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target

# --- Enable and start services ---
echo "🚀 Enabling and starting services..."
sudo systemctl daemon-reload
sudo systemctl enable vncserver novnc
sudo systemctl restart vncserver novnc

echo "✅ Setup complete!"
echo "Access your desktop at: https://$(curl -s ifconfig.me):6080/"
echo "VNC Password: chrome123"
