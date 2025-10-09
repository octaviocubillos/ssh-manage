#!/usr/bin/env python3
# ==============================================================================
#                 GESTOR DE CONEXIONES SSH v7.0 (Python)
# ==============================================================================

import os
import sys
import subprocess
import shlex
from pathlib import Path
import yaml
from rich.console import Console
from rich.table import Table
from rich.prompt import Prompt, Confirm, IntPrompt

# --- CONFIGURACIÓN ---
VERSION = "7.0-python"
CONFIG_DIR = Path.home() / ".config" / "ssh-manager"
CONNECTIONS_FILE = CONFIG_DIR / "connections.yml"
console = Console()

# --- FUNCIONES AUXILIARES ---

def ensure_config_files():
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    CONNECTIONS_FILE.touch()

def load_connections():
    if not CONNECTIONS_FILE.exists() or CONNECTIONS_FILE.read_text().strip() == "":
        return {}
    with open(CONNECTIONS_FILE, 'r') as f:
        try:
            return yaml.safe_load(f) or {}
        except yaml.YAMLError:
            return {}

def save_connections(connections):
    with open(CONNECTIONS_FILE, 'w') as f:
        yaml.dump(connections, f, indent=2, default_flow_style=False)

def get_decrypted_pass(password):
    if not password or not password.startswith("enc:"):
        return password
    
    keyword = Prompt.ask("[yellow]Palabra clave para desencriptar", password=True)
    encrypted_data = password.replace("enc:", "", 1)
    command = f"echo '{encrypted_data}' | openssl enc -aes-256-cbc -a -d -salt -pbkdf2 -pass pass:'{keyword}' 2>/dev/null"
    try:
        proc = subprocess.run(command, shell=True, text=True, capture_output=True, check=True)
        decrypted_pass = proc.stdout.strip()
        if not decrypted_pass:
            console.print("[bold red]Error: Falló la desencriptación. Palabra clave incorrecta o datos corruptos.[/bold red]")
            return None
        return decrypted_pass
    except subprocess.CalledProcessError:
        console.print("[bold red]Error al ejecutar OpenSSL o palabra clave incorrecta.[/bold red]")
        return None

def select_alias(prompt_text):
    connections = load_connections()
    aliases = list(connections.keys())
    if not aliases:
        console.print("[bold red]No hay conexiones guardadas. Usa 'sshm add' para añadir una.[/bold red]")
        return None

    table = Table(title=f"Selecciona la conexión para {prompt_text}")
    table.add_column("Índice", style="cyan")
    table.add_column("Alias", style="magenta")
    table.add_column("Detalles", style="green")

    for i, alias in enumerate(aliases):
        conn = connections[alias]
        table.add_row(str(i + 1), alias, f"{conn.get('user', 'N/A')}@{conn.get('host', 'N/A')}")
    
    console.print(table)
    idx = IntPrompt.ask("Elige un número de índice", choices=[str(i+1) for i in range(len(aliases))], show_choices=False)
    return aliases[idx - 1]

# --- FUNCIONES PRINCIPALES ---

def add_connection(args):
    console.print("[bold cyan]Añadiendo una nueva conexión...[/bold cyan]")
    connections = load_connections()
    
    while True:
        alias = Prompt.ask("Alias (nombre corto)")
        if not alias: console.print("[red]El alias no puede estar vacío.[/red]"); continue
        if alias in connections: console.print(f"[red]El alias '{alias}' ya existe.[/red]"); continue
        break

    host = Prompt.ask("Host (IP o dominio)")
    user = Prompt.ask("Usuario", default=os.getlogin())
    port = IntPrompt.ask("Puerto", default=22)
    
    key_path = ""; password = ""
    auth_choice = Prompt.ask(
        "\nTipo de autenticación:\n1) Clave SSH\n2) Contraseña (texto plano)\n3) Contraseña Encriptada\n4) Ninguna",
        choices=["1", "2", "3", "4"], default="1"
    )
    
    if auth_choice == '1': key_path = Prompt.ask("Ruta a la clave privada (ej: ~/.ssh/id_rsa)")
    elif auth_choice == '2': password = Prompt.ask("Contraseña", password=True)
    elif auth_choice == '3':
        keyword = Prompt.ask("Palabra clave para encriptar", password=True)
        pass_to_encrypt = Prompt.ask("Contraseña a encriptar", password=True)
        command = f"echo '{pass_to_encrypt}' | openssl enc -aes-256-cbc -a -salt -pbkdf2 -pass pass:'{keyword}'"
        encrypted_pass = subprocess.check_output(command, shell=True, text=True).strip()
        password = f"enc:{encrypted_pass}"
    
    remote_dir = Prompt.ask("Directorio remoto (opcional)")
    default_cmd = Prompt.ask("Comando por defecto (opcional)")
    
    connections[alias] = {
        'host': host, 'user': user, 'port': port,
        'key': key_path, 'pass': password, 'dir': remote_dir, 'cmd': default_cmd
    }
    save_connections(connections)
    console.print(f"[bold green]¡Conexión '{alias}' añadida con éxito![/bold green]")

