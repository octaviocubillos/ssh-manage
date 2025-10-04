#!/bin/bash

# ==============================================================================
#                 DESINSTALADOR DE SSH MANAGER
# ==============================================================================
#
#   Este script elimina los comandos `ssh-manage` y `sshm` del sistema
#   y opcionalmente borra el directorio de configuración.
#
#   Uso (Linux/macOS): curl -fsSL https://raw.githubusercontent.com/octaviocubillos/ssh-manage/master/uninstall.sh | sudo bash
#   Uso (Termux):      curl -fsSL https://raw.githubusercontent.com/octaviocubillos/ssh-manage/master/uninstall.sh | bash
#
# ==============================================================================

set -e # Salir inmediatamente si un comando falla

# --- VARIABLES ---
MAIN_CMD="ssh-manage"
ALIAS_CMD="sshm"

# --- LÓGICA DE DESINSTALACIÓN ---
main() {
    local INSTALL_DIR
    local original_user="${SUDO_USER:-$USER}"
    local config_dir="$HOME/.config/ssh-manager"

    # Si se ejecuta con sudo, el home puede ser el de root
    if [ "$original_user" != "root" ] && [ -n "$SUDO_USER" ]; then
        config_dir="/home/$original_user/.config/ssh-manager"
    fi
    
    # Detección del entorno
    if [[ -d "$HOME/.termux" ]]; then
        INSTALL_DIR="$PREFIX/bin"
    else
        INSTALL_DIR="/usr/local/bin"
        if [ "$EUID" -ne 0 ]; then
            echo "Este desinstalador necesita privilegios de superusuario."; exit 1
        fi
    fi

    echo "Iniciando la desinstalación de SSH Manager..."

    # Eliminar comandos
    if [ -f "$INSTALL_DIR/$MAIN_CMD" ]; then
        echo "Eliminando $INSTALL_DIR/$MAIN_CMD..."
        rm -f "$INSTALL_DIR/$MAIN_CMD"
    fi
    if [ -L "$INSTALL_DIR/$ALIAS_CMD" ]; then
        echo "Eliminando $INSTALL_DIR/$ALIAS_CMD..."
        rm -f "$INSTALL_DIR/$ALIAS_CMD"
    fi

    # Preguntar sobre el directorio de configuración
    if [ -d "$config_dir" ]; then
        echo ""
        read -p "¿Deseas eliminar también el directorio de configuración y todas tus conexiones guardadas en '$config_dir'? (s/n): " choice
        case "$choice" in
            s|S )
                echo "Eliminando directorio de configuración..."
                rm -rf "$config_dir"
                ;;
            * )
                echo "Se conservará el directorio de configuración.";;
        esac
    fi

    echo ""
    echo "--------------------------------------------------------"
    echo " ¡Desinstalación completada!"
    echo "--------------------------------------------------------"
    echo ""
}

# Ejecutar la función principal
main
