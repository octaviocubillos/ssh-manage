#!/bin/bash

# ==============================================================================
#                 GESTOR DE CONEXIONES SSH v1.0.0 (Bash)
# ==============================================================================
#
#   Un script de Bash para gestionar múltiples conexiones SSH, con un menú
#   interactivo navegable por flechas y funcionalidades de red avanzadas.
#
# ==============================================================================


# --- CONFIGURACIÓN PRINCIPAL ---
VERSION="1.0.0"
REPO_BASE_URL="https://raw.githubusercontent.com/octaviocubillos/ssh-manage/master"

IS_TERMUX=false
if [[ -n "$PREFIX" ]]; then IS_TERMUX=true; fi

SUDO_CMD="sudo"
if [ "$EUID" -eq 0 ]; then
    SUDO_CMD=""
fi

CONFIG_DIR="$HOME/.config/ssh-manager"
MASTER_CONFIG_FILE="$CONFIG_DIR/config"
CONNECTIONS_FILE=""
DEPS_LOG=""
TUNNELS_PID_FILE=""

load_config() {
    mkdir -p "$CONFIG_DIR"
    if [ ! -f "$MASTER_CONFIG_FILE" ]; then
        echo "CONNECTIONS_PATH=$CONFIG_DIR/connections.txt" > "$MASTER_CONFIG_FILE"
        echo "DEPS_LOG_PATH=$CONFIG_DIR/installed_deps.log" >> "$MASTER_CONFIG_FILE"
        echo "TUNNELS_PID_PATH=$CONFIG_DIR/tunnels.pid" >> "$MASTER_CONFIG_FILE"
    fi
    source "$MASTER_CONFIG_FILE"
    
    # Set defaults if not present (backward compatibility)
    if [ -z "$DEPS_LOG_PATH" ]; then DEPS_LOG_PATH="$CONFIG_DIR/installed_deps.log"; fi
    if [ -z "$TUNNELS_PID_PATH" ]; then TUNNELS_PID_PATH="$CONFIG_DIR/tunnels.pid"; fi

    CONFIG_FILE="$CONNECTIONS_PATH"
    DEPS_LOG="$DEPS_LOG_PATH"
    TUNNELS_PID_FILE="$TUNNELS_PID_PATH"
    
    # Ensure files exist
    if [ ! -f "$CONFIG_FILE" ]; then touch "$CONFIG_FILE"; fi
    if [ ! -f "$DEPS_LOG" ]; then touch "$DEPS_LOG"; fi
    if [ ! -f "$TUNNELS_PID_FILE" ]; then touch "$TUNNELS_PID_FILE"; fi
}

VERBOSE_FLAG=""
args=()
for arg in "$@"; do
    if [ "$arg" == "--verbose" ]; then VERBOSE_FLAG="-v"; else args+=("$arg"); fi
done
set -- "${args[@]}"

RESERVED_COMMANDS=("add" "-a" "edit" "-e" "list" "-l" "connect" "-c" "browse" "-b" "delete" "-d" "update" "-u" "scp" "-s" "tunnel" "-t" "reverse-tunnel" "-rt" "help" "-h" "version" "-v" "list-tunnels" "-lt" "stop-tunnel" "-st")

# --- VERIFICACIÓN DE DEPENDENCIAS ---

show_spinner() {
    if ! command -v "tput" &> /dev/null; then while true; do sleep 1; done; return; fi
    local -r FRAMES='|/-\'; local i=0; tput civis; trap 'tput cnorm' EXIT
    while true; do printf "\b%s" "${FRAMES:i++%${#FRAMES}:1}"; sleep 0.1; done
}

install_package() {
    local pkg=$1
    local install_cmd=""

    if $IS_TERMUX; then
        install_cmd="pkg install -y $pkg"
    elif command -v apt-get &> /dev/null; then
        install_cmd="$SUDO_CMD apt-get update -y && $SUDO_CMD apt-get install -y $pkg"
    elif command -v dnf &> /dev/null; then
        install_cmd="$SUDO_CMD dnf install -y $pkg"
    elif command -v yum &> /dev/null; then
        if [ "$pkg" == "fuse-sshfs" ]; then
            install_cmd="$SUDO_CMD yum install -y epel-release && $SUDO_CMD yum install -y $pkg"
        else
            install_cmd="$SUDO_CMD yum install -y $pkg"
        fi
    elif command -v pacman &> /dev/null; then
        install_cmd="$SUDO_CMD pacman -Syu --noconfirm $pkg"
    elif command -v zypper &> /dev/null; then
        install_cmd="$SUDO_CMD zypper --non-interactive install $pkg"
    elif command -v apk &> /dev/null; then
        install_cmd="$SUDO_CMD apk add --no-cache $pkg"
    elif command -v brew &> /dev/null; then
        install_cmd="brew install $pkg"
    else
        return 1
    fi

    eval "$install_cmd" > /dev/null 2>&1
}

ensure_dependency() {
    local dep=$1
    local pkg=${2:-$1}

    # Termux specific: openssl binary is provided by openssl-tool package
    if [ "$dep" == "openssl" ] && $IS_TERMUX; then dep="openssl-tool"; fi

    # Check if dependency is already installed
    if command -v "$dep" &> /dev/null; then return 0; fi

    echo "La herramienta '$dep' es necesaria. Intentando instalar '$pkg'..."

    # Yum specific: sshfs package is named fuse-sshfs
    if command -v yum &> /dev/null && [ "$dep" == "sshfs" ]; then pkg="fuse-sshfs"; fi

    printf "Instalando...  "
    show_spinner &
    local spinner_pid=$!

    if install_package "$pkg"; then
        kill $spinner_pid &>/dev/null
        wait $spinner_pid 2>/dev/null
        printf "\b\bListo.\n"
        hash -r
        
        if ! command -v "$dep" &> /dev/null; then 
            echo "Error: La instalación de '$pkg' falló."
            return 1
        fi
        
        if ! grep -q "^$pkg$" "$DEPS_LOG"; then echo "$pkg" >> "$DEPS_LOG"; fi
    else
        kill $spinner_pid &>/dev/null
        wait $spinner_pid 2>/dev/null
        printf "\b\bFalló.\n"
        echo "Error: Gestor de paquetes no compatible o fallo en la instalación."
        return 1
    fi
    return 0
}

