python tools/bootstrap_client.py
cd client
flutter build windows --release
docker compose build --no-cache music-service
PAUSE