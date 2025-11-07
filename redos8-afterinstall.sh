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
dnf upgrade -y
dnf install -y tmux ncdu bmon traceroute htop eza wget unzip zip curl fish bash-completion sysstat || true

# 2) Патчим /etc/bashrc — бэкап + override PS1
BRC=/etc/bashrc
echo "=== Шаг 2: Backup и патчинг $BRC ==="
if [ -f "$BRC" ]; then
  cp -f "$BRC" "${BRC}.bak"
else
  echo "Внимание: $BRC не найден, создаём новый."
  touch "$BRC"
  cp -f "$BRC" "${BRC}.bak"
fi

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
  local HOME_DIR=$1
  local USER=$2
  local URL=$3

  # Удаляем старую конфигурацию и создаём директорию
  rm -rf "$HOME_DIR/.config/mc"
  mkdir -p "$HOME_DIR/.config/mc"

  # Скачиваем ini (если не удалось — предупреждение, но не фатально)
  if curl -fsSL "$URL" -o "$HOME_DIR/.config/mc/ini"; then
    chown -R "$USER:$USER" "$HOME_DIR/.config/mc"
    echo "  • mc.ini для $USER обновлён"
  else
    echo "  ! Не удалось скачать mc.ini из $URL для $USER (пропускаем)"
  fi
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
if curl -fsSL https://raw.githubusercontent.com/imomaliev/tmux-bash-completion/master/completions/tmux -o "$COMPDIR/tmux"; then
  echo "  • автодополнение tmux установлено"
else
  echo "  ! Не удалось установить автодополнение tmux"
fi

# 4.2) конфиг для каждого
install_tmux_conf() {
  local HOME_DIR=$1
  local USER=$2

  mkdir -p "$HOME_DIR"
  # скачиваем конфиг прямо в целевую домашнюю папку
  if curl -fsSL https://raw.githubusercontent.com/Cyber-Watcher/usefulbashscripts/refs/heads/main/tmux/base_server.config \
       -o "$HOME_DIR/.tmux.conf"; then
    chown "$USER:$USER" "$HOME_DIR/.tmux.conf"
    chmod 660 "$HOME_DIR/.tmux.conf"
    echo "  • .tmux.conf для $USER создан"
  else
    echo "  ! Не удалось скачать .tmux.conf для $USER"
  fi
}

install_tmux_conf "$ORIG_HOME" "$ORIG_USER"
install_tmux_conf "/root" "root"

# 5) Добавляем алиасы ls и eza в ~/.bashrc пользователей
echo "=== Шаг 5: Добавление алиасов ls и eza в bashrc ==="
add_aliases() {
  local RC_FILE=$1
  # Убедимся, что файл существует
  if [ ! -f "$RC_FILE" ]; then
    touch "$RC_FILE"
  fi

  # Добавляем только если ещё нет
  if ! grep -q "^alias ll=" "$RC_FILE"; then
    cat >> "$RC_FILE" << 'ALIASES'

# Пользовательские алиасы для ls и eza
alias ll='eza -lag' 2>/dev/null || alias ll='ls -la'
alias ls='ls -A --color=auto'
alias la='ls -la'
alias l='ls'
ALIASES
    echo "  • Алиасы добавлены в $RC_FILE"
  else
    echo "  ℹ️ Алиасы уже присутствуют в $RC_FILE"
  fi
}

add_aliases "$ORIG_HOME/.bashrc"
add_aliases "/root/.bashrc"

# 6) Добавляем настройки автодополнения в .bashrc
echo "=== Шаг 6: Добавление настроек автодополнения в bashrc ==="
add_bashrc_settings() {
  local bashrc_file="$1"
  local owner="$2"

  if [ ! -f "$bashrc_file" ]; then
    touch "$bashrc_file"
    chown "$owner:$owner" "$bashrc_file"
  fi

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

  mkdir -p "$fish_dir/functions"

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

  if curl -fsSL https://raw.githubusercontent.com/Cyber-Watcher/usefulbashscripts/refs/heads/main/fish/fish_variables_for_server -o "$fish_dir/fish_variables"; then
    echo "  • Цвета Fish скачаны для $owner"
  else
    echo "  ! Цвета Fish не скачаны для $owner"
  fi

  chown -R "$owner:$owner" "$fish_dir" || true
  chmod 755 "$fish_dir" "$fish_dir/functions" || true
  chmod 644 "$prompt_file" || true
  echo "  • Fish prompt настроен для $owner"
}

install_fish_prompt "$ORIG_HOME" "$ORIG_USER"
install_fish_prompt "/root" "root"

# --- Шаг 8: Автоподключение к tmux при SSH-сессии ---
echo "=== Шаг 8: Добавление автоподключения к tmux при SSH ==="
add_tmux_autostart() {
  local bashrc_file="$1"
  local owner="$2"
  local tmux_block='
if [[ -n "$SSH_CONNECTION" ]] && [[ -z "$TMUX" ]] && [[ $- == *i* ]]; then
    if tmux has-session -t itpro 2>/dev/null; then
        tmux attach -t itpro
    else
        tmux new -s itpro
    fi
fi
'
  if [ ! -f "$bashrc_file" ]; then
    touch "$bashrc_file"
    chown "$owner:$owner" "$bashrc_file"
  fi

  if ! grep -q "tmux attach -t itpro" "$bashrc_file"; then
    echo -e "\n# Автоподключение к tmux при SSH" >> "$bashrc_file"
    echo "$tmux_block" >> "$bashrc_file"
    chown "$owner:$owner" "$bashrc_file"
    echo "  • Блок автоподключения добавлен в $bashrc_file"
  else
    echo "  ℹ️ Блок автоподключения уже есть в $bashrc_file"
  fi
}

add_tmux_autostart "$ORIG_HOME/.bashrc" "$ORIG_USER"
add_tmux_autostart "/root/.bashrc" "root"

echo -e "\n🎉 Установка завершена!\n" \
     "• Новый prompt для bash и fish настроен\n" \
     "• Алиасы ll/la/l добавлены для '$ORIG_USER' и root\n" \
     "• Настройки автодополнения добавлены в .bashrc\n" \
     "• Конфиги mc и tmux сконфигурированы\n" \
     "• Fish с настроенным промптом установлен\n\n" \
     "Чтобы применить настройки bash, выполните:\n" \
     "    source /etc/bashrc && source ~/.bashrc\n" \
     "Для использования fish просто введите 'fish' в терминале."
