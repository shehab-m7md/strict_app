import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';

class LogFilePage extends StatefulWidget {
  final String logFileId;

  const LogFilePage({super.key, required this.logFileId});

  @override
  State<LogFilePage> createState() => _LogFilePageState();
}

class _LogFilePageState extends State<LogFilePage> {
  String? _content;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadContent();
  }

  Future<void> _loadContent() async {
    final doc = await FirebaseFirestore.instance
        .collection("log_files")
        .doc(widget.logFileId)
        .get();

    if (!mounted) return;
    setState(() {
      _content = doc.data()?['content'] as String? ?? '';
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('log_file'.tr()),
        centerTitle: true,
        actions: [
          if (_content != null)
            IconButton(
              icon: const Icon(Icons.copy),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _content!));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('copied_log'.tr()),
                    duration: const Duration(seconds: 3),
                  ),
                );
              },
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _content == null || _content!.isEmpty
              ? Center(child: Text('no_content'.tr()))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: SelectableText(
                    _content!,
                    style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      height: 1.6,
                    ),
                  ),
                ),
    );
  }
}