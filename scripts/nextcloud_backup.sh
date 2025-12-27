#!/bin/bash
# Updated via GitHub Actions: Test 1
# --- НАЛАШТУВАННЯ ---
BACKUP_DIR="/home/ruban/backups"
DATE=$(date +"%Y-%m-%d_%H-%M")
REMOTE_NAME="gdrive"
REMOTE_FOLDER="Nextcloud_Backups"

# ВАЖЛИВО: Вказуємо шлях до конфіга Rclone користувача ruban
# (Це вирішує проблему з "Config file not found" при запуску через sudo)
RCLONE_CONF="/home/ruban/.config/rclone/rclone.conf"

# Дані бази
CONTAINER_DB="nextcloud_db"
DB_USER="nextcloud"
DB_PASSWORD="YOUR_REAL_PASSWORD_HERE" # <--- ПЕРЕВІРТЕ ПАРОЛЬ!
DB_NAME="nextcloud"

# Шляхи
NC_DATA="/mnt/ssd_storage/nc_data"
# Папка де лежать ваші скрипти (перевірте, чи вони тут)
SCRIPTS_DIR="/home/ruban"

mkdir -p "$BACKUP_DIR/temp_$DATE"

log() {
    echo "[$(date '+%H:%M:%S')] $1"
}

log "=== Початок бекапу ==="
log "INFO: Запуск автоматичного бекапу версії 2.2 (GitHub Deploy)"

# 1. БЕКАП БАЗИ ДАНИХ
log "1. Дамп бази даних..."
if docker exec "$CONTAINER_DB" /usr/bin/mysqldump -u "$DB_USER" --password="$DB_PASSWORD" "$DB_NAME" > "$BACKUP_DIR/temp_$DATE/nextcloud-db.sql"; then
    gzip "$BACKUP_DIR/temp_$DATE/nextcloud-db.sql"
    log "   [OK] База збережена."
else
    log "   [ERROR] Не вдалося зберегти базу! Перевірте пароль."
    exit 1
fi

# 2. БЕКАП КОНФІГІВ
log "2. Копіювання конфігів..."
docker cp nextcloud_app:/var/www/html/config/config.php "$BACKUP_DIR/temp_$DATE/config.php"

# Копіюємо скрипти тільки якщо вони існують (щоб не було помилок)
if [ -f "$SCRIPTS_DIR/nextcloud_sorter.sh" ]; then
    cp "$SCRIPTS_DIR/nextcloud_sorter.sh" "$BACKUP_DIR/temp_$DATE/"
else
    log "   [INFO] nextcloud_sorter.sh не знайдено (пропускаємо)."
fi

if [ -f "$SCRIPTS_DIR/nextcloud_backup.sh" ]; then
    cp "$SCRIPTS_DIR/nextcloud_backup.sh" "$BACKUP_DIR/temp_$DATE/"
fi

# Копіюємо docker-compose (спробуємо знайти в папці nextcloud)
if [ -f "$SCRIPTS_DIR/nextcloud/docker-compose.yml" ]; then
    cp "$SCRIPTS_DIR/nextcloud/docker-compose.yml" "$BACKUP_DIR/temp_$DATE/nc-docker-compose.yml"
fi

# 3. БЕКАП ДОКУМЕНТІВ
log "3. Архівування документів..."
tar -czf "$BACKUP_DIR/temp_$DATE/documents_archive.tar.gz" \
    --exclude="*.mp4" --exclude="*.MOV" --exclude="*.avi" --exclude="*.mkv" \
    --exclude="*.jpg" --exclude="*.jpeg" --exclude="*.png" --exclude="*.heic" \
    --exclude="*.mp3" --exclude="*.wav" \
    -C "$NC_DATA" . >/dev/null 2>&1

# 4. СТВОРЕННЯ АРХІВУ
log "4. Створення фінального архіву..."
cd "$BACKUP_DIR"
FINAL_ARCHIVE="Backup_Server_$DATE.tar.gz"
tar -czf "$FINAL_ARCHIVE" -C "$BACKUP_DIR/temp_$DATE" .
rm -rf "$BACKUP_DIR/temp_$DATE"

# 5. ЗАВАНТАЖЕННЯ (Виправлено для sudo)
log "5. Завантаження на Google Drive..."
# Додаємо прапорець --config, щоб root бачив ваші налаштування
if rclone copy "$BACKUP_DIR/$FINAL_ARCHIVE" "$REMOTE_NAME:$REMOTE_FOLDER" --config "$RCLONE_CONF"; then
    log "   [OK] Успішно завантажено в хмару."
else
    log "   [ERROR] Помилка завантаження! Перевірте інтернет або налаштування Rclone."
    exit 1
fi

# 6. ОЧИЩЕННЯ
log "6. Очищення старих копій..."
find "$BACKUP_DIR" -name "Backup_Server_*.tar.gz" -type f -mtime +3 -delete
rclone delete "$REMOTE_NAME:$REMOTE_FOLDER" --min-age 30d --include "Backup_Server_*.tar.gz" --config "$RCLONE_CONF"

log "=== Бекап успішно завершено! ==="
