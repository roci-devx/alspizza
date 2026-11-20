# Al's Driver

Al's Driver — the in-house drivers' app as a native Android & iOS app (screens live in package:als/driver).

```
cd driver_app
flutter run                                                        # debug on a connected phone/tablet
flutter build apk --release --dart-define=API_URL=https://alspizza-api.rocidevs.com.et
```

Icons and splash: `dart run flutter_launcher_icons && dart run flutter_native_splash:create`.
