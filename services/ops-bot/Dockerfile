# Використовуємо легку версію Python
FROM python:3.10-slim

# Робоча папка всередині контейнера
WORKDIR /app

# Копіюємо список бібліотек і встановлюємо їх
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Копіюємо сам код бота
COPY main.py .

# Команда запуску
CMD ["python", "main.py"]