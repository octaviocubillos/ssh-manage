#!/bin/bash

# ==============================================================================
#                 INSTALADOR DE SSH MANAGER
# ==============================================================================
#
#   Este script descarga la última versión de ssh-manager, la instala
#   globalmente y crea los alias `ssh-manage` y `sshm`.
#
#   Uso (Linux/macOS): curl -fsSL https://raw.githubusercontent.com/octaviocubillos/ssh-manage/master/install.sh | sudo bash
#   Uso (Termux):      curl -fsSL https://raw.githubusercontent.com/octaviocubillos/ssh-manage/master/install.sh | bash
#
# ==============================================================================

set -e # Salir inmediatamente si un comando falla

# --- VARIABLES ---
REPO_URL="https://raw.githubusercontent.com/octaviocubillos/ssh-manage/master/ssh-manager.sh"
MAIN_CMD="ssh-manage"
ALIAS_CMD="sshm"

# --- LÓGICA DE INSTALACIÓN ---

main() {
    local INSTALL_DIR

    # Detección del entorno (Termux o estándar)
    if [[ -d "$HOME/.termux" ]]; then
        echo "Detectado entorno Termux."
        INSTALL_DIR="$PREFIX/bin"
    else
        echo "Detectado entorno estándar (Linux/macOS)."
        INSTALL_DIR="/usr/local/bin"
        # Verificar si se está ejecutando como root fuera de Termux
        if [ "$EUID" -ne 0 ]; then
            echo "Este instalador necesita privilegios de superusuario en este sistema."
            echo "Por favor, ejecútalo con: curl ... | sudo bash"
            exit 1
        fi
    fi

    echo "Iniciando la instalación de SSH Manager..."

    # Descargar el script principal
    echo "Descargando la última versión desde GitHub..."
    if ! curl -fsSL "$REPO_URL" -o "$INSTALL_DIR/$MAIN_CMD"; then
        echo "Error: No se pudo descargar el script. Verifica la URL y tu conexión a internet."
        exit 1
    fi

    # Hacer el script ejecutable
    echo "Estableciendo permisos de ejecución..."
    chmod +x "$INSTALL_DIR/$MAIN_CMD"

    # Crear el alias/symlink
    echo "Creando el atajo 'sshm'..."
    # -f para forzar la sobreescritura si ya existe
    ln -sf "$INSTALL_DIR/$MAIN_CMD" "$INSTALL_DIR/$ALIAS_CMD"
    
    echo ""
    echo "--------------------------------------------------------"
    echo " ¡Instalación completada con éxito!"
    echo "--------------------------------------------------------"
    echo ""
    echo "Ahora puedes usar los comandos 'ssh-manage' o 'sshm' desde cualquier lugar."
    echo "Ejemplo: sshm add"
    echo ""
    echo "La primera vez que ejecutes el script, se creará el directorio de configuración en: ~/.config/ssh-manager/"
    echo ""
}

# Ejecutar la función principal
main
