#!/bin/bash

# Configuration
INSTALL_DIR="$HOME/Scripts/Whisper"
SHELL_RC="$HOME/.$(basename $SHELL)rc"

# Remove installation directory
if [ -d "$INSTALL_DIR" ]; then
    echo "Removing Whisper installation directory..."
    rm -rf "$INSTALL_DIR"
fi

# Remove alias from shell configuration
if grep -q "alias whisper=" "$SHELL_RC"; then
    echo "Removing whisper alias from $SHELL_RC..."
    # Create a temporary file without the whisper alias line
    grep -v "alias whisper=" "$SHELL_RC" > "$SHELL_RC.tmp"
    mv "$SHELL_RC.tmp" "$SHELL_RC"
fi

echo "Uninstallation complete!"
echo "Please run 'source $SHELL_RC' to update your shell configuration"
