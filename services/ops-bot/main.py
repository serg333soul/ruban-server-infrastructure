import logging
import os
import psutil
from telegram import Update
from telegram.ext import ApplicationBuilder, ContextTypes, CommandHandler

# Налаштування логування
logging.basicConfig(
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    level=logging.INFO
)

# Отримуємо змінні (Docker візьме їх з файлу telegram.env)
TOKEN = os.getenv("TELEGRAM_BOT_TOKEN")
ADMIN_ID = os.getenv("TELEGRAM_CHAT_ID") # Додали цю змінну

# Перевірка безпеки (Декоратор)
# Ця функція перевіряє, чи пише адміністратор
def restricted(func):
    async def wrapped(update: Update, context: ContextTypes.DEFAULT_TYPE, *args, **kwargs):
        user_id = update.effective_user.id
        # Якщо ADMIN_ID заданий і ID юзера не співпадає — ігноруємо
        if ADMIN_ID and str(user_id) != str(ADMIN_ID):
            print(f"Unauthorized access attempt from {user_id}")
            return
        return await func(update, context, *args, **kwargs)
    return wrapped

@restricted
async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await context.bot.send_message(
        chat_id=update.effective_chat.id,
        text="👋 Привіт! Я Ruban OpsBot. Я слідкую за твоїм сервером.\nСпробуй команду /status"
    )

@restricted
async def status(update: Update, context: ContextTypes.DEFAULT_TYPE):
    cpu_usage = psutil.cpu_percent(interval=1)
    ram = psutil.virtual_memory()
    disk = psutil.disk_usage('/')
    
    msg = (
        f"🖥 <b>Server Status:</b>\n\n"
        f"🧠 <b>CPU:</b> {cpu_usage}%\n"
        f"💾 <b>RAM:</b> {ram.percent}% ({round(ram.used / 1024**3, 1)}GB / {round(ram.total / 1024**3, 1)}GB)\n"
        f"💿 <b>Disk:</b> {disk.percent}% ({round(disk.free / 1024**3, 1)}GB free)"
    )
    
    await context.bot.send_message(
        chat_id=update.effective_chat.id,
        text=msg,
        parse_mode='HTML'
    )

if __name__ == '__main__':
    if not TOKEN:
        print("Error: TELEGRAM_BOT_TOKEN not found!")
        exit(1)

    application = ApplicationBuilder().token(TOKEN).build()
    
    application.add_handler(CommandHandler('start', start))
    application.add_handler(CommandHandler('status', status))
    
    print("Bot started...")
    application.run_polling()