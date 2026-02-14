#!/bin/bash
set -euo pipefail

# Проверяем, что запущено через sudo
if [ -z "${SUDO_USER:-}" ]; then
  echo "Ошибка: скрипт нужно запускать через sudo."
  exit 1
fi

# Неинтерактивный режим
export DEBIAN_FRONTEND=noninteractive

# Определяем текущего пользователя и его домашнюю папку
ORIG_USER="$SUDO_USER"
ORIG_HOME=$(getent passwd "$ORIG_USER" | cut -d: -f6)

# Определяем версию Ubuntu
UBUNTU_VERSION=$(lsb_release -rs)

echo "=== Шаг 1: обновление и установка базовых пакетов ==="
apt update && apt upgrade -y
apt install -y iputils-ping iputils-tracepath traceroute unzip zip mc nano tmux \
               cron bash-completion less ncdu fzf bmon tldr curl fish sysstat \
               flake8 yamllint shellcheck btop vim bat

echo "=== Шаг 2: установка eza/exa и определение LS_TOOL ==="
if dpkg --compare-versions "$UBUNTU_VERSION" ge "24.04"; then
    apt install -y eza
    LS_TOOL="eza"
    echo "Будем использовать eza"
else
    apt install -y exa
    LS_TOOL="exa"
    echo "Будем использовать exa"
fi

# Функция для применения общих правок .bashrc
patch_bashrc() {
  local TARGET_RC="$1"
  # Заменяем ls на eza/exa
  sed -i "s|ls -alF|${LS_TOOL} -lag|g"           "$TARGET_RC"
  sed -i "s|ls -A|ls -lA|g"           "$TARGET_RC"
  sed -i "s|ls -CF|ls|g"           "$TARGET_RC"
  # Переносим '$' на новую строку
  sed -i 's/\\\$/\\n\\$/' "$TARGET_RC"
  # Добавляем bash-completion, если нет
  grep -q "source /etc/profile.d/bash_completion.sh" "$TARGET_RC" \
    || echo "source /etc/profile.d/bash_completion.sh" >> "$TARGET_RC"
}

# --- Настройка для оригинального пользователя ---
echo "=== Шаг 3: настройка для пользователя $ORIG_USER ==="
patch_bashrc "$ORIG_HOME/.bashrc"

# tmux config для пользователя
curl -fsSL https://raw.githubusercontent.com/Cyber-Watcher/usefulbashscripts/refs/heads/main/tmux/base_server.config \
     -o "$ORIG_HOME/.tmux.conf"
chown "$ORIG_USER:$ORIG_USER" "$ORIG_HOME/.tmux.conf"
chmod 660 "$ORIG_HOME/.tmux.conf"

# автодополнение tmux (system-wide)
curl -fsSL https://raw.githubusercontent.com/imomaliev/tmux-bash-completion/master/completions/tmux \
     -o /usr/share/bash-completion/completions/tmux

# mc конфиг для пользователя
mkdir -p "$ORIG_HOME/.config/mc"
curl -fsSL https://raw.githubusercontent.com/Cyber-Watcher/usefulbashscripts/main/mc/ini \
     -o "$ORIG_HOME/.config/mc/ini"
chown -R "$ORIG_USER:$ORIG_USER" "$ORIG_HOME/.config"

# --- Настройка для root ---
echo "=== Шаг 4: настройка для пользователя root ==="
patch_bashrc "/root/.bashrc"

# tmux confog для root
cp "$ORIG_HOME/.tmux.conf" /root/.tmux.conf
chmod 600 /root/.tmux.conf 

# mc конфиг для root
mkdir -p /root/.config/mc
curl -fsSL https://raw.githubusercontent.com/Cyber-Watcher/usefulbashscripts/main/mcroot/ini \
     -o /root/.config/mc/ini
chown -R root:root /root/.config

# --- Шаг 5: Принудительное включение цветного prompt в login-shell ---
echo "=== Шаг 5: создание /etc/profile.d/force-color-prompt.sh ==="
cat > /etc/profile.d/force-color-prompt.sh << 'EOF'
# /etc/profile.d/force-color-prompt.sh
# Принудительно включаем цветной prompt в login-shell
force_color_prompt=yes
export force_color_prompt
EOF
chmod 644 /etc/profile.d/force-color-prompt.sh
echo "✅ /etc/profile.d/force-color-prompt.sh создан."

