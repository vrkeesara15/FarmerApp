import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../tokens/tokens.g.dart';

/// Horizontal sowing -> harvest timeline (SPEC 13.1 `StageTimeline`).
class StageTimeline extends StatelessWidget {
  /// Creates the timeline.
  const StageTimeline({
    required this.stages,
    required this.currentIndex,
    super.key,
  });

  /// Localised stage labels in order.
  final List<String> stages;

  /// Index of the current stage; earlier ones are done, later upcoming.
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    return Row(
      children: <Widget>[
        for (var i = 0; i < stages.length; i++)
          Expanded(
            child: _Stage(
              label: stages[i],
              done: i < currentIndex,
              current: i == currentIndex,
              first: i == 0,
              last: i == stages.length - 1,
              activeColor: p.primary,
              inactiveColor: p.border,
              lineWidth: app.borderWidth + 1,
            ),
          ),
      ],
    );
  }
}

class _Stage extends StatelessWidget {
  const _Stage({
    required this.label,
    required this.done,
    required this.current,
    required this.first,
    required this.last,
    required this.activeColor,
    required this.inactiveColor,
    required this.lineWidth,
  });

  final String label;
  final bool done;
  final bool current;
  final bool first;
  final bool last;
  final Color activeColor;
  final Color inactiveColor;
  final double lineWidth;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final active = done || current;
    final dotColor = active ? activeColor : inactiveColor;
    return Semantics(
      label: label,
      selected: current,
      child: Column(
        children: <Widget>[
          SizedBox(
            height: Tokens.space6,
            child: Row(
              children: <Widget>[
                Expanded(
                  child: ColoredBox(
                    color: first
                        ? Colors.transparent
                        : (active ? activeColor : inactiveColor),
                    child: SizedBox(height: lineWidth),
                  ),
                ),
                Container(
                  width: current ? Tokens.space6 : Tokens.space4,
                  height: current ? Tokens.space6 : Tokens.space4,
                  decoration: BoxDecoration(
                    color: done ? activeColor : p.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: dotColor, width: lineWidth),
                  ),
                  child: done
                      ? Icon(
                          Icons.check,
                          size: Tokens.space3,
                          color: p.primaryOn,
                        )
                      : null,
                ),
                Expanded(
                  child: ColoredBox(
                    color: last
                        ? Colors.transparent
                        : (done ? activeColor : inactiveColor),
                    child: SizedBox(height: lineWidth),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Tokens.space1),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: app.text.caption.copyWith(
              color: active ? p.text : p.textSecondary,
              fontWeight: current ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}