check_base_requirements() {
    ensure_dependency "tput" "ncurses-bin" || ensure_dependency "tput" "ncurses" || ensure_dependency "tput" "ncurses-utils"
    ensure_dependency "ssh" "openssh-client" || ensure_dependency "ssh" "openssh"
}

# --- FUNCIONES DE LA APLICACIÓN ---

show_usage() {
    echo "Uso: $(basename "$0") [comando] [argumentos...]"
    echo "  o: $(basename "$0") <alias> [comando-remoto...]"
    echo ""
    echo "Comandos de Conexión:"
    printf "  %-35s %s\n" "add,    -a" "Añade una nueva conexión."
    printf "  %-35s %s\n" "edit,   -e <alias> [campo]" "Edita una conexión (campo: host,user,port,auth,dir,cmd)."
    printf "  %-35s %s\n" "list,   -l [-a | -p]" "Lista conexiones. -a: detalles, -p: ver contraseñas."
    printf "  %-35s %s\n" "connect,-c <alias> [cmd]" "Conecta a un servidor (o usa solo el <alias>)."
    printf "  %-35s %s\n" "delete, -d <alias>" "Elimina una conexión."
    if ! $IS_TERMUX; then
        printf "  %-35s %s\n" "browse, -b <alias>" "Abre explorador SFTP visual."
    fi
    echo ""
    echo "Comandos de Utilidad:"
    printf "  %-35s %s\n" "scp,    -s <orig> <dest>" "Copia archivos (ej: alias:ruta/archivo ./local)."
    printf "  %-35s %s\n" "tunnel, -t <alias> <spec>" "Crea túnel local (spec: puerto_local:host_dest:puerto_dest)."
    printf "  %-35s %s\n" "reverse-tunnel, -rt <alias> <spec>" "Crea túnel reverso (spec: puerto_remoto:host_local:puerto_local)."
    printf "  %-35s %s\n" "list-tunnels,   -lt" "Lista túneles activos en segundo plano."
    printf "  %-35s %s\n" "stop-tunnel,    -st [pid]" "Detiene un túnel activo."
    echo ""
    echo "Otros:"
    printf "  %-35s %s\n" "update, -u" "Busca y aplica actualizaciones."
    printf "  %-35s %s\n" "version,-v" "Muestra la versión actual."
    printf "  %-35s %s\n" "help,   -h" "Muestra esta ayuda."
    echo ""
    echo "Opciones Globales:"
    printf "  %-35s %s\n" "--verbose" "Activa modo detallado para comandos de red."
    echo ""
    echo "Si no se especifican comandos, se abrirá el menú interactivo."
}

show_version() { echo "ssh-manager version $VERSION"; }
is_alias_reserved() { local alias_to_check=$1; for cmd in "${RESERVED_COMMANDS[@]}"; do if [[ "$cmd" == "$alias_to_check" ]]; then return 0; fi; done; return 1; }

