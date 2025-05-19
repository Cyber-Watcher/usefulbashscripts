#!/bin/bash

FILE="/etc/bashrc"

if [ ! -f "$FILE" ]; then
    echo "Error: File $FILE not found!"
    exit 1
fi

# Create a backup before making changes
cp "$FILE" "$FILE.bak"

# Perform replacements:
# 1. Replace \W with \w in lines containing PS1
# 2. Add \n before \$ in lines containing PS1
sed -i 's/\\W/\\w/g' "$FILE"
sed -i 's/\\\$ /\\n\\$ /g' "$FILE"

echo "Changes have been applied to $FILE. The original file has been saved as $FILE.bak."