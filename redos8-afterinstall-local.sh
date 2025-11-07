#!/bin/bash
set -euo pipefail

# =========================================
# Скрипт: redos8-afterinstall-local.sh
# Для: RedOS 8 (автоконфигурация без GitHub)
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
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
install_mc_ini_local() {
  local HOME_DIR=$1
  local USER=$2
  local SRC_PATH=$3

  rm -rf "$HOME_DIR/.config/mc"
  mkdir -p "$HOME_DIR/.config/mc"

  if [ -f "$SRC_PATH/ini" ]; then
    cp -f "$SRC_PATH/ini" "$HOME_DIR/.config/mc/ini"
    chown -R "$USER:$USER" "$HOME_DIR/.config/mc"
    echo "  • mc.ini для $USER установлен из $SRC_PATH"
  else
    echo "  ! Не найден файл $SRC_PATH/ini (пропускаем)"
  fi
}

install_mc_ini_local "$ORIG_HOME" "$ORIG_USER" "$BASE_DIR/mc"
install_mc_ini_local "/root" "root" "$BASE_DIR/mcroot"

# 4) Настройка tmux + автодополнение
echo "=== Шаг 4: Настройка tmux ==="
COMPDIR=/usr/share/bash-completion/completions
mkdir -p "$COMPDIR"
if [ -f "$BASE_DIR/tmux/tmux" ]; then
  cp -f "$BASE_DIR/tmux/tmux" "$COMPDIR/tmux"
  echo "  • автодополнение tmux установлено локально"
else
  echo "  ! Автодополнение tmux не найдено в $BASE_DIR/tmux (пропускаем)"
fi

install_tmux_conf_local() {
  local HOME_DIR=$1
  local USER=$2

  mkdir -p "$HOME_DIR"
  if [ -f "$BASE_DIR/tmux/base_server.config" ]; then
    cp -f "$BASE_DIR/tmux/base_server.config" "$HOME_DIR/.tmux.conf"
    chown "$USER:$USER" "$HOME_DIR/.tmux.conf"
    chmod 660 "$HOME_DIR/.tmux.conf"
    echo "  • .tmux.conf для $USER установлен"
  else
    echo "  ! Не найден $BASE_DIR/tmux/base_server.config"
  fi
}

install_tmux_conf_local "$ORIG_HOME" "$ORIG_USER"
install_tmux_conf_local "/root" "root"

# 5) Алиасы
echo "=== Шаг 5: Добавление алиасов ls и eza в bashrc ==="
add_aliases() {
  local RC_FILE=$1
  if [ ! -f "$RC_FILE" ]; then
    touch "$RC_FILE"
  fi
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

# 6) Настройки автодополнения
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

# 7) Fish prompt
echo "=== Шаг 7: Настройка fish_prompt ==="
install_fish_prompt_local() {
  local home_dir="$1"
  local owner="$2"
  local fish_dir="$home_dir/.config/fish"
  local prompt_file="$fish_dir/functions/fish_prompt.fish"

  mkdir -p "$fish_dir/functions"

  # Файл fish_prompt берём локально
  if [ -f "$BASE_DIR/fish/fish_prompt.fish" ]; then
    cp -f "$BASE_DIR/fish/fish_prompt.fish" "$prompt_file"
    echo "  • Fish prompt скопирован для $owner"
  else
    echo "  ! Не найден $BASE_DIR/fish/fish_prompt.fish"
  fi

  # Цветовые настройки
  if [ -f "$BASE_DIR/fish/fish_variables_for_server" ]; then
    cp -f "$BASE_DIR/fish/fish_variables_for_server" "$fish_dir/fish_variables"
    echo "  • Цвета Fish скопированы для $owner"
  else
    echo "  ! Не найден $BASE_DIR/fish/fish_variables_for_server"
  fi

  chown -R "$owner:$owner" "$fish_dir" || true
  chmod 755 "$fish_dir" "$fish_dir/functions" || true
  chmod 644 "$prompt_file" || true
}

install_fish_prompt_local "$ORIG_HOME" "$ORIG_USER"
install_fish_prompt_local "/root" "root"

# 8) Автоподключение tmux
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

echo -e "\n🎉 Установка завершена (локальный режим)!\n" \
     "• Конфиги mc, tmux, fish взяты из локальных директорий\n" \
     "• Новый prompt для bash и fish настроен\n" \
     "• Алиасы и автодополнение добавлены\n\n" \
     "Чтобы применить настройки bash, выполните:\n" \
     "    source /etc/bashrc && source ~/.bashrc\n" \
     "Для использования fish просто введите 'fish' в терминале."
