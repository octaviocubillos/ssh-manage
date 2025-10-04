#!/bin/bash

# ==============================================================================
#                 INSTALADOR DE SSH MANAGER
# ==============================================================================
#
#   Este script descarga la última versión de ssh-manager, la instala en
#   /usr/local/bin y crea los alias `ssh-manage` y `sshm`.
#
#   Uso: curl -fsSL https://raw.githubusercontent.com/octaviocubillos/ssh-manage/main/install.sh | sudo bash
#
# ==============================================================================

set -e # Salir inmediatamente si un comando falla

# --- VARIABLES ---
REPO_URL="https://raw.githubusercontent.com/octaviocubillos/ssh-manage/main/ssh-manager.sh"
INSTALL_DIR="/usr/local/bin"
MAIN_CMD="ssh-manage"
ALIAS_CMD="sshm"

# --- LÓGICA DE INSTALACIÓN ---

main() {
    # Verificar si se está ejecutando como root
    if [ "$EUID" -ne 0 ]; then
        echo "Este instalador necesita privilegios de superusuario."
        echo "Por favor, ejecútalo con sudo o como root."
        exit 1
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
    
    # Crear el directorio de configuración para el usuario que invocó sudo
    local original_user="${SUDO_USER:-$USER}"
    if [ "$original_user" != "root" ]; then
        local config_dir="/home/$original_user/.config/ssh-manager"
        echo "Creando el directorio de configuración en $config_dir..."
        # Usar 'runuser' o 'sudo -u' para ejecutar como el usuario original
        runuser -u "$original_user" -- mkdir -p "$config_dir"
    fi

    echo ""
    echo "--------------------------------------------------------"
    echo " ¡Instalación completada con éxito!"
    echo "--------------------------------------------------------"
    echo ""
    echo "Ahora puedes usar los comandos 'ssh-manage' o 'sshm' desde cualquier lugar."
    echo "Ejemplo: sshm add"
    echo ""
    echo "Tu archivo de configuración se encuentra en: ~/.config/ssh-manager/connections.txt"
    echo ""
}

# Ejecutar la función principal
main
