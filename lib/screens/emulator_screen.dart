











import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'dart:ui';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../services/jellyfin_api.dart';
import '../services/prefs.dart';
import 'package:gamepads/gamepads.dart';
import 'dart:async';
import 'dart:convert';
import '../services/core_manager.dart';
import '../widgets/save_state_manager.dart';
import '../widgets/ios_gamepad.dart';
import '../services/ios_controls.dart';



const _channel = MethodChannel('com.retrostream.vantage/emulator');

enum ScalingMode {
  stretch,
  fit,
  originalAspectRatio,
}

class EmulatorScreen extends StatefulWidget {
  final String romPath;
  final String corePath;
  final String title;
  final String? itemId;
  final String serverUrl;
  final String token;
  final String userId;

  const EmulatorScreen({
    super.key,
    required this.romPath,
    required this.corePath,
    required this.title,
    this.itemId,
    required this.serverUrl,
    required this.token,
    required this.userId,
  });

  @override
  State<EmulatorScreen> createState() => _EmulatorScreenState();
}

class _EmulatorScreenState extends State<EmulatorScreen>
    with WidgetsBindingObserver {
  bool _paused = false;
  bool _showVirtualPad = false; 
  int? _textureId;
  bool _showDock = false;
  bool _dockMinimized = true;
  double _volume = 1.0;
  bool _fastForward = false;
  bool _slowMotion = false;
  double _coreAspectRatio = 4.0 / 3.0;
  ScalingMode _scalingMode = ScalingMode.fit;
  bool _showSaveManagerPanel = false;
  final FocusNode _focusNode = FocusNode();
  final FocusNode _dockFocusNode = FocusNode();
  final FocusScopeNode _saveManagerFocusScopeNode = FocusScopeNode();
  Offset _bubblePos = const Offset(100, 100);
  final _api = JellyfinApi();
  StreamSubscription? _gamepadSub;
  final _prefs = Prefs();
  int _selectedActionIndex = 0;
  
  List<String> get _dockActions {
    return [
      'pause', 'save', 'load', 'saves', 'reset', 'fastforward', 
      if (!Platform.isAndroid) 'scaling',
      if (!Platform.isAndroid) 'volume',
      'minimize', 'exit'
    ];
  }
  
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
    WidgetsBinding.instance.addObserver(this);
    _loadInputMap();
    _launch();
    _focusNode.requestFocus();
    _initGamepads();
    
    // Hide status bar and bottom navigation bar for a true console-like gameplay experience
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
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
        if (mounted) setState(() {
          
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
        if (mounted) setState(() {
          
          final actionsInLoadedMap = loadedMap.values.toSet();
          _gamepadMap.removeWhere((k, v) => actionsInLoadedMap.contains(v));
          _gamepadMap.addAll(loadedMap);
        });
      }
    } catch (e) {
      debugPrint('Failed to load input map: $e');
    }
  }

  void _initGamepads() {
    _gamepadSub = Gamepads.events.listen((event) {
      if (!mounted) return;

      // Handle Quick Menu toggle via Select (6) or Start (7) buttons
      // These are often buttons 6, 7 or similar on gamepads
      if (event.type == KeyType.button && event.value > 0) {
        if (event.key == '6' || event.key == '7' || event.key == 'buttonSelect' || event.key == 'buttonStart' || (Platform.isIOS && event.key == 'buttonHome')) {
          setState(() {
            if (_showDock) {
              _showDock = false;
              _focusNode.requestFocus();
            } else {
              _showDock = true;
              Future.delayed(const Duration(milliseconds: 50), () {
                _dockFocusNode.requestFocus();
              });
            }
          });
          return;
        }
      }



      
      
      if (event.type == KeyType.analog && event.value.abs() < 0.2) {
        final idPlus = _gamepadMap['${event.key}+'];
        if (idPlus != null && idPlus < 100) _channel.invokeMethod('keyUp', {'keyCode': _toPlatformKeyCode(idPlus)});
        
        final idMinus = _gamepadMap['${event.key}-'];
        if (idMinus != null && idMinus < 100) _channel.invokeMethod('keyUp', {'keyCode': _toPlatformKeyCode(idMinus)});
        
        final idBase = _gamepadMap[event.key];
        if (idBase != null && idBase >= 100) {
           _channel.invokeMethod('setAnalog', {
             'index': (idBase >= 104) ? 1 : 0, 
             'id': (idBase == 100 || idBase == 101 || idBase == 104 || idBase == 105) ? 0 : 1,
             'value': 0,
          });
        }
        return;
      }

      String lookupKey = event.key;
      if (event.type == KeyType.analog) {
        lookupKey = '${event.key}${event.value > 0 ? '+' : '-'}';
        if (Platform.isIOS) {
          final opposite = _gamepadMap['${event.key}${event.value > 0 ? '-' : '+'}'];
          if (opposite != null && opposite < 100) {
            _channel.invokeMethod('keyUp', {'keyCode': opposite});
          }
        }
      }

      int? retroId = _gamepadMap[lookupKey];
      if (retroId == null && event.type == KeyType.analog) {
        retroId = _gamepadMap[event.key];
      }

      if (retroId != null) {
        if (retroId >= 100) {
          
          int value = 0;
          if (event.type == KeyType.analog) {
            value = (event.value * 32767).toInt();
          } else if (event.type == KeyType.button) {
            if (event.value > 0) {
              value = (retroId % 2 == 0) ? -32767 : 32767;
            } else {
              value = 0;
            }
          }
          
          _channel.invokeMethod('setAnalog', {
             'index': (retroId >= 104) ? 1 : 0, 
             'id': (retroId == 100 || retroId == 101 || retroId == 104 || retroId == 105) ? 0 : 1,
             'value': value,
          });
        } else {
          
          if (event.type == KeyType.button) {
            final method = event.value > 0 ? 'keyDown' : 'keyUp';
            _channel.invokeMethod(method, {'keyCode': _toPlatformKeyCode(retroId)});
          } else if (event.type == KeyType.analog) {
            final isPressed = event.value.abs() > 0.5;
            final method = isPressed ? 'keyDown' : 'keyUp';
            _channel.invokeMethod(method, {'keyCode': _toPlatformKeyCode(retroId)});
          }
        }
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _channel.invokeMethod('resetMappingMode');
    _channel.invokeMethod('stop');
    _focusNode.dispose();
    _dockFocusNode.dispose();
    _saveManagerFocusScopeNode.dispose();
    _gamepadSub?.cancel();
    // Restore standard edge-to-edge system UI overlay styles upon exiting gameplay
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _channel.invokeMethod('pause');
    } else if (state == AppLifecycleState.resumed && !_paused) {
      _channel.invokeMethod('resume');
    }
  }

  int _toPlatformKeyCode(int retroId) {
    if (!Platform.isAndroid) return retroId;
    switch (retroId) {
      case 0: return 97; 
      case 1: return 100; 
      case 2: return 109; 
      case 3: return 108; 
      case 4: return 19; 
      case 5: return 20; 
      case 6: return 21; 
      case 7: return 22; 
      case 8: return 96; 
      case 9: return 99; 
      case 10: return 102; 
      case 11: return 103; 
      case 12: return 104; 
      case 13: return 105; 
      case 14: return 106; 
      case 15: return 107; 
      default: return retroId;
    }
  }

  Future<void> _launch() async {
    try {
      _channel.invokeMethod('resetMappingMode');
      final dynamic result = await _channel.invokeMethod('launch', {
        'romPath': widget.romPath,
        'corePath': widget.corePath,
        'systemPath': CoreManager.instance.systemDir,
      });
      if (mounted) {
        if (result is int) {
          setState(() => _textureId = result);
        }
        
        final double? ar = await _channel.invokeMethod<double>('getAspectRatio');
        if (ar != null && ar > 0) {
          setState(() {
            _coreAspectRatio = ar;
          });
        }
      }

      
      if (widget.itemId != null) {
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted) _cloudLoad(silent: true);
        });
      }
    } on PlatformException catch (e) {
      debugPrint('EMULATOR ERROR: ${e.code} | ${e.message} | ${e.details}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Emulator error: ${e.message ?? e.code}'),
            backgroundColor: Colors.redAccent,
          ),
        );
        // Don't pop immediately if it's a specific error we want to see
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) Navigator.pop(context);
        });
      }
    } catch (e) {
      debugPrint('GENERAL ERROR DURING LAUNCH: $e');
      if (mounted) Navigator.pop(context);
    }
  }

  void _pause() {
    _paused = true;
    _channel.invokeMethod('pause');
  }

  void _resume() {
    _paused = false;
    _channel.invokeMethod('resume');
  }

  void _showPauseMenu() {
    _pause();

    final hasCloud = widget.itemId != null;
    final options = [
      'Resume',
      'Save State',
      'Load State',
      if (hasCloud) 'Save Manager',
      'Reset',
      'Exit',
    ];

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF16213E),
        title: Text(widget.title,
            style: const TextStyle(color: Colors.white)),
        content: SizedBox(
          width: 280,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: options
                .map((opt) => ListTile(
                      title: Text(opt,
                          style: const TextStyle(color: Colors.white)),
                      onTap: () {
                        Navigator.pop(context);
                        _handleMenuOption(opt);
                      },
                    ))
                .toList(),
          ),
        ),
      ),
    ).then((_) {
      if (_paused) _resume();
    });
  }

  Future<void> _handleMenuOption(String opt) async {
    switch (opt) {
      case 'Resume':
        _resume();
      case 'Save State':
        await _localSave();
        _resume();
      case 'Load State':
        await _localLoad();
        _resume();
      case 'Save Manager':
        await _showSaveManager();
        _resume();
      case 'Reset':
        await _channel.invokeMethod('reset');
        _resume();
      case 'Exit':
        Navigator.pop(context);
    }
  }

  Future<void> _localSave() async {
    try {
      final id = widget.itemId ?? widget.title.hashCode.toString();
      final Uint8List? data = await _channel.invokeMethod<Uint8List>('saveState');
      if (data == null) return;
      
      final directory = await getApplicationDocumentsDirectory();
      final saveDir = Directory('${directory.path}/Vantage/States');
      if (!await saveDir.exists()) await saveDir.create(recursive: true);
      
      final file = File('${saveDir.path}/$id.state');
      await file.writeAsBytes(data);
      
      _snack('State saved for ${widget.title}');
    } catch (e) {
      _snack('Save failed: $e');
    }
  }

  Future<void> _localLoad() async {
    try {
      final id = widget.itemId ?? widget.title.hashCode.toString();
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/Vantage/States/$id.state');
      
      if (!await file.exists()) {
        _snack('No save state found for ${widget.title}');
        return;
      }
      
      final data = await file.readAsBytes();
      final bool? success = await _channel.invokeMethod<bool>('loadState', {'state': data});
      
      if (success == true) {
        _snack('State loaded for ${widget.title}');
      } else {
        _snack('Load failed');
      }
    } catch (e) {
      _snack('Load error: $e');
    }
  }

  Future<void> _setVolume(double value) async {
    setState(() => _volume = value);
    await _channel.invokeMethod('setVolume', value);
  }

  void _toggleFastForward() {
    setState(() {
      _fastForward = !_fastForward;
      if (_fastForward) _slowMotion = false; 
    });
    _channel.invokeMethod('setFastForward', _fastForward);
    _channel.invokeMethod('setSlowMotion', _slowMotion);
  }

  void _toggleSlowMotion() {
    setState(() {
      _slowMotion = !_slowMotion;
      if (_slowMotion) _fastForward = false; 
    });
    _channel.invokeMethod('setSlowMotion', _slowMotion);
    _channel.invokeMethod('setFastForward', _fastForward);
  }

  Future<void> _showSaveManager() async {
    if (widget.itemId == null) return;
    
    await showDialog(
      context: context,
      builder: (_) => SaveStateManager(
        itemId: widget.itemId!,
        title: widget.title,
        serverUrl: widget.serverUrl,
        token: widget.token,
        userId: widget.userId,
        onGetLocalState: () async {
          return await _channel.invokeMethod<Uint8List>('saveState');
        },
        onApplyLocalState: (data) async {
          await _channel.invokeMethod('loadState', {'state': data});
        },
      ),
    );
  }

  void _triggerDockAction(String action) {
    switch (action) {
      case 'pause':
        if (_paused) _resume(); else _pause();
        setState(() {});
        break;
      case 'save':
        _localSave();
        break;
      case 'load':
        _localLoad();
        break;
      case 'saves':
        setState(() => _showSaveManagerPanel = !_showSaveManagerPanel);
        break;
      case 'scaling':
        setState(() {
          _scalingMode = ScalingMode.values[(_scalingMode.index + 1) % ScalingMode.values.length];
        });
        break;

      case 'fastforward':
        _toggleFastForward();
        break;
      case 'minimize':
        setState(() => _showDock = false);
        break;
      case 'exit':
        Navigator.pop(context);
        break;
    }
  }

  Future<bool> _upload(String url, Uint8List data, String contentType) async {
    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Authorization': 'MediaBrowser Token="${widget.token}"',
          'Content-Type': contentType,
        },
        body: data,
      );
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      debugPrint('Upload error: $e');
      return false;
    }
  }

  Future<Uint8List?> _httpGet(Uri uri) async {
    try {
      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'MediaBrowser Token="${widget.token}"',
        },
      );
      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
      return null;
    } catch (e) {
      debugPrint('Download error: $e');
      return null;
    }
  }

  void _snack(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _cloudLoad({bool silent = false}) async {
    if (widget.itemId == null) return;
    try {
      final cloudTime = await _api.getSaveMetadata(
        widget.serverUrl,
        widget.token,
        widget.userId,
        widget.itemId!,
        slot: 1,
      );

      if (cloudTime == null) {
        if (!silent) _snack('No cloud save found');
        return;
      }

      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/Vantage/States/${widget.itemId}.state');
      DateTime? localTime;
      if (await file.exists()) {
        localTime = await file.lastModified();
      }

      if (silent && localTime != null && cloudTime.isBefore(localTime)) {
        return;
      }

      final data = await _api.downloadSave(
        widget.serverUrl,
        widget.token,
        widget.userId,
        widget.itemId!,
        slot: 1,
      );

      if (data != null) {
        final bool? success = await _channel.invokeMethod<bool>('loadState', {'state': data});
        if (success == true) {
          if (!silent) _snack('Cloud state loaded');
          if (!await file.parent.exists()) await file.parent.create(recursive: true);
          await file.writeAsBytes(data);
          
          try {
            await file.setLastModified(cloudTime);
          } catch (e) {
            debugPrint('Failed to set last modified in _cloudLoad: $e');
          }
        }
      }
    } catch (e) {
      if (!silent) _snack('Cloud load error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    
    
    final isNarrowPortrait =
        MediaQuery.of(context).size.aspectRatio < 1 &&
            MediaQuery.of(context).size.shortestSide < 600;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        
        // If any overlay is open, close it and DON'T re-open anything
        if (_showSaveManagerPanel) {
          setState(() => _showSaveManagerPanel = false);
          return;
        }

        if (_showDock) {
          setState(() {
            _showDock = false;
            _focusNode.requestFocus();
          });
        } else {
          setState(() {
            _showDock = true;
            _selectedActionIndex = 0; // Reset to first item
            Future.delayed(const Duration(milliseconds: 50), () {
              _dockFocusNode.requestFocus();
            });
          });
        }
      },
      child: Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        focusNode: _focusNode,
        onKeyEvent: (node, event) {
          if (_showSaveManagerPanel) {
            return KeyEventResult.ignored;
          }

          if (_showDock) {
            if (event is KeyDownEvent) {
              if (event.logicalKey == LogicalKeyboardKey.escape || event.logicalKey == LogicalKeyboardKey.goBack) {
                setState(() => _showDock = false);
                return KeyEventResult.handled;
              }
              
              if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                setState(() => _selectedActionIndex = (_selectedActionIndex - 1).clamp(0, _dockActions.length - 1));
                return KeyEventResult.handled;
              }
              if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                setState(() => _selectedActionIndex = (_selectedActionIndex + 1).clamp(0, _dockActions.length - 1));
                return KeyEventResult.handled;
              }
              
              // Handle Volume Adjustment when volume is selected
              if (_dockActions[_selectedActionIndex] == 'volume') {
                if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                  _setVolume((_volume + 0.05).clamp(0.0, 1.0));
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                  _setVolume((_volume - 0.05).clamp(0.0, 1.0));
                  return KeyEventResult.handled;
                }
              }

              if (event.logicalKey == LogicalKeyboardKey.select || event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.gameButtonA) {
                _triggerDockAction(_dockActions[_selectedActionIndex]);
                return KeyEventResult.handled;
              }
            }
            return KeyEventResult.handled; // Consume all when dock is open
          }

          if (event is KeyDownEvent) {
            debugPrint('DEBUG: KeyDown: ${event.logicalKey.debugName} | Label: ${event.logicalKey.keyLabel} | ID: ${event.logicalKey.keyId}');
          }
          
          



          final libretroId = _keyMap[event.logicalKey];
          if (libretroId != null) {
            if (event is KeyEvent) {
              final method = (event is KeyDownEvent) ? 'keyDown' : 'keyUp';
              if (event is KeyDownEvent || event is KeyUpEvent) {
                if (libretroId < 100) {
                  _channel.invokeMethod(method, {'keyCode': _toPlatformKeyCode(libretroId)});
                } else {
                  
                  final isDown = event is KeyDownEvent;
                  final value = isDown ? 32767 : 0;
                  final negValue = isDown ? -32768 : 0;
                  
                  switch (libretroId) {
                    case 100: _channel.invokeMethod('setAnalog', {'index': 0, 'id': 0, 'value': negValue}); break; 
                    case 101: _channel.invokeMethod('setAnalog', {'index': 0, 'id': 0, 'value': value}); break;    
                    case 102: _channel.invokeMethod('setAnalog', {'index': 0, 'id': 1, 'value': negValue}); break; 
                    case 103: _channel.invokeMethod('setAnalog', {'index': 0, 'id': 1, 'value': value}); break;    
                    case 104: _channel.invokeMethod('setAnalog', {'index': 1, 'id': 0, 'value': negValue}); break; 
                    case 105: _channel.invokeMethod('setAnalog', {'index': 1, 'id': 0, 'value': value}); break;    
                    case 106: _channel.invokeMethod('setAnalog', {'index': 1, 'id': 1, 'value': negValue}); break; 
                    case 107: _channel.invokeMethod('setAnalog', {'index': 1, 'id': 1, 'value': value}); break;    
                  }
                }
              }
            }
            
            return KeyEventResult.handled;
          }
          
          
          
          final label = event.logicalKey.keyLabel.toLowerCase();
          if (label.contains('game button') || label.contains('arrow') || label.contains('dpad')) {
            return KeyEventResult.handled;
          }
          
          return KeyEventResult.ignored;
        },
        child: Stack(
          children: [
            
            Positioned.fill(
              child: _EmulatorSurface(
                romPath: widget.romPath,
                corePath: widget.corePath,
                systemPath: CoreManager.instance.systemDir,
                textureId: _textureId,
                scalingMode: _scalingMode,
                coreAspectRatio: _coreAspectRatio,
              ),
            ),

            
            if (Platform.isIOS)
              Positioned.fill(child: IosGamepad(
                onDown: (code) => _channel.invokeMethod('keyDown', {'keyCode': code}),
                onUp: (code) => _channel.invokeMethod('keyUp', {'keyCode': code}),
              )),
            if (isNarrowPortrait && !Platform.isIOS)
              Positioned.fill(
                child: VirtualGamepad(
                  onButtonDown: (btn) => _channel
                      .invokeMethod('keyDown', {'keyCode': btn}),
                  onButtonUp: (btn) =>
                      _channel.invokeMethod('keyUp', {'keyCode': btn}),
                ),
              ),

            
            if (_showDock)
              Positioned.fill(
                child: RepaintBoundary(
                  child: FocusScope(
                    node: FocusScopeNode(),
                    child: Stack(
                      children: [
                        // Backdrop Dim/Blur (Conditional for performance)
                        Positioned.fill(
                          child: GestureDetector(
                            onTap: () => setState(() => _showDock = false),
                            child: Platform.isAndroid 
                              ? Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Colors.black.withOpacity(0.2),
                                        Colors.black.withOpacity(0.8),
                                      ],
                                    ),
                                  ),
                                )
                              : BackdropFilter(
                                  filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                                  child: Container(color: Colors.black.withOpacity(0.4)),
                                ),
                          ),
                        ),
                      // The Dock itself
                      Positioned(
                        bottom: (isNarrowPortrait ? 40 : 20) + MediaQuery.of(context).padding.bottom,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Focus(
                            focusNode: _dockFocusNode,
                            child: _PremiumDock(
                              selectedIndex: _selectedActionIndex,
                              onReset: () async {
                                await _channel.invokeMethod('reset');
                                setState(() => _showDock = false);
                              },
                              onExit: () => Navigator.pop(context),
                              onSave: _localSave,
                              onLoad: _localLoad,
                              onTogglePause: () {
                                if (_paused) _resume(); else _pause();
                                setState(() {});
                              },
                              isPaused: _paused,
                              onMinimize: () => setState(() => _showDock = false),
                              volume: _volume,
                               onVolumeChanged: _setVolume,
                               isFastForward: _fastForward,
                               onToggleFastForward: _toggleFastForward,
                               isSlowMotion: _slowMotion,
                               onToggleSlowMotion: _toggleSlowMotion,
                               scalingMode: _scalingMode,
                               onCycleScaling: () {
                                 setState(() {
                                   _scalingMode = ScalingMode.values[(_scalingMode.index + 1) % ScalingMode.values.length];
                                 });
                               },
                               onOpenSaveManager: () {
                                 setState(() {
                                   _showSaveManagerPanel = true;
                                   _showDock = false;
                                 });
                                 Future.delayed(const Duration(milliseconds: 50), () {
                                   _saveManagerFocusScopeNode.requestFocus();
                                 });
                               },
                               showSaveManagerPanel: _showSaveManagerPanel,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            
            if (_showSaveManagerPanel && widget.itemId != null)
              Positioned(
                bottom: (isNarrowPortrait ? 120 : 100) + MediaQuery.of(context).padding.bottom,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    width: 340,
                    decoration: BoxDecoration(
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.5),
                          blurRadius: 20,
                          spreadRadius: 5,
                        )
                      ],
                    ),
                    child: FocusScope(
                      node: _saveManagerFocusScopeNode,
                      child: SaveStateManager(
                        itemId: widget.itemId!,
                        title: widget.title,
                        serverUrl: widget.serverUrl,
                        token: widget.token,
                        userId: widget.userId,
                        onGetLocalState: () async {
                          return await _channel.invokeMethod<Uint8List>('saveState');
                        },
                        onApplyLocalState: (data) async {
                          await _channel.invokeMethod('loadState', {'state': data});
                        },
                        onClose: () {
                          setState(() {
                            _showSaveManagerPanel = false;
                            _showDock = true;
                          });
                          Future.delayed(const Duration(milliseconds: 50), () {
                            _dockFocusNode.requestFocus();
                          });
                        },
                      ),
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



class _PremiumDock extends StatelessWidget {
  final VoidCallback onReset;
  final VoidCallback onExit;
  final VoidCallback onSave;
  final VoidCallback onLoad;
  final VoidCallback onTogglePause;
  final VoidCallback onMinimize;
  final double volume;
  final Function(double) onVolumeChanged;
  final bool isFastForward;
  final VoidCallback onToggleFastForward;
  final bool isSlowMotion;
  final VoidCallback onToggleSlowMotion;
  final bool isPaused;
  final ScalingMode scalingMode;
  final VoidCallback onCycleScaling;
  final VoidCallback onOpenSaveManager;
  final bool showSaveManagerPanel;

  final int selectedIndex;

  const _PremiumDock({
    required this.selectedIndex,
    required this.onReset,
    required this.onExit,
    required this.onSave,
    required this.onLoad,
    required this.onTogglePause,
    required this.onMinimize,
    required this.volume,
    required this.onVolumeChanged,
    required this.isFastForward,
    required this.onToggleFastForward,
    required this.isSlowMotion,
    required this.onToggleSlowMotion,
    required this.isPaused,
    required this.scalingMode,
    required this.onCycleScaling,
    required this.onOpenSaveManager,
    required this.showSaveManagerPanel,
  });

  @override
  Widget build(BuildContext context) {
    final isSmall = MediaQuery.of(context).size.width < 800;

    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Platform.isAndroid
            ? Container(
                height: isSmall ? 56 : 64,
                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width - 32),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A).withOpacity(0.95),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                ),
                child: _buildDockContent(isSmall),
              )
            : BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  height: isSmall ? 56 : 64,
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width - 32),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white.withOpacity(0.2)),
                  ),
                  child: _buildDockContent(isSmall),
                ),
              ),
      ),
    );
  }

  Widget _buildDockContent(bool isSmall) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _DockButton(icon: isPaused ? Icons.play_arrow : Icons.pause, onPressed: onTogglePause, isSelected: selectedIndex == 0),
          const _VerticalDivider(),
          _DockButton(icon: Icons.save, onPressed: onSave, isSelected: selectedIndex == 1),
          _DockButton(icon: Icons.upload_file, onPressed: onLoad, isSelected: selectedIndex == 2),
          _DockButton(
            icon: Icons.cloud_sync, 
            onPressed: onOpenSaveManager,
            color: showSaveManagerPanel ? const Color(0xFFFF5C00) : Colors.white70,
            isSelected: selectedIndex == 3,
          ),
          const _VerticalDivider(),
          _DockButton(icon: Icons.refresh, onPressed: onReset, isSelected: selectedIndex == 4),
          const _VerticalDivider(),
          _DockButton(
            icon: Icons.bolt, 
            onPressed: onToggleFastForward, 
            color: isFastForward ? Colors.yellowAccent : Colors.white70,
            isSelected: selectedIndex == 5,
          ),
          const _VerticalDivider(),
          
          if (!Platform.isAndroid) ...[
            _DockButton(
              icon: scalingMode == ScalingMode.stretch ? Icons.aspect_ratio : (scalingMode == ScalingMode.fit ? Icons.fit_screen : Icons.zoom_in),
              onPressed: onCycleScaling,
              color: Colors.white70,
              isSelected: selectedIndex == 6,
            ),
            const _VerticalDivider(),
          ],

          // Volume Group (Desktop Only)
          if (!Platform.isAndroid) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: selectedIndex == 7 ? Colors.white.withOpacity(0.1) : Colors.transparent,
                border: Border.all(color: selectedIndex == 7 ? Colors.white24 : Colors.transparent),
              ),
              child: Row(
                children: [
                  Icon(volume == 0 ? Icons.volume_off : Icons.volume_up, color: Colors.white70, size: 18),
                  SizedBox(
                    width: isSmall ? 60 : 80,
                    child: SliderTheme(
                      data: SliderThemeData(
                        trackHeight: 2,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                        activeTrackColor: Colors.white,
                        inactiveTrackColor: Colors.white24,
                        thumbColor: Colors.white,
                      ),
                      child: Slider(
                        value: volume,
                        onChanged: onVolumeChanged,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const _VerticalDivider(),
          ],

          _DockButton(icon: Icons.keyboard_arrow_down, onPressed: onMinimize, isSelected: selectedIndex == (Platform.isAndroid ? 6 : 8)),
          _DockButton(icon: Icons.close, onPressed: onExit, color: Colors.redAccent, isSelected: selectedIndex == (Platform.isAndroid ? 7 : 9)),
        ],
      ),
    );
  }
}

