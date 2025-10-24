#!/bin/bash
set -e

echo "🚀 Starting full RDP/noVNC setup..."

# === 1️⃣ SYSTEM UPDATE ===
export DEBIAN_FRONTEND=noninteractive
apt update -y && apt upgrade -y
apt install -y xfce4 xfce4-goodies tightvncserver novnc websockify python3-numpy curl wget net-tools ufw unzip -q

# === 2️⃣ ADD 16GB SWAP ===
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
mkdir -p /home/azureuser/.vnc
echo $VNC_PASS | vncpasswd -f > /home/azureuser/.vnc/passwd
chown -R azureuser:azureuser /home/azureuser/.vnc
chmod 600 /home/azureuser/.vnc/passwd

cat > /home/azureuser/.vnc/xstartup <<'EOF'
#!/bin/bash
xrdb $HOME/.Xresources
startxfce4 &
EOF
chmod +x /home/azureuser/.vnc/xstartup

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

# === 5️⃣ INSTALL CHROME ===
echo "🌐 Installing Google Chrome..."
cd /home/azureuser
wget -q https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
apt install -y ./google-chrome-stable_current_amd64.deb || apt -f install -y
rm -f google-chrome-stable_current_amd64.deb

# === 6️⃣ CONFIGURE noVNC ===
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

# === 7️⃣ FIREWALL (UFW + Azure NSG) ===
echo "🔓 Configuring firewall..."
ufw allow 22/tcp
ufw allow 3389/tcp
ufw allow 5901/tcp
ufw allow 6080/tcp
ufw --force enable || true

# Azure NSG rule auto-open (if Azure CLI is installed)
if command -v az &> /dev/null; then
  VMNAME=$(hostname)
  RG=$(curl -s -H Metadata:true "http://169.254.169.254/metadata/instance/compute/resourceGroupName?api-version=2021-02-01&format=text" || echo "")
  NSG=$(az network nsg list --resource-group "$RG" --query "[0].name" -o tsv 2>/dev/null || echo "")
  if [ -n "$NSG" ]; then
    for port in 3389 5901 6080; do
      az network nsg rule create --resource-group "$RG" --nsg-name "$NSG" \
        --name allow-$port --priority $((300+$port)) \
        --access Allow --protocol Tcp --direction Inbound \
        --destination-port-ranges $port --source-address-prefixes '*' >/dev/null 2>&1 || true
    done
  fi
fi

# === 8️⃣ FINISH ===
echo "✅ Setup completed!"
echo "➡️ Access via: http://<your-public-ip>:6080/vnc.html"
echo "   VNC: localhost:5901"
echo "   Password: $VNC_PASS"
