FROM ghcr.io/cirruslabs/flutter:3.27.1 AS frontend
WORKDIR /app/frontend
COPY frontend/pubspec.yaml frontend/pubspec.lock ./
RUN flutter pub get
COPY frontend/ ./
RUN flutter build web --release --pwa-strategy=none

FROM python:3.12-slim
WORKDIR /app
COPY backend/requirements.lock ./backend/requirements.lock
RUN pip install --no-cache-dir -r backend/requirements.lock
COPY backend/ ./backend/
COPY alembic.ini ./
COPY --from=frontend /app/frontend/build/web ./frontend/build/web
RUN useradd --create-home gateway && chown -R gateway:gateway /app
USER gateway
EXPOSE 8000
CMD ["sh", "-c", "alembic upgrade head && uvicorn backend.app.main:app --host 0.0.0.0 --port 8000"]
