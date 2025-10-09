# SSH Manager (Versión Python)

Un gestor de conexiones SSH moderno y potente escrito en Python. Te permite guardar, gestionar y conectar a tus servidores de forma rápida y eficiente, todo desde una interfaz de terminal hermosa y robusta.

## ✨ Características

- **Interfaz Moderna**: Menús y tablas claras y coloridas gracias a la librería `rich`.
- **Gestión de Conexiones**: Añade, edita, lista y elimina conexiones SSH fácilmente.
- **Configuración Robusta**: Utiliza el formato YAML para guardar las conexiones, más legible y potente que el texto plano.
- **Atajos Inteligentes**: Conéctate a tus servidores usando un alias corto (ej: `sshm mi-servidor`).
- **Seguridad Opcional**: Guarda contraseñas encriptadas con una palabra clave usando OpenSSL.
- **...y todas las demás funcionalidades** que ya conoces, como comandos remotos, `scp`, túneles, auto-actualización, etc.

## 🚀 Instalación

**Requisitos**: `python3` y `pip3`.

El nuevo instalador se encarga de todo, incluyendo la creación de un entorno virtual para no afectar las librerías de tu sistema.

```bash
curl -fsSL [https://raw.githubusercontent.com/octaviocubillos/ssh-manage/master/install.sh](https://raw.githubusercontent.com/octaviocubillos/ssh-manage/master/install.sh) | sudo bash
```

## 💻 Uso

El uso es idéntico a la versión anterior. Puedes llamarlo con `ssh-manage` o el atajo `sshm`.

```bash
# Entrar al modo interactivo (muestra la ayuda en esta versión)
sshm

# Listar todas las conexiones
sshm list

# Conectar a un servidor
sshm connect mi-servidor

