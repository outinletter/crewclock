import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Hosts the system glass material and controls on iOS.
class NativeGlassControl extends StatefulWidget {
  const NativeGlassControl({
    super.key,
    required this.kind,
    required this.onActivate,
    required this.fallback,
    required this.height,
    this.label = '',
    this.labels = const [],
    this.selected = 0,
    this.enabled = true,
    this.onDarkHeader = false,
  });

  final String kind, label;
  final List<String> labels;
  final int selected;
  final bool enabled, onDarkHeader;
  final double height;
  final ValueChanged<int> onActivate;
  final Widget fallback;

  @override
  State<NativeGlassControl> createState() => _NativeGlassControlState();
}

class _NativeGlassControlState extends State<NativeGlassControl> {
  MethodChannel? _channel;

  Map<String, Object> get _configuration => {
        'kind': widget.kind,
        'label': widget.label,
        'labels': widget.labels,
        'selected': widget.selected,
        'enabled': widget.enabled,
        'dark': Theme.of(context).brightness == Brightness.dark,
        'header': widget.onDarkHeader,
      };

  @override
  void didUpdateWidget(covariant NativeGlassControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    _update();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _update();
  }

  void _update() {
    _channel?.invokeMethod<void>('update', _configuration);
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      return widget.fallback;
    }
    return SizedBox(
      height: widget.height,
      child: UiKitView(
        viewType: 'crewclock/glass',
        creationParams: _configuration,
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: (id) {
          _channel = MethodChannel('crewclock/glass/$id')
            ..setMethodCallHandler((call) async {
              if (call.method == 'activate' && mounted && widget.enabled) {
                widget.onActivate((call.arguments as num?)?.toInt() ?? 0);
              }
            });
          // State can change while UIKit creates the view.
          _update();
        },
      ),
    );
  }
}
