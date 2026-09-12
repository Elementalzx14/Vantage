import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gamepads/gamepads.dart';
import '../services/prefs.dart';
import '../services/theme_service.dart';
import '../services/ios_controls.dart';

class InputManagerScreen extends StatefulWidget {
  const InputManagerScreen({super.key});

  @override
  State<InputManagerScreen> createState() => _InputManagerScreenState();
}

class _InputManagerScreenState extends State<InputManagerScreen> with SingleTickerProviderStateMixin {
  final _prefs = Prefs();
  late final TabController _tabController;
  StreamSubscription? _gamepadSub;

  int _selectedBindIndex = 0; // 0 to 26: 0 is TabBar focus, 1 to 24 are bind buttons, 25 is Reset, 26 is Done
  int? _bindingRetroId;
  bool _isGamepadTab = false;

  late final List<GlobalKey> _keyboardKeys;
  late final List<GlobalKey> _gamepadKeys;

  static final Map<String, int> _defaultGamepadMap = Platform.isIOS ? iosGamepadMap : Platform.isAndroid ? {
    'button_0': 8,
    'button_1': 0,
    'button_2': 9,
    'button_3': 1,
    'button_4': 10,
    'button_5': 11,
    'button_6': 2,
    'button_7': 3,
    'button_8': 14,
    'button_9': 15,
    'dpad_up': 4,
    'dpad_down': 5,
    'dpad_left': 6,
    'dpad_right': 7,
  } : {
    'a': 8,
    'b': 0,
    'x': 9,
    'y': 1,
    'leftShoulder': 10,
    'rightShoulder': 11,
    'view': 2,
    'menu': 3,
    'leftThumbstickClick': 14,
    'rightThumbstickClick': 15,
    'dpadUp': 4,
    'dpadDown': 5,
    'dpadLeft': 6,
    'dpadRight': 7,
  };

  static final Map<LogicalKeyboardKey, int> _defaultKeyMap = {
    LogicalKeyboardKey.arrowUp: 4,
    LogicalKeyboardKey.arrowDown: 5,
    LogicalKeyboardKey.arrowLeft: 6,
    LogicalKeyboardKey.arrowRight: 7,
    LogicalKeyboardKey.keyX: 8,
    LogicalKeyboardKey.keyZ: 0,
    LogicalKeyboardKey.keyS: 9,
    LogicalKeyboardKey.keyA: 1,
    LogicalKeyboardKey.enter: 3,
    LogicalKeyboardKey.shiftLeft: 2,
    LogicalKeyboardKey.keyQ: 10,
    LogicalKeyboardKey.keyW: 11,
    LogicalKeyboardKey.keyE: 12,
    LogicalKeyboardKey.keyR: 13,
    LogicalKeyboardKey.gameButtonA: 8,
    LogicalKeyboardKey.gameButtonB: 0,
    LogicalKeyboardKey.gameButtonX: 9,
    LogicalKeyboardKey.gameButtonY: 1,
    LogicalKeyboardKey.gameButtonStart: 3,
    LogicalKeyboardKey.gameButtonSelect: 2,
    LogicalKeyboardKey.gameButtonLeft1: 10,
    LogicalKeyboardKey.gameButtonRight1: 11,
  };

