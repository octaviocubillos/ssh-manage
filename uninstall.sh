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
    local original_user="${SUDO_USER:-$USER}"
    local user_home
    local pointer_file
    local config_dir
    local deps_log

    if [ "$original_user" != "root" ] && [ -n "$SUDO_USER" ]; then user_home=$(eval echo "~$original_user"); else user_home="$HOME"; fi
    pointer_file="$user_home/.sshm_config_path"
    if [ -f "$pointer_file" ]; then config_dir=$(cat "$pointer_file"); else config_dir="$user_home/.config/ssh-manager"; fi
    deps_log="$config_dir/installed_deps.log"
    
    if [[ -n "$PREFIX" ]]; then INSTALL_DIR="$PREFIX/bin"; else INSTALL_DIR="/usr/local/bin"; if [ "$EUID" -ne 0 ]; then echo "Se necesitan privilegios de superusuario."; exit 1; fi; fi

    echo "Iniciando la desinstalación de SSH Manager..."

    # Eliminar comandos
    if [ -f "$INSTALL_DIR/$MAIN_CMD" ]; then echo "Eliminando $INSTALL_DIR/$MAIN_CMD..."; rm -f "$INSTALL_DIR/$MAIN_CMD"; fi
    if [ -L "$INSTALL_DIR/$ALIAS_CMD" ]; then echo "Eliminando $INSTALL_DIR/$ALIAS_CMD..."; rm -f "$INSTALL_DIR/$ALIAS_CMD"; fi

    # Desinstalar dependencias
    if [ -f "$deps_log" ]; then
        echo ""
        read -p "¿Deseas desinstalar las dependencias que SSH Manager instaló? (s/n): " choice
        if [[ "$choice" =~ ^[sS]$ ]]; then
            echo "Desinstalando dependencias..."
            local uninstall_cmd=""
            local packages=$(cat "$deps_log")
            if command -v pkg &> /dev/null; then uninstall_cmd="pkg uninstall -y $packages"
            elif command -v apt-get &> /dev/null; then uninstall_cmd="sudo apt-get purge -y $packages"
            elif command -v dnf &> /dev/null; then uninstall_cmd="sudo dnf remove -y $packages"
            elif command -v yum &> /dev/null; then uninstall_cmd="sudo yum remove -y $packages"
            elif command -v pacman &> /dev/null; then uninstall_cmd="sudo pacman -Rns --noconfirm $packages"
            elif command -v zypper &> /dev/null; then uninstall_cmd="sudo zypper --non-interactive remove $packages"
            elif command -v apk &> /dev/null; then uninstall_cmd="sudo apk del $packages"
            elif command -v brew &> /dev/null; then uninstall_cmd="brew uninstall $packages"; fi
            
            if [ -n "$uninstall_cmd" ]; then
                if eval "$uninstall_cmd"; then echo "Dependencias eliminadas."; else echo "No se pudieron eliminar todas las dependencias."; fi
            fi
        fi
    fi

    # Preguntar sobre el directorio de configuración
    if [ -d "$config_dir" ]; then
        echo ""
        read -p "¿Deseas eliminar también el directorio de configuración '$config_dir'? (s/n): " choice
        if [[ "$choice" =~ ^[sS]$ ]]; then echo "Eliminando directorio de configuración..."; rm -rf "$config_dir"; else echo "Se conservará el directorio de configuración."; fi
    fi
    
    if [ -f "$pointer_file" ]; then echo "Eliminando archivo de ruta..."; rm -f "$pointer_file"; fi
    echo ""; echo "--------------------------------------------------------"; echo " ¡Desinstalación completada!"; echo "--------------------------------------------------------"; echo ""
}

main
