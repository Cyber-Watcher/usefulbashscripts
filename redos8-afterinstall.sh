#!/bin/bash
set -euo pipefail

# =========================================
# Скрипт: setup-redos8.sh
# Для: RedOS 8 
# =========================================

# 0) Проверка запуска под root/sudo
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

# 1) Установка tmux и утилит (mc и bash-completion уже есть)
echo "=== Шаг 1: Обновление системы и установка tmux и утилит ==="
dnf makecache --refresh -y
dnf update -y
dnf install -y tmux ncdu bmon traceroute htop eza wget unzip zip curl

# 2) Патчим /etc/bashrc — бэкап + override PS1
BRC=/etc/bashrc
echo "=== Шаг 2: Backup и патчинг $BRC ==="
cp "$BRC" "${BRC}.bak"

cat >> "$BRC" << 'EOF'

# --- Переопределение PS1: полный путь + цветные [user@host] и разный знак ---
_override_prompt() {
  local YELLOW="\[\e[0;33m\]"
  local WHITE="\[\e[0;37m\]"
  local GREEN="\[\e[0;32m\]"
  local CYAN="\[\e[0;36m\]"
  local ORANGE="\[\e[38;5;202m\]"
  local RESET="\[\e[0m\]"

  local PREFIX="${WHITE}[${YELLOW}\u${WHITE}@${GREEN}\h${WHITE}]"
  if [ "$EUID" -eq 0 ]; then
    PS1="${PREFIX}${CYAN} \w${RESET}\n${ORANGE}# ${RESET}"
  else
    PS1="${PREFIX}${CYAN} \w${RESET}\n${WHITE}\$ ${RESET}"
  fi
}
if [ -n "$PS1" ]; then _override_prompt; fi
unset -f _override_prompt

EOF

echo "Бэкап сохранён как ${BRC}.bak"

# 3) Обновление конфигов mc
echo "=== Шаг 3: Обновление конфигов mc ==="
install_mc_ini() {
  local HOME_DIR=$1 USER=$2 URL=$3
  rm -rf "$HOME_DIR/.config/mc"
  mkdir -p "$HOME_DIR/.config/mc"
  curl -fsSL "$URL" -o "$HOME_DIR/.config/mc/ini"
  chown -R "$USER:$USER" "$HOME_DIR/.config/mc"
  echo "  • mc.ini для $USER обновлён"
}
install_mc_ini "$ORIG_HOME" "$ORIG_USER" \
  "https://raw.githubusercontent.com/Cyber-Watcher/usefulbashscripts/main/mc/ini"
install_mc_ini "/root" "root" \
  "https://raw.githubusercontent.com/Cyber-Watcher/usefulbashscripts/main/mcroot/ini"

# 4) Настройка tmux + автодополнение
echo "=== Шаг 4: Настройка tmux ==="
# 4.1) автодополнение
COMPDIR=/usr/share/bash-completion/completions
mkdir -p "$COMPDIR"
curl -fsSL https://raw.githubusercontent.com/imomaliev/tmux-bash-completion/master/completions/tmux \
     -o "$COMPDIR/tmux"
echo "  • автодополнение tmux установлено"

# 4.2) конфиг для каждого
install_tmux_conf() {
  local HOME_DIR=$1 USER=$2
  cat > "$HOME_DIR/.tmux.conf" << 'EOF'
set -g default-terminal "screen-256color"
set -g mouse on
EOF
  chown "$USER:$USER" "$HOME_DIR/.tmux.conf"
  chmod 660 "$HOME_DIR/.tmux.conf"
  echo "  • .tmux.conf для $USER создан"
}
install_tmux_conf "$ORIG_HOME" "$ORIG_USER"
install_tmux_conf "/root" "root"

# 5) Добавляем алиасы ls и eza в ~/.bashrc пользователей
echo "=== Шаг 5: Добавление алиасов ls и eza в bashrc ==="
add_aliases() {
  local RC_FILE=$1
  grep -q "^alias ll=" "$RC_FILE" || cat >> "$RC_FILE" << 'ALIASES'

# Пользовательские алиасы для ls и eza
alias ll='eza -lag'
alias ls='ls -A --color=auto'
alias la='ls -la'
alias l='ls'
ALIASES
  echo "  • Алиасы добавлены в $RC_FILE"
}

add_aliases "$ORIG_HOME/.bashrc"
add_aliases "/root/.bashrc"

echo -e "\n🎉 Установка завершена!\n" \
     "• Новый prompt заработает при следующем интерактивном shell.\n" \
     "• Алиасы ll/la/l добавлены для '$ORIG_USER' и root.\n" \
     "• Конфиги mc и tmux сконфигурированы.\n\n" \
     "Чтобы применить сейчас, выполните:\n" \
     "    source /etc/bashrc && source ~/.bashrc\n" \
     "или просто откройте новый терминал/SSH-сессию."