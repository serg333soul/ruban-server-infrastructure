#!/bin/bash

# --- 1. БЕЗПЕКА ТА НАЛАШТУВАННЯ (Error Handling) ---
set -euo pipefail

# Перевірка на запуск від root
if [[ $EUID -ne 0 ]]; then
   echo "Цей скрипт потрібно запускати з sudo!" 
   exit 1
fi

# -e: зупинити скрипт при будь-якій помилці
# -u: вважати використання невизначених змінних помилкою
# -o pipefail: якщо падає частина пайплайну, падає весь скрипт

# --- 2. КОНФІГУРАЦІЯ ---
LOG_FILE="/var/log/nc_sorter.log"
LOCK_FILE="/tmp/nc_sorter.lock"
#LOCK_FILE="/var/lock/nc_sorter.lock"
DATA_PATH="/mnt/ssd_storage/nc_data"
NC_USER="admin"
CONTAINER_NAME="nextcloud_app"

# Кореневі папки
BASE_DIR="$DATA_PATH/$NC_USER/files"
INBOX="$BASE_DIR/Inbox"

# Асоціативний масив: "Папка" -> "Розширення"
declare -A RULES=(
    ["Photo"]="jpg jpeg png heic webp gif bmp raw cr2 nef"
    ["Video"]="mp4 mov avi mkv wmv flv webm"
    ["Audio"]="mp3 wav m4a flac aac ogg"
    ["Documents"]="pdf doc docx txt xls xlsx ppt pptx epub"
)

# --- 3. ФУНКЦІЇ (Modular Structure) ---

# Функція логування
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# --- 4. ПЕРЕВІРКА БЛОКУВАННЯ (Singleton Pattern) ---
exec 200>"$LOCK_FILE"
flock -n 200 || { log "Скрипт вже виконується. Пропускаємо запуск."; exit 1; }

# --- 5. ОСНОВНА ЛОГІКА ---

# Перевірка наявності папки Inbox
if [ ! -d "$INBOX" ]; then
    log "УВАГА: Папка Inbox не знайдена ($INBOX). Створення..."
    mkdir -p "$INBOX"
    chown 33:33 "$INBOX"
fi

CHANGES_DETECTED=0

log "Початок сортування..."

for TARGET_FOLDER in "${!RULES[@]}"; do
    EXTENSIONS="${RULES[$TARGET_FOLDER]}"
    FULL_TARGET_PATH="$BASE_DIR/$TARGET_FOLDER"

    # 5.1. Перевірка існування цільової папки
    if [ ! -d "$FULL_TARGET_PATH" ]; then
        mkdir -p "$FULL_TARGET_PATH"
        # Одразу ставимо правильні права для папки
        chown 33:33 "$FULL_TARGET_PATH"
        log "Створено директорію: $TARGET_FOLDER"
    fi

    # 5.2. Формування аргументів для find (оптимізовано)
    # Створюємо рядок типу: -iname "*.jpg" -o -iname "*.png" ...
    FIND_ARGS=()
    FIRST=1
    for ext in $EXTENSIONS; do
        if [ $FIRST -eq 0 ]; then
            FIND_ARGS+=("-o")
        fi
        FIND_ARGS+=("-iname" "*.$ext")
        FIRST=0
    done

    # 5.3. Пошук і переміщення
    # Використовуємо Process Substitution для підрахунку переміщених файлів
    MOVED_COUNT=0
    
    # Знаходимо файли і переміщуємо їх
    while IFS= read -r file; do
        # 1. Ігноруємо .part файли (недокачані)
        if [[ "$file" == *.part ]]; then
             continue
        fi

        # 2. Пробуємо перемістити. 
        # Конструкція "if mv ...; then ... else ... fi" не дасть спрацювати set -e, 
        # бо помилка оброблена всередині умови.
        if mv "$file" "$FULL_TARGET_PATH/"; then
            log "Переміщено: $(basename "$file") -> $TARGET_FOLDER"
            MOVED_COUNT=$((MOVED_COUNT + 1))
            CHANGES_DETECTED=1
        else
            log "ПОМИЛКА: Не вдалося перемістити $file. Пропускаємо."
            # Тут ми НЕ виходимо, скрипт піде до наступного файлу
        fi
    done < <(find "$INBOX" -maxdepth 1 -type f \( "${FIND_ARGS[@]}" \) -print)
done

# --- 6. ФІНАЛІЗАЦІЯ (Idempotency & Optimization) ---

if [ $CHANGES_DETECTED -eq 1 ]; then
    log "Зміни виявлено. Виконуємо post-processing..."

    # 6.1. Оптимізований chown (тільки для файлів, що не належать www-data)
    # Шукаємо в цільових папках файли, власник яких НЕ 33 (www-data)
    find "$BASE_DIR" -type f ! -user 33 -exec chown 33:33 {} +
    log "Права доступу виправлено."

    # 6.2. Сканування бази (один раз на весь профіль користувача)
    log "Оновлення бази даних Nextcloud..."
    
    # Запускаємо команду, перенаправляємо помилки (stderr) в стандартний вивід (stdout),
    # щоб записати все у змінну. "|| true" гарантує, що скрипт не впаде через set -e.
    SCAN_OUTPUT=$(docker exec -u 33 "$CONTAINER_NAME" php occ files:scan --path="/$NC_USER/files" 2>&1) || true
    
    # Перевіряємо, чи в тексті виводу є слово "Errors" з ненульовим значенням або інші ознаки біди,
    # АБО просто дивимось на код повернення (але через || true код завжди 0, тому дивимось на текст).
    
    # Простіший варіант перевірки успіху:
    if [[ "$SCAN_OUTPUT" == *"Starting scan"* ]]; then
        log "Результат сканування:"
        # Виводимо в лог тільки табличку або важливі рядки, щоб не смітити
        echo "$SCAN_OUTPUT" | grep -E "Folders|\| [0-9]" | tee -a "$LOG_FILE"
    else
        log "⚠️ УВАГА: Можлива помилка при скануванні. Деталі:"
        log "$SCAN_OUTPUT"
    fi
else
    log "Нових файлів не знайдено. Спимо..."
fi

log "Роботу завершено."
exit 0
