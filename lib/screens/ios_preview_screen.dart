import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/core_entry.dart';

// Retain this route so unsupported consoles have a useful destination.
class IosPreviewScreen extends StatefulWidget {
  const IosPreviewScreen({super.key});
  @override
  State<IosPreviewScreen> createState() => _IosPreviewScreenState();
}

class _IosPreviewScreenState extends State<IosPreviewScreen> {
  static const _channel = MethodChannel('com.retrostream.vantage/emulator');
  late final _cores =
      _channel.invokeMapMethod<String, String>('getBundledCores');

  Future<void> _license(CoreEntry core) async {
    final licenses =
        await _channel.invokeMapMethod<String, String>('getCoreLicenses');
    if (!mounted) return;
    showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text('${core.displayName} license'),
              content: SingleChildScrollView(
                  child: SelectableText(
                      licenses?[core.id] ?? 'License unavailable.')),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'))
              ],
            ));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('iOS emulators')),
        body: SafeArea(
            child: FutureBuilder<Map<String, String>?>(
          future: _cores,
          builder: (context, snapshot) =>
              ListView(padding: const EdgeInsets.all(24), children: [
            const Text(
                'This build supports NES, SNES, Game Boy, Game Boy Color and Game Boy Advance. '
                'Other consoles are not available yet. Use uncompressed ROM files for this first build.'),
            const SizedBox(height: 20),
            if (snapshot.hasError)
              const Text(
                  'Could not read the bundled emulators. Reinstall the latest IPA.'),
            for (final core in coreCatalog
                .where((core) => iosBundledCoreIds.contains(core.id)))
              ListTile(
                title: Text('${core.system} — ${core.displayName}'),
                subtitle: Text(snapshot.connectionState != ConnectionState.done
                    ? 'Checking…'
                    : (snapshot.data?.containsKey(core.id) ?? false)
                        ? 'Included in this app'
                        : 'Missing from this build'),
                trailing: IconButton(
                    icon: const Icon(Icons.info_outline),
                    tooltip: 'License',
                    onPressed: () => _license(core)),
              ),
            const SizedBox(height: 20),
            const Text(
                'Choose a game from your library to play. Emulator updates are included in new app builds.'),
          ]),
        )),
      );
}
