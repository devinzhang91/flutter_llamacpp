import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui';

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'dart:ffi' as ffi;
import 'dart:convert' show utf8;
import 'dart:io' show Platform;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:file_picker/file_picker.dart';

typedef HelloFuncNative = ffi.Pointer<Utf8> Function();
typedef HelloFunc = ffi.Pointer<Utf8> Function();

// cpp function: int llamacpp_init(char* model_path);
typedef LlamacppInitFuncNative = ffi.Int Function( ffi.Pointer<Utf8>);
typedef LlamacppInitFunc = int Function(ffi.Pointer<Utf8>);
// cpp function: int llamacpp_generate(char* prompt, char* output);
typedef CallbackType = ffi.Int32 Function(ffi.Pointer<Utf8>, ffi.Int32);
typedef LlamacppGenerateFuncNative = ffi.Int Function( ffi.Pointer<Utf8>, ffi.Int, ffi.Pointer<Utf8>, ffi.Int, ffi.Pointer<ffi.NativeFunction<CallbackType>>);
typedef LlamacppGenerateFunc = int Function(ffi.Pointer<Utf8>, int, ffi.Pointer<Utf8>, int, ffi.Pointer<ffi.NativeFunction<CallbackType>>);
// cpp function: int llamacpp_deinit();
typedef LlamacppDeinitFuncNative = ffi.Int Function();
typedef LlamacppDeinitFunc = int Function();

class _GenerateIsolateArgs {
  final String prompt;
  final SendPort sendPort;

  _GenerateIsolateArgs(this.prompt, this.sendPort);
}

class llamacpp_native{
  
  static final dylib = ffi.DynamicLibrary.open(
    'libllamacpp${Platform.isWindows ? '.dll' : '.so'}',
  );

  static void test_native() {
    final dl_hello = dylib.lookupFunction<HelloFuncNative, HelloFunc >('getHello');
    var hello_buff = dl_hello();
    print(hello_buff);
    // free the memory allocated in C
    malloc.free(hello_buff);
  }

  static final dl_llamacpp_init = dylib.lookupFunction<LlamacppInitFuncNative, LlamacppInitFunc >('llamacpp_init');
  static final dl_llamacpp_generate = dylib.lookupFunction<LlamacppGenerateFuncNative, LlamacppGenerateFunc >('llamacpp_generate');
  static final dl_llamacpp_deinit = dylib.lookupFunction<LlamacppDeinitFuncNative, LlamacppDeinitFunc >('llamacpp_deinit');

