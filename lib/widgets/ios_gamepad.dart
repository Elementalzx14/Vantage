import 'package:flutter/material.dart';

class IosGamepad extends StatelessWidget {
  final void Function(int) onDown;
  final void Function(int) onUp;
  const IosGamepad({super.key, required this.onDown, required this.onUp});

  Widget button(String label, int code) => _TouchButton(
        key: ValueKey('ios-pad-$code'),
        label: label,
        onDown: () => onDown(code),
        onUp: () => onUp(code),
      );

  Widget cluster(bool directions) => AspectRatio(
        aspectRatio: 1,
        child: LayoutBuilder(builder: (_, size) {
          final unit = size.maxWidth / 3;
          Widget at(int x, int y, String label, int code) => Positioned(
                left: x * unit,
                top: y * unit,
                width: unit,
                height: unit,
                child: button(label, code),
              );
          return Stack(
              children: directions
                  ? [
                      at(1, 0, '↑', 4),
                      at(1, 2, '↓', 5),
                      at(0, 1, '←', 6),
                      at(2, 1, '→', 7),
                    ]
                  : [
                      at(1, 0, 'X', 9),
                      at(1, 2, 'B', 0),
                      at(0, 1, 'Y', 1),
                      at(2, 1, 'A', 8),
                    ]);
        }),
      );

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Expanded(
                    flex: 3,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      SizedBox(height: 32, width: 76, child: button('L', 10)),
                      cluster(true),
                    ])),
                Expanded(
                    flex: 2,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        SizedBox(height: 32, child: button('SELECT', 2)),
                        const SizedBox(height: 6),
                        SizedBox(height: 32, child: button('START', 3)),
                      ]),
                    )),
                Expanded(
                    flex: 3,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      SizedBox(height: 32, width: 76, child: button('R', 11)),
                      cluster(false),
                    ])),
              ]),
            ),
          ),
        ),
      );
}

class _TouchButton extends StatefulWidget {
  final String label;
  final VoidCallback onDown, onUp;
  const _TouchButton(
      {super.key,
      required this.label,
      required this.onDown,
      required this.onUp});
  @override
  State<_TouchButton> createState() => _TouchButtonState();
}

class _TouchButtonState extends State<_TouchButton> {
  final _pointers = <int>{};
  void release(int pointer) {
    if (!_pointers.remove(pointer)) return;
    if (_pointers.isEmpty) widget.onUp();
    setState(() {});
  }

  @override
  void dispose() {
    if (_pointers.isNotEmpty) widget.onUp();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
        label: widget.label,
        button: true,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) {
            if (_pointers.isEmpty) widget.onDown();
            setState(() => _pointers.add(event.pointer));
          },
          onPointerUp: (event) => release(event.pointer),
          onPointerCancel: (event) => release(event.pointer),
          child: Container(
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: _pointers.isEmpty ? Colors.white24 : Colors.deepOrange,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white54),
            ),
            alignment: Alignment.center,
            child: Text(widget.label,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold)),
          ),
        ),
      );
}
