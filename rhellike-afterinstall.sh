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
  "https://raw.githubusercontent.com/Cyber-Watcher/usefulbashscripts/main/mc/ini"
install_mc_ini "/root" "root" \
  "https://raw.githubusercontent.com/Cyber-Watcher/usefulbashscripts/main/mcroot/ini"

# --- 4) Установка bash-completion (если нужно) и tmux + автодополнение ---
echo "=== Шаг 4: проверка и установка bash-completion ==="
if ! rpm -q bash-completion &>/dev/null; then
  echo "bash-completion не найден — устанавливаем..."
  dnf install -y bash-completion
else
  echo "bash-completion уже установлен"
fi

# --- ДОБАВЛЕНО: Настройка автодополнения в .bashrc ---
echo "=== Шаг 4.1: настройка автодополнения в .bashrc ==="
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
    echo "✅ Настройки автодополнения добавлены в $bashrc_file"
  else
    echo "ℹ️ Настройки автодополнения уже присутствуют в $bashrc_file"
  fi
}

# Добавляем настройки для обычного пользователя и root
add_bashrc_settings "$ORIG_HOME/.bashrc" "$ORIG_USER"
add_bashrc_settings "/root/.bashrc" "root"

echo "=== Шаг 4.2: установка tmux ==="
if ! rpm -q tmux &>/dev/null; then
  dnf install -y tmux
else
  echo "tmux уже установлен"
fi

# 4.3) Автодополнение tmux (system-wide)
echo "=== Шаг 4.3: установка автодополнения для tmux ==="
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

# --- ДОБАВЛЕНО: Установка и настройка Fish ---
echo "=== Шаг 6: установка epel-release и fish ==="

# Сначала устанавливаем EPEL
if ! rpm -q epel-release &>/dev/null; then
  dnf install -y epel-release
  echo "✅ EPEL репозиторий добавлен"
  # Обновляем кэш после добавления репозитория
  dnf makecache --refresh
else
  echo "ℹ️ EPEL репозиторий уже установлен"
fi

# Теперь устанавливаем fish
if ! rpm -q fish &>/dev/null; then
  dnf install -y fish
  echo "✅ Fish установлен"
else
  echo "ℹ️ Fish уже установлен"
fi

# Функция для установки fish_prompt
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
  echo "✅ Fish prompt настроен для $owner"
}

echo "=== Шаг 6.1: настройка fish_prompt ==="
install_fish_prompt "$ORIG_HOME" "$ORIG_USER"
install_fish_prompt "/root" "root"

echo "=== Шаг 7: установка дополнительных утилит ==="
dnf install -y ncdu bmon traceroute htop zip unzip wget

echo -e "\n🎉 Готово! Пользователь '$ORIG_USER' и root получили:\n" \
     "- цветной prompt [user@host] /path\n" \
     "- настройки автодополнения в .bashrc\n" \
     "- mc с конфигами\n" \
     "- bash-completion, tmux и его автодополнение + конфиги\n" \
     "- fish с настроенным промптом\n" \
     "- дополнительные утилиты (ncdu, bmon и др.)\n\n" \
     "Откройте новый login shell или выполните 'source /etc/profile.d/custom-prompt.sh' и 'source ~/.bashrc'."