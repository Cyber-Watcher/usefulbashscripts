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
               cron bash-completion less ncdu fzf bmon tldr curl

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
  #sed -i "s|ls --color=auto|${LS_TOOL}|g"        "$TARGET_RC"
  sed -i "s|ls -alF|${LS_TOOL} -lag|g"           "$TARGET_RC"
  sed -i "s|ls -A|ls -lA|g"           "$TARGET_RC"
  sed -i "s|ls -CF|${LS_TOOL}|g"           "$TARGET_RC"
  # Переносим '$' на новую строку
  sed -i 's/\\\$/\\n\\$/' "$TARGET_RC"
  # Добавляем bash-completion, если нет
  grep -q "source /etc/profile.d/bash_completion.sh" "$TARGET_RC" \
    || echo "source /etc/profile.d/bash_completion.sh" >> "$TARGET_RC"
}

# --- Настройка для оригинального пользователя ---
echo "=== Шаг 3: настройка для пользователя $ORIG_USER ==="
patch_bashrc "$ORIG_HOME/.bashrc"

# tmux конфиг
cat > "$ORIG_HOME/.tmux.conf" <<'EOF'
set -g default-terminal "screen-256color"
set -g mouse on
EOF
chown "$ORIG_USER:$ORIG_USER" "$ORIG_HOME/.tmux.conf"
chmod 660 "$ORIG_HOME/.tmux.conf"

# автодополнение tmux (system-wide)
curl -fsSL https://raw.githubusercontent.com/imomaliev/tmux-bash-completion/master/completions/tmux \
     -o /usr/share/bash-completion/completions/tmux

# mc конфиг для пользователя
mkdir -p "$ORIG_HOME/.config/mc"
curl -fsSL https://gitlab.com/cyber_watcher/usefulbashscripts/-/raw/main/mc/ini \
     -o "$ORIG_HOME/.config/mc/ini"
chown -R "$ORIG_USER:$ORIG_USER" "$ORIG_HOME/.config"

# --- Настройка для root ---
echo "=== Шаг 4: настройка для пользователя root ==="
patch_bashrc "/root/.bashrc"

# tmux конфиг для root
cat > /root/.tmux.conf <<'EOF'
set -g default-terminal "screen-256color"
set -g mouse on
EOF
chmod 600 /root/.tmux.conf

# mc конфиг для root
mkdir -p /root/.config/mc
curl -fsSL https://gitlab.com/cyber_watcher/usefulbashscripts/-/raw/main/mcroot/ini \
     -o /root/.config/mc/ini
chown -R root:root /root/.config

echo -e "\nГотово! Настройки применены для пользователя '$ORIG_USER' и для 'root'."
echo    "Перезапустите терминал или выполните 'source ~/.bashrc'."
