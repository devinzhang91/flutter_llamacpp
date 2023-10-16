import 'dart:io';

import 'package:flutter/material.dart';
import 'package:filesystem_picker/filesystem_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';

class GPTParamsDialog extends StatefulWidget {
  final Function(double, double, int, String) onLoaded;

  const GPTParamsDialog({super.key, 
    required this.onLoaded,
  });


  @override
  _GPTParamsDialogState createState() => _GPTParamsDialogState();

}

class _GPTParamsDialogState extends State<GPTParamsDialog> {
  double _topP = 0.8;
  double _temperature = 0.2;
  int _token = 64;
  String _modelPath = '/sdcard/';

  Future<void> _selcetModel() async {
    // 显示文件选择器    // for android Directory 
    Directory appDocDir = await Directory("/sdcard/").create(recursive: true);

    // ignore: use_build_context_synchronously
    var result = await FilesystemPicker.open( allowedExtensions: [".gguf"],
                                              context: context,
                                              rootDirectory: appDocDir);
    if (result != null) {
        File file = File(result);
        print('modle file path: ${file.path}');
    } else {
      // User canceled the picker
      return;
    }
    String? filePath = File(result).path;
    // 更新模型路径
    setState(() {
      _modelPath = filePath;
    });
}

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('LLM Parameters'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Text('Top P:'),
              const SizedBox(width: 8),
              Expanded(
                child: Slider(
                  value: _topP,
                  min: 0,
                  max: 1,
                  divisions: 10,
                  onChanged: (value) {
                    setState(() {
                      _topP = value;
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              Text(_topP.toStringAsFixed(1)),
            ],
          ),
          Row(
            children: [
              const Text('Temperature:'),
              const SizedBox(width: 8),
              Expanded(
                child: Slider(
                  value: _temperature,
                  min: 0,
                  max: 1,
                  divisions: 10,
                  onChanged: (value) {
                    setState(() {
                      _temperature = value;
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              Text(_temperature.toStringAsFixed(1)),
            ],
          ),
          Row(
            children: [
              const Text('Token:'),
              const SizedBox(width: 8),
              Expanded(
                child: Slider(
                  value: _token.toDouble(),
                  min: 1,
                  max: 256,
                  divisions: 255,
                  onChanged: (value) {
                    setState(() {
                      _token = value.toInt();
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              Text(_token.toString()),
            ],
          ),
          TextField(
            decoration: const InputDecoration(
              labelText: 'Model Path',
            ),
            controller: TextEditingController(text: _modelPath),
            onChanged: (value) {
              setState(() {
                _modelPath = value;
              });
            },
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _selcetModel,
            child: const Text('Choose Model File'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            widget.onLoaded(_topP, _temperature, _token, _modelPath);
            Navigator.of(context).pop();
          },
          child: const Text('Load'),
        ),
      ],
    );
  }
}