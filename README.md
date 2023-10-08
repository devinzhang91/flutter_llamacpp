# flutter_llamacpp
llamacpp with flutter.

- Android is supported.

How to use:
install flutter and dart.
install android sdk and ndk.
install cmake.

pull llamacpp
```bash
git submodule update --init
```

modify android/app/build.gradle
set * YOUR *  ndkVersion
set * YOUR *  CMAKE_C_FLAGS (my setting is -DCMAKE_C_FLAGS=-march=armv8.4a+dotprod)
-DANDROID_PLATFORM must be upper than 23
