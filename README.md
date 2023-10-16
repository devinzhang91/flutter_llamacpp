# flutter_llamacpp
llamacpp with flutter.

- Android is supported.

## How to use:
- install flutter and dart.
- install android sdk and ndk.
- install cmake.
- pull llamacpp
```bash
git submodule update --init
```

### Modify android/app/build.gradle
- set ** YOUR **  ndkVersion
- set ** YOUR **  CMAKE_C_FLAGS (my setting is -DCMAKE_C_FLAGS=-march=armv8.4a+dotprod)
- -DANDROID_PLATFORM must be upper than 23

### Build
build project with release mode, debug mode runs slowly.
```bash
flutter build apk
```
you can get apk file in build/app/outputs/flutter-apk/app-release.apk
or 
```bash
flutter run --release
``` 