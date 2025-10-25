#!/bin/bash
set -e

echo "🚀 Starting full RDP + VNC + noVNC setup..."

# === 1️⃣ SYSTEM UPDATE ===
export DEBIAN_FRONTEND=noninteractive
apt update -y && apt upgrade -y
apt install -y xfce4 xfce4-goodies tightvncserver novnc websockify python3-numpy curl wget net-tools ufw unzip xrdp -q

# === 2️⃣ ADD 16GB SWAP (if not exists) ===
if [ ! -f /swapfile ]; then
  echo "💾 Creating 16GB swap..."
  fallocate -l 16G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=16384
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' | tee -a /etc/fstab
fi

# === 3️⃣ CONFIGURE VNC ===
VNC_PASS="chrome123"
USER_HOME="/home/azureuser"

mkdir -p $USER_HOME/.vnc
echo $VNC_PASS | vncpasswd -f > $USER_HOME/.vnc/passwd
chown -R azureuser:azureuser $USER_HOME/.vnc
chmod 600 $USER_HOME/.vnc/passwd

cat > $USER_HOME/.vnc/xstartup <<'EOF'
#!/bin/bash
xrdb $HOME/.Xresources
startxfce4 &
EOF
chmod +x $USER_HOME/.vnc/xstartup

# === 4️⃣ CREATE SYSTEMD SERVICE FOR VNC ===
cat > /etc/systemd/system/vncserver.service <<'EOF'
[Unit]
Description=VNC Server for azureuser
After=network.target

[Service]
Type=forking
User=azureuser
PAMName=login
PIDFile=/home/azureuser/.vnc/%H:1.pid
ExecStartPre=-/usr/bin/vncserver -kill :1 > /dev/null 2>&1
ExecStart=/usr/bin/vncserver :1 -geometry 1280x800 -depth 24
ExecStop=/usr/bin/vncserver -kill :1

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable vncserver
systemctl start vncserver

# === 5️⃣ INSTALL GOOGLE CHROME ===
echo "🌐 Installing Google Chrome..."
cd $USER_HOME
wget -q https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
apt install -y ./google-chrome-stable_current_amd64.deb || apt -f install -y
rm -f google-chrome-stable_current_amd64.deb

# === 6️⃣ CREATE SYSTEMD SERVICE FOR noVNC ===
echo "🕸️ Setting up noVNC..."
ln -sf /usr/share/novnc /opt/novnc
ln -sf /usr/share/novnc/utils/websockify /usr/bin/websockify

cat > /etc/systemd/system/novnc.service <<'EOF'
[Unit]
Description=noVNC WebSocket proxy
After=network.target vncserver.service

[Service]
User=root
ExecStart=/usr/bin/websockify --web=/usr/share/novnc/ 6080 localhost:5901
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable novnc
systemctl restart novnc

# === 7️⃣ CONFIGURE XRDP ===
echo "🖥️ Enabling xRDP..."
echo xfce4-session > /home/azureuser/.xsession
chown azureuser:azureuser /home/azureuser/.xsession
systemctl enable xrdp
systemctl restart xrdp

# === 8️⃣ FIREWALL RULES ===
echo "🔓 Configuring UFW..."
ufw allow 22/tcp
ufw allow 3389/tcp
ufw allow 5901/tcp
ufw allow 6080/tcp
ufw --force enable || true

# === 9️⃣ DISPLAY ACCESS INFO ===
IP=$(hostname -I | awk '{print $1}')
echo "✅ Setup Completed!"
echo "➡️ RDP: $IP:3389  (login with Ubuntu user)"
echo "➡️ noVNC: http://$IP:6080/vnc.html  (password: $VNC_PASS)"
echo "➡️ VNC: $IP:5901  (password: $VNC_PASS)"
