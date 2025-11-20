#!/bin/bash

# ==============================================================================
#                 DESINSTALADOR DE SSH MANAGER
# ==============================================================================
#
#   Este script elimina los comandos `ssh-manage` y `sshm` del sistema,
#   y opcionalmente borra el directorio de configuración y las dependencias.
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
    local original_user
    local user_home
    local master_config_file
    local config_dir
    local deps_log

    if [ -n "$SUDO_USER" ]; then original_user="$SUDO_USER"; else original_user=$(whoami); fi
    if [ "$original_user" == "root" ]; then user_home="/root"; else user_home=$(getent passwd "$original_user" | cut -d: -f6); fi
    
    master_config_file="$user_home/.config/ssh-manager/config"
    if [ -f "$master_config_file" ]; then
        source "$master_config_file"
        config_dir=$(dirname "$CONNECTIONS_PATH")
        if [ -n "$DEPS_LOG_PATH" ]; then
            deps_log="$DEPS_LOG_PATH"
        else
            deps_log="$config_dir/installed_deps.log"
        fi
    else
        config_dir="$user_home/.config/ssh-manager"
        deps_log="$config_dir/installed_deps.log"
    fi

    local SUDO_CMD="sudo"
    if [ "$EUID" -eq 0 ]; then
        SUDO_CMD=""
    fi

    if [[ -n "$PREFIX" ]]; then INSTALL_DIR="$PREFIX/bin"; else INSTALL_DIR="/usr/local/bin"; if [ "$EUID" -ne 0 ]; then echo "Se necesita sudo."; exit 1; fi; fi

    echo "Iniciando la desinstalación de SSH Manager..."
    rm -f "$INSTALL_DIR/$MAIN_CMD" "$INSTALL_DIR/$ALIAS_CMD"
    echo "Comandos eliminados."

    if [ -f "$deps_log" ] && [ -s "$deps_log" ]; then
        read -p "¿Desinstalar dependencias instaladas por el script? (s/n): " choice < /dev/tty
        if [[ "$choice" =~ ^[sS]$ ]]; then
            echo "Desinstalando dependencias..."
            local uninstall_cmd=""
            local packages=$(tr '\n' ' ' < "$deps_log")
            if command -v pkg &> /dev/null; then uninstall_cmd="pkg uninstall -y $packages"
            elif command -v apt-get &> /dev/null; then uninstall_cmd="$SUDO_CMD apt-get purge -y $packages"
            elif command -v dnf &> /dev/null; then uninstall_cmd="$SUDO_CMD dnf remove -y $packages"
            elif command -v yum &> /dev/null; then uninstall_cmd="$SUDO_CMD yum remove -y $packages"
            elif command -v pacman &> /dev/null; then uninstall_cmd="$SUDO_CMD pacman -Rns --noconfirm $packages"
            elif command -v zypper &> /dev/null; then uninstall_cmd="$SUDO_CMD zypper --non-interactive remove $packages"
            elif command -v apk &> /dev/null; then uninstall_cmd="$SUDO_CMD apk del $packages"
            elif command -v brew &> /dev/null; then uninstall_cmd="brew uninstall $packages"; fi
            
            if [ -n "$uninstall_cmd" ]; then
                if eval "$uninstall_cmd"; then echo "Dependencias eliminadas."; else echo "No se pudieron eliminar todas las dependencias."; fi
            fi
        fi
    fi

    if [ -d "$config_dir" ]; then
        read -p "¿Eliminar el directorio de configuración '$config_dir'? (s/n): " choice < /dev/tty
        if [[ "$choice" =~ ^[sS]$ ]]; then rm -rf "$config_dir"; echo "Directorio de configuración eliminado."; fi
    fi
    echo "¡Desinstalación completada!"
}
main
