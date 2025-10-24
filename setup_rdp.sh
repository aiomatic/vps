#!/bin/bash
# ============================================================
# setup_rdp.sh — Ubuntu XFCE + noVNC desktop for Azure VM
# Fully non-interactive. Auto-starts VNC & noVNC after reboot.
# ============================================================

set -e
export HOME=/home/azureuser

echo "🧩 Starting Azure VM Desktop Setup..."

# ------------------------------------------------------------
# 1️⃣ Update
# ------------------------------------------------------------
apt update -y && apt upgrade -y

# ------------------------------------------------------------
# 2️⃣ 16 GB Swap
# ------------------------------------------------------------
if [ ! -f /swapfile ]; then
  echo "🌿 Creating 16 GB swap file..."
  fallocate -l 16G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=16384
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

# ------------------------------------------------------------
# 3️⃣ Install XFCE + Tools
# ------------------------------------------------------------
echo "🖥️ Installing XFCE and dependencies..."
DEBIAN_FRONTEND=noninteractive apt install -y xfce4 xfce4-goodies tightvncserver novnc websockify python3-numpy curl wget unzip net-tools dbus-x11

# ------------------------------------------------------------
# 4️⃣ Create azureuser home directories
# ------------------------------------------------------------
mkdir -p /home/azureuser/.vnc /home/azureuser/Desktop
chown -R azureuser:azureuser /home/azureuser

# ------------------------------------------------------------
# 5️⃣ Configure VNC (non-interactive)
# ------------------------------------------------------------
echo "🔐 Configuring VNC password..."
echo "chrome123" | vncpasswd -f > /home/azureuser/.vnc/passwd
chmod 600 /home/azureuser/.vnc/passwd
chown azureuser:azureuser /home/azureuser/.vnc/passwd

cat <<'EOF' > /home/azureuser/.vnc/xstartup
#!/bin/bash
xrdb $HOME/.Xresources
startxfce4 &
EOF
chmod +x /home/azureuser/.vnc/xstartup
chown azureuser:azureuser /home/azureuser/.vnc/xstartup

# ------------------------------------------------------------
# 6️⃣ Install Chrome
# ------------------------------------------------------------
echo "🌐 Installing Google Chrome..."
wget -q https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb -O /tmp/chrome.deb
apt install -y /tmp/chrome.deb || true
rm -f /tmp/chrome.deb

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
chown -R azureuser:azureuser /home/azureuser/Desktop

# ------------------------------------------------------------
# 7️⃣ SSL cert for noVNC
# ------------------------------------------------------------
mkdir -p /etc/ssl/novnc
openssl req -x509 -nodes -newkey rsa:2048 \
  -keyout /etc/ssl/novnc/self.pem \
  -out /etc/ssl/novnc/self.pem \
  -days 365 \
  -subj "/CN=localhost"

# ------------------------------------------------------------
# 8️⃣ VNC + noVNC services
# ------------------------------------------------------------
cat <<'EOF' > /etc/systemd/system/vncserver.service
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

cat <<'EOF' > /etc/systemd/system/novnc.service
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
# 9️⃣ Disable sleep
# ------------------------------------------------------------
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target || true

# ------------------------------------------------------------
# 🔟 Enable on next boot (not now)
# ------------------------------------------------------------
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable vncserver novnc

# Do not start now to avoid root TTY failure
echo "🚀 Setup finished. Services will start automatically after reboot."

# ------------------------------------------------------------
# 🔁 Reboot to activate
# ------------------------------------------------------------
reboot
