#!/bin/bash
# setup_rdp.sh — Auto RDP setup on Ubuntu for Azure
# ⚠️ For demo/lab use only — RDP on port 80 without auth is insecure.

set -e

# 1. Update system
sudo apt update -y && sudo apt upgrade -y

# 2. Install XFCE desktop + xrdp
sudo apt install xfce4 xfce4-goodies xrdp wget -y
echo xfce4-session > ~/.xsession
sudo systemctl enable xrdp

# 3. Change xrdp to port 80
sudo sed -i 's/3389/80/' /etc/xrdp/xrdp.ini

# 4. Disable xrdp password auth (lab only)
sudo sed -i 's/^auth required/#auth required/' /etc/pam.d/xrdp-sesman

# 5. Restart service
sudo systemctl restart xrdp

# 6. Allow port 80
sudo ufw allow 80/tcp || true
sudo ufw reload || true

# 7. Install Google Chrome
wget -q https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
sudo apt install ./google-chrome-stable_current_amd64.deb -y

# 8. Create desktop shortcut
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

# 9. Disable sleep/hibernate
sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target

echo "✅ RDP setup complete. Connect with mstsc /v:<server_ip>:80"
