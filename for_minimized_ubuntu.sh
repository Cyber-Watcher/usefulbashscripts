#!/bin/bash
set -euo pipefail

# --- Вспомогательные функции ---
yellow_echo() {
    echo -e "\033[1;33m$1\033[0m"
}

# Проверяем, что запущено через sudo
if [ -z "${SUDO_USER:-}" ]; then
    yellow_echo "Ошибка: скрипт нужно запускать через sudo."
    exit 1
fi

# Неинтерактивный режим
export DEBIAN_FRONTEND=noninteractive

# Определяем текущего пользователя и его домашнюю папку
ORIG_USER="$SUDO_USER"
ORIG_HOME=$(getent passwd "$ORIG_USER" | cut -d: -f6)

# Определяем версию Ubuntu
UBUNTU_VERSION=$(lsb_release -rs)

# --- Шаг 1 ---
yellow_echo "=== Шаг 1: обновление и установка базовых пакетов ==="
apt update && apt upgrade -y
apt install -y iputils-ping iputils-tracepath traceroute unzip zip mc nano tmux \
               cron bash-completion less ncdu fzf bmon tldr curl fish sysstat \
               flake8 yamllint shellcheck btop vim bat

# --- Шаг 2 ---
yellow_echo "=== Шаг 2: установка eza/exa и определение LS_TOOL ==="
if dpkg --compare-versions "$UBUNTU_VERSION" ge "24.04"; then
    apt install -y eza
    LS_TOOL="eza"
    yellow_echo "Будем использовать eza"
else
    apt install -y exa
    LS_TOOL="exa"
    yellow_echo "Будем использовать exa"
fi

# --- Шаг 3 ---
yellow_echo "=== Шаг 3: Настраиваем конфиги mc, tmux и .bashrc ==="
# Функция для применения общих правок .bashrc
patch_bashrc() {
    local TARGET_RC="$1"
    # Заменяем ls на eza/exa
    sed -i "s|ls -alF|${LS_TOOL} -lag|g"           "$TARGET_RC"
    sed -i "s|ls -A|ls -lA|g"                      "$TARGET_RC"
    sed -i "s|ls -CF|ls|g"                         "$TARGET_RC"
    # Добавляем bash-completion, если нет
    grep -q "source /etc/profile.d/bash_completion.sh" "$TARGET_RC" \
        || echo "source /etc/profile.d/bash_completion.sh" >> "$TARGET_RC"
}


setup_user_environment() {
    local home_dir="$1"
    local owner="$2"
    local is_root="${3:-false}"

    yellow_echo "=== Настройка окружения для: $owner ==="

    # 1. Патчим .bashrc
    patch_bashrc "$home_dir/.bashrc"

    # 2. Настройка tmux config
    curl -fsSL https://raw.githubusercontent.com/Cyber-Watcher/usefulbashscripts/refs/heads/main/tmux/base_server.config \
         -o "$home_dir/.tmux.conf"
    
    if [ "$is_root" = true ]; then
        chmod 600 "$home_dir/.tmux.conf"
    else
        chmod 660 "$home_dir/.tmux.conf"
    fi
    chown "$owner:$owner" "$home_dir/.tmux.conf"

    # 3. Настройка mc конфига
    mkdir -p "$home_dir/.config/mc"
    local mc_url="https://raw.githubusercontent.com/Cyber-Watcher/usefulbashscripts/main/mc/ini"
    [ "$is_root" = true ] && mc_url="https://raw.githubusercontent.com/Cyber-Watcher/usefulbashscripts/main/mcroot/ini"
    
    curl -fsSL "$mc_url" -o "$home_dir/.config/mc/ini"
    chown -R "$owner:$owner" "$home_dir/.config"
}

# Выполняем настройку для пользователя и root
setup_user_environment "$ORIG_HOME" "$ORIG_USER" false
setup_user_environment "/root" "root" true

# Автодополнение tmux (system-wide)
curl -fsSL https://raw.githubusercontent.com/imomaliev/tmux-bash-completion/master/completions/tmux \
     -o /usr/share/bash-completion/completions/tmux

