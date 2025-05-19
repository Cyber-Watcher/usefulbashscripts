#!/bin/bash

for code in {0..255}; do
    # Устанавливаем цвет фона и белый текст
    printf "\e[48;5;%sm\e[38;5;255m%3d\e[0m " "$code" "$code"
    
    # Переход на новую строку после каждых 16 цветов
    if [ $(( (code + 1) % 16 )) -eq 0 ]; then
        echo
    fi
done