#!/bin/bash
# ============================================================
# Azure Ubuntu Desktop Setup Script (XFCE + Chrome + VNC + noVNC)
# Author: Usman Farooq
# GitHub: https://github.com/aiomatic/vps
# Last Updated: Oct 2025
# ============================================================

set -e
export DEBIAN_FRONTEND=noninteractive

echo "🚀 Starting Azure Ubuntu Desktop setup..."

# ------------------------------------------------------------
# 1️⃣ Update system and install essentials
# ------------------------------------------------------------
apt-get update -y
apt-get upgrade -y
apt-get install -y xfce4 xfce4-goodies tightvncserver novnc websockify python3-numpy \
    xterm dbus-x11 policykit-1 wget curl sudo unzip software-properties-common \
    apt-transport-https gnupg ufw

# ------------------------------------------------------------
# 2️⃣ Set up 16 GB swap file
# ------------------------------------------------------------
if [ ! -f /swapfile ]; then
  echo "⚙️ Creating 16 GB swap..."
  fallocate -l 16G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=16384
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' | tee -a /etc/fstab
fi

# ------------------------------------------------------------
# 3️⃣ Set up VNC password and XFCE startup
# ------------------------------------------------------------
echo "🧩 Setting VNC password..."
mkdir -p /home/azureuser/.vnc
echo "chrome123" | vncpasswd -f > /home/azureuser/.vnc/passwd
chmod 600 /home/azureuser/.vnc/passwd
chown -R azureuser:azureuser /home/azureuser/.vnc

cat > /home/azureuser/.vnc/xstartup <<'EOF'
#!/bin/bash
xrdb $HOME/.Xresources
startxfce4 &
EOF
chmod +x /home/azureuser/.vnc/xstartup
chown azureuser:azureuser /home/azureuser/.vnc/xstartup

# ------------------------------------------------------------
# 4️⃣ Install Google Chrome
# ------------------------------------------------------------
echo "🌐 Installing Google Chrome..."
cd /home/azureuser
wget -q https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
apt install -y ./google-chrome-stable_current_amd64.deb || apt-get install -f -y
rm -f google-chrome-stable_current_amd64.deb

# ------------------------------------------------------------
# 5️⃣ Create reliable VNC startup service
# ------------------------------------------------------------
echo "🖥️ Creating VNC auto-start service..."
cat > /usr/local/bin/start_vnc.sh <<'EOF'
#!/bin/bash
USER="azureuser"
DISPLAY=":1"
GEOMETRY="1280x800"
DEPTH="24"
LOG="/home/$USER/.vnc/vnc_startup.log"

sleep 10
/usr/bin/vncserver -kill $DISPLAY >/dev/null 2>&1 || true
mkdir -p /home/$USER/.vnc
chown -R $USER:$USER /home/$USER/.vnc

sudo -u $USER -H /usr/bin/vncserver $DISPLAY -geometry $GEOMETRY -depth $DEPTH >> "$LOG" 2>&1
EOF
chmod +x /usr/local/bin/start_vnc.sh

cat > /etc/systemd/system/vnc-autostart.service <<'EOF'
[Unit]
Description=Auto-start VNC server for azureuser
After=network-online.target systemd-user-sessions.service
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/start_vnc.sh
Restart=always
RestartSec=15

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable vnc-autostart
systemctl start vnc-autostart

# ------------------------------------------------------------
# 6️⃣ Set up noVNC service
# ------------------------------------------------------------
echo "🌍 Setting up noVNC service..."
cat > /etc/systemd/system/novnc.service <<'EOF'
[Unit]
Description=noVNC Web Access
After=vnc-autostart.service

[Service]
ExecStart=/usr/bin/websockify --web=/usr/share/novnc/ --wrap-mode=ignore 6080 localhost:5901
Restart=always
User=azureuser

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable novnc
systemctl start novnc

# ------------------------------------------------------------
# 7️⃣ Security & usability improvements
# ------------------------------------------------------------
echo "💤 Disabling sleep and hibernate..."
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target

ufw allow 22/tcp
ufw allow 5901/tcp
ufw allow 6080/tcp
ufw --force enable

# ------------------------------------------------------------
# ✅ Final check
# ------------------------------------------------------------
echo "✅ Installation completed successfully!"
echo "🖥️ Access via VNC at: <your-public-ip>:5901"
echo "🌍 Access via browser (noVNC): http://<your-public-ip>:6080/"
echo "🔑 VNC password: chrome123"