select_alias() {
    local prompt_text=$1
    # Read aliases and details into an array
    local options=()
    local aliases=()
    
    while IFS='|' read -r alias host user port _ _ _ _ _; do
        if [[ "$alias" =~ ^# ]] || [ -z "$alias" ]; then continue; fi
        aliases+=("$alias")
        options+=("$alias ($user@$host)")
    done < "$CONFIG_FILE"

    if [ ${#options[@]} -eq 0 ]; then echo "Error: No hay conexiones guardadas." >&2; return 1; fi
    
    options+=("Volver al menú principal")

    local selected=0
    while true; do
        clear >&2
        echo "$prompt_text" >&2
        echo "Usa ↑/↓ para moverte, Enter/→ para seleccionar, ←/q para volver." >&2
        echo "------------------------------------------" >&2

        for i in "${!options[@]}"; do
            if [ $i -eq $selected ]; then
                printf " > \e[32m%s\e[0m\n" "${options[$i]}" >&2
            else
                echo "   ${options[$i]}" >&2
            fi
        done
        echo "------------------------------------------" >&2

        read -rsn1 key
        if [[ $key == $'\x1b' ]]; then
            read -rsn2 key
        fi

        case "$key" in
            '[A') # Up
                selected=$(( (selected - 1 + ${#options[@]}) % ${#options[@]} ))
                ;;
            '[B') # Down
                selected=$(( (selected + 1) % ${#options[@]} ))
                ;;
            '[D'|q|Q) # Left or q - Back
                return 1
                ;;
            ''|'[C') # Enter or Right - Select
                if [ $selected -eq $((${#options[@]} - 1)) ]; then
                    return 1 # "Volver al menú principal" selected
                else
                    echo "${aliases[$selected]}"
                    return 0
                fi
                ;;
        esac
    done
}

add_connection() {
    echo "Añadiendo una nueva conexión (dejar vacío para cancelar)..."
    local alias; while true; do read -p "Alias: " alias; if [ -z "$alias" ]; then echo "Cancelado."; return 1; elif grep -qE "^${alias}\|" "$CONFIG_FILE"; then echo "Error: Alias ya existe."; elif is_alias_reserved "$alias"; then echo "Error: Alias reservado."; else break; fi; done
    local host; while true; do read -p "Host: " host; if [ -z "$host" ]; then echo "Cancelado."; return 1; else break; fi; done
    local current_user=$(whoami); read -p "Usuario [$current_user]: " user; user=${user:-$current_user}
    read -p "Puerto [22]: " port; port=${port:-22}
    echo "Tipo auth: 1) Clave SSH, 2) Pass (plano), 3) Pass (encriptada), 4) Ninguna"; read -p "Opción: " auth_choice
    key_path=""; password=""
    if [ "$auth_choice" = "1" ]; then read -p "Ruta a clave: " key_path
    elif [ "$auth_choice" = "2" ]; then read -s -p "Contraseña: " password; echo ""
    elif [ "$auth_choice" = "3" ]; then ensure_dependency "openssl" || return 1; read -s -p "Palabra clave: " keyword; echo ""; read -s -p "Contraseña a encriptar: " pass_to_encrypt; echo ""; encrypted_pass=$(echo "$pass_to_encrypt" | openssl enc -aes-256-cbc -a -salt -pbkdf2 -pass pass:"$keyword"); password="enc:$encrypted_pass"
    fi
    read -p "Directorio remoto (opcional): " remote_dir
    read -p "Comando por defecto (opcional): " default_cmd
    echo "$alias|$host|$user|$port|$key_path|$password|$remote_dir|$default_cmd|" >> "$CONFIG_FILE"; echo "¡Conexión '$alias' añadida!"
}

edit_connection() {
    local alias_to_edit=$1; local field_to_edit=$2; if [ -z "$alias_to_edit" ]; then alias_to_edit=$(select_alias "Editar conexión"); if [ $? -ne 0 ]; then return 1; fi; fi
    local connection_line; connection_line=$(grep -E "^${alias_to_edit}\|" "$CONFIG_FILE"); if [ -z "$connection_line" ]; then echo "Error: Alias no encontrado."; return 1; fi
    IFS='|' read -r old_alias old_host old_user old_port old_key old_pass old_remote_dir old_cmd _ <<< "$connection_line"
    local new_alias="$old_alias"; local new_host="$old_host"; local new_user="$old_user"; local new_port="$old_port"; local new_key="$old_key"; local new_pass="$old_pass"; local new_remote_dir="$old_remote_dir"; local new_cmd="$old_cmd"
    if [ -n "$field_to_edit" ]; then
        echo "Editando campo '$field_to_edit' para '$alias_to_edit'..."; case $field_to_edit in alias) while true; do read -p "Nuevo alias: " new_alias; if [ -z "$new_alias" ]; then echo "Alias vacío."; elif [[ "$new_alias" != "$old_alias" ]] && grep -qE "^${new_alias}\|" "$CONFIG_FILE"; then echo "Alias ya existe."; elif is_alias_reserved "$new_alias"; then echo "Alias reservado."; else break; fi; done;; host) while true; do read -p "Nuevo host: " new_host; if [ -z "$new_host" ]; then echo "Host obligatorio."; else break; fi; done;; user) while true; do read -p "Nuevo usuario: " new_user; if [ -z "$new_user" ]; then echo "Usuario obligatorio."; else break; fi; done;; port) read -p "Nuevo puerto: " new_port;; dir) read -p "Nuevo dir. remoto: " new_remote_dir;; cmd|command) read -p "Nuevo comando por defecto: " new_cmd;; auth) echo "Tipo auth: 1) Clave SSH, 2) Pass (plano), 3) Pass (encriptada), 4) Ninguna"; read -p "Opción: " auth_choice; new_key=""; new_pass=""; if [ "$auth_choice" = "1" ]; then read -p "Ruta a clave: " new_key; elif [ "$auth_choice" = "2" ]; then read -s -p "Nueva Contraseña: " new_pass; echo ""; elif [ "$auth_choice" = "3" ]; then ensure_dependency "openssl" || return 1; read -s -p "Palabra clave: " keyword; echo ""; read -s -p "Nueva Contraseña: " pass_to_encrypt; echo ""; encrypted_pass=$(echo "$pass_to_encrypt" | openssl enc -aes-256-cbc -a -salt -pbkdf2 -pass pass:"$keyword"); new_pass="enc:$encrypted_pass"; fi;; *) echo "Error: Campo '$field_to_edit' desconocido."; return 1;; esac
    else
        echo "Editando '$old_alias'. Enter para mantener valor."; while true; do read -p "Nuevo alias [$old_alias]: " new_alias; new_alias=${new_alias:-$old_alias}; if [ -z "$new_alias" ]; then echo "Alias vacío."; elif [[ "$new_alias" != "$old_alias" ]] && grep -qE "^${new_alias}\|" "$CONFIG_FILE"; then echo "Alias ya existe."; elif is_alias_reserved "$new_alias"; then echo "Alias reservado."; else break; fi; done; while true; do read -p "Nuevo host [$old_host]: " new_host; new_host=${new_host:-$old_host}; if [ -z "$new_host" ]; then echo "Host obligatorio."; else break; fi; done; while true; do read -p "Nuevo usuario [$old_user]: " new_user; new_user=${new_user:-$old_user}; if [ -z "$new_user" ]; then echo "Usuario obligatorio."; else break; fi; done; read -p "Nuevo puerto [$old_port]: " new_port; new_port=${new_port:-$old_port}; read -p "Nuevo dir. remoto [$old_remote_dir]: " new_remote_dir; new_remote_dir=${new_remote_dir:-$old_remote_dir}; read -p "Nuevo comando por defecto [$old_cmd]: " new_cmd; new_cmd=${new_cmd:-$old_cmd}; read -p "¿Cambiar auth? (s/n): " change_auth; if [[ "$change_auth" =~ ^[sS]$ ]]; then echo "Tipo auth: 1) Clave SSH, 2) Pass (plano), 3) Pass (encriptada), 4) Ninguna"; read -p "Opción: " auth_choice; new_key=""; new_pass=""; if [ "$auth_choice" = "1" ]; then read -p "Ruta a clave: " new_key; elif [ "$auth_choice" = "2" ]; then read -s -p "Nueva Contraseña: " new_pass; echo ""; elif [ "$auth_choice" = "3" ]; then ensure_dependency "openssl" || return 1; read -s -p "Palabra clave: " keyword; echo ""; read -s -p "Nueva Contraseña: " pass_to_encrypt; echo ""; encrypted_pass=$(echo "$pass_to_encrypt" | openssl enc -aes-256-cbc -a -salt -pbkdf2 -pass pass:"$keyword"); new_pass="enc:$encrypted_pass"; else new_key="$old_key"; new_pass="$old_pass"; fi; fi
    fi
    local new_line="$new_alias|$new_host|$new_user|$new_port|$new_key|$new_pass|$new_remote_dir|$new_cmd|"
    grep -vE "^${old_alias}\|" "$CONFIG_FILE" > "${CONFIG_FILE}.tmp"; echo "$new_line" >> "${CONFIG_FILE}.tmp"; mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"; echo "¡Conexión '$new_alias' actualizada!"
}

connect_to_host() {
    local alias_to_connect=$1; local remote_command=$2
    if [ -z "$alias_to_connect" ]; then alias_to_connect=$(select_alias "Conectar a servidor"); if [ $? -ne 0 ]; then return 1; fi; fi
    local connection_line; connection_line=$(grep -E "^${alias_to_connect}\|" "$CONFIG_FILE"); if [ -z "$connection_line" ]; then echo "Error: Alias no encontrado."; return 1; fi
    IFS='|' read -r alias host user port key pass remote_dir default_cmd _ <<< "$connection_line"
    local command_to_run="${remote_command:-$default_cmd}"
    echo "Conectando a $user@$host en el puerto $port..."; local decrypted_pass=""; if [[ "$pass" == enc:* ]]; then ensure_dependency "openssl" || return 1; read -s -p "Palabra clave: " keyword; echo ""; local encrypted_data=${pass#enc:}; decrypted_pass=$(echo "$encrypted_data" | openssl enc -aes-256-cbc -a -d -salt -pbkdf2 -pass pass:"$keyword" 2>/dev/null); if [ -z "$decrypted_pass" ]; then echo "Error de desencriptación."; return 1; fi; elif [ -n "$pass" ]; then decrypted_pass="$pass"; fi
    local final_command="$command_to_run"; if [ -n "$remote_dir" ]; then if [ -n "$final_command" ]; then final_command="cd \"$remote_dir\" && $final_command"; else final_command="cd \"$remote_dir\" && exec \${SHELL:-bash} -l"; fi; fi
    if [ -n "$final_command" ] && [ "$final_command" != "$remote_command" ]; then echo "Iniciando en dir: $remote_dir"; elif [ -n "$remote_command" ]; then echo "Ejecutando: $remote_command"; fi
    local tty_option=""; if [ -n "$final_command" ]; then tty_option="-t"; fi

    if [ -n "$key" ]; then
        ssh $VERBOSE_FLAG $tty_option -i "$key" -p "$port" "$user@$host" "$final_command"
    elif [ -n "$decrypted_pass" ]; then
        ensure_dependency "sshpass" || return 1
        sshpass -p "$decrypted_pass" ssh $VERBOSE_FLAG $tty_option -p "$port" "$user@$host" -o StrictHostKeyChecking=no "$final_command"
    else
        ssh $VERBOSE_FLAG $tty_option -p "$port" "$user@$host" "$final_command"
    fi
}

delete_connection() {
    local alias_to_delete=$1; if [ -z "$alias_to_delete" ]; then alias_to_delete=$(select_alias "Eliminar conexión"); if [ $? -ne 0 ]; then return 1; fi; fi
    grep -vE "^${alias_to_delete}\|" "$CONFIG_FILE" > "${CONFIG_FILE}.tmp"; mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    echo "Conexión '$alias_to_delete' eliminada."
}

update_script() {
    echo "Buscando actualizaciones..."
    local remote_version; remote_version=$(curl -fsSL "$REPO_BASE_URL/version.txt" 2>/dev/null)
    if [ -z "$remote_version" ]; then echo "No se pudo verificar la versión remota."; return 1; fi
    if [ "$VERSION" == "$remote_version" ]; then echo "Ya tienes la última versión instalada ($VERSION)."; else
        echo "¡Nueva versión disponible! ($remote_version)"; read -p "¿Deseas actualizar ahora? (s/n): " choice
        if [[ "$choice" =~ ^[sS]$ ]]; then
            local install_script_url="$REPO_BASE_URL/install.sh"; local exec_cmd="curl -fsSL $install_script_url | sudo bash"
            if $IS_TERMUX; then exec_cmd="curl -fsSL $install_script_url | bash"; fi
            echo "Ejecutando el instalador..."; sh -c "$exec_cmd"; echo "Actualización completada. Por favor, reinicia el script."; exit 0
        else echo "Actualización cancelada."; fi
    fi
}

run_scp() {
    ensure_dependency "scp" "openssh-client" || ensure_dependency "scp" "openssh" || return 1
    local source=$1; local destination=$2; if [ -z "$source" ] || [ -z "$destination" ]; then echo "Error: se requieren un origen y un destino."; show_usage; return 1; fi
    local alias_str=""; if [[ "$source" == *":"* ]]; then alias_str=$(echo "$source" | cut -d: -f1); elif [[ "$destination" == *":"* ]]; then alias_str=$(echo "$destination" | cut -d: -f1); else echo "Error: el origen o el destino debe tener el formato <alias>:/ruta"; show_usage; return 1; fi
    local connection_line; connection_line=$(grep -E "^${alias_str}\|" "$CONFIG_FILE"); if [ -z "$connection_line" ]; then echo "Error: Alias '$alias_str' no encontrado."; return 1; fi
    IFS='|' read -r _ host user port key pass _ <<< "$connection_line"
    local decrypted_pass=""; if [[ "$pass" == enc:* ]]; then ensure_dependency "openssl" || return 1; read -s -p "Palabra clave: " keyword; echo ""; local encrypted_data=${pass#enc:}; decrypted_pass=$(echo "$encrypted_data" | openssl enc -aes-256-cbc -a -d -salt -pbkdf2 -pass pass:"$keyword" 2>/dev/null); if [ -z "$decrypted_pass" ]; then echo "Error de desencriptación."; return 1; fi; elif [ -n "$pass" ]; then decrypted_pass="$pass"; fi
    local scp_command="scp $VERBOSE_FLAG -r -P $port"; if [ -n "$key" ]; then scp_command+=" -i $key"; fi
    local final_source="$source"; local final_destination="$destination"
    final_source=${final_source/$alias_str/$user@$host}; final_destination=${final_destination/$alias_str/$user@$host}
    echo "Copiando archivos..."; if [ -n "$decrypted_pass" ]; then ensure_dependency "sshpass" || return 1; sshpass -p "$decrypted_pass" $scp_command "$final_source" "$final_destination"; else $scp_command "$final_source" "$final_destination"; fi; echo "Copia completada."
}

run_tunnel() {
    local alias_str=$1; local tunnel_spec=$2; local reverse=${3:-false}; local background=${4:-false}
    if [ -z "$alias_str" ] || [ -z "$tunnel_spec" ]; then echo "Error: se requiere un alias y una especificación de túnel."; show_usage; return 1; fi
    local connection_line; connection_line=$(grep -E "^${alias_str}\|" "$CONFIG_FILE"); if [ -z "$connection_line" ]; then echo "Error: Alias '$alias_str' no encontrado."; return 1; fi
    IFS='|' read -r _ host user port key pass _ <<< "$connection_line"
    local decrypted_pass=""; if [[ "$pass" == enc:* ]]; then ensure_dependency "openssl" || return 1; read -s -p "Palabra clave: " keyword; echo ""; local encrypted_data=${pass#enc:}; decrypted_pass=$(echo "$encrypted_data" | openssl enc -aes-256-cbc -a -d -salt -pbkdf2 -pass pass:"$keyword" 2>/dev/null); if [ -z "$decrypted_pass" ]; then echo "Error de desencriptación."; return 1; fi; elif [ -n "$pass" ]; then decrypted_pass="$pass"; fi
    local tunnel_flag="-L"; local tunnel_type="local"; if [ "$reverse" = true ]; then tunnel_flag="-R"; tunnel_type="reverso"; fi
    local ssh_command="ssh $VERBOSE_FLAG -o StrictHostKeyChecking=no -N $tunnel_flag $tunnel_spec -p $port"; if [ -n "$key" ]; then ssh_command+=" -i $key"; fi
    if [ "$background" = true ]; then ssh_command+=" -f"; echo "Estableciendo túnel SSH $tunnel_type en segundo plano..."; else echo "Estableciendo túnel SSH $tunnel_type. Presiona Ctrl+C para cerrarlo."; fi
    if [ -n "$decrypted_pass" ]; then
        ensure_dependency "sshpass" || return 1
        export SSHPASS="$decrypted_pass"
        sshpass -e $ssh_command "$user@$host"
        unset SSHPASS
    else
        $ssh_command "$user@$host"
    fi
    if [ "$background" = true ]; then
        sleep 1; local tunnel_pid; tunnel_pid=$(pgrep -f "ssh.*$tunnel_spec.*$user@$host")
        if [ -n "$tunnel_pid" ]; then echo "$tunnel_pid|$alias_str|$tunnel_spec" >> "$TUNNELS_PID_FILE"; echo "Túnel creado en segundo plano con PID: $tunnel_pid"; else echo "Error: Falló la creación del túnel en segundo plano."; fi
    fi
}

list_tunnels() {
    if [ ! -s "$TUNNELS_PID_FILE" ]; then echo "No hay túneles activos gestionados."; return; fi
    local temp_pid_file; temp_pid_file=$(mktemp); local active_tunnels=false
    echo "Túneles activos en segundo plano:"; echo "--------------------------------"
    while IFS='|' read -r pid alias_str spec || [ -n "$pid" ]; do
        if ps -p "$pid" > /dev/null; then
            printf "  PID: %-10s | Alias: %-15s | Spec: %s\n" "$pid" "$alias_str" "$spec"
            echo "$pid|$alias_str|$spec" >> "$temp_pid_file"; active_tunnels=true
        fi
    done < "$TUNNELS_PID_FILE"
    if [ "$active_tunnels" = false ]; then echo "No se encontraron túneles activos. Limpiando registro..."; fi
    mv "$temp_pid_file" "$TUNNELS_PID_FILE"
}

select_tunnel() {
    if [ ! -s "$TUNNELS_PID_FILE" ]; then echo "No hay túneles activos gestionados." >&2; return 1; fi
    
    local options=()
    local pids=()
    
    # Filter active tunnels
    local temp_pid_file; temp_pid_file=$(mktemp)
    while IFS='|' read -r pid alias_str spec || [ -n "$pid" ]; do
        if ps -p "$pid" > /dev/null; then
            options+=("$pid - $alias_str ($spec)")
            pids+=("$pid")
            echo "$pid|$alias_str|$spec" >> "$temp_pid_file"
        fi
    done < "$TUNNELS_PID_FILE"
    mv "$temp_pid_file" "$TUNNELS_PID_FILE"

    if [ ${#options[@]} -eq 0 ]; then echo "No hay túneles activos." >&2; return 1; fi
    options+=("Volver")

    local selected=0
    while true; do
        clear >&2
        echo "Selecciona el túnel a detener:" >&2
        echo "Usa ↑/↓ para moverte, Enter/→ para seleccionar, ←/q para volver." >&2
        echo "------------------------------------------" >&2

        for i in "${!options[@]}"; do
            if [ $i -eq $selected ]; then
                printf " > \e[32m%s\e[0m\n" "${options[$i]}" >&2
            else
                echo "   ${options[$i]}" >&2
            fi
        done
        echo "------------------------------------------" >&2

        read -rsn1 key
        if [[ $key == $'\x1b' ]]; then
            read -rsn2 key
        fi

        case "$key" in
            '[A') # Up
                selected=$(( (selected - 1 + ${#options[@]}) % ${#options[@]} ))
                ;;
            '[B') # Down
                selected=$(( (selected + 1) % ${#options[@]} ))
                ;;
            '[D'|q|Q) # Left or q - Back
                return 1
                ;;
            ''|'[C') # Enter or Right - Select
                if [ $selected -eq $((${#options[@]} - 1)) ]; then
                    return 1 # "Volver" selected
                else
                    echo "${pids[$selected]}"
                    return 0
                fi
                ;;
        esac
    done
}

stop_tunnel() {
    local pid_to_kill=$1
    if [ -z "$pid_to_kill" ]; then
        pid_to_kill=$(select_tunnel)
        if [ $? -ne 0 ] || [ -z "$pid_to_kill" ]; then return 1; fi
    fi
    
    if grep -q "^${pid_to_kill}|" "$TUNNELS_PID_FILE"; then
        if kill "$pid_to_kill"; then 
            echo "Túnel con PID $pid_to_kill detenido."
            grep -v "^${pid_to_kill}|" "$TUNNELS_PID_FILE" > "${TUNNELS_PID_FILE}.tmp" && mv "${TUNNELS_PID_FILE}.tmp" "$TUNNELS_PID_FILE"
        else 
            echo "Error al detener el proceso."
        fi
    else 
        echo "Error: No se encontró un túnel gestionado con el PID $pid_to_kill."
    fi
}

browse_sftp() {
    ensure_dependency "mc" || return 1; ensure_dependency "sshfs" || return 1
    if $IS_TERMUX; then echo "Error: La función 'browse' no está disponible en Termux."; return 1; fi
    # ... (lógica de fuse checks omitida por brevedad)
    local alias_to_browse=$1; if [ -z "$alias_to_browse" ]; then alias_to_browse=$(select_alias "Explorar archivos"); if [ $? -ne 0 ]; then return 1; fi; fi
    local connection_line; connection_line=$(grep -E "^${alias_to_browse}\|" "$CONFIG_FILE"); if [ -z "$connection_line" ]; then echo "Error: Alias no encontrado."; return 1; fi
    IFS='|' read -r _ host user port key pass remote_dir _ <<< "$connection_line"
    local decrypted_pass=""; if [[ "$pass" == enc:* ]]; then ensure_dependency "openssl" || return 1; read -s -p "Palabra clave: " keyword; echo ""; local encrypted_data=${pass#enc:}; decrypted_pass=$(echo "$encrypted_data" | openssl enc -aes-256-cbc -a -d -salt -pbkdf2 -pass pass:"$keyword" 2>/dev/null); if [ -z "$decrypted_pass" ]; then echo "Error de desencriptación."; return 1; fi; elif [ -n "$pass" ]; then decrypted_pass="$pass"; fi
    local MOUNT_POINT; MOUNT_POINT=$(mktemp -d); trap 'fusermount -u "$MOUNT_POINT" 2>/dev/null; rmdir "$MOUNT_POINT" 2>/dev/null; echo "Conexión SFTP cerrada.";' INT TERM EXIT
    echo "Montando sistema de archivos remoto en $MOUNT_POINT..."; local sshfs_opts="-p $port -o StrictHostKeyChecking=no"; if ! $IS_TERMUX; then sshfs_opts+=" -o allow_other,default_permissions"; fi; if [ -n "$key" ]; then sshfs_opts+=" -o IdentityFile=$key"; fi
    local remote_path_to_mount; local mc_start_path; if [ -n "$remote_dir" ]; then remote_path_to_mount="/"; mc_start_path="$MOUNT_POINT/$(echo "$remote_dir" | sed 's#^/##')"; else remote_path_to_mount=""; mc_start_path="$MOUNT_POINT"; fi
    if [ -n "$decrypted_pass" ]; then ensure_dependency "sshpass" || return 1; if ! echo "$decrypted_pass" | sshfs "${user}@${host}:${remote_path_to_mount}" "$MOUNT_POINT" -o password_stdin $sshfs_opts; then echo "Error de montaje."; return 1; fi
    else if ! sshfs "${user}@${host}:${remote_path_to_mount}" "$MOUNT_POINT" $sshfs_opts; then echo "Error de montaje."; return 1; fi; fi
    echo "¡Montaje exitoso! Sale con F10 para desmontar."; mc "$mc_start_path"
}

list_connections() {
    local show_all=false
    local show_pass=false

    for arg in "$@"; do
        case "$arg" in
            -a|--all) show_all=true ;;
            -p|--password) show_pass=true ;;
            -ap|-pa) show_all=true; show_pass=true ;;
        esac
    done

    if [ ! -s "$CONFIG_FILE" ]; then echo "No hay conexiones guardadas."; return; fi

    echo "Conexiones guardadas:"
    echo "---------------------"
    if [ "$show_all" = true ] || [ "$show_pass" = true ]; then
        # Header for detailed view
        printf "%-15s | %-30s | %-20s | %s\n" "Alias" "Target" "Auth" "Extra"
        echo "----------------------------------------------------------------------------------------------------"
    fi

    while IFS='|' read -r alias host user port key pass remote_dir cmd _; do
        # Skip comments or empty lines
        if [[ "$alias" =~ ^# ]] || [ -z "$alias" ]; then continue; fi

        if [ "$show_all" = true ] || [ "$show_pass" = true ]; then
            # Format Target: User@Host:Port
            local target="$user@$host"
            if [ "$port" != "22" ]; then target="$target:$port"; fi

            # Format Auth
            local auth_info="None"
            if [ -n "$key" ]; then
                auth_info="Key: $(basename "$key")"
            elif [ -n "$pass" ]; then
                if [ "$show_pass" = true ]; then
                    auth_info="Pass: $pass"
                else
                    auth_info="Pass: ******"
                fi
            fi

            # Format Extra
            local extra=""
            if [ -n "$remote_dir" ]; then extra="Dir: $remote_dir "; fi
            if [ -n "$cmd" ]; then extra="${extra}Cmd: $cmd"; fi

            printf "%-15s | %-30s | %-20s | %s\n" "$alias" "$target" "$auth_info" "$extra"
        else
            echo "  - $alias ($user@$host)"
        fi
    done < "$CONFIG_FILE"
    echo ""
}

run_tunnels_menu() {
    local options=("Listar túneles activos" "Detener túnel" "Crear túnel local" "Crear túnel reverso" "Volver")
    local selected=0

    while true; do
        clear >&2
        echo "==========================================" >&2
        echo "           TÚNELES SSH" >&2
        echo "==========================================" >&2
        echo "Usa ↑/↓ para moverte, Enter/→ para seleccionar, ←/q para volver." >&2
        echo "------------------------------------------" >&2

        for i in "${!options[@]}"; do
            if [ $i -eq $selected ]; then
                printf " > \e[32m%s\e[0m\n" "${options[$i]}" >&2
            else
                echo "   ${options[$i]}" >&2
            fi
        done
        echo "==========================================" >&2

        read -rsn1 key
        if [[ $key == $'\x1b' ]]; then
            read -rsn2 key
        fi

        case "$key" in
            '[A') # Up
                selected=$(( (selected - 1 + ${#options[@]}) % ${#options[@]} ))
                ;;
            '[B') # Down
                selected=$(( (selected + 1) % ${#options[@]} ))
                ;;
            '[D'|q|Q) # Left or q - Back
                return
                ;;
            ''|'[C') # Enter or Right - Select
                local choice="${options[$selected]}"
                case "$choice" in
                    "Listar túneles activos") list_tunnels; read -p "Presiona Enter para continuar..." ;;
                    "Detener túnel") stop_tunnel; read -p "Presiona Enter para continuar..." ;;
                    "Crear túnel local") 
                        local a; a=$(select_alias "Selecciona conexión para el túnel")
                        if [ $? -ne 0 ] || [ -z "$a" ]; then continue; fi
                        
                        echo "Configurando túnel local (Puerto Local -> Host:Puerto Remoto)"
                        read -p "Puerto Local (tu máquina): " l_port
                        if [ -z "$l_port" ]; then echo "Cancelado."; sleep 1; continue; fi
                        
                        read -p "Host Destino (desde el servidor) [localhost]: " d_host
                        d_host=${d_host:-localhost}
                        
                        read -p "Puerto Destino (en el servidor/red): " d_port
                        if [ -z "$d_port" ]; then echo "Cancelado."; sleep 1; continue; fi
                        
                        run_tunnel "$a" "$l_port:$d_host:$d_port" false true
                        read -p "Presiona Enter para continuar..." 
                        ;;
                    "Crear túnel reverso") 
                        local a; a=$(select_alias "Selecciona conexión para el túnel")
                        if [ $? -ne 0 ] || [ -z "$a" ]; then continue; fi

                        echo "Configurando túnel reverso (Puerto Remoto -> Host:Puerto Local)"
                        read -p "Puerto Remoto (en el servidor): " r_port
                        if [ -z "$r_port" ]; then echo "Cancelado."; sleep 1; continue; fi

                        read -p "Host Local (desde tu máquina) [localhost]: " l_host
                        l_host=${l_host:-localhost}

                        read -p "Puerto Local (tu máquina): " l_port
                        if [ -z "$l_port" ]; then echo "Cancelado."; sleep 1; continue; fi

                        run_tunnel "$a" "$r_port:$l_host:$l_port" true true
                        read -p "Presiona Enter para continuar..." 
                        ;;
                    "Volver") return ;;
                esac
                ;;
        esac
    done
}

run_settings_menu() {
    local options=("Archivo de conexiones" "Archivo de logs (deps)" "Archivo PID túneles" "Actualizar script" "Volver")
    local selected=0

    while true; do
        clear >&2
        echo "==========================================" >&2
        echo "               AJUSTES" >&2
        echo "==========================================" >&2
        echo "Usa ↑/↓ para moverte, Enter/→ para seleccionar, ←/q para volver." >&2
        echo "------------------------------------------" >&2

        for i in "${!options[@]}"; do
            if [ $i -eq $selected ]; then
                printf " > \e[32m%s\e[0m\n" "${options[$i]}" >&2
            else
                echo "   ${options[$i]}" >&2
            fi
        done
        echo "==========================================" >&2

        read -rsn1 key
        if [[ $key == $'\x1b' ]]; then
            read -rsn2 key
        fi

        case "$key" in
            '[A') # Up
                selected=$(( (selected - 1 + ${#options[@]}) % ${#options[@]} ))
                ;;
            '[B') # Down
                selected=$(( (selected + 1) % ${#options[@]} ))
                ;;
            '[D'|q|Q) # Left or q - Back
                return
                ;;
            ''|'[C') # Enter or Right - Select
                local choice="${options[$selected]}"
                case "$choice" in
                    "Archivo de conexiones")
                        echo "Ubicación actual: $CONNECTIONS_PATH"
                        read -p "Nueva ubicación (vacío para cancelar): " new_path
                        if [ -n "$new_path" ]; then
                            # Expand tilde if present
                            new_path="${new_path/#\~/$HOME}"
                            # Update master config
                            if grep -q "CONNECTIONS_PATH=" "$MASTER_CONFIG_FILE"; then
                                sed -i "s|^CONNECTIONS_PATH=.*|CONNECTIONS_PATH=$new_path|" "$MASTER_CONFIG_FILE"
                            else
                                echo "CONNECTIONS_PATH=$new_path" >> "$MASTER_CONFIG_FILE"
                            fi
                            load_config
                            echo "Configuración actualizada."
                            read -p "Presiona Enter para continuar..."
                        fi
                        ;;
                    "Archivo de logs (deps)")
                        echo "Ubicación actual: $DEPS_LOG"
                        read -p "Nueva ubicación (vacío para cancelar): " new_path
                        if [ -n "$new_path" ]; then
                            new_path="${new_path/#\~/$HOME}"
                            if grep -q "DEPS_LOG_PATH=" "$MASTER_CONFIG_FILE"; then
                                sed -i "s|^DEPS_LOG_PATH=.*|DEPS_LOG_PATH=$new_path|" "$MASTER_CONFIG_FILE"
                            else
                                echo "DEPS_LOG_PATH=$new_path" >> "$MASTER_CONFIG_FILE"
                            fi
                            load_config
                            echo "Configuración actualizada."
                            read -p "Presiona Enter para continuar..."
                        fi
                        ;;
                    "Archivo PID túneles")
                        echo "Ubicación actual: $TUNNELS_PID_FILE"
                        read -p "Nueva ubicación (vacío para cancelar): " new_path
                        if [ -n "$new_path" ]; then
                            new_path="${new_path/#\~/$HOME}"
                            if grep -q "TUNNELS_PID_PATH=" "$MASTER_CONFIG_FILE"; then
                                sed -i "s|^TUNNELS_PID_PATH=.*|TUNNELS_PID_PATH=$new_path|" "$MASTER_CONFIG_FILE"
                            else
                                echo "TUNNELS_PID_PATH=$new_path" >> "$MASTER_CONFIG_FILE"
                            fi
                            load_config
                            echo "Configuración actualizada."
                            read -p "Presiona Enter para continuar..."
                        fi
                        ;;
                    "Actualizar script") update_script; read -p "Presiona Enter para continuar..." ;;
                    "Volver") return ;;
                esac
                ;;
        esac
    done
}

run_interactive_menu() {
    local options=("Conectar a un servidor" "Listar conexiones" "Añadir nueva conexión" "Editar conexión" "Eliminar conexión")
    if ! $IS_TERMUX; then options+=("Explorar archivos"); fi
    options+=("Túneles SSH" "Ajustes" "Salir")

    local selected=0
    while true; do
        clear
        echo "=========================================="
        echo "      SSH MANAGER v$VERSION"
        echo "=========================================="
        echo "Usa ↑/↓ para moverte, Enter/→ para seleccionar, ←/q para salir."
        echo "------------------------------------------"

        for i in "${!options[@]}"; do
            if [ $i -eq $selected ]; then
                printf " > \e[32m%s\e[0m\n" "${options[$i]}"
            else
                echo "   ${options[$i]}"
            fi
        done
        echo "=========================================="

        read -rsn1 key
        if [[ $key == $'\x1b' ]]; then
            read -rsn2 key
        fi

        case "$key" in
            '[A') # Up
                selected=$(( (selected - 1 + ${#options[@]}) % ${#options[@]} ))
                ;;
            '[B') # Down
                selected=$(( (selected + 1) % ${#options[@]} ))
                ;;
            '[D'|q|Q) # Left or q - Exit
                exit 0
                ;;
            ''|'[C') # Enter or Right - Select
                local choice="${options[$selected]}"
                case "$choice" in
                    "Conectar a un servidor") connect_to_host ;;
                    "Listar conexiones") list_connections -a; read -p "Presiona Enter para continuar..." ;;
                    "Añadir nueva conexión") if add_connection; then read -p "Presiona Enter para continuar..."; fi ;;
                    "Editar conexión") if edit_connection; then read -p "Presiona Enter para continuar..."; fi ;;
                    "Eliminar conexión") if delete_connection; then read -p "Presiona Enter para continuar..."; fi ;;
                    "Explorar archivos") browse_sftp ;;
                    "Túneles SSH") run_tunnels_menu ;;
                    "Ajustes") run_settings_menu ;;
                    "Salir") exit 0 ;;
                esac
                ;;
        esac
    done
}

# --- PUNTO DE ENTRADA PRINCIPAL ---
main() {
    load_config
    check_base_requirements

    if [ "$#" -gt 0 ]; then
        local COMMAND=$1; shift
        case "$COMMAND" in
            add|-a) add_connection ;;
            edit|-e) edit_connection "$1" "$2" ;;
            list|-l) list_connections "$@" ;;
            connect|-c) connect_to_host "$1" "$2" ;;
            browse|-b) browse_sftp "$1" ;;
            delete|-d) delete_connection "$1" ;;
            update|-u) update_script ;;
            version|-v) show_version ;;
            help|-h) show_usage ;;
            scp|-s) run_scp "$1" "$2" ;;
            tunnel|-t) run_tunnel "$1" "$2" "$3" "$4" ;;
            reverse-tunnel|-rt) run_tunnel "$1" "$2" true "$4" ;;
            list-tunnels|-lt) list_tunnels ;;
            stop-tunnel|-st) stop_tunnel "$1" ;;
            *) 
                # Check if it's an alias directly
                if grep -qE "^${COMMAND}\|" "$CONFIG_FILE"; then
                    connect_to_host "$COMMAND" "$@"
                else
                    echo "Comando desconocido: $COMMAND"
                    show_usage
                    exit 1
                fi
                ;;
        esac
    else
        run_interactive_menu
    fi
}

main "$@"
