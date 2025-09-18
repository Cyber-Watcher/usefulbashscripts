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

# 1) Установка tmux, fish и утилит
echo "=== Шаг 1: Обновление системы и установка пакетов ==="
dnf makecache --refresh -y
dnf update -y
dnf install -y tmux ncdu bmon traceroute htop eza wget unzip zip curl fish bash-completion

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

# 6) Добавляем настройки автодополнения в .bashrc
echo "=== Шаг 6: Добавление настроек автодополнения в bashrc ==="
add_bashrc_settings() {
  local bashrc_file="$1"
  local owner="$2"
  
  # Проверяем, не добавлены ли уже настройки
  if ! grep -q "history-search-backward" "$bashrc_file"; then
    echo "" >> "$bashrc_file"
    echo "# Авто-дополнение при вводе (добавлено скриптом)" >> "$bashrc_file"
    echo 'bind '\''"\e[A": history-search-backward'\''   # Стрелка вверх' >> "$bashrc_file"
    echo 'bind '\''"\e[B": history-search-forward'\''    # Стрелка вниз' >> "$bashrc_file"
    echo 'bind '\''"\t": menu-complete'\''               # Tab для циклического выбора' >> "$bashrc_file"
    chown "$owner:$owner" "$bashrc_file"
    echo "  • Настройки автодополнения добавлены в $bashrc_file"
  else
    echo "  ℹ️ Настройки автодополнения уже присутствуют в $bashrc_file"
  fi
}

add_bashrc_settings "$ORIG_HOME/.bashrc" "$ORIG_USER"
add_bashrc_settings "/root/.bashrc" "root"

# 7) Установка fish_prompt для пользователя и root
echo "=== Шаг 7: Настройка fish_prompt ==="
install_fish_prompt() {
  local home_dir="$1"
  local owner="$2"
  local fish_dir="$home_dir/.config/fish"
  local prompt_file="$fish_dir/functions/fish_prompt.fish"
  
  # Создаем необходимые директории
  mkdir -p "$fish_dir/functions"
  
  # Создаем файл с промптом
  cat > "$prompt_file" <<'EOF'
function fish_prompt
    set -l last_status $status
    set -g fish_prompt_pwd_dir_length 0
    echo
    set_color yellow
    echo -n (whoami)
    set_color white
    echo -n "@"
    set_color green
    echo -n (hostname -s)
    set_color white
    echo -n ": "
    set_color blue
    echo -n (prompt_pwd)
    set_color normal
    echo
    if test $last_status -eq 0
        set_color --bold green
    else
        set_color --bold red
    end
    echo -n "▸"
    set_color normal
    echo -n " "
end
EOF
  
  # Устанавливаем владельца и права
  chown -R "$owner:$owner" "$fish_dir"
  chmod 755 "$fish_dir" "$fish_dir/functions"
  chmod 644 "$prompt_file"
  echo "  • Fish prompt настроен для $owner"
}

install_fish_prompt "$ORIG_HOME" "$ORIG_USER"
install_fish_prompt "/root" "root"

echo -e "\n🎉 Установка завершена!\n" \
     "• Новый prompt для bash и fish настроен\n" \
     "• Алиасы ll/la/l добавлены для '$ORIG_USER' и root\n" \
     "• Настройки автодополнения добавлены в .bashrc\n" \
     "• Конфиги mc и tmux сконфигурированы\n" \
     "• Fish с настроенным промптом установлен\n\n" \
     "Чтобы применить настройки bash, выполните:\n" \
     "    source /etc/bashrc && source ~/.bashrc\n" \
     "Для использования fish просто введите 'fish' в терминале."