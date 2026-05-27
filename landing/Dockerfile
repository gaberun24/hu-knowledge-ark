FROM python:3.13-slim

# A futtató user gyökerét és a /data mountot különválasztjuk,
# a UID/GID-et a docker-compose adja a `user:` direktívával futás közben.

WORKDIR /app

# Függőségek
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Az alkalmazás
COPY app.py .
COPY templates/ ./templates/
COPY static/ ./static/

ENV FLASK_APP=app.py
ENV PYTHONUNBUFFERED=1
ENV TZ=Europe/Budapest

EXPOSE 5000

# Production WSGI server (waitress, Python-only, nincs natív lib)
CMD ["python", "-m", "waitress", "--host=0.0.0.0", "--port=5000", "app:app"]
