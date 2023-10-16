import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';
import 'dart:ffi' as ffi;
import 'dart:convert' show utf8;
import 'dart:io' show Platform;

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'native_interface.dart';
import 'gpt_params_dialog.dart';

void main() {

  runApp(const MyApp());
  llamacpp_native.test_native();
}

class ChatMessage extends StatelessWidget {
  final String role;
  final String text;

  const ChatMessage({Key? key, required this.role, required this.text})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    requestManageExternalStoragePermission();
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const ChatRoom(title: 'Flutter Demo Home Page'),
    );
  }
  
}

class ChatRoom extends StatefulWidget {
  final String title;
  const ChatRoom({super.key, required this.title});

  @override
  State<ChatRoom> createState() => _ChatRoomState();

}

class _ChatRoomState extends State<ChatRoom> with WidgetsBindingObserver {
  final TextEditingController _textController = TextEditingController();
  final List<ChatMessage> _messages = <ChatMessage>[];
  bool _isSubmitButtonDisabled = false;
  bool _isModelLoaded = false;
  int _maxToken = 64;

  void _flushModelGenerateCallback(String text) {
    setState(() {
      print('_flush_model_generate_callback:' + text);
      _messages.first = ChatMessage(role: _messages.first.role, text: text);
    });
  }

  void _handleSubmitted(String text) async {
    _textController.clear();
    setState(() {
      _isSubmitButtonDisabled = true;
      _messages.insert(0, ChatMessage(role: 'user', text: text));
      _messages.insert(0, const ChatMessage(role: 'bot', text: ''));
      print('_messages insert done');
    });
    await llamacpp_native().modelGenerate(text, _maxToken, _flushModelGenerateCallback);
    print('model_generate done');
    setState(() {
      _isSubmitButtonDisabled = false;
    });
  }

  Widget _buildTextComposer() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Row(
        children: 
          _isModelLoaded?
            <Widget>[
              Flexible(
                child: TextField(
                  controller: _textController,
                  onSubmitted: _handleSubmitted,
                  decoration:
                      const InputDecoration.collapsed(hintText: 'Send a message'),
                ),
              ),
              IconButton(
                icon: _isSubmitButtonDisabled
                    ? const SizedBox(
                        width: 24.0,
                        height: 24.0,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.0,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                        ),
                      )
                    : const Icon(Icons.send, size: 24,),
                // onPressed: () => _handleSubmitted(_textController.text),
                onPressed: () => _isSubmitButtonDisabled 
                    ? null 
                    : _handleSubmitted(_textController.text),
              ),
            ] :
            <Widget>[
              Flexible(
                child: TextField(
                  enabled: _isModelLoaded,
                  controller: _textController,
                  onSubmitted: _handleSubmitted,
                  decoration:
                      const InputDecoration.collapsed(hintText: 'Load a Large Language Model'),
                ),
              ),
            ]
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('LLM chat'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _isModelLoaded? null: () async {
              double _topP = 0.9;
              double _temperature = 0.1;
              String _modelPath = '';
              await showDialog(
                context: context,
                builder: (context) {
                  return GPTParamsDialog(
                    onLoaded: (topP, temperature, token, modelPath) => {
                      print('onLoaded'),
                      _topP = topP,
                      _temperature = temperature,
                      _maxToken = token,
                      _modelPath = modelPath,
                    },
                  );
                },
              );
              // 在这里执行初始化操作
              Future<int> ret = llamacpp_native().modelInit(_modelPath, _topP, _temperature);
              _showLoadingDialog();
              ret.then((value) => {
                Navigator.of(context).pop(),
                if (value == 0) {
                  _showDialog('Success', 'Model loaded successfully'),
                  setState(() {
                    _isModelLoaded = true;
                  })
                } else {
                  _showDialog('Fail', 'Model loaded failed'),
                  setState(() {
                    _isModelLoaded = false;
                  })
                  // _exitApp()
                }
              });
            } 
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Flexible(
            child: ListView.builder(
              padding: const EdgeInsets.all(8.0),
              reverse: true,
              itemCount: _messages.length,
              itemBuilder: (_, int index) {
                final message = _messages[index];
                return Wrap(
                  // direction: Axis.horizontal,
                  alignment: message.role == 'user'
                      ? WrapAlignment.end
                      : WrapAlignment.start,
                  children: [
                    message.role == 'user' ?
                    const SizedBox(width: 0) :Container(
                      margin: const EdgeInsets.all(8.0),
                      child: const Icon(
                        Icons.android,
                        size: 32.0,
                      ),
                    ) ,
                    Container(
                      margin: const EdgeInsets.symmetric(vertical: 4.0),
                      padding: const EdgeInsets.all(8.0),
                      decoration: BoxDecoration(
                        color: message.role == 'user'
                            ? Colors.grey[300]
                            : Colors.blue[200],
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                      child: Text(
                        message.text,
                        style: const TextStyle(fontSize: 16.0),
                      ),
                    ),
                    message.role == 'user' ?
                    Container(
                      margin: const EdgeInsets.all(8.0),
                      child: const Icon(
                        Icons.account_circle,
                        size: 32.0,
                      ),
                    ) : const SizedBox(width: 0),
                  ],
                );
              },
            ),
          ),
          const Divider(height: 1.0),
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
            ),
            child: _buildTextComposer(),
          ),
          const Divider(height: 4.0),
          const SizedBox(height: 8),
        ],
      ),
    );
  }


  Widget _buildListItem(String message) {
    return ListTile(
      title: Text(message),
    );
  }

  void _showDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              child: Text('OK'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  void _showLoadingDialog() async {
    WidgetsFlutterBinding.ensureInitialized();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return WillPopScope(
          onWillPop: () async => false,
          child: Dialog(
            child: Container(
              padding: const EdgeInsets.all(16.0),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(width: 16.0),
                  Text('Loading Large Language Model...'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _exitApp() {
    SystemNavigator.pop();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // 在这里执行清理操作
    llamacpp_native().modelDeinit();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // 应用程序进入后台，执行清理操作
    }
  }
}

Future<void> requestManageExternalStoragePermission() async {
  var status = await Permission.manageExternalStorage.status;
  if (status.isDenied) {
    // 如果权限被拒绝，请求权限
    status = await Permission.manageExternalStorage.request();
  }
  if (status.isGranted) {
    // 如果权限被授予，执行文件读写操作
    print("权限被授予");
  } else {
    // 如果权限被拒绝，提示用户无法执行文件读写操作
    print('权限被拒绝');
  }
}