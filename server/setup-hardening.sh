#!/usr/bin/env bash
# ================================================
# Setup-Skript: UFW + SSH-Härtung + Fail2Ban + SSH-Key-Import
# Autor: Jannik Fissahn
# ================================================
set -euo pipefail

# === 1) Variablen anpassen ===
SSH_PORT=1928 # Port für SSH (Standard: 22, hier geändert auf 1928)
# Trage hier zusätzliche Ports ein, z.B. 80 443
EXTRA_PORTS=(80 443)

# Dein Public Key für Root (ganze Zeile, z.B. "ssh-rsa AAAAB3… user@host")
SSH_PUB_KEY="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCTYfra/lvcx3QNdaI6fB4J+9xtIxTXK3BJziZiQeubCPYi9+HkSQoSuCQwV+kjn+47fNLZU5vh4MViwdOpxUMXek+cueaS6QrkI6ok4OuhENj7QQTolpNBFchbdIX8YYXR6laLQtfhYmLhLD1FVQ0i4gew8PWkf7COsr3xm3mewGdW7Olh7uItpDygdO71BvoM12lY4GuP0TELZenwOsecGrkPz9tg86qleInf6maCSPNdrNRMPLpx4K1J33ZmSK9AgetQ1A+5kN1JCsfW9kNA85Se3P/nnc0X2vI+cUp3XYeBpjUFOjHhaQcjsa3O5iwsXk5mnTSvrxnUyImAaLQJ rsa-key-20250620"

# === 2) Root-Check ===
if [[ $EUID -ne 0 ]]; then
  echo "Dieses Skript muss als root ausgeführt werden." >&2
  exit 1
fi

# === 3) System updaten & Pakete installieren ===
echo ">>> System aktualisieren und Basispakete installieren…"
apt update
DEBIAN_FRONTEND=noninteractive apt install -y ufw fail2ban openssh-server

# === 4) SSH-Key für Root hinzufügen ===
echo ">>> SSH-Key für Root einrichten…"
mkdir -p /root/.ssh
chmod 700 /root/.ssh
# Verhindern, dass derselbe Key mehrfach angehängt wird
grep -qxF "$SSH_PUB_KEY" /root/.ssh/authorized_keys 2>/dev/null \
  || echo "$SSH_PUB_KEY" >> /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
echo "SSH-Key installiert."

# === 5) UFW konfigurieren ===
echo ">>> UFW zurücksetzen und konfigurieren…"
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow "${SSH_PORT}/tcp"
for port in "${EXTRA_PORTS[@]}"; do
  ufw allow "${port}/tcp"
done
ufw --force enable
echo "UFW aktiviert."

# === 6) OpenSSH hart machen ===
SSHD_CONFIG=/etc/ssh/sshd_config
BACKUP="/etc/ssh/sshd_config.bak.$(date +%Y%m%d%H%M%S)"
echo ">>> Backup der SSH-Config: ${BACKUP}"
cp "$SSHD_CONFIG" "$BACKUP"

echo ">>> SSHD-Konfiguration anpassen…"
sed -i -E "
  s/^#?Port .*/Port ${SSH_PORT}/;
  s|^#?PermitRootLogin .*|PermitRootLogin prohibit-password|;
  s/^#?PasswordAuthentication .*/PasswordAuthentication no/;
  s/^#?PubkeyAuthentication .*/PubkeyAuthentication yes/;
  s/^#?UsePAM .*/UsePAM no/;
" "$SSHD_CONFIG"

systemctl enable ssh
systemctl restart ssh
echo "SSH gehärtet, Port ${SSH_PORT}, Root-Key-Login aktiviert."

# === 7) Fail2Ban einrichten ===
echo ">>> Fail2Ban konfigurieren…"
cat > /etc/fail2ban/jail.d/sshd.local <<EOF
[DEFAULT]
bantime  = 1d
findtime = 10m
maxretry = 3

[sshd]
enabled = true
port    = ${SSH_PORT}
EOF

systemctl enable fail2ban
systemctl restart fail2ban
echo "Fail2Ban läuft im aggressiven Modus."

# === 8) Zusammenfassung ===
cat <<EOF

=== Setup abgeschlossen ===
• UFW: aktiv, Default incoming=deny, offene Ports: ${SSH_PORT}, ${EXTRA_PORTS[*]}
• SSH: Port=${SSH_PORT}, Key-Only-Login für Root (PermitRootLogin prohibit-password), Passwort-Auth aus
• SSH-Key für Root installiert (authorized_keys)
• Fail2Ban: aktiv (maxretry=3, bantime=1d)

Melde dich jetzt per SSH mit deinem Key auf Port ${SSH_PORT} an:
  ssh -i /pfad/zu/deinem/key -p ${SSH_PORT} root@<server-ip>

EOF