class _DockButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final Color color;
  final bool isSelected;

  const _DockButton({
    required this.icon,
    required this.onPressed,
    this.color = Colors.white70,
    this.isSelected = false,
  });

  @override
  State<_DockButton> createState() => _DockButtonState();
}

class _DockButtonState extends State<_DockButton> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: widget.isSelected ? widget.color : Colors.transparent,
          width: 2,
        ),
        color: widget.isSelected ? widget.color.withOpacity(0.2) : Colors.transparent,
      ),
      child: IconButton(
        icon: Icon(widget.icon, color: widget.color),
        onPressed: widget.onPressed,
        hoverColor: Colors.white.withOpacity(0.1),
        splashRadius: 24,
      ),
    );
  }
}

class _VerticalDivider extends StatelessWidget {
  const _VerticalDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 24,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: Colors.white.withOpacity(0.1),
    );
  }
}




class _EmulatorSurface extends StatelessWidget {
  final String romPath;
  final String corePath;
  final String? systemPath;
  final int? textureId;
  final ScalingMode scalingMode;
  final double coreAspectRatio;

  const _EmulatorSurface({
    required this.romPath,
    required this.corePath,
    this.systemPath,
    this.textureId,
    required this.scalingMode,
    required this.coreAspectRatio,
  });

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (Platform.isWindows || Platform.isIOS) {
      if (textureId != null) {
        child = Texture(
          textureId: textureId!,
          filterQuality: FilterQuality.none, 
        );
      } else {
        child = const Center(child: Text("Loading Emulator...", style: TextStyle(color: Colors.white)));
      }
    } else {
      child = PlatformViewLink(
        viewType: 'com.retrostream.vantage/retro_view',
        surfaceFactory: (context, controller) {
          return AndroidViewSurface(
            controller: controller as AndroidViewController,
            gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
            hitTestBehavior: PlatformViewHitTestBehavior.opaque,
          );
        },
        onCreatePlatformView: (params) {
          return PlatformViewsService.initExpensiveAndroidView(
            id: params.id,
            viewType: 'com.retrostream.vantage/retro_view',
            layoutDirection: TextDirection.ltr,
            creationParams: {
              'romPath': romPath,
              'corePath': corePath,
              'systemPath': systemPath,
            },
            creationParamsCodec: const StandardMessageCodec(),
          )
            ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
            ..create();
        },
      );
    }

