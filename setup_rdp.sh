#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive

# === Helper ===
retry() {
  local n=1 max=3 delay=5
  while true; do
    "$@" && break || {
      if [[ $n -lt $max ]]; then
        echo "⚠️  Attempt $n/$max failed. Retrying in $delay s..."
        ((n++))
        sleep $delay
      else
        echo "❌  Command failed after $max attempts: $*"
        return 1
      fi
    }
  done
}

echo "🚀 Starting full RDP + VNC + noVNC + Tinyproxy setup..."

# === 1️⃣ System update & base packages ===
retry apt update -y
retry apt upgrade -y
retry apt install -y xfce4 xfce4-goodies tightvncserver novnc websockify python3-websockify \
    python3-numpy curl wget net-tools ufw unzip xrdp python3-pip tinyproxy

# === 2️⃣ Swapfile (once only) ===
if [ ! -f /swapfile ]; then
  echo "💾 Creating 16 GB swap..."
  retry fallocate -l 16G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=16384
  chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
  echo '/swapfile none swap sw 0 0' | tee -a /etc/fstab
fi

# === 3️⃣ VNC configuration ===
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

# === 4️⃣ Stable VNC systemd service ===
cat > /etc/systemd/system/vncserver.service <<'EOF'
[Unit]
Description=VNC Server for azureuser
After=network.target

[Service]
Type=simple
User=azureuser
WorkingDirectory=/home/azureuser

# Clean old sessions before start
ExecStartPre=-/usr/bin/bash -c 'pkill Xtightvnc || true; rm -f /home/azureuser/.vnc/*.pid /tmp/.X1-lock'

# Start VNC securely (localhost only)
ExecStart=/usr/bin/vncserver :1 -geometry 1280x800 -depth 24 -nolock -localhost
ExecStop=/usr/bin/vncserver -kill :1

Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
retry systemctl enable vncserver
retry systemctl restart vncserver

# === 5️⃣ Google Chrome ===
echo "🌐 Installing Google Chrome..."
cd $USER_HOME
retry wget -q https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
retry apt install -y ./google-chrome-stable_current_amd64.deb || apt -f install -y
rm -f google-chrome-stable_current_amd64.deb

# === 6️⃣ Ensure working websockify ===
echo "⚙️ Checking websockify..."
if ! command -v websockify &>/dev/null; then
  retry pip3 install websockify
fi
if [ ! -x /usr/bin/websockify ]; then
  echo "🧩 Creating manual websockify launcher..."
  cat >/usr/bin/websockify <<'EOW'
#!/usr/bin/env python3
from websockify import websocketproxy
if __name__ == "__main__":
    websocketproxy.websockify_init()
EOW
  chmod +x /usr/bin/websockify
fi

# === 7️⃣ noVNC service ===
cat > /etc/systemd/system/novnc.service <<'EOF'
[Unit]
Description=noVNC WebSocket proxy
After=network.target vncserver.service
[Service]
User=root
ExecStart=/usr/bin/websockify --web=/usr/share/novnc/ 6080 localhost:5901
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
retry systemctl enable novnc
retry systemctl restart novnc

# === 8️⃣ xRDP ===
echo xfce4-session > /home/azureuser/.xsession
chown azureuser:azureuser /home/azureuser/.xsession
retry systemctl enable xrdp
retry systemctl restart xrdp

# === 9️⃣ Tinyproxy (no authentication) ===
echo "🧱 Configuring Tinyproxy..."
mkdir -p /var/log/tinyproxy
chown nobody:nogroup /var/log/tinyproxy

cat > /etc/tinyproxy/tinyproxy.conf <<'EOF'
User nobody
Group nogroup
Port 8888
Timeout 600
DefaultErrorFile "/usr/share/tinyproxy/default.html"
StatFile "/usr/share/tinyproxy/stats.html"
Logfile "/var/log/tinyproxy/tinyproxy.log"
PidFile "/run/tinyproxy/tinyproxy.pid"
MaxClients 100
MinSpareServers 5
MaxSpareServers 20
StartServers 10
Allow 0.0.0.0/0
ConnectPort 443
ConnectPort 563
ViaProxyName "tinyproxy"
EOF

retry systemctl enable tinyproxy
retry systemctl restart tinyproxy

# === 🔟 Firewall ===
ufw allow 22/tcp
ufw allow 3389/tcp
ufw allow 5901/tcp
ufw allow 6080/tcp
ufw allow 8888/tcp
ufw --force enable || true

# === 11️⃣ Auto-restart services on boot ===
cat > /etc/systemd/system/auto-restart-services.service <<'EOF'
[Unit]
Description=Ensure VNC, noVNC, xRDP, and Tinyproxy restart on boot
After=network.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c '
  systemctl restart vncserver || true
  systemctl restart novnc || true
  systemctl restart xrdp || true
  systemctl restart tinyproxy || true
'
[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable auto-restart-services

# === ✅ Summary ===
IP=$(hostname -I | awk '{print $1}')
echo "✅ Setup Completed!"
echo "➡️ RDP: $IP:3389 (User: azureuser / Pass: chrome123)"
echo "➡️ noVNC: http://$IP:6080/vnc.html (password: chrome123)"
echo "➡️ VNC: localhost:5901 (password: chrome123)"
echo "➡️ Tinyproxy: $IP:8888 (no authentication)"
