#!/bin/bash
# ==============================================================================
#                 DESINSTALADOR DE SSH MANAGER (Versión Python)
# ==============================================================================
set -e
MAIN_CMD="ssh-manage"
ALIAS_CMD="sshm"

main() {
    local original_user="${SUDO_USER:-$USER}"
    local user_home
    if [ "$original_user" != "root" ] && [ -n "$SUDO_USER" ]; then user_home=$(eval echo "~$original_user"); else user_home="$HOME"; fi
    local CONFIG_DIR="$user_home/.config/ssh-manager"
    local INSTALL_DIR

    if [[ -n "$PREFIX" ]]; then INSTALL_DIR="$PREFIX/bin"; else INSTALL_DIR="/usr/local/bin"; if [ "$EUID" -ne 0 ]; then echo "Se necesita sudo."; exit 1; fi; fi

    echo "Iniciando la desinstalación de SSH Manager..."
    
    rm -f "$INSTALL_DIR/$MAIN_CMD"
    rm -f "$INSTALL_DIR/$ALIAS_CMD"
    echo "Comandos '$MAIN_CMD' y '$ALIAS_CMD' eliminados."

    if [ -d "$CONFIG_DIR" ]; then
        read -p "¿Eliminar el directorio de configuración y todas las conexiones en '$CONFIG_DIR'? (s/n): " choice < /dev/tty
        if [[ "$choice" =~ ^[sS]$ ]]; then
            rm -rf "$CONFIG_DIR"
            echo "Directorio de configuración eliminado."
        else
            echo "Se conservará el directorio de configuración."
        fi
    fi
    echo "[Éxito] Desinstalación completada."
}
main
