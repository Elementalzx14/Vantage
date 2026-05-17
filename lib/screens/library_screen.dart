


import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../models/jellyfin_models.dart';
import '../services/jellyfin_api.dart';
import '../services/prefs.dart';
import '../services/core_manager.dart';
import '../services/theme_service.dart';
import '../services/launch_service.dart';
import '../widgets/theme_selector_dialog.dart';
import '../services/updater_service.dart';
import '../widgets/update_dialog.dart';
import '../version.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _prefs = Prefs();
  final _api = JellyfinApi();
  final _scrollCtrl = ScrollController();

  final List<JfItem> _allGames = [];
  final List<JfItem> _items = [];
  final List<String> _allPlatforms = [];
  final Map<String, int> _downloading = {};

  int _visibleCount = 24;
  bool _isLoading = false;

  String? _selectedPlatform;

  String _serverUrl = '';
  String _token = '';
  String _userId = '';

  VantageUpdate? _pendingUpdate;

  Future<void> _checkForUpdatesSilently() async {
    try {
      final update = await UpdaterService.instance.checkForUpdate();
      if (update != null && mounted) {
        setState(() {
          _pendingUpdate = update;
        });
      }
    } catch (e) {
      print('VANTAGE_LIB: Silent update check failed: $e');
    }
  }

  Future<void> _triggerManualUpdateCheck() async {
    _snack('SYSTEM: CHECKING FOR SYSTEM UPDATES...');
    try {
      final update = await UpdaterService.instance.checkForUpdate();
      if (!mounted) return;
      if (update != null) {
        setState(() {
          _pendingUpdate = update;
        });
        UpdateDialog.show(context, update);
      } else {
        _snack('SYSTEM: YOU ARE ON THE LATEST VERSION ($appVersion)');
      }
    } catch (e) {
      _snack('SYSTEM: UPDATE CHECK FAILED');
    }
  }

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _boot();
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    _serverUrl = await _prefs.serverUrl;
    _token = await _prefs.token;
    _userId = await _prefs.userId;
    await _loadAllGames();
    _checkForUpdatesSilently();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >= _scrollCtrl.position.maxScrollExtent - 400) {
      _loadMoreVisible();
    }
  }

  Future<void> _loadAllGames() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      final result = await _api.getItems(
        _serverUrl, _token, _userId,
        recursive: true,
        includeItemTypes: 'Game',
        limit: 10000,
      );

      final validGames = result.items
          .where((item) => item.isGame && item.tags?.any((t) => t.toLowerCase() == 'pico-8') != true)
          .toList();

      final platforms = <String>{};
      for (final item in validGames) {
        final tag = item.platformTag;
        if (tag != null) {
          platforms.add(tag);
        }
      }

      print('VANTAGE_LIB: Retrieved ${result.items.length} raw items, ${validGames.length} valid games.');
      print('VANTAGE_LIB: Unique Platforms found: ${platforms.toList()..sort()}');

      setState(() {
        _allGames.clear();
        _allGames.addAll(validGames);
        _allPlatforms.clear();
        _allPlatforms.addAll(platforms.toList()..sort());
        _updateVisibleItems(refresh: true);
      });
    } catch (e) {
      _snack('ERROR: UPLINK_FAILURE [$e]');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _updateVisibleItems({bool refresh = false}) {
    if (refresh) {
      _visibleCount = 24;
    }

    final filtered = _allGames.where((item) {
      if (_selectedPlatform == null) return true;
      return item.platformTag == _selectedPlatform;
    }).toList();

    setState(() {
      _items.clear();
      _items.addAll(filtered.take(_visibleCount));
    });
  }

  void _loadMoreVisible() {
    final totalFiltered = _allGames.where((item) {
      if (_selectedPlatform == null) return true;
      return item.platformTag == _selectedPlatform;
    }).length;

    if (_visibleCount < totalFiltered) {
      setState(() {
        _visibleCount += 24;
        _updateVisibleItems();
      });
    }
  }


  Future<void> _purgeAllCache() async {
    final cacheDir = await getTemporaryDirectory();
    final romsDir = Directory('${cacheDir.path}/roms');
    if (await romsDir.exists()) {
      await romsDir.delete(recursive: true);
      _snack('SYSTEM: ALL CACHED ROMS PURGED');
      setState(() {});
    }
  }

  Future<void> _deleteRom(JfItem item) async {
    final localFile = await _localRomFile(item);
    if (await localFile.exists()) {
      await localFile.delete();
      _snack('PURGED: LOCAL CACHE [${item.name}]');
      setState(() {});
    }
  }

  void _openDetails(JfItem item) {
    context.push('/details', extra: {
      'item': item,
      'serverUrl': _serverUrl,
      'token': _token,
      'userId': _userId,
    }).then((_) {
      // Refresh cache labels when returning
      setState(() {});
    });
  }

  Future<void> _launchGame(JfItem item) async {
    try {
      await LaunchService.instance.launchGame(item);
      setState(() {}); // Update to show 'CACHED' tag if it was downloaded
    } catch (e) {
      _snack('ERROR: LAUNCH FAILED');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
        backgroundColor: const Color(0xFFFF5C00),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<File> _localRomFile(JfItem item) => LaunchService.instance.getLocalRomFile(item);

  Future<void> _logout() async {
    await _prefs.logout();
    if (mounted) context.go('/login');
  }

  int _spanCount(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width >= 1600) return 8;
    if (width >= 1200) return 6;
    if (width >= 800) return 4;
    return 2;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final size = MediaQuery.of(context).size;
    final isSmall = size.width < 600;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('LIBRARY'),
        actions: isSmall 
          ? [
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 20),
                onSelected: (val) {
                  if (val == 'sync') _loadAllGames();
                  if (val == 'cores') context.push('/cores');
                  if (val == 'inputs') context.push('/inputs');
                  if (val == 'purge') _purgeAllCache();
                  if (val == 'update') _triggerManualUpdateCheck();
                  if (val == 'logout') _logout();
                },
                itemBuilder: (ctx) => [
                  const PopupMenuItem(value: 'sync', child: Text('SYNC')),
                  const PopupMenuItem(value: 'cores', child: Text('CORE MGR')),
                  const PopupMenuItem(value: 'inputs', child: Text('INPUT MAP')),
                  const PopupMenuItem(value: 'purge', child: Text('PURGE CACHE', style: TextStyle(color: Colors.redAccent))),
                  const PopupMenuItem(value: 'update', child: Text('CHECK FOR UPDATES')),
                  const PopupMenuItem(value: 'logout', child: Text('LOGOUT', style: TextStyle(color: Color(0xFFFF5C00)))),
                ],
              ),
              _ThemeToggleButton(),
              const SizedBox(width: 8),
            ]
          : [
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: _loadAllGames,
                tooltip: 'SYNC',
              ),
              IconButton(
                icon: const Icon(Icons.memory, size: 20),
                onPressed: () => context.push('/cores'),
                tooltip: 'CORE MGR',
              ),
              IconButton(
                icon: const Icon(Icons.gamepad, size: 20),
                onPressed: () => context.push('/inputs'),
                tooltip: 'INPUT MAP',
              ),
              IconButton(
                icon: const Icon(Icons.delete_sweep, size: 20, color: Colors.redAccent),
                onPressed: _purgeAllCache,
                tooltip: 'PURGE ALL CACHE',
              ),
              IconButton(
                icon: const Icon(Icons.system_update_alt, size: 20, color: Colors.blueAccent),
                onPressed: _triggerManualUpdateCheck,
                tooltip: 'CHECK FOR UPDATES',
              ),
              _ThemeToggleButton(),
              IconButton(
                icon: const Icon(Icons.power_settings_new, size: 20, color: Color(0xFFFF5C00)),
                onPressed: _logout,
                tooltip: 'LOGOUT',
              ),
              const SizedBox(width: 12),
            ],
      ),
      body: Stack(
        children: [
          _LibraryBackground(isDark: isDark),

          SafeArea(
            top: false,
            bottom: true,
            child: Column(
              children: [
                _buildUpdateBanner(),
                _buildSystemFilterRow(),
                Expanded(
                  child: _items.isEmpty && !_isLoading
                      ? const Center(child: Text('NO GAMES FOUND FOR THIS SYSTEM', style: TextStyle(color: Colors.black26, fontWeight: FontWeight.bold, letterSpacing: 2)))
                      : GridView.builder(
                          controller: _scrollCtrl,
                          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: _spanCount(context),
                            crossAxisSpacing: 24,
                            mainAxisSpacing: 24,
                            childAspectRatio: 0.72,
                          ),
                          itemCount: _items.length + (_isLoading ? 1 : 0),
                          itemBuilder: (ctx, i) {
                            if (i == _items.length) {
                              return const Center(child: CircularProgressIndicator(color: Color(0xFFFF5C00)));
                            }
                            return FutureBuilder<bool>(
                              future: _localRomFile(_items[i]).then((f) => f.exists()),
                              builder: (ctx, snapshot) {
                                return _NasaGameCard(
                                  item: _items[i],
                                  serverUrl: _serverUrl,
                                  token: _token,
                                  downloadProgress: LaunchService.instance.downloadProgress.value,
                                  hasLocal: snapshot.data ?? false,
                                  onTap: () => _openDetails(_items[i]),
                                  onDelete: () => _deleteRom(_items[i]),
                                );
                              }
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSystemFilterRow() {
    if (_allPlatforms.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 60,
      margin: const EdgeInsets.symmetric(vertical: 16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(
          children: [
            _TvFilterChip(
              label: 'ALL',
              isSelected: _selectedPlatform == null,
              onTap: () {
                if (_selectedPlatform != null) {
                  setState(() => _selectedPlatform = null);
                  _updateVisibleItems(refresh: true);
                }
              },
            ),
            for (final plat in _allPlatforms) ...[
              const SizedBox(width: 12),
              _TvFilterChip(
                label: plat,
                isSelected: _selectedPlatform == plat,
                onTap: () {
                  if (_selectedPlatform != plat) {
                    setState(() => _selectedPlatform = plat);
                    _updateVisibleItems(refresh: true);
                  }
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildUpdateBanner() {
    if (_pendingUpdate == null) return const SizedBox.shrink();

    return _UpdateBannerCard(
      update: _pendingUpdate!,
      onTap: () {
        UpdateDialog.show(context, _pendingUpdate!);
      },
    );
  }
}



class _ThemeToggleButton extends StatefulWidget {
  @override
  State<_ThemeToggleButton> createState() => _ThemeToggleButtonState();
}

class _ThemeToggleButtonState extends State<_ThemeToggleButton> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeService.instance,
      builder: (context, _) {
        final isDark = ThemeService.instance.isDarkMode;
        return Focus(
          onFocusChange: (f) => setState(() => _isFocused = f),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: _isFocused ? const Color(0xFFFF5C00) : Colors.transparent,
                width: 2,
              ),
              color: _isFocused ? const Color(0xFFFF5C00).withOpacity(0.1) : Colors.transparent,
            ),
            child: IconButton(
              icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode, size: 20),
              onPressed: () => ThemeSelectorDialog.show(context),
            ),
          ),
        );
      },
    );
  }
}

class _NasaGameCard extends StatefulWidget {
  final JfItem item;
  final String serverUrl;
  final String token;
  final int? downloadProgress;
  final bool hasLocal;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _NasaGameCard({
    required this.item, required this.serverUrl, required this.token,
    required this.downloadProgress, required this.hasLocal,
    required this.onTap, required this.onDelete,
  });

  @override
  State<_NasaGameCard> createState() => _NasaGameCardState();
}

class _NasaGameCardState extends State<_NasaGameCard> {
  bool _isFocused = false;

  void _showContextMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.rocket_launch, color: Color(0xFFFF5C00)),
              title: const Text('RE-DOWNLOAD', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1)),
              onTap: () { Navigator.pop(ctx); widget.onTap(); },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
              title: const Text('PURGE LOCAL ROM', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1)),
              onTap: () { Navigator.pop(ctx); widget.onDelete(); },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final downloading = widget.downloadProgress != null;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Focus(
      onFocusChange: (f) => setState(() => _isFocused = f),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && (
          event.logicalKey == LogicalKeyboardKey.select ||
          event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.gameButtonA
        )) {
          if (!downloading) widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: InkWell(
        onTap: downloading ? null : widget.onTap,
        onLongPress: () => _showContextMenu(context),
        borderRadius: BorderRadius.circular(32),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(32),
            boxShadow: [
              if (_isFocused)
                BoxShadow(color: const Color(0xFFFF5C00).withOpacity(0.4), blurRadius: 20, spreadRadius: 2)
              else
                BoxShadow(color: Colors.black.withOpacity(isDark ? 0.3 : 0.05), blurRadius: 20, offset: const Offset(0, 6)),
            ],
            border: Border.all(
              color: _isFocused ? const Color(0xFFFF5C00) : theme.dividerColor.withOpacity(0.05),
              width: _isFocused ? 3 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              
              CachedNetworkImage(
                imageUrl: widget.item.posterUrl(widget.serverUrl, widget.token),
                fit: BoxFit.cover,
                httpHeaders: {'Authorization': 'MediaBrowser Token="${widget.token}"'},
                placeholder: (_, __) => Container(color: Colors.black.withOpacity(0.05), child: const Center(child: Icon(Icons.image, color: Colors.black12))),
                errorWidget: (_, __, ___) => Container(color: Colors.black.withOpacity(0.05), child: const Center(child: Icon(Icons.broken_image, color: Colors.black12))),
              ),


              if (widget.hasLocal)
                Positioned(
                  top: 12, right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: const Color(0xFF4ADE80), borderRadius: BorderRadius.circular(8)),
                    child: const Text('CACHED', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w900)),
                  ),
                ),

              
              Positioned(
                bottom: 0, left: 0, right: 0,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter, end: Alignment.topCenter,
                      colors: [Colors.black.withOpacity(0.8), Colors.transparent],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.item.platformTag != null)
                        Text(widget.item.platformTag!.toUpperCase(), style: const TextStyle(color: Color(0xFFFF5C00), fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 1)),
                      Text(
                        downloading ? (widget.downloadProgress! < 0 ? 'SYNCING...' : 'SYNCING ${widget.downloadProgress}%') : widget.item.name.toUpperCase(),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                      ),
                    ],
                  ),
                ),
              ),

              
              if (downloading)
                Positioned(
                  bottom: 0, left: 0, right: 0,
                  child: LinearProgressIndicator(
                    value: widget.downloadProgress! < 0 ? null : widget.downloadProgress! / 100.0,
                    backgroundColor: Colors.white10,
                    color: const Color(0xFFFF5C00),
                    minHeight: 4,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LibraryBackground extends StatelessWidget {
  final bool isDark;
  const _LibraryBackground({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _LibraryGridPainter(isDark: isDark),
      child: Container(),
    );
  }
}

class _LibraryGridPainter extends CustomPainter {
  final bool isDark;
  _LibraryGridPainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = (isDark ? Colors.white : Colors.black).withOpacity(0.015)..strokeWidth = 1;
    for (double i = 0; i < size.width; i += 80) { canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint); }
    for (double i = 0; i < size.height; i += 80) { canvas.drawLine(Offset(0, i), Offset(size.width, i), paint); }
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _TvFilterChip extends StatefulWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _TvFilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_TvFilterChip> createState() => _TvFilterChipState();
}

class _TvFilterChipState extends State<_TvFilterChip> {
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
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          transform: Matrix4.identity()..scale(_isFocused ? 1.08 : 1.0),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: widget.isSelected 
                ? const Color(0xFFFF5C00) 
                : (_isFocused ? Colors.white24 : Colors.white.withOpacity(0.05)),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _isFocused ? Colors.white : (widget.isSelected ? const Color(0xFFFF5C00) : Colors.white10),
              width: _isFocused ? 2.5 : 1.5,
            ),
            boxShadow: [
              if (_isFocused || widget.isSelected)
                BoxShadow(
                  color: const Color(0xFFFF5C00).withOpacity(widget.isSelected ? 0.3 : 0.15),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
            ],
          ),
          child: Text(
            widget.label.toUpperCase(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.0,
            ),
          ),
        ),
      ),
    );
  }
}