# --- Шаг 6: Добавление настроек автодополнения в .bashrc ---
echo "=== Шаг 6: Добавление настроек автодополнения в .bashrc ==="
add_bashrc_settings() {
  local bashrc_file="$1"
  local owner="$2"
  
  # Проверяем, не добавлены ли уже настройки
  if ! grep -q "history-search-backward" "$bashrc_file"; then
    echo "" >> "$bashrc_file"
    echo "# Авто-дополнение при вводе" >> "$bashrc_file"
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

# --- Шаг 7: Настройка fish_prompt ---
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

  # Устанавливаем цвета для fish
  curl -fsSL https://raw.githubusercontent.com/Cyber-Watcher/usefulbashscripts/refs/heads/main/fish/fish_variables_for_server \
     -o "$fish_dir/fish_variables"

  echo "  Цвета Fish настроены для $owner"  
  
  # Устанавливаем владельца и права
  chown -R "$owner:$owner" "$fish_dir"
  chmod 755 "$fish_dir" "$fish_dir/functions"
  chmod 644 "$prompt_file"
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

# --- Шаг 9: Установка Vim "Золотой стандарт v1.19" ---
echo "=== Шаг 9: Настройка Vim (DARK SANDS) ==="

install_vim_standard() {
  local home_dir="$1"
  local owner="$2"
  local vimrc_file="$home_dir/.vimrc"
  local undo_dir="$home_dir/.vim/undo-dir"

  # 1. Создаем структуру каталогов заранее, чтобы Vim не выдавал уведомлений
  mkdir -p "$undo_dir"

  # 2. Тянем конфиг из репозитория (как и tmux)
  # Мы переименовываем vimrc_dark_sands в .vimrc при сохранении
  curl -fsSL https://raw.githubusercontent.com/Cyber-Watcher/usefulbashscripts/refs/heads/main/vim/vimrc_dark_sands \
       -o "$vimrc_file"

  # 3. Устанавливаем права и владельца
  chown -R "$owner:$owner" "$home_dir/.vim" "$vimrc_file"
  chmod 644 "$vimrc_file"
  
  echo "  • Vim DARK SANDS подтянут и настроен для $owner"
}

# Применяем для основного пользователя и root
install_vim_standard "$ORIG_HOME" "$ORIG_USER"
install_vim_standard "/root" "root"

# --- Шаг 10: Настройка цветопередачи терминала (БЕЗ АРТЕФАКТОВ) ---
echo "=== Шаг 10: Настройка True Color в .bashrc ==="

patch_color_settings() {
  local bashrc_file="$1"
  local owner="$2"
  
  # Оборачиваем в проверку на интерактивность [[ $- == *i* ]]
  # Это уберет мусор (артефакты) при логине
  local color_block='
# Включение True Color только для интерактивных сессий
if [[ $- == *i* ]]; then
    export COLORTERM=truecolor
    export TERM=xterm-256color
fi
'

  if ! grep -q "COLORTERM=truecolor" "$bashrc_file"; then
    if grep -q "set a fancy prompt" "$bashrc_file"; then
      # Используем временный файл для чистой вставки блока
      sed -i "/# set a fancy prompt/i $color_block" "$bashrc_file"
      echo "  • True Color настройки добавлены в $bashrc_file"
    else
      echo -e "$color_block" >> "$bashrc_file"
      echo "  • Маркер не найден, настройки добавлены в конец $bashrc_file"
    fi
    chown "$owner:$owner" "$bashrc_file"
  else
    echo "  ℹ️ Настройки True Color уже присутствуют в $bashrc_file"
  fi
}

patch_color_settings "$ORIG_HOME/.bashrc" "$ORIG_USER"
patch_color_settings "/root/.bashrc" "root"

echo -e "\nГотово! Настройки применены для пользователя '$ORIG_USER' и для 'root'."
echo    "Перезапустите терминал или выполните 'source ~/.bashrc'."
echo    "Для использования fish просто введите 'fish' в терминале."