def list_connections(args):
    connections = load_connections()
    if not connections: console.print("[yellow]No hay conexiones guardadas.[/yellow]"); return

    table = Table(title="Conexiones Guardadas")
    table.add_column("Alias", style="cyan", no_wrap=True); table.add_column("Host", style="magenta"); table.add_column("Usuario", style="green")
    if args.all:
        table.add_column("Puerto", justify="right", style="yellow"); table.add_column("Auth", style="blue"); table.add_column("Directorio", style="white"); table.add_column("Comando", style="red")

    for alias, conn in connections.items():
        auth_method = "Ninguno";
        if conn.get('key'): auth_method = "Clave SSH"
        elif conn.get('pass'): auth_method = "Encriptada" if conn['pass'].startswith("enc:") else "Texto Plano"
        if args.all: table.add_row(alias, conn.get('host'), conn.get('user'), str(conn.get('port')), auth_method, conn.get('dir'), conn.get('cmd'))
        else: table.add_row(alias, conn.get('host'), conn.get('user'))
    console.print(table)

def connect_to_host(args):
    alias = args.alias or select_alias("conectar")
    if not alias: return

    connections = load_connections()
    conn = connections.get(alias)
    if not conn: console.print(f"[bold red]Error: Alias '{alias}' no encontrado.[/bold red]"); return
        
    password = get_decrypted_pass(conn.get('pass'))
    if password is None: return

    command_to_run = ' '.join(args.command) or conn.get('cmd')
    
    final_command = command_to_run
    if conn.get('dir'):
        if final_command: final_command = f"cd \"{conn['dir']}\" && {final_command}"
        else: final_command = f"cd \"{conn['dir']}\" && exec $SHELL -l"
    
    ssh_cmd_list = ["ssh"]
    if final_command: ssh_cmd_list.append("-t")
    if conn.get('key'): ssh_cmd_list.extend(["-i", conn['key']])
    
    ssh_cmd_list.extend(["-p", str(conn.get('port', 22)), f"{conn.get('user')}@{conn.get('host')}"])
    if final_command: ssh_cmd_list.append(final_command)

    console.print(f"Conectando a [green]{conn.get('user')}@{conn.get('host')}[/green]...")

    try:
        if password:
            # sshpass no es ideal, pero es la forma más directa
            full_cmd_list = ["sshpass", "-p", password] + ssh_cmd_list
            subprocess.run(full_cmd_list, check=True)
        else:
            subprocess.run(ssh_cmd_list, check=True)
    except FileNotFoundError:
        console.print("[bold red]Error: 'ssh' o 'sshpass' no están instalados o no se encuentran en tu PATH.[/bold red]")
    except subprocess.CalledProcessError as e:
        console.print(f"[red]La conexión SSH finalizó con un error (código {e.returncode}).[/red]")

def main():
    import argparse
    parser = argparse.ArgumentParser(description=f"Gestor de Conexiones SSH v{VERSION} (Python)")
    
    subparsers = parser.add_subparsers(dest='command', help='Comandos disponibles')

    add_p = subparsers.add_parser('add', aliases=['-a'], help='Añade una nueva conexión.')
    add_p.set_defaults(func=add_connection)

    list_p = subparsers.add_parser('list', aliases=['-l'], help='Lista las conexiones.')
    list_p.add_argument('-a', '--all', action='store_true', help='Muestra todos los detalles.')
    list_p.set_defaults(func=list_connections)

    connect_p = subparsers.add_parser('connect', aliases=['-c'], help='Conecta a un servidor.')
    connect_p.add_argument('alias', nargs='?', help='Alias de la conexión.')
    connect_p.add_argument('command', nargs=argparse.REMAINDER, help='Comando a ejecutar en el servidor.')
    connect_p.set_defaults(func=connect_to_host)

    # ... Aquí se añadirían los parsers para los demás comandos (edit, delete, etc.)

    # Lógica para manejar atajos de alias (ej: sshm mi-servidor)
    if len(sys.argv) > 1 and sys.argv[1] not in [cmd for p in subparsers.choices.values() for cmd in [p.prog.split(' ')[-1]] + p.aliases] + ['-h', '--help']:
        connections = load_connections()
        if sys.argv[1] in connections:
            # Es un atajo de alias
            args = parser.parse_args(['connect'] + sys.argv[1:])
        else:
            parser.print_help()
            sys.exit(f"\nError: Comando o alias '{sys.argv[1]}' no reconocido.")
    else:
        args = parser.parse_args()
    
    ensure_config_files()

    if 'func' in args:
        args.func(args)
    elif not args.command:
        # Modo interactivo
        # Aquí se implementaría el menú con rich
        console.print("[bold yellow]Modo Interactivo no implementado en esta versión. Usa los comandos:[/bold yellow]")
        parser.print_help()
    else:
        parser.print_help()

if __name__ == "__main__":
    main()
