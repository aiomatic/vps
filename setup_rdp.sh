#!/bin/bash
# ============================================================
# setup_rdp.sh — Ubuntu XFCE + noVNC (port 6080)
# Fully automated for Azure VMs — no prompts, no failures.
# ============================================================

set -e
export HOME=/home/azureuser
cd $HOME

echo "🧩 Starting Ubuntu desktop setup..."

# ------------------------------------------------------------
# 1️⃣ Update system
# ------------------------------------------------------------
sudo apt update -y && sudo apt upgrade -y

# ------------------------------------------------------------
# 2️⃣ Create 16 GB Swap file
# ------------------------------------------------------------
echo "🌿 Creating 16 GB swap..."
if [ ! -f /swapfile ]; then
  sudo fallocate -l 16G /swapfile || sudo dd if=/dev/zero of=/swapfile bs=1M count=16384
  sudo chmod 600 /swapfile
  sudo mkswap /swapfile
  sudo swapon /swapfile
  echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
fi

# ------------------------------------------------------------
# 3️⃣ Install Desktop & Tools
# ------------------------------------------------------------
sudo apt install -y xfce4 xfce4-goodies tightvncserver novnc websockify python3-numpy curl wget unzip net-tools

# ------------------------------------------------------------
# 4️⃣ Prepare VNC password & xstartup
# ------------------------------------------------------------
echo "🔐 Setting VNC password..."
sudo mkdir -p /home/azureuser/.vnc
echo "chrome123" | vncpasswd -f | sudo tee /home/azureuser/.vnc/passwd >/dev/null
sudo chmod 600 /home/azureuser/.vnc/passwd
sudo chown -R azureuser:azureuser /home/azureuser/.vnc

cat <<EOF | sudo tee /home/azureuser/.vnc/xstartup
#!/bin/bash
xrdb \$HOME/.Xresources
startxfce4 &
EOF
sudo chmod +x /home/azureuser/.vnc/xstartup
sudo chown azureuser:azureuser /home/azureuser/.vnc/xstartup

# ------------------------------------------------------------
# 5️⃣ Create VNC systemd service
# ------------------------------------------------------------
cat <<EOF | sudo tee /etc/systemd/system/vncserver.service
[Unit]
Description=VNC Server for azureuser
After=network.target

[Service]
Type=forking
User=azureuser
WorkingDirectory=/home/azureuser
PAMName=login
PIDFile=/home/azureuser/.vnc/%H:1.pid
ExecStartPre=-/usr/bin/vncserver -kill :1
ExecStart=/usr/bin/vncserver :1 -geometry 1280x800 -depth 24
ExecStop=/usr/bin/vncserver -kill :1
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# ------------------------------------------------------------
# 6️⃣ Install Google Chrome
# ------------------------------------------------------------
cd /home/azureuser
wget -q https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
sudo apt install -y ./google-chrome-stable_current_amd64.deb || true
rm -f google-chrome-stable_current_amd64.deb

# ------------------------------------------------------------
# 7️⃣ Chrome desktop shortcut
# ------------------------------------------------------------
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
# 8️⃣ SSL certificate for noVNC
# ------------------------------------------------------------
sudo mkdir -p /etc/ssl/novnc
sudo openssl req -x509 -nodes -newkey rsa:2048 \
  -keyout /etc/ssl/novnc/self.pem \
  -out /etc/ssl/novnc/self.pem \
  -days 365 \
  -subj "/CN=localhost"

# ------------------------------------------------------------
# 9️⃣ noVNC service
# ------------------------------------------------------------
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
# 🔟 Disable sleep
# ------------------------------------------------------------
sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target || true

# ------------------------------------------------------------
# 11️⃣ Enable & start
# ------------------------------------------------------------
sudo systemctl daemon-reload
sudo systemctl enable vncserver novnc
sudo systemctl restart vncserver || true
sudo systemctl restart novnc || true

echo "✅ Setup complete!"
echo "🌍 Access: http://<your-vm-ip>:6080/"
echo "🔑 Password: chrome123"
