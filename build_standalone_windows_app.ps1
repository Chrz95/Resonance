python tools/bootstrap_client.py
cd client
flutter analyze --no-fatal-infos
flutter test
flutter build windows --release
PAUSE