    final orientation = MediaQuery.of(context).orientation;
    final alignment = orientation == Orientation.portrait ? Alignment.topCenter : Alignment.center;

    
    
    if (Platform.isAndroid || (Platform.isIOS && orientation == Orientation.portrait)) {
      return Align(
        alignment: alignment,
        child: AspectRatio(
          aspectRatio: coreAspectRatio,
          child: child,
        ),
      );
    }

    switch (scalingMode) {
      case ScalingMode.stretch:
        return SizedBox.expand(child: child);
      case ScalingMode.fit:
      case ScalingMode.originalAspectRatio:
        return Center(
          child: AspectRatio(
            aspectRatio: coreAspectRatio,
            child: child,
          ),
        );
    }
  }
}





const int _kDpadUp    = 19; 
const int _kDpadDown  = 20;
const int _kDpadLeft  = 21;
const int _kDpadRight = 22;
const int _kA         = 96; 
const int _kB         = 97;
const int _kX         = 99;
const int _kY         = 100;
const int _kSelect    = 109; 
const int _kStart     = 108; 
const int _kL1        = 102;
const int _kR1        = 103;
const int _kL2        = 104;
const int _kR2        = 105;

class _Btn {
  final int keyCode;
  final String label;
  double cx = 0, cy = 0, r = 0;
  double rw = 0, rh = 0;
  final bool isRect;
  bool pressed = false;