# --- Шаг 4 ---
yellow_echo "=== Шаг 4: создание /etc/profile.d/force-color-prompt.sh ==="
cat > /etc/profile.d/force-color-prompt.sh << 'EOF'
# /etc/profile.d/force-color-prompt.sh
# Принудительно включаем цветной prompt в login-shell
force_color_prompt=yes
export force_color_prompt
EOF
chmod 644 /etc/profile.d/force-color-prompt.sh
yellow_echo "✅ /etc/profile.d/force-color-prompt.sh создан."

# --- Шаг 5 ---
yellow_echo "=== Шаг 5: Добавление настроек автодополнения в .bashrc ==="
add_bashrc_settings() {
    local bashrc_file="$1"
    local owner="$2"
    
    if ! grep -q "history-search-backward" "$bashrc_file"; then
        echo "" >> "$bashrc_file"
        echo "# Авто-дополнение при вводе" >> "$bashrc_file"
        echo 'bind '\''"\e[A": history-search-backward'\''   # Стрелка вверх' >> "$bashrc_file"
        echo 'bind '\''"\e[B": history-search-forward'\''    # Стрелка вниз' >> "$bashrc_file"
        echo 'bind '\''"\t": menu-complete'\''                # Tab для циклического выбора' >> "$bashrc_file"
        chown "$owner:$owner" "$bashrc_file"
        yellow_echo "  • Настройки автодополнения добавлены в $bashrc_file"
    else
        yellow_echo "  ℹ️ Настройки автодополнения уже присутствуют в $bashrc_file"
    fi
}

add_bashrc_settings "$ORIG_HOME/.bashrc" "$ORIG_USER"
add_bashrc_settings "/root/.bashrc" "root"

# --- Шаг 6 ---
yellow_echo "=== Шаг 6: Настройка fish_prompt ==="
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

    curl -fsSL https://raw.githubusercontent.com/Cyber-Watcher/usefulbashscripts/refs/heads/main/fish/fish_variables_for_server \
         -o "$fish_dir/fish_variables"
    
    chown -R "$owner:$owner" "$fish_dir"
    chmod 755 "$fish_dir" "$fish_dir/functions"
    chmod 644 "$prompt_file"
    yellow_echo "  • Fish prompt настроен для $owner"
}

install_fish_prompt "$ORIG_HOME" "$ORIG_USER"
install_fish_prompt "/root" "root"

# --- Шаг 7 ---
yellow_echo "=== Шаг 7: Добавление автоподключения к tmux при SSH ==="
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
        yellow_echo "  • Блок автоподключения добавлен в $bashrc_file"
    else
        yellow_echo "  ℹ️ Блок автоподключения уже есть в $bashrc_file"
    fi
}

add_tmux_autostart "$ORIG_HOME/.bashrc" "$ORIG_USER"
add_tmux_autostart "/root/.bashrc" "root"

# --- Шаг 8 ---
yellow_echo "=== Шаг 8: Настройка Vim (DARK SANDS) ==="
install_vim_standard() {
    local home_dir="$1"
    local owner="$2"
    local vimrc_file="$home_dir/.vimrc"
    local undo_dir="$home_dir/.vim/undo-dir"

    mkdir -p "$undo_dir"
    curl -fsSL https://raw.githubusercontent.com/Cyber-Watcher/usefulbashscripts/refs/heads/main/vim/vimrc_dark_sands \
         -o "$vimrc_file"

    chown -R "$owner:$owner" "$home_dir/.vim" "$vimrc_file"
    chmod 644 "$vimrc_file"
    yellow_echo "  • Vim DARK SANDS настроен для $owner"
}

install_vim_standard "$ORIG_HOME" "$ORIG_USER"
install_vim_standard "/root" "root"

