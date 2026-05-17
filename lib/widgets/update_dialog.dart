import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/updater_service.dart';

class UpdateDialog extends StatefulWidget {
  final VantageUpdate update;

  const UpdateDialog({super.key, required this.update});

  static Future<void> show(BuildContext context, VantageUpdate update) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => UpdateDialog(update: update),
    );
  }

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  final _updateFocusNode = FocusNode();
  final _laterFocusNode = FocusNode();
  final _dismissFocusNode = FocusNode();

  bool _isDownloading = false;
  double _progress = 0.0;
  String? _apkPath;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _updateFocusNode.dispose();
    _laterFocusNode.dispose();
    _dismissFocusNode.dispose();
    super.dispose();
  }

  Future<void> _startUpdate() async {
    setState(() {
      _isDownloading = true;
      _error = null;
    });

    try {
      final downloadedPath = await UpdaterService.instance.downloadUpdate(
        widget.update,
        (p) => setState(() => _progress = p),
      );

      if (downloadedPath == null) {
        setState(() {
          _isDownloading = false;
          _error = 'DOWNLOAD_FAILED';
        });
        return;
      }

      final resultPath = await UpdaterService.instance.executeUpdate(downloadedPath);
      
      if (Platform.isAndroid) {
        setState(() {
          _isDownloading = false;
          _apkPath = resultPath;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _dismissFocusNode.requestFocus();
        });
      }
    } catch (e) {
      setState(() {
        _isDownloading = false;
        _error = 'UPDATE_ERROR: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;
    final isSmall = size.width < 600;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(horizontal: isSmall ? 20 : 40, vertical: 24),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 550, maxHeight: 600),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withOpacity(0.95),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: const Color(0xFFFF5C00).withOpacity(0.2), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF5C00).withOpacity(0.1),
                blurRadius: 40,
                spreadRadius: 5,
              )
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 32),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: theme.dividerColor.withOpacity(0.05))),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.system_update_alt, color: Color(0xFFFF5C00), size: 28),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'SYSTEM UPDATE',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _apkPath != null
                                ? 'DOWNLOAD COMPLETE'
                                : (_isDownloading ? 'DOWNLOADING BINARIES...' : 'NEW VERSION AVAILABLE: ${widget.update.version}'),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                              color: _apkPath != null ? const Color(0xFF4ADE80) : Colors.white38,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Content Body
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: _buildBody(theme),
                ),
              ),

              // Footer Actions
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  border: Border(top: BorderSide(color: theme.dividerColor.withOpacity(0.05))),
                ),
                child: _buildActions(context, theme),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_apkPath != null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle_outline, color: Color(0xFF4ADE80), size: 64),
          const SizedBox(height: 24),
          const Text(
            'DOWNLOAD COMPLETED!',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'The update binary has been saved to your downloads folder:',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.white70, height: 1.4),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.03),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.05)),
            ),
            child: Text(
              _apkPath ?? '',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: Color(0xFFFF5C00),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Open your device\'s Files app, navigate to this folder, and tap the APK to finalize installation.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.white30, height: 1.4),
          ),
        ],
      );
    }

    if (_isDownloading) {
      final pct = (_progress * 100).toInt();
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$pct%',
            style: const TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
              color: Color(0xFFFF5C00),
            ),
          ),
          const SizedBox(height: 24),
          ClipRRect(
            borderRadius: BorderRadius.circular(100),
            child: LinearProgressIndicator(
              value: _progress,
              minHeight: 10,
              backgroundColor: Colors.white.withOpacity(0.05),
              color: const Color(0xFFFF5C00),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Downloading: ${widget.update.fileName}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Colors.white38, letterSpacing: 0.5),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.redAccent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        const Text(
          'RELEASE NOTES:',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
            color: Colors.white38,
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.02),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.03)),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Text(
                widget.update.releaseNotes,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActions(BuildContext context, ThemeData theme) {
    if (_apkPath != null) {
      return _UpdateDialogButton(
        label: 'CLOSE',
        onPressed: () => Navigator.pop(context),
        selectedColor: const Color(0xFFFF5C00),
        focusNode: _dismissFocusNode,
      );
    }

    if (_isDownloading) {
      return const SizedBox.shrink(); // Prevent exit during download
    }

    return Row(
      children: [
        Expanded(
          child: _UpdateDialogButton(
            label: 'LATER',
            onPressed: () => Navigator.pop(context),
            selectedColor: Colors.white24,
            focusNode: _laterFocusNode,
            isOutlined: true,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _UpdateDialogButton(
            label: 'UPDATE NOW',
            onPressed: _startUpdate,
            selectedColor: const Color(0xFFFF5C00),
            focusNode: _updateFocusNode,
          ),
        ),
      ],
    );
  }
}

class _UpdateDialogButton extends StatefulWidget {
  final String label;
  final VoidCallback onPressed;
  final Color selectedColor;
  final FocusNode focusNode;
  final bool isOutlined;

  const _UpdateDialogButton({
    required this.label,
    required this.onPressed,
    required this.selectedColor,
    required this.focusNode,
    this.isOutlined = false,
  });

  @override
  State<_UpdateDialogButton> createState() => _UpdateDialogButtonState();
}

class _UpdateDialogButtonState extends State<_UpdateDialogButton> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (f) => setState(() => _isFocused = f),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && (
          event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.select ||
          event.logicalKey == LogicalKeyboardKey.space ||
          event.logicalKey == LogicalKeyboardKey.gameButtonA
        )) {
          widget.onPressed();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedScale(
        scale: _isFocused ? 1.03 : 1.0,
        duration: const Duration(milliseconds: 150),
        child: widget.isOutlined
            ? OutlinedButton(
                focusNode: FocusNode(skipTraversal: true),
                onPressed: widget.onPressed,
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                    color: _isFocused ? Colors.white : Colors.white24,
                    width: _isFocused ? 2.5 : 1.5,
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: Text(
                  widget.label,
                  style: TextStyle(
                    color: _isFocused ? Colors.white : Colors.white54,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                    fontSize: 12,
                  ),
                ),
              )
            : ElevatedButton(
                focusNode: FocusNode(skipTraversal: true),
                onPressed: widget.onPressed,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isFocused ? widget.selectedColor : Colors.white10,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: _isFocused ? widget.selectedColor : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  shadowColor: _isFocused ? widget.selectedColor : Colors.transparent,
                  elevation: _isFocused ? 15 : 0,
                ),
                child: Text(
                  widget.label,
                  style: TextStyle(
                    color: _isFocused ? Colors.white : Colors.white70,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                    fontSize: 12,
                  ),
                ),
              ),
      ),
    );
  }
}
