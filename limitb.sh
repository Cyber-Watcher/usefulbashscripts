#!/bin/bash

# ./setup_cgroup_with_memory_check.sh 1.5 -v

# Проверка наличия аргумента с размером памяти
if [ -z "$1" ]; then
    echo "Использование: $0 <размер_памяти_в_ГБ> [-v]"
    exit 1
fi

MEMORY_LIMIT_GB=$1
MEMORY_LIMIT_BYTES=$(echo "$MEMORY_LIMIT_GB * 1024 * 1024 * 1024" | bc)

# Проверка наличия флага verbose
VERBOSE=false
if [ "$2" == "-v" ]; then
    VERBOSE=true
fi

# Название группы cgroup
GROUP_NAME="browser_group"
CGROUP_PATH="/sys/fs/cgroup/$GROUP_NAME"

# Получение пользователя, запустившего скрипт с sudo
USER=${SUDO_USER:-$(whoami)}

# Функция для создания cgroup и установки лимита
create_and_set_cgroup() {
    if [ ! -d "$CGROUP_PATH" ]; then
        echo "Создание cgroup $GROUP_NAME..."
        sudo mkdir -p "$CGROUP_PATH"
    fi

    # Установка лимита памяти
    current_limit=$(cat "$CGROUP_PATH/memory.max" 2>/dev/null)
    if [ "$current_limit" != "$MEMORY_LIMIT_BYTES" ]; then
        echo $MEMORY_LIMIT_BYTES | sudo tee "$CGROUP_PATH/memory.max" > /dev/null
    fi
}

# Функция для добавления PID в cgroup
add_pids_to_cgroup() {
    local pids=$1
    if [ -n "$pids" ]; then
        for pid in $pids; do
            echo $pid | sudo tee -a "$CGROUP_PATH/cgroup.procs" > /dev/null
        done
    fi
}

# Функция для отображения суммарного потребления памяти
display_memory_usage() {
    local browser_name=$1
    local pid_command=$2

    # Получение всех PID процессов браузера
    pids=$(eval $pid_command 2>/dev/null)
    if [ -n "$pids" ]; then
        # Суммирование использования памяти
        total_rss=0
        for pid in $pids; do
            rss=$(ps -o rss= -p $pid 2>/dev/null)
            total_rss=$((total_rss + rss))
        done

        # Преобразование RSS из килобайт в гигабайты
        total_gb=$(echo "scale=2; $total_rss / 1024 / 1024" | bc)

        echo "$browser_name:"
        echo "Суммарное использование памяти: $total_gb GB"
        if $VERBOSE; then
            echo "PID процессов $browser_name: $pids"
        fi
        echo
    else
        echo "$browser_name не запущен."
    fi
}

# Создание cgroup и установка лимита
create_and_set_cgroup

# Список браузеров и команд для получения PID
declare -A browsers=(
    [firefox]="pgrep -u $USER -f firefox"
    [opera]="pgrep -u $USER -f opera"
    [chrome]="pgrep -u $USER -f chrome"
    [msedge]="pgrep -u $USER -f msedge"
)

# Применение ограничений для каждого браузера и отображение потребления памяти
for browser in "${!browsers[@]}"; do
    echo "Проверка и применение ограничений для $browser..."
    pid_command="${browsers[$browser]}"
    pids=$(eval $pid_command 2>/dev/null)

    # Добавление всех PID в cgroup
    if [ -n "$pids" ]; then
        add_pids_to_cgroup "$pids"
    fi

    # Отображение суммарного использования памяти
    display_memory_usage "$browser" "$pid_command"
done

echo "Завершено."
