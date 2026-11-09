import 'package:flutter/material.dart';

class SwipeToRevealDelete extends StatefulWidget {
  const SwipeToRevealDelete(
      {super.key, required this.child, required this.onDelete});
  final Widget child;
  final Future<void> Function() onDelete;
  @override
  State<SwipeToRevealDelete> createState() => _SwipeToRevealDeleteState();
}

class _SwipeToRevealDeleteState extends State<SwipeToRevealDelete> {
  bool open = false, deleting = false;
  double drag = 0;
  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(children: [
          if (open)
            Positioned.fill(
                child: Align(
                    alignment: Alignment.centerRight,
                    child: SizedBox(
                        width: 64,
                        child: IconButton.filledTonal(
                            tooltip: 'Delete reminder',
                            style: IconButton.styleFrom(
                                backgroundColor: Theme.of(context)
                                    .colorScheme
                                    .errorContainer,
                                foregroundColor: Theme.of(context)
                                    .colorScheme
                                    .onErrorContainer),
                            onPressed: deleting
                                ? null
                                : () async {
                                    setState(() => deleting = true);
                                    try {
                                      await widget.onDelete();
                                    } finally {
                                      if (mounted) {
                                        setState(() {
                                          deleting = false;
                                          open = false;
                                        });
                                      }
                                    }
                                  },
                            icon: const Icon(Icons.delete_outline))))),
          GestureDetector(
            onHorizontalDragStart: (_) => drag = 0,
            onHorizontalDragUpdate: (details) => drag += details.delta.dx,
            onHorizontalDragEnd: (_) {
              if (drag.abs() > 16) setState(() => open = drag < 0);
            },
            child: AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                transform: Matrix4.translationValues(open ? -64 : 0, 0, 0),
                child: widget.child),
          ),
        ]),
      );
}
