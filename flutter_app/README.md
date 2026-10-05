# Flutter client

This is the Flutter portion of the Smart Queue Management System.

## Create platform folders

Flutter is not installed in the repository workspace used to prepare this code. On a machine with Flutter installed, from this directory run:

```bash
flutter create .
flutter pub get
```

If `flutter create .` asks whether to overwrite `pubspec.yaml`, keep this project's `pubspec.yaml` and replace only generated platform files if necessary.

## Run against the backend

Start the backend first. For an Android emulator:

```bash
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000/api
```

For an iOS simulator:

```bash
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:3000/api
```

For a physical phone, replace the host with the development computer's LAN IP address and ensure the phone and computer are on the same network.

The app intentionally keeps the JWT in memory to avoid adding a storage package to this class project. Logging out or restarting the app requires logging in again.
