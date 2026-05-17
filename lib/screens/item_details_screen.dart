import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../models/jellyfin_models.dart';
import '../services/jellyfin_api.dart';
import '../services/launch_service.dart';
import '../services/prefs.dart';
import '../services/theme_service.dart';

class ItemDetailsScreen extends StatefulWidget {
  final JfItem item;
  final String serverUrl;
  final String token;
  final String userId;

  const ItemDetailsScreen({
    super.key,
    required this.item,
    required this.serverUrl,
    required this.token,
    required this.userId,
  });

  @override
  State<ItemDetailsScreen> createState() => _ItemDetailsScreenState();
}

class _ItemDetailsScreenState extends State<ItemDetailsScreen> {
  late JfItem _item;
  bool _isLoadingDetails = false;
  bool _isLocal = false;
  bool _isChecking = true;
  final _prefs = Prefs();
  final _api = JellyfinApi();

  @override
  void initState() {
    super.initState();
    _item = widget.item;
    _checkLocal();
    _loadFullDetails();
  }

  Future<void> _loadFullDetails() async {
    if (_item.overview != null && _item.overview!.isNotEmpty) {
      return;
    }

    setState(() => _isLoadingDetails = true);
    try {
      final fullItem = await _api.getItem(
        widget.serverUrl,
        widget.token,
        widget.userId,
        widget.item.id,
      );
      if (mounted) {
        setState(() {
          _item = fullItem;
          _isLoadingDetails = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading full item details: $e');
      if (mounted) {
        setState(() => _isLoadingDetails = false);
      }
    }
  }

  Future<void> _checkLocal() async {
    final file = await LaunchService.instance.getLocalRomFile(_item);
    if (mounted) {
      setState(() {
        _isLocal = file.existsSync();
        _isChecking = false;
      });
    }
  }

  Future<void> _deleteRom() async {
    final file = await LaunchService.instance.getLocalRomFile(_item);
    if (file.existsSync()) {
      try {
        await file.delete();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('PURGED: LOCAL CACHE [${_item.name}]', style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
              backgroundColor: const Color(0xFFFF5C00),
              behavior: SnackBarBehavior.floating,
            ),
          );
          _checkLocal();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('ERROR: FAILED TO DELETE ROM [$e]', style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
              backgroundColor: Colors.redAccent,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  String? _getRegion() {
    final regions = ['USA', 'Europe', 'Japan', 'World', 'UK', 'France', 'Germany', 'Spain', 'Italy', 'Korea', 'China'];
    for (final tag in _item.tags ?? []) {
      final upper = tag.toUpperCase();
      for (final r in regions) {
        if (upper.contains(r.toUpperCase())) return r;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;
    final isSmall = size.width < 900;
    
    final platform = _item.platformTag ?? 'Unknown Platform';
    final region = _getRegion();
    final disc = _item.discTag;
    final overview = _item.overview ?? 
        (_isLoadingDetails ? 'Loading description...' : 'No description available.');

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Immersive Background
          Positioned.fill(
            child: RepaintBoundary(
              child: Stack(
                children: [
                  if (_item.backdropTags != null && _item.backdropTags!.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: '${widget.serverUrl}/Items/${_item.id}/Images/Backdrop/0?api_key=${widget.token}',
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                    )
                  else
                    CachedNetworkImage(
                      imageUrl: _item.posterUrl(widget.serverUrl, widget.token),
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                    ),
                  BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                    child: Container(
                      color: Colors.black.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 2. Content Layer
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: _TvBackButton(
                    onPressed: () => context.pop(),
                  ),
                ),

                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.symmetric(horizontal: isSmall ? 24 : 64, vertical: 24),
                    child: isSmall 
                      ? _buildPortraitLayout(platform, region, disc, overview, theme)
                      : _buildLandscapeLayout(platform, region, disc, overview, theme),
                  ),
                ),
              ],
            ),
          ),
          
          // 3. Launch/Download Progress Overlay (Global Listener)
          ValueListenableBuilder<int?>(
            valueListenable: LaunchService.instance.downloadProgress,
            builder: (context, progress, child) {
              if (progress == null) return const SizedBox.shrink();
              return Container(
                color: Colors.black87,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: Color(0xFFFF5C00)),
                      const SizedBox(height: 24),
                      Text(
                        progress == -1 ? 'INITIALIZING...' : 'DOWNLOADING ROM: $progress%',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLandscapeLayout(String platform, String? region, String? disc, String overview, ThemeData theme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Poster Art
        Hero(
          tag: 'poster_${_item.id}',
          child: Container(
            width: 320,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 30,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: CachedNetworkImage(
                imageUrl: _item.posterUrl(widget.serverUrl, widget.token),
                fit: BoxFit.cover,
              ),
            ),
          ),
        ),
        const SizedBox(width: 48),

        // Metadata Panel
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _item.name.toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 48,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1,
                  height: 1.0,
                ),
              ),
              const SizedBox(height: 16),
              
              // Tags Row
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _InfoPill(label: platform, color: const Color(0xFFFF5C00)),
                  if (region != null) _InfoPill(label: region, color: Colors.blueAccent),
                  if (disc != null && disc.isNotEmpty) _InfoPill(label: disc.toUpperCase(), color: Colors.purpleAccent),
                  if (_item.year != null) _InfoPill(label: '${_item.year}', color: Colors.white12),
                ],
              ),
              const SizedBox(height: 32),

              // Action Bar (Moved above overview for Android TV / focus friendly design)
              _buildActionBar(theme),
              const SizedBox(height: 32),

              // Focusable, scroll-assist Description container
              Focus(
                child: Builder(
                  builder: (context) {
                    final isFocused = Focus.of(context).hasFocus;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isFocused ? Colors.white.withOpacity(0.05) : Colors.transparent,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isFocused ? const Color(0xFFFF5C00).withOpacity(0.5) : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      child: Text(
                        overview,
                        style: TextStyle(
                          color: isFocused ? Colors.white : Colors.white.withOpacity(0.7),
                          fontSize: 18,
                          height: 1.6,
                        ),
                      ),
                    );
                  }
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPortraitLayout(String platform, String? region, String? disc, String overview, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Poster
        Hero(
          tag: 'poster_${_item.id}',
          child: Center(
            child: Container(
              width: 240,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 20,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: CachedNetworkImage(
                  imageUrl: _item.posterUrl(widget.serverUrl, widget.token),
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 32),

        Text(
          _item.name.toUpperCase(),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 32,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 16),

        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            _InfoPill(label: platform, color: const Color(0xFFFF5C00)),
            if (region != null) _InfoPill(label: region, color: Colors.blueAccent),
            if (disc != null && disc.isNotEmpty) _InfoPill(label: disc.toUpperCase(), color: Colors.purpleAccent),
          ],
        ),
        const SizedBox(height: 32),

        // Action Bar (Moved above overview)
        _buildActionBar(theme, isPortrait: true),
        const SizedBox(height: 32),

        // Focusable, scroll-assist Description container
        Focus(
          child: Builder(
            builder: (context) {
              final isFocused = Focus.of(context).hasFocus;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isFocused ? Colors.white.withOpacity(0.05) : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isFocused ? const Color(0xFFFF5C00).withOpacity(0.5) : Colors.transparent,
                    width: 1.5,
                  ),
                ),
                child: Text(
                  overview,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isFocused ? Colors.white : Colors.white.withOpacity(0.7),
                    fontSize: 16,
                    height: 1.5,
                  ),
                ),
              );
            }
          ),
        ),
      ],
    );
  }

  Widget _buildActionBar(ThemeData theme, {bool isPortrait = false}) {
    final buttons = [
      _TvActionButton(
        onPressed: () async {
          await LaunchService.instance.launchGame(_item);
          _checkLocal(); // Refresh status after launch/download
        },
        icon: _isLocal ? Icons.play_arrow : Icons.download,
        label: _isLocal ? 'PLAY NOW' : 'DOWNLOAD ROM',
        isFullWidth: isPortrait,
      ),
      if (_isLocal) ...[
        if (!isPortrait) const SizedBox(width: 16) else const SizedBox(height: 12),
        _TvActionButton(
          onPressed: _deleteRom,
          icon: Icons.delete_forever,
          label: 'DELETE ROM',
          isSecondary: true,
          isFullWidth: isPortrait,
        ),
      ],
    ];

    if (isPortrait) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: buttons,
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      children: buttons,
    );
  }
}

class _InfoPill extends StatelessWidget {
  final String label;
  final Color color;

  const _InfoPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color.withOpacity(0.9),
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _TvBackButton extends StatefulWidget {
  final VoidCallback onPressed;
  const _TvBackButton({required this.onPressed});

  @override
  State<_TvBackButton> createState() => _TvBackButtonState();
}

class _TvBackButtonState extends State<_TvBackButton> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (focused) => setState(() => _isFocused = focused),
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
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _isFocused ? Colors.white.withOpacity(0.2) : Colors.white.withOpacity(0.05),
            shape: BoxShape.circle,
            border: Border.all(
              color: _isFocused ? const Color(0xFFFF5C00) : Colors.white24,
              width: _isFocused ? 2.5 : 1,
            ),
            boxShadow: [
              if (_isFocused)
                BoxShadow(
                  color: const Color(0xFFFF5C00).withOpacity(0.3),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
            ],
          ),
          child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

class _TvActionButton extends StatefulWidget {
  final VoidCallback onPressed;
  final IconData icon;
  final String label;
  final Color baseColor;
  final bool isSecondary;
  final bool isFullWidth;

  const _TvActionButton({
    required this.onPressed,
    required this.icon,
    required this.label,
    this.baseColor = const Color(0xFFFF5C00),
    this.isSecondary = false,
    this.isFullWidth = false,
  });

  @override
  State<_TvActionButton> createState() => _TvActionButtonState();
}

class _TvActionButtonState extends State<_TvActionButton> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final focusColor = widget.isSecondary ? Colors.redAccent : widget.baseColor;
    final bg = widget.isSecondary 
        ? Colors.white10 
        : widget.baseColor;

    return Focus(
      onFocusChange: (focused) {
        setState(() {
          _isFocused = focused;
        });
      },
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
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          transform: Matrix4.identity()..scale(_isFocused ? 1.05 : 1.0),
          width: widget.isFullWidth ? double.infinity : null,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          decoration: BoxDecoration(
            color: _isFocused ? focusColor : bg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _isFocused ? Colors.white : (widget.isSecondary ? Colors.white24 : Colors.transparent),
              width: _isFocused ? 3 : 1.5,
            ),
            boxShadow: [
              if (_isFocused)
                BoxShadow(
                  color: focusColor.withOpacity(0.5),
                  blurRadius: 15,
                  spreadRadius: 2,
                ),
            ],
          ),
          child: Row(
            mainAxisSize: widget.isFullWidth ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(widget.icon, color: Colors.white, size: 22),
              const SizedBox(width: 12),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    widget.label.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