  Future<String?> pickGGUFFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      // allowedExtensions: ['gguf'],
    );
    if (result == null) {
      // 用户取消了选择
      return null;
    }
    return result.files.single.path;
  }

  Future<int> modelInit() async {
    // final filePath = "/data/user/0/com.example.flutter_llamacpp_android/cache/file_picker/ggml-model-f16_q4_0.gguf";
    final filePath = await pickGGUFFile();
    if (filePath != null) {
      print('Selected file: $filePath');
    } else {
      print('No file selected.');
      return -1;
    }
    
    //第1步: 默认执行环境下是rootIsolate，所以创建的是一个rootIsolateReceivePort
    ReceivePort rootIsolateReceivePort = ReceivePort();
    //第2步: 获取rootIsolateSendPort
    SendPort rootIsolateSendPort = rootIsolateReceivePort.sendPort;
    Isolate newIsolate = await Isolate.spawn(_initIsolateEntryPoint, _GenerateIsolateArgs(filePath.toString(), rootIsolateSendPort));
    final message = await rootIsolateReceivePort.first;
    print('Received message: $message[1]');
    return message[0];
  }

  Future<int> modelDeinit() async{
    //第1步: 默认执行环境下是rootIsolate，所以创建的是一个rootIsolateReceivePort
    ReceivePort rootIsolateReceivePort = ReceivePort();
    //第2步: 获取rootIsolateSendPort
    SendPort rootIsolateSendPort = rootIsolateReceivePort.sendPort;
    Isolate newIsolate = await Isolate.spawn(_deinitIsolateEntryPoint, _GenerateIsolateArgs('', rootIsolateSendPort)); 
    final message = await rootIsolateReceivePort.first;
    print('Received message: $message[1]');
    return message[0];
  }

  Future<void> modelGenerate(String prompt, Function callback) async {

    Completer<void> completer = Completer<void>();
    //第1步: 默认执行环境下是rootIsolate，所以创建的是一个rootIsolateReceivePort
    ReceivePort rootIsolateReceivePort = ReceivePort();
    //第2步: 获取rootIsolateSendPort
    SendPort rootIsolateSendPort = rootIsolateReceivePort.sendPort;

    // 监听 rootIsolateReceivePort 的消息
    final stream = rootIsolateReceivePort.asBroadcastStream();
    // 订阅消息
    StreamSubscription subscription = stream.listen((message) {
      if(message[0]>0){
        final text = message[1];
        print('Received message: $text');
        callback(text);
      } else {
        print('_generateIsolateEntryPoint done.');
        completer.complete();
      }
    });

    //第3步: 创建一个newIsolate实例，并把rootIsolateSendPort作为参数传入到newIsolate中，为的是让newIsolate中持有rootIsolateSendPort, 这样在newIsolate中就能向rootIsolate发送消息了
    Isolate newIsolate = await Isolate.spawn(_generateIsolateEntryPoint, _GenerateIsolateArgs(prompt, rootIsolateSendPort)); // 在新线程中执行_generateIsolateEntryPoint函数，并将参数传递给新线程
    // 等待新线程执行完毕
    await completer.future;
    // 取消订阅
    subscription.cancel();
    
  }

  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  //特别需要注意:__rootIsolateSendPort 和 __newIsolateSendPort 是在newIsolate中创建的，所以这两个变量的执行环境就是newIsolate
  static late SendPort __rootIsolateSendPort;
  static late SendPort __newIsolateSendPort;

  static int _flushCallback(ffi.Pointer<Utf8> strBuff, int i) {
    // print('in callback ' + i.toString() + ' str_buff: ' + strBuff.toDartString());
    __rootIsolateSendPort.send([i ,strBuff.toDartString()]);
    return 0;
  }

  void _initIsolateEntryPoint(_GenerateIsolateArgs args) async {
    final ret = dl_llamacpp_init(args.prompt.toNativeUtf8());
    if (ret != 0) {
      print('llamacpp_init failed');
      args.sendPort.send([ret, 'llamacpp_init failed']);
    } else {
      print('llamacpp_init success');
      args.sendPort.send([ret, 'llamacpp_init success']);
    }
  }

  void _deinitIsolateEntryPoint(_GenerateIsolateArgs args) async {
    final ret = dl_llamacpp_deinit();
    if (ret != 0) {
      print('llamacpp_deinit failed');
      args.sendPort.send([ret, 'llamacpp_deinit failed']);
    } else {
      print('llamacpp_deinit success');
      args.sendPort.send([ret, 'llamacpp_deinit success']);
    }
  }

  void _generateIsolateEntryPoint(_GenerateIsolateArgs args) async {
    //第4步: 注意callback这个函数执行环境就会变为newIsolate, 所以创建的是一个newIsolateReceivePort
    ReceivePort newIsolateReceivePort = ReceivePort();
    //第5步: 获取newIsolateSendPort, 有人可能疑问这里为啥不是直接让全局newIsolateSendPort赋值，注意这里执行环境不是rootIsolate
    __rootIsolateSendPort = args.sendPort;
    __newIsolateSendPort = newIsolateReceivePort.sendPort;
    
    final output = malloc.allocate<Utf8>(256);
    final output_len = dl_llamacpp_generate(args.prompt.toNativeUtf8(), args.prompt.length, output, 32, ffi.Pointer.fromFunction(_flushCallback, 0));
    final output_str = output.toDartString();
    malloc.free(output);
    // 发送消息给rootIsolate， 表示newIsolate执行完毕
    __rootIsolateSendPort.send([0 , '']);
  }
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

}