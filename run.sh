#!/bin/bash
set -e  # Detener ejecución ante cualquier error
# Ejecución normal (sin debug)
#./script.sh nom_dir_destino  nom_app_default master_password
# O también funciona así:
#export DEBUG=1
#./script.sh nom_dir_destino  nom_app_default master_password
# Activar debug solo si DEBUG=1
if [[ "$DEBUG" == "1" ]]; then
    set -x
fi

if [ -z "$TOKEN" ]; then
    log_error "La variable TOKEN no está definida"
    exit 1
fi

# ============================================
# VARIABLES DE CONFIGURACIÓN
# ============================================
DESTINATION=${1:-odoo-saas}
DEFAULTAPP=${2:-erp}
MASTERPASSWORD=${3:-adminpasswd}
BASE=$(pwd)

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ============================================
# FUNCIONES DE UTILIDAD
# ============================================
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_error() {
    if [ $? -ne 0 ]; then
        log_error "Fallo en el paso: $1"
        exit 1
    fi
}
# ============================================
# CLONAR O ACTUALIZAR REPOSITORIO
# ============================================
if [ ! -d "$DESTINATION" ]; then
    log_info "Clonando repositorio..."
    git clone https://"$TOKEN"@github.com/jrporto2/odoo-18-docker-compose_saas.git "$DESTINATION"
    check_error "Clonado de repositorio"
else
    log_warn "Directorio $DESTINATION ya existe, actualizando..."
    # Uso de subshell () para evitar que un fallo de cd o git rompa el flujo principal
    (cd "$DESTINATION" && git pull) || log_warn "No se pudo actualizar el repositorio, se continuará con la versión local."
fi
# ============================================
# VALIDACIONES INICIALES
# ============================================
# Verificar que Docker está instalado
if ! command -v docker &> /dev/null; then
    log_error "Docker no está instalado"
    exit 1
fi

# Verificar que Docker Compose está disponible
if ! docker compose version &> /dev/null; then
    log_error "Docker Compose no está disponible"
    exit 1
fi


# Verificar que existe docker-compose.yml
if [ ! -f "./$DESTINATION/datadrive/core/docker-compose.yml" ]; then
    log_error "No se encuentra ./$DESTINATION/datadrive/core/docker-compose.yml"
    exit 1
fi

log_info "Iniciando instalación de Odoo SaaS en $BASE/$DESTINATION"

# ============================================
# CONFIGURACIÓN DEL SISTEMA (Linux)
# ============================================
if [[ "$OSTYPE" != "darwin"* ]]; then
    log_info "Configurando límites del sistema..."
    if ! grep -qF "fs.inotify.max_user_watches" /etc/sysctl.conf; then
        echo "fs.inotify.max_user_watches = 524288" | sudo tee -a /etc/sysctl.conf
        sudo sysctl -p
        check_error "Configuración de inotify"
    else
        log_info "inotify ya configurado"
    fi
fi

 
# ============================================
# CREACIÓN DE DIRECTORIOS
# ============================================
log_info "Creando estructura de directorios..."

rm -rf "$BASE/$DESTINATION/.git"
mkdir -p "$BASE/$DESTINATION/datadrive/admin/scripts"
mkdir -p "$BASE/$DESTINATION/datadrive/backup"
mkdir -p "$BASE/$DESTINATION/datadrive/clients"
mkdir -p "$BASE/$DESTINATION/datadrive/core"
mkdir -p "$BASE/$DESTINATION/datadrive/logs"
mkdir -p "$BASE/$DESTINATION/datadrive/nginx"/{certs,conf.d,logs}
mkdir -p "$BASE/$DESTINATION/datadrive/pgadmin/sessions"
mkdir -p "$BASE/$DESTINATION/datadrive/postgres"
mkdir -p "$BASE/$DESTINATION/datadrive/templates/clients"/{addons,data,logs}
check_error "Creación de directorios"

# ============================================
# PERMISOS BASE 
# ============================================
log_info "Configurando permisos base..."

# 1. Permisos del usuario host (solo una vez)
sudo chown -R "$USER":"$USER" "$DESTINATION"
sudo chmod 750 "$DESTINATION"
sudo chmod 750 "$DESTINATION/datadrive"
# 2. Postgres (debe ser antes de cualquier find)
sudo chown -R 999:999 "./$DESTINATION/datadrive/postgres"
sudo chmod 750 "./$DESTINATION/datadrive/postgres"
# 3. Odoo y Nginx (usuario 101)
sudo chown -R 101:101 "./$DESTINATION/datadrive/clients"
sudo chown -R 101:101 "./$DESTINATION/datadrive/templates"
sudo chown -R 101:101 "./$DESTINATION/datadrive/logs"
sudo chmod 755 "./$DESTINATION/datadrive/clients"
sudo chmod 755 "./$DESTINATION/datadrive/templates"
sudo chmod 750 "./$DESTINATION/datadrive/logs"

