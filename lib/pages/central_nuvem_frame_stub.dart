import 'package:flutter/material.dart';

Widget buildCentralNuvemFrame(String url, {Key? key}) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.open_in_browser,
            size: 42,
            color: Colors.orangeAccent,
          ),
          const SizedBox(height: 12),
          const Text(
            'A Central da Nuvem está disponível no portal web.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 12),
          SelectableText(
            url,
            style: const TextStyle(color: Colors.lightBlueAccent),
          ),
        ],
      ),
    ),
  );
}
