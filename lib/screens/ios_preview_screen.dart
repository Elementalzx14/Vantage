import 'package:flutter/material.dart';

/// Honest status for the first iOS build while native emulation is ported.
class IosPreviewScreen extends StatelessWidget {
  const IosPreviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('iOS preview')),
      body: const SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.construction, size: 48),
              SizedBox(height: 24),
              Text('Game playback is not available yet.',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              SizedBox(height: 16),
              Text('This preview lets you sign in and browse your library. '
                  'An iPhone emulator is still being added. '
                  'No game or emulator core was downloaded.'),
            ],
          ),
        ),
      ),
    );
  }
}