# 4. pgAdmin
sudo chown -R 5050:5050 "./$DESTINATION/datadrive/pgadmin"
sudo chmod 755 "./$DESTINATION/datadrive/pgadmin"
if [ -d "./$DESTINATION/datadrive/pgadmin/sessions" ]; then
    sudo chmod 770 "./$DESTINATION/datadrive/pgadmin/sessions"
fi

# 5. Admin scripts
sudo chown -R "$USER":"$USER" "./$DESTINATION/datadrive/admin"

sudo chmod 750 "./$DESTINATION/datadrive/admin"
if [ -f "./$DESTINATION/datadrive/admin/scripts/create-client.sh" ]; then
    sudo chmod 700 "./$DESTINATION/datadrive/admin/scripts/create-client.sh"
fi
check_error "Permisos base"

# ============================================
# CERTIFICADOS SSL
# ============================================
log_info "Copiando certificados SSL..."
if [ -f "/etc/ssl/certs/origin_certificate.pem" ]; then
    sudo cp /etc/ssl/certs/origin_certificate.pem "./$DESTINATION/datadrive/nginx/certs/pgadmin.multipath.net.pe.crt"
    sudo cp /etc/ssl/certs/origin_private_key.pem "./$DESTINATION/datadrive/nginx/certs/pgadmin.multipath.net.pe.key"
    check_error "Copia de certificados"
    log_info "Certificados copiados correctamente"
else
    log_warn "Certificados no encontrados.. Creando certificados autofirmados..."
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "./$DESTINATION/datadrive/nginx/certs/pgadmin.multipath.net.pe.key" \
        -out "./$DESTINATION/datadrive/nginx/certs/pgadmin.multipath.net.pe.crt" \
        -subj "/CN=pgadmin.multipath.net.pe"
    check_error "Creación de certificados autofirmados"
fi

# Permisos seguros para certificados
sudo chown -R 101:101 "./$DESTINATION/datadrive/nginx/certs"
sudo chmod 750 "./$DESTINATION/datadrive/nginx/certs"
sudo chmod 600 "./$DESTINATION/datadrive/nginx/certs/"*.key 2>/dev/null || true
sudo chmod 644 "./$DESTINATION/datadrive/nginx/certs/"*.crt 2>/dev/null || true

# ============================================
# PERMISOS GRANULARES POR SERVICIO
# ============================================
log_info "Aplicando permisos específicos por servicio..."

find "./$DESTINATION" -type f -name "*.key" -exec chmod 600 {} \; 2>/dev/null || true
find "./$DESTINATION" -type f -name "*.crt" -exec chmod 644 {} \; 2>/dev/null || true
find "./$DESTINATION" -type f -name "*.conf" -exec chmod 640 {} \; 2>/dev/null || true
find "./$DESTINATION" -type f -name "*.sh" -exec chmod 755 {} \; 2>/dev/null || true

# Nginx (ya tiene permisos, solo ajustamos si es necesario)
if [ -d "./$DESTINATION/datadrive/nginx" ]; then
    sudo chmod 750 "./$DESTINATION/datadrive/nginx"
    sudo chmod 750 "./$DESTINATION/datadrive/nginx/conf.d"
    sudo chmod 750 "./$DESTINATION/datadrive/nginx/logs"
fi

# Clients y backup (ya tienen permisos, solo ajustamos)
if [ -d "./$DESTINATION/datadrive/backup" ]; then
    sudo chmod 750 "./$DESTINATION/datadrive/backup"
fi

check_error "Permisos específicos"

# ============================================
# PREPARACIÓN DE SCRIPTS Y CONFIGURACIÓN
# ============================================
log_info "Preparando scripts de administración..."

if [ -f "./$DESTINATION/entrypoint.sh" ]; then
    sudo chmod +x "./$DESTINATION/entrypoint.sh"
fi

if [ -f "./$DESTINATION/datadrive/admin/scripts/create-client.sh" ]; then
 
    # Se añade validación para no duplicar la sustitución si corres el script más de una vez
    if ! grep -q "\./\$DESTINATION" "./$DESTINATION/datadrive/admin/scripts/create-client.sh"; then
        sed -i "s|DESTINATION|./$DESTINATION|g" "./$DESTINATION/datadrive/admin/scripts/create-client.sh"
        check_error "Configuración de create-client.sh"
    fi
    sudo chmod 700 "./$DESTINATION/datadrive/admin/scripts/create-client.sh"
else
    log_warn "No se encuentra create-client.sh"
fi