  Map<String, int> _gamepadMap = Map.from(_defaultGamepadMap);
  Map<LogicalKeyboardKey, int> _keyMap = Map.from(_defaultKeyMap);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      setState(() {
        _isGamepadTab = _tabController.index == 1;
        _selectedBindIndex = 0; // reset focus on tab change
      });
    });

    _keyboardKeys = List.generate(25, (_) => GlobalKey());
    _gamepadKeys = List.generate(25, (_) => GlobalKey());

    _loadInputMap();
    _initGamepadListener();
  }

  @override
  void dispose() {
    _gamepadSub?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadInputMap() async {
    try {
      final keyMapStr = await _prefs.keyMapJson;
      if (keyMapStr != null && keyMapStr.isNotEmpty) {
        final Map<String, dynamic> decoded = jsonDecode(keyMapStr);
        final Map<LogicalKeyboardKey, int> loadedMap = {};
        for (final entry in decoded.entries) {
          loadedMap[LogicalKeyboardKey(int.parse(entry.key))] = entry.value as int;
        }
        setState(() {
          final actionsInLoadedMap = loadedMap.values.toSet();
          _keyMap.removeWhere((k, v) => actionsInLoadedMap.contains(v));
          _keyMap.addAll(loadedMap);
        });
      }

      final gamepadMapStr = await _prefs.gamepadMapJson;
      if (gamepadMapStr != null && gamepadMapStr.isNotEmpty) {
        final Map<String, dynamic> decoded = jsonDecode(gamepadMapStr);
        final Map<String, int> loadedMap = {};
        for (final entry in decoded.entries) {
          loadedMap[entry.key] = entry.value as int;
        }
        setState(() {
          final actionsInLoadedMap = loadedMap.values.toSet();
          _gamepadMap.removeWhere((k, v) => actionsInLoadedMap.contains(v));
          _gamepadMap.addAll(loadedMap);
        });
      }
    } catch (e) {
      debugPrint('Failed to load input map in manager: $e');
    }
  }

  Future<void> _saveKeyMap() async {
    final Map<String, int> mapToSave = {};
    for (final entry in _keyMap.entries) {
      mapToSave[entry.key.keyId.toString()] = entry.value;
    }
    await _prefs.setKeyMapJson(jsonEncode(mapToSave));
  }

  Future<void> _saveGamepadMap() async {
    await _prefs.setGamepadMapJson(jsonEncode(_gamepadMap));
  }

  void _resetKeyboardMapping() {
    setState(() {
      _keyMap = Map.from(_defaultKeyMap);
    });
    _saveKeyMap();
    _snack('SYSTEM: KEYBOARD BINDINGS RESET TO DEFAULT');
  }

  void _resetGamepadMapping() {
    setState(() {
      _gamepadMap = Map.from(_defaultGamepadMap);
    });
    _saveGamepadMap();
    _snack('SYSTEM: GAMEPAD BINDINGS RESET TO DEFAULT');
  }

  void _initGamepadListener() {
    _gamepadSub = Gamepads.events.listen((event) {
      if (!mounted) return;

      if (_bindingRetroId != null && _isGamepadTab) {
        if (event.type == KeyType.button && event.value > 0) {
          setState(() {
            _gamepadMap.removeWhere((k, v) => k == event.key);
            _gamepadMap.removeWhere((k, v) => v == _bindingRetroId);
            _gamepadMap[event.key] = _bindingRetroId!;
            _bindingRetroId = null;
          });
          _saveGamepadMap();
          _snack('SYSTEM: GAMEPAD KEY BOUND');
          return;
        } else if (event.type == KeyType.analog && event.value.abs() > 0.5) {
          setState(() {
            final keyWithPolarity = '${event.key}${event.value > 0 ? '+' : '-'}';
            _gamepadMap.removeWhere((k, v) => k == keyWithPolarity);
            _gamepadMap.removeWhere((k, v) => v == _bindingRetroId);
            _gamepadMap[keyWithPolarity] = _bindingRetroId!;
            _gamepadMap[event.key] = _bindingRetroId!;
            _bindingRetroId = null;
          });
          _saveGamepadMap();
          _snack('SYSTEM: ANALOG AXIS BOUND');
          return;
        }
      }
    });
  }

  void _scrollToSelected() {
    if (_selectedBindIndex < 1 || _selectedBindIndex > 24) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final index = _selectedBindIndex - 1;
      if (!_isGamepadTab) {
        final kbCtx = _keyboardKeys[index].currentContext;
        if (kbCtx != null) {
          Scrollable.ensureVisible(kbCtx, duration: const Duration(milliseconds: 150), alignment: 0.5);
        }
      } else {
        final gpCtx = _gamepadKeys[index].currentContext;
        if (gpCtx != null) {
          Scrollable.ensureVisible(gpCtx, duration: const Duration(milliseconds: 150), alignment: 0.5);
        }
      }
    });
  }

  void _triggerSelectedBindAction() {
    if (_selectedBindIndex == 0) {
      // Toggle tab
      _tabController.animateTo((_tabController.index + 1) % 2);
    } else if (_selectedBindIndex >= 1 && _selectedBindIndex <= 24) {
      final retroIds = [
        4, 5, 6, 7, // UP DOWN LEFT RIGHT
        8, 0, 9, 1, // A B X Y
        3, 2,       // START SELECT
        10, 11, 12, 13, 14, 15, // L R L2 R2 L3 R3
        100, 101, 102, 103, // LX- LX+ LY- LY+
        104, 105, 106, 107, // RX- RX+ RY- RY+
      ];
      setState(() {
        _bindingRetroId = retroIds[_selectedBindIndex - 1];
      });
    } else if (_selectedBindIndex == 25) {
      _isGamepadTab ? _resetGamepadMapping() : _resetKeyboardMapping();
    } else if (_selectedBindIndex == 26) {
      Navigator.of(context).pop();
    }
  }

  String _getKeyName(int retroId, bool isGamepad) {
    final names = <String>[];
    if (isGamepad) {
      for (final entry in _gamepadMap.entries) {
        if (entry.value == retroId) {
          names.add(entry.key);
        }
      }
      final toRemove = <String>[];
      for (final name in names) {
        if (name.endsWith('+') || name.endsWith('-')) {
          final base = name.substring(0, name.length - 1);
          if (names.contains(base)) {
            toRemove.add(base);
          }
        }
      }
      names.removeWhere((n) => toRemove.contains(n));
    } else {
      for (final entry in _keyMap.entries) {
        if (entry.value == retroId) {
          var label = entry.key.keyLabel;
          if (label.isEmpty) {
            label = entry.key.debugName ?? "Unknown";
            if (label.contains('#')) {
              label = label.split('#').last;
            }
          }
          if (!label.toLowerCase().contains('game button')) {
            names.add(label);
          }
        }
      }
    }
    return names.isEmpty ? "None" : names.first.toUpperCase();
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final size = MediaQuery.of(context).size;
    final isSmall = size.width < 600;

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (_bindingRetroId != null) {
          if (!_isGamepadTab && event is KeyDownEvent) {
            final keyLabel = event.logicalKey.keyLabel.toLowerCase();
            if (keyLabel.contains('volume') || keyLabel.contains('power') || keyLabel.contains('home')) {
              return KeyEventResult.ignored;
            }
            setState(() {
              _keyMap.removeWhere((k, v) => k == event.logicalKey);
              _keyMap.removeWhere((k, v) => v == _bindingRetroId);
              _keyMap[event.logicalKey] = _bindingRetroId!;
              _bindingRetroId = null;
            });
            _saveKeyMap();
            _snack('SYSTEM: KEYBOARD KEY BOUND');
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        }

        if (event is KeyDownEvent) {
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.arrowUp) {
            setState(() {
              _selectedBindIndex = (_selectedBindIndex - 1 + 27) % 27;
            });
            _scrollToSelected();
            return KeyEventResult.handled;
          } else if (key == LogicalKeyboardKey.arrowDown) {
            setState(() {
              _selectedBindIndex = (_selectedBindIndex + 1) % 27;
            });
            _scrollToSelected();
            return KeyEventResult.handled;
          } else if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.gameButtonLeft1) {
            if (_selectedBindIndex == 0) {
              _tabController.animateTo(0);
            } else {
              setState(() {
                _selectedBindIndex = (_selectedBindIndex - 1 + 27) % 27;
              });
              _scrollToSelected();
            }
            return KeyEventResult.handled;
          } else if (key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.gameButtonRight1) {
            if (_selectedBindIndex == 0) {
              _tabController.animateTo(1);
            } else {
              setState(() {
                _selectedBindIndex = (_selectedBindIndex + 1) % 27;
              });
              _scrollToSelected();
            }
            return KeyEventResult.handled;
          } else if (key == LogicalKeyboardKey.enter ||
                     key == LogicalKeyboardKey.select ||
                     key == LogicalKeyboardKey.space ||
                     key == LogicalKeyboardKey.gameButtonA) {
            _triggerSelectedBindAction();
            return KeyEventResult.handled;
          } else if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.gameButtonB) {
            Navigator.of(context).pop();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          title: const Text('INPUT CONFIG'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
          bottom: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: "KEYBOARD"),
              Tab(text: "GAMEPAD"),
            ],
            indicatorColor: const Color(0xFFFF5C00),
            labelStyle: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 13),
            unselectedLabelColor: Colors.white24,
            labelColor: const Color(0xFFFF5C00),
          ),
        ),
        body: Stack(
          children: [
            _CoresBackground(isDark: isDark),
            SafeArea(
              top: false,
              bottom: true,
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      _bindingRetroId != null
                          ? "WAITING FOR INPUT... PRESS A KEY OR GAMEPAD BUTTON"
                          : "TV FRIENDLY D-PAD Traversal • CLICK ANY ROW TO CONFIGURE",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _bindingRetroId != null ? const Color(0xFFFF5C00) : Colors.white54,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildBindList(false),
                        _buildBindList(true),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      border: Border(top: BorderSide(color: theme.dividerColor.withOpacity(0.05))),
                    ),
                    child: isSmall
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: double.infinity,
                                child: _DoneButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  selected: _selectedBindIndex == 26,
                                ),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: _ResetButton(
                                  onPressed: _isGamepadTab ? _resetGamepadMapping : _resetKeyboardMapping,
                                  selected: _selectedBindIndex == 25,
                                ),
                              ),
                            ],
                          )
                        : Row(
                            children: [
                              Expanded(
                                child: _ResetButton(
                                  onPressed: _isGamepadTab ? _resetGamepadMapping : _resetKeyboardMapping,
                                  selected: _selectedBindIndex == 25,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: _DoneButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  selected: _selectedBindIndex == 26,
                                ),
                              ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBindList(bool isGamepad) {
    final keys = isGamepad ? _gamepadKeys : _keyboardKeys;
    final rowActions = [
      _RowDef("UP", 4),
      _RowDef("DOWN", 5),
      _RowDef("LEFT", 6),
      _RowDef("RIGHT", 7),
      _RowDef("A", 8),
      _RowDef("B", 0),
      _RowDef("X", 9),
      _RowDef("Y", 1),
      _RowDef("START", 3),
      _RowDef("SELECT", 2),
      _RowDef("L", 10),
      _RowDef("R", 11),
      _RowDef("L2", 12),
      _RowDef("R2", 13),
      _RowDef("L3", 14),
      _RowDef("R3", 15),
      _RowDef("LX- (ANALOG LEFT)", 100),
      _RowDef("LX+ (ANALOG RIGHT)", 101),
      _RowDef("LY- (ANALOG UP)", 102),
      _RowDef("LY+ (ANALOG DOWN)", 103),
      _RowDef("RX- (ANALOG LEFT)", 104),
      _RowDef("RX+ (ANALOG RIGHT)", 105),
      _RowDef("RY- (ANALOG UP)", 106),
      _RowDef("RY+ (ANALOG DOWN)", 107),
    ];

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      itemCount: rowActions.length,
      itemBuilder: (ctx, i) {
        final def = rowActions[i];
        final index = i + 1;
        final selected = _selectedBindIndex == index;
        final isBinding = _bindingRetroId == def.retroId;

        return _BindRow(
          key: keys[i],
          label: def.label,
          currentValue: _getKeyName(def.retroId, isGamepad),
          selected: selected,
          isBinding: isBinding,
          onTap: () {
            setState(() {
              _selectedBindIndex = index;
              _bindingRetroId = def.retroId;
            });
          },
        );
      },
    );
  }
}

class _RowDef {
  final String label;
  final int retroId;
  _RowDef(this.label, this.retroId);
}

class _BindRow extends StatelessWidget {
  final String label;
  final String currentValue;
  final bool selected;
  final bool isBinding;
  final VoidCallback onTap;

  const _BindRow({
    super.key,
    required this.label,
    required this.currentValue,
    required this.selected,
    required this.isBinding,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glowColor = isBinding
        ? Colors.blue
        : (selected ? const Color(0xFFFF5C00) : Colors.transparent);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: selected
            ? const Color(0xFFFF5C00).withOpacity(0.08)
            : theme.colorScheme.surface.withOpacity(0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected
              ? const Color(0xFFFF5C00).withOpacity(0.5)
              : theme.dividerColor.withOpacity(0.05),
          width: selected ? 2 : 1,
        ),
        boxShadow: selected ? [
          BoxShadow(
            color: const Color(0xFFFF5C00).withOpacity(0.15),
            blurRadius: 10,
            spreadRadius: 2,
          )
        ] : null,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    letterSpacing: 2,
                    color: selected ? Colors.white : Colors.white70,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    constraints: const BoxConstraints(maxWidth: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: isBinding
                          ? Colors.blue.withOpacity(0.2)
                          : (selected ? const Color(0xFFFF5C00).withOpacity(0.2) : Colors.white.withOpacity(0.05)),
                      borderRadius: BorderRadius.circular(100),
                      border: Border.all(
                        color: isBinding
                            ? Colors.blue
                            : (selected ? const Color(0xFFFF5C00) : Colors.transparent),
                      ),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        isBinding ? "LISTENING..." : currentValue,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: isBinding
                              ? Colors.blue
                              : (selected ? const Color(0xFFFF5C00) : Colors.white),
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.chevron_right,
                    size: 16,
                    color: selected ? const Color(0xFFFF5C00) : Colors.white24,
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

class _ResetButton extends StatelessWidget {
  final VoidCallback onPressed;
  final bool selected;

  const _ResetButton({required this.onPressed, required this.selected});

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: selected ? 1.03 : 1.0,
      duration: const Duration(milliseconds: 150),
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          side: BorderSide(
            color: selected ? Colors.redAccent : Colors.white24,
            width: selected ? 2 : 1,
          ),
          padding: const EdgeInsets.symmetric(vertical: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            "RESET TO DEFAULTS",
            style: TextStyle(
              color: selected ? Colors.redAccent : Colors.white54,
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

class _DoneButton extends StatelessWidget {
  final VoidCallback onPressed;
  final bool selected;

  const _DoneButton({required this.onPressed, required this.selected});

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: selected ? 1.03 : 1.0,
      duration: const Duration(milliseconds: 150),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: selected ? const Color(0xFFFF5C00) : Colors.white10,
          padding: const EdgeInsets.symmetric(vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: selected ? const Color(0xFFFF5C00) : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          "DONE",
          style: TextStyle(
            color: selected ? Colors.white : Colors.white70,
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _CoresBackground extends StatelessWidget {
  final bool isDark;
  const _CoresBackground({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _CoresGridPainter(isDark: isDark),
      child: Container(),
    );
  }
}

class _CoresGridPainter extends CustomPainter {
  final bool isDark;
  _CoresGridPainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = (isDark ? Colors.white : Colors.black).withOpacity(0.015)
      ..strokeWidth = 1;
    for (double i = 0; i < size.width; i += 80) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
    for (double i = 0; i < size.height; i += 80) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
