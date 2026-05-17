
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import '../services/jellyfin_api.dart';

class SaveStateManager extends StatefulWidget {
  final String itemId;
  final String title;
  final String serverUrl;
  final String token;
  final String userId;
  final Future<Uint8List?> Function() onGetLocalState;
  final Future<void> Function(Uint8List) onApplyLocalState;
  final VoidCallback? onClose;

  const SaveStateManager({
    super.key,
    required this.itemId,
    required this.title,
    required this.serverUrl,
    required this.token,
    required this.userId,
    required this.onGetLocalState,
    required this.onApplyLocalState,
    this.onClose,
  });

  @override
  State<SaveStateManager> createState() => _SaveStateManagerState();
}

class _SaveStateManagerState extends State<SaveStateManager> {
  final _api = JellyfinApi();
  DateTime? _localTime;
  DateTime? _cloudTime;
  bool _loading = true;
  String? _error;
  int _selectedIndex = 0; // 0 = Upload, 1 = Download, 2 = Close

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _triggerSelectedAction() {
    if (_selectedIndex == 0) {
      if (_localTime != null) _upload();
    } else if (_selectedIndex == 1) {
      if (_cloudTime != null) _download();
    } else if (_selectedIndex == 2) {
      widget.onClose?.call();
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Get local state time
      final docDir = await getApplicationDocumentsDirectory();
      final localFile = File('${docDir.path}/Vantage/States/${widget.itemId}.state');
      if (await localFile.exists()) {
        _localTime = await localFile.lastModified();
      } else {
        _localTime = null;
      }

      // Get cloud state time (Slot 1)
      _cloudTime = (await _api.getSaveMetadata(
        widget.serverUrl,
        widget.token,
        widget.userId,
        widget.itemId,
        slot: 1,
      ))?.toLocal();
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _upload() async {
    setState(() => _loading = true);
    try {
      final data = await widget.onGetLocalState();
      if (data == null) throw Exception('Failed to capture game state');

      await _api.uploadSave(
        widget.serverUrl,
        widget.token,
        widget.userId,
        widget.itemId,
        data,
        slot: 1,
      );
      
      // Also update local file timestamp if it exists, or create it
      final docDir = await getApplicationDocumentsDirectory();
      final localFile = File('${docDir.path}/Vantage/States/${widget.itemId}.state');
      if (!await localFile.parent.exists()) await localFile.parent.create(recursive: true);
      await localFile.writeAsBytes(data);
      
      await _refresh();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Upload successful')));
    } catch (e) {
      if (mounted) setState(() => _error = 'Upload failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _download() async {
    setState(() => _loading = true);
    try {
      final bytes = await _api.downloadSave(
        widget.serverUrl,
        widget.token,
        widget.userId,
        widget.itemId,
        slot: 1,
      );

      if (bytes == null) throw Exception('No cloud save found');

      await widget.onApplyLocalState(bytes);
      
      // Save to local file too
      final docDir = await getApplicationDocumentsDirectory();
      final localFile = File('${docDir.path}/Vantage/States/${widget.itemId}.state');
      if (!await localFile.parent.exists()) await localFile.parent.create(recursive: true);
      await localFile.writeAsBytes(bytes);

      if (_cloudTime != null) {
        try {
          await localFile.setLastModified(_cloudTime!);
        } catch (e) {
          debugPrint('Failed to set last modified on local save file: $e');
        }
      }

      await _refresh();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Download successful')));
    } catch (e) {
      if (mounted) setState(() => _error = 'Download failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('yyyy-MM-dd HH:mm:ss');

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.arrowLeft || 
              key == LogicalKeyboardKey.arrowUp ||
              key == LogicalKeyboardKey.gameButtonLeft1) {
            setState(() {
              _selectedIndex = (_selectedIndex - 1 + 3) % 3;
            });
            return KeyEventResult.handled;
          } else if (key == LogicalKeyboardKey.arrowRight || 
                     key == LogicalKeyboardKey.arrowDown ||
                     key == LogicalKeyboardKey.gameButtonRight1) {
            setState(() {
              _selectedIndex = (_selectedIndex + 1) % 3;
            });
            return KeyEventResult.handled;
          } else if (key == LogicalKeyboardKey.enter || 
                     key == LogicalKeyboardKey.select || 
                     key == LogicalKeyboardKey.space ||
                     key == LogicalKeyboardKey.gameButtonA) {
            _triggerSelectedAction();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Card(
        elevation: 20,
        color: const Color(0xFF16213E).withOpacity(0.95),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.cloud_sync, color: Color(0xFFFF5C00)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Cloud Sync',
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  _TvCloseButton(
                    onPressed: widget.onClose,
                    selected: _selectedIndex == 2,
                  )
                ],
              ),
              const Divider(color: Colors.white10, height: 24),
              if (_error != null)
                Container(
                  padding: const EdgeInsets.all(8),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(color: Colors.red.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                  child: Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                ),
              
              _StateRow(
                label: 'Local Save (Slot 1)',
                time: _localTime != null ? fmt.format(_localTime!) : 'None',
                icon: Icons.phonelink,
                isAvailable: _localTime != null,
              ),
              const SizedBox(height: 16),
              _StateRow(
                label: 'Cloud Save (Slot 1)',
                time: _cloudTime != null ? fmt.format(_cloudTime!) : 'None',
                icon: Icons.cloud_queue,
                isAvailable: _cloudTime != null,
              ),
              
              const SizedBox(height: 24),
              if (_loading)
                const CircularProgressIndicator(color: Color(0xFFFF5C00))
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Expanded(
                      child: _TvSaveButton(
                        onPressed: _localTime != null ? _upload : null,
                        icon: Icons.cloud_upload,
                        label: 'Upload',
                        selected: _selectedIndex == 0,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _TvSaveButton(
                        onPressed: _cloudTime != null ? _download : null,
                        icon: Icons.cloud_download,
                        label: 'Download',
                        isPrimary: true,
                        selected: _selectedIndex == 1,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TvSaveButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final IconData icon;
  final String label;
  final bool isPrimary;
  final bool selected;

  const _TvSaveButton({
    required this.onPressed,
    required this.icon,
    required this.label,
    this.isPrimary = false,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final primaryColor = const Color(0xFFFF5C00);
    
    Color bg;
    if (!enabled) {
      bg = Colors.white.withOpacity(0.02);
    } else if (selected) {
      bg = primaryColor;
    } else if (isPrimary) {
      bg = primaryColor.withOpacity(0.8);
    } else {
      bg = Colors.white.withOpacity(0.05);
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected && enabled ? Colors.white : Colors.transparent,
          width: 2,
        ),
        boxShadow: selected && enabled ? [
          BoxShadow(color: primaryColor.withOpacity(0.3), blurRadius: 8, spreadRadius: 1)
        ] : [],
      ),
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: enabled ? Colors.white : Colors.white24,
          disabledBackgroundColor: Colors.white.withOpacity(0.02),
          disabledForegroundColor: Colors.white24,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: selected ? 8 : 0,
        ),
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
      ),
    );
  }
}

class _TvCloseButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool selected;

  const _TvCloseButton({required this.onPressed, this.selected = false});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? Colors.redAccent.withOpacity(0.2) : Colors.transparent,
        border: Border.all(color: selected ? Colors.redAccent : Colors.transparent, width: 1.5),
      ),
      child: IconButton(
        icon: Icon(Icons.close, color: selected ? Colors.redAccent : Colors.white24, size: 20),
        onPressed: onPressed,
      ),
    );
  }
}

class _StateRow extends StatelessWidget {
  final String label;
  final String time;
  final IconData icon;
  final bool isAvailable;

  const _StateRow({required this.label, required this.time, required this.icon, required this.isAvailable});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: isAvailable ? const Color(0xFFFF5C00) : Colors.white24, size: 20),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
              Text(time, style: TextStyle(color: isAvailable ? Colors.white : Colors.white24, fontSize: 14)),
            ],
          ),
        ),
      ],
    );
  }
}
