#!/bin/bash
set -euo pipefail

# --- Проверка запуска через sudo/root ---
if [ "$(id -u)" -ne 0 ]; then
  echo "Ошибка: запускайте скрипт от root (или через sudo)."
  exit 1
fi

ORIG_USER=${SUDO_USER:-}
if [ -z "$ORIG_USER" ]; then
  echo "Ошибка: не удалось определить пользователя, запустившего sudo."
  exit 1
fi
ORIG_HOME=$(getent passwd "$ORIG_USER" | cut -d: -f6)

# --- 1) Устанавливаем цветной prompt через /etc/profile.d ---
echo "=== Шаг 1: Устанавливаем цветной prompt ==="
cat > /etc/profile.d/custom-prompt.sh << 'EOF'
# Цветной prompt: [user@host] /full/path\n# или $
YELLOW="\[\e[0;33m\]"   # жёлтый (user)
WHITE="\[\e[0;37m\]"    # белый (brackets, @, space)
GREEN="\[\e[0;32m\]"    # зелёный (host)
CYAN="\[\e[0;36m\]"     # голубой (path)
ORANGE="\[\e[38;5;202m\]"   # оранжевый (root #)
RESET="\[\e[0m\]"

USERHOST="${WHITE}[${YELLOW}\u${WHITE}@${GREEN}\h${WHITE}]"

if [ "$EUID" -eq 0 ]; then
  export PS1="${USERHOST}${CYAN} \w${RESET}\n${ORANGE}# ${RESET}"
else
  export PS1="${USERHOST}${CYAN} \w${RESET}\n${WHITE}\$ ${RESET}"
fi
EOF
chmod 644 /etc/profile.d/custom-prompt.sh
echo "✅ Цветной prompt установлен (формат [user@host] /path)."

# --- 2) Обновление ОС и установка Midnight Commander (mc) ---
echo "=== Шаг 2: Обновление ОС и установка mc ==="
dnf makecache --refresh -y
dnf update -y
if ! rpm -q mc &>/dev/null; then
  dnf install -y mc
else
  echo "mc уже установлен"
fi

# --- 3) Перезапись конфигов mc для пользователя и root ---
echo "=== Шаг 3.1: настройка конфигов mc для root ==="
install_mc_ini() {
  local HOME_DIR=$1 OWNER=$2 URL=$3
  rm -rf "$HOME_DIR/.config/mc"
  mkdir -p "$HOME_DIR/.config/mc"
  curl -fsSL "$URL" -o "$HOME_DIR/.config/mc/ini"
  chown -R "$OWNER:$OWNER" "$HOME_DIR/.config/mc"
  echo "✅ Конфиг mc для $OWNER"
}

echo "=== Шаг 3.2: настройка конфигов mc для '$ORIG_USER' ==="
install_mc_ini "$ORIG_HOME" "$ORIG_USER" \
  "https://gitlab.com/cyber_watcher/usefulbashscripts/-/raw/main/mc/ini"
install_mc_ini "/root" "root" \
  "https://gitlab.com/cyber_watcher/usefulbashscripts/-/raw/main/mcroot/ini"

# --- 4) Установка bash-completion (если нужно) и tmux + автодополнение ---
echo "=== Шаг 4: проверка и установка bash-completion ==="
if ! rpm -q bash-completion &>/dev/null; then
  echo "bash-completion не найден — устанавливаем..."
  dnf install -y bash-completion
else
  echo "bash-completion уже установлен"
fi

echo "=== Шаг 4.1: установка tmux ==="
if ! rpm -q tmux &>/dev/null; then
  dnf install -y tmux
else
  echo "tmux уже установлен"
fi

# 4.2) Автодополнение tmux (system-wide)
echo "=== Шаг 4.2: установка автодополнения для tmux ==="
COMPDIR="/usr/share/bash-completion/completions"
mkdir -p "$COMPDIR"
curl -fsSL https://raw.githubusercontent.com/imomaliev/tmux-bash-completion/master/completions/tmux \
     -o "$COMPDIR/tmux"
echo "✅ Автодополнение для tmux установлено"

# --- 5) Конфиг tmux для пользователя и root ---
install_tmux_conf() {
  local HOME_DIR=$1 OWNER=$2
  cat > "$HOME_DIR/.tmux.conf" <<'EOF'
set -g default-terminal "screen-256color"
set -g mouse on
EOF
  chown "$OWNER:$OWNER" "$HOME_DIR/.tmux.conf"
  chmod 660 "$HOME_DIR/.tmux.conf"
  echo "✅ Конфиг tmux для $OWNER"
}

echo "=== Шаг 5: настройка tmux ==="
install_tmux_conf "$ORIG_HOME" "$ORIG_USER"
install_tmux_conf "/root" "root"

echo "=== Шаг 6: устасновка дополнительных утилит ==="
dnf install -y epel-release
dnf install -y ncdu bmon traceroute htop zip unzip wget

echo -e "\n🎉 Готово! Пользователь '$ORIG_USER' и root получили:\n" \
     "- цветной prompt [user@host] /path\n" \
     "- mc с конфигами\n" \
     "- bash-completion, tmux и его автодополнение + конфиги\n\n" \
     "Откройте новый login shell или выполните 'source /etc/profile.d/custom-prompt.sh' и 'source ~/.bashrc'."