# --- Шаг 9 ---
yellow_echo "=== Шаг 9: Настройка True Color в .bashrc ==="
patch_color_settings() {
    local bashrc_file="$1"
    local owner="$2"
    
    if ! grep -q "^export COLORTERM=truecolor" "$bashrc_file"; then
        # Используем ограничение диапазона 0,/esac/, чтобы добавить ТОЛЬКО после первого esac
        sed -i '0,/esac/s/esac/esac\n\nexport COLORTERM=truecolor\nexport TERM=xterm-256color/' "$bashrc_file"
        chown "$owner:$owner" "$bashrc_file"
        yellow_echo "  • True Color добавлен в начало $bashrc_file"
    else
        yellow_echo "  ℹ️ Настройки True Color уже активны в $bashrc_file"
    fi
}

patch_color_settings "$ORIG_HOME/.bashrc" "$ORIG_USER"
patch_color_settings "/root/.bashrc" "root"

# --- Шаг 10 ---
yellow_echo "=== Шаг 10: Настройка batcat (симлинк и конфиг) ==="

install_bat_settings() {
    local home_dir="$1"
    local owner="$2"
    local bin_dir="$home_dir/bin"
    local bat_config_dir="$home_dir/.config/bat"

    # Создаем папку ~/bin если её нет
    mkdir -p "$bin_dir"

    # Создаем симлинк bat -> /usr/bin/batcat
    # -f нужен, чтобы не вылетала ошибка, если линк уже есть
    ln -sf /usr/bin/batcat "$bin_dir/bat"

    # Тянем конфиг
    mkdir -p "$bat_config_dir"
    curl -fsSL https://raw.githubusercontent.com/Cyber-Watcher/usefulbashscripts/refs/heads/main/batcat/config \
         -o "$bat_config_dir/config"

    # Устанавливаем владельца на конфиг
    chown -R "$owner:$owner" "$bin_dir" "$home_dir/.config"
    
    yellow_echo "  • batсat (simlink bat) настроен для $owner"
}

# Применяем для пользователя и root
install_bat_settings "$ORIG_HOME" "$ORIG_USER"
install_bat_settings "/root" "root"

# --- Шаг 11 ---
yellow_echo "=== Шаг 11: Настройка цветов Bash Prompt (User@Host) ==="

append_custom_prompt() {
    local bashrc_file="$1"
    local owner="$2"
    
    # Обновленный промпт (Yellow \u, White @, Green \h, Blue \w, Newline before $)
    local prompt_string="PS1='\[\033[01;33m\]\u\[\033[00m\]@\[\033[01;32m\]\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\n\$ '"

    if ! grep -q "Обновленный промпт" "$bashrc_file"; then
        echo -e "\n# Обновленный промпт" >> "$bashrc_file"
        echo "$prompt_string" >> "$bashrc_file"
        chown "$owner:$owner" "$bashrc_file"
        yellow_echo "  • Промпт добавлен в конец $bashrc_file"
    else
        yellow_echo "  ℹ️ Промпт уже присутствует в $bashrc_file"
    fi
}

append_custom_prompt "$ORIG_HOME/.bashrc" "$ORIG_USER"
append_custom_prompt "/root/.bashrc" "root"

# --- Шаг 12 ---
yellow_echo "=== Шаг 12: Настройка yamllint (отключение document-start) ==="

configure_yamllint() {
    local home_dir="$1"
    local owner="$2"
    local config_dir="$home_dir/.config/yamllint"
    
    mkdir -p "$config_dir"
    
    cat > "$config_dir/config" <<EOF
# Глобальный конфиг yamllint (Dark Sands Edition)
extends: default

rules:
  document-start: disable  # Убираем требование '---' в начале файла
  line-length:
    max: 120               # Расширяем лимит строки до 120 символов
EOF

    chown -R "$owner:$owner" "$home_dir/.config"
    yellow_echo "  • Глобальный yamllint конфиг создан для $owner"
}

configure_yamllint "$ORIG_HOME" "$ORIG_USER"
configure_yamllint "/root" "root"

yellow_echo "\nГотово! Настройки применены."
yellow_echo "Перезапустите терминал или выполните 'source ~/.bashrc'."