  _Btn(this.keyCode, this.label, {this.isRect = false});

  bool hit(double x, double y) {
    if (isRect) {
      return x >= cx - rw && x <= cx + rw && y >= cy - rh && y <= cy + rh;
    }
    final dx = x - cx, dy = y - cy;
    return dx * dx + dy * dy <= r * r;
  }
}

class VirtualGamepad extends StatefulWidget {
  final void Function(int keyCode) onButtonDown;
  final void Function(int keyCode) onButtonUp;

  const VirtualGamepad({
    super.key,
    required this.onButtonDown,
    required this.onButtonUp,
  });

  @override
  State<VirtualGamepad> createState() => _VirtualGamepadState();
}

class _VirtualGamepadState extends State<VirtualGamepad> {
  final List<_Btn> _buttons = [];
  final Map<int, _Btn> _activePointers = {};
  Size _lastSize = Size.zero;

  List<_Btn> _buildButtons(Size s) {
    final w = s.width, h = s.height;
    final sideMargin = w * 0.25;
    final bottomMargin = h * 0.20; 
    final btnR = w * 0.075;
    final dpad = w * 0.08;

    final dcx = sideMargin;
    final dcy = h - bottomMargin - dpad * 3.0;
    final gap = dpad * 1.45;

    final fcx = w - sideMargin;
    final fcy = h - bottomMargin - btnR * 3.0;
    final fg = btnR * 1.55;

    final mcy = h - (bottomMargin * 0.9); 
    final mw = btnR * 1.3, mh = btnR * 0.5;
    final mcx = w / 2;

    final sy = dcy - dpad * 3.5;
    final sw = btnR * 2.0, sh = btnR * 0.7;

    final s2y = sy - sh * 2.2;

    return [
      _Btn(_kDpadUp,    String.fromCharCode(Icons.keyboard_arrow_up.codePoint))..cx=dcx..cy=dcy-gap..r=dpad,
      _Btn(_kDpadDown,  String.fromCharCode(Icons.keyboard_arrow_down.codePoint))..cx=dcx..cy=dcy+gap..r=dpad,
      _Btn(_kDpadLeft,  String.fromCharCode(Icons.keyboard_arrow_left.codePoint))..cx=dcx-gap..cy=dcy..r=dpad,
      _Btn(_kDpadRight, String.fromCharCode(Icons.keyboard_arrow_right.codePoint))..cx=dcx+gap..cy=dcy..r=dpad,
      _Btn(_kA, 'A')..cx=fcx+fg..cy=fcy..r=btnR,
      _Btn(_kB, 'B')..cx=fcx..cy=fcy+fg..r=btnR,
      _Btn(_kX, 'X')..cx=fcx..cy=fcy-fg..r=btnR,
      _Btn(_kY, 'Y')..cx=fcx-fg..cy=fcy..r=btnR,
      _Btn(_kSelect, 'SEL', isRect: true)..cx=mcx-mw*1.2..cy=mcy..rw=mw..rh=mh,
      _Btn(_kStart,  'STA', isRect: true)..cx=mcx+mw*1.2..cy=mcy..rw=mw..rh=mh,
      _Btn(_kL1, 'L',  isRect: true)..cx=sideMargin..cy=sy..rw=sw..rh=sh,
      _Btn(_kR1, 'R',  isRect: true)..cx=w-sideMargin..cy=sy..rw=sw..rh=sh,
      _Btn(_kL2, 'L2', isRect: true)..cx=sideMargin..cy=s2y..rw=sw*0.8..rh=sh*0.8,
      _Btn(_kR2, 'R2', isRect: true)..cx=w-sideMargin..cy=s2y..rw=sw*0.8..rh=sh*0.8,
    ];
  }

