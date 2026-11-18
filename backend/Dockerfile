FROM python:3.12-slim
WORKDIR /srv
COPY backend/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY backend/ ./backend/
COPY content/build/ ./content/build/
WORKDIR /srv/backend
ENV CONTENT_DIR=/srv/content/build
EXPOSE 8000
# Migrate, load course content, then serve. Hosts such as Render set PORT.
CMD ["sh", "-c", "python -m alembic upgrade head && python -m app.seed && uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}"]