if [ -f "./$DESTINATION/datadrive/core/odoo.conf" ]; then
    ESCAPED_PASS=$(printf '%s\n' "$MASTERPASSWORD" | sed 's/[&/\]/\\&/g')
    sed -i "s/adminpasswd/$ESCAPED_PASS/g" "./$DESTINATION/datadrive/core/odoo.conf"
    log_info "Master password configurado en odoo.conf"
else
    log_warn "No se encuentra odoo.conf, puede estar en otra ubicación"
fi
# ============================================
# VERIFICACIÓN DE RECURSOS
# ============================================
log_info "Verificando recursos del sistema..."

# Verificar RAM disponible (mínimo 4GB recomendado)
TOTAL_RAM=$(free -m | awk '/^Mem:/{print $2}')
if [ "$TOTAL_RAM" -lt 4096 ]; then
    log_warn "Memoria RAM baja: ${TOTAL_RAM}MB (recomendado 4096MB para Odoo SaaS)"
fi

# Verificar espacio en disco (mínimo 20GB)

DISK_SPACE=$(df -BG "$BASE" | awk 'NR==2 {print $4}' | sed 's/G//')

if [ "$DISK_SPACE" -lt 20 ]; then
    log_warn "Espacio en disco bajo: ${DISK_SPACE}GB disponible (recomendado 20GB+)"
fi

# ============================================
# INICIO DE CONTENEDORES
# ============================================
log_info "Iniciando contenedores Docker..."

# Detener contenedores previos si existen
docker compose -f "./$DESTINATION/datadrive/core/docker-compose.yml" down 2>/dev/null || true

# Levantar contenedores
docker compose -f "./$DESTINATION/datadrive/core/docker-compose.yml" up -d

check_error "Inicio de contenedores"

# ============================================
# VERIFICACIÓN DE SERVICIOS
# ============================================
log_info "Verificando estado de los servicios..."
sleep 5  # Esperar inicialización

# Verificar que los contenedores están corriendo
CONTAINERS=$(docker compose -f "./$DESTINATION/datadrive/core/docker-compose.yml" ps --services --filter "status=running" | wc -l)

if [ "$CONTAINERS" -lt 3 ]; then
    log_warn "Solo $CONTAINERS contenedores activos (esperado 4+: Odoo, Postgres, Nginx, pgAdmin)"
    docker compose -f "./$DESTINATION/datadrive/core/docker-compose.yml" ps
else
    log_info "Todos los contenedores están activos"
fi

# ============================================
# CREACIÓN DE CLIENTE ERP
# ============================================
if [ -f "./$DESTINATION/datadrive/admin/scripts/create-client.sh" ]; then
    log_info "Creando cliente $DEFAULTAPP..."
    # Pasamos los parámetros limpios evitando problemas de rutas relativas duplicadas
    "./$DESTINATION/datadrive/admin/scripts/create-client.sh" "$DESTINATION" "$DEFAULTAPP"
    check_error "Creación de cliente ERP"
else
    log_error "Archivo: ./$DESTINATION/datadrive/admin/scripts/create-client.sh NO encontrado"
fi

# ============================================
# RESUMEN FINAL
# ============================================
echo ""
echo "=========================================="
echo -e "${GREEN}✅ INSTALACIÓN COMPLETADA${NC}"
echo "=========================================="
echo -e "📍 Odoo URL:       ${GREEN}https://$DEFAULTAPP.multipath.net.pe${NC}"
echo -e "🔑 Master Password: ${GREEN}${MASTERPASSWORD}${NC}"
echo -e "📊 pgAdmin:        ${GREEN}https://pgadmin.multipath.net.pe${NC}"
echo "=========================================="
echo ""
echo "Comandos útiles:"
echo "  Ver logs:    docker compose -f ./$DESTINATION/datadrive/core/docker-compose.yml logs -f"
echo "  Detener:     docker compose -f ./$DESTINATION/datadrive/core/docker-compose.yml down"
echo "  Reiniciar:   docker compose -f ./$DESTINATION/datadrive/core/docker-compose.yml restart"
echo "=========================================="

# ============================================
# HEALTH CHECK
# ============================================
log_info "Realizando health check..."
sleep 10
if curl -s -o /dev/null -w "%{http_code}" "https://$DEFAULTAPP.multipath.net.pe" | grep -q "200\|301\|302"; then
    log_info "Health check: Odoo responde correctamente ✅"
else
    log_warn "Health check: Odoo no responde mediante HTTPS público, revisa los logs."
    # Si falla, intentamos revisar el contenedor principal de Odoo en la ruta Core
    docker compose -f "./$DESTINATION/datadrive/core/docker-compose.yml" logs --tail=50 2>/dev/null || true
fi