  void _press(int ptr, _Btn btn) {
    _activePointers[ptr] = btn;
    btn.pressed = true;
    widget.onButtonDown(btn.keyCode);
    setState(() {});
  }

  void _release(int ptr) {
    final btn = _activePointers.remove(ptr);
    if (btn == null) return;
    if (_activePointers.values.every((b) => b != btn)) {
      btn.pressed = false;
      widget.onButtonUp(btn.keyCode);
    }
    setState(() {});
  }

  _Btn? _hitTest(double x, double y) {
    for (final b in _buttons) {
      if (b.hit(x, y)) return b;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, constraints) {
      final size = Size(constraints.maxWidth, constraints.maxHeight);
      if (size != _lastSize) {
        _lastSize = size;
        _buttons
          ..clear()
          ..addAll(_buildButtons(size));
      }
      return GestureDetector(
        onTapDown: (d) {
          final btn = _hitTest(d.localPosition.dx, d.localPosition.dy);
          if (btn != null) _press(0, btn);
        },
        onTapUp: (_) => _release(0),
        child: CustomPaint(
          painter: _GamepadPainter(_buttons),
          size: Size.infinite,
        ),
      );
    });
  }
}

class _GamepadPainter extends CustomPainter {
  final List<_Btn> buttons;

  _GamepadPainter(this.buttons);