class _UpdateBannerCard extends StatefulWidget {
  final VantageUpdate update;
  final VoidCallback onTap;

  const _UpdateBannerCard({required this.update, required this.onTap});

  @override
  State<_UpdateBannerCard> createState() => _UpdateBannerCardState();
}

class _UpdateBannerCardState extends State<_UpdateBannerCard> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Focus(
      onFocusChange: (f) => setState(() => _isFocused = f),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && (
          event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.select ||
          event.logicalKey == LogicalKeyboardKey.gameButtonA
        )) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: InkWell(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFFFF5C00).withOpacity(_isFocused ? 0.2 : 0.08),
                Colors.white.withOpacity(0.02),
              ],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _isFocused ? const Color(0xFFFF5C00) : const Color(0xFFFF5C00).withOpacity(0.3),
              width: _isFocused ? 2 : 1,
            ),
            boxShadow: [
              if (_isFocused)
                BoxShadow(
                  color: const Color(0xFFFF5C00).withOpacity(0.2),
                  blurRadius: 12,
                  spreadRadius: 1,
                ),
            ],
          ),
          child: Row(
            children: [
              const Icon(Icons.system_update_alt, color: Color(0xFFFF5C00), size: 22),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'VANTAGE SYSTEM UPDATE AVAILABLE: VERSION ${widget.update.version}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'CLICK OR PRESS SELECT TO DOWNLOAD AND INSTALL THE LATEST SYSTEM VERSION.',
                      style: TextStyle(
                        color: Colors.white38,
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              const Icon(
                Icons.arrow_forward_ios,
                color: Color(0xFFFF5C00),
                size: 14,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