  static final _fill = Paint()
    ..color = const Color(0x96B4B4D2)
    ..style = PaintingStyle.fill;
  static final _pressed = Paint()
    ..color = const Color(0xD27C5CBF)
    ..style = PaintingStyle.fill;
  static final _stroke = Paint()
    ..color = const Color(0x64FFFFFF)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;

  @override
  void paint(Canvas canvas, Size size) {
    final labelStyle = TextStyle(
      color: Colors.white,
      fontSize: size.width * 0.035,
      fontWeight: FontWeight.bold,
    );

    for (final btn in buttons) {
      final paint = btn.pressed ? _pressed : _fill;
      if (btn.isRect) {
        final rect = RRect.fromLTRBR(
          btn.cx - btn.rw, btn.cy - btn.rh,
          btn.cx + btn.rw, btn.cy + btn.rh,
          Radius.circular(btn.rh),
        );
        canvas.drawRRect(rect, paint);
        canvas.drawRRect(rect, _stroke);
      } else {
        canvas.drawCircle(Offset(btn.cx, btn.cy), btn.r, paint);
        canvas.drawCircle(Offset(btn.cx, btn.cy), btn.r, _stroke);
      }

      
      final isIcon = btn.label.length == 1 && btn.label.codeUnitAt(0) > 0xE000;
      final tp = TextPainter(
        text: TextSpan(
          text: btn.label, 
          style: labelStyle.copyWith(
            fontFamily: isIcon ? 'MaterialIcons' : null,
            fontSize: isIcon ? size.width * 0.05 : labelStyle.fontSize,
          )
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas,
          Offset(btn.cx - tp.width / 2, btn.cy - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_GamepadPainter oldDelegate) => true;
}

