import 'package:flutter/material.dart';

import '../domain/enums.dart';

class ElementChip extends StatelessWidget {
  final MonsterElement element;
  final bool compact;

  const ElementChip({
    super.key,
    required this.element,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 10,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: element.softColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: element.color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(element.icon, size: compact ? 12 : 14, color: element.color),
          const SizedBox(width: 4),
          Text(
            element.label,
            style: TextStyle(
              fontSize: compact ? 10.5 : 12,
              fontWeight: FontWeight.w700,
              color: element.color,
            ),
          ),
        ],
      ),
    );
  }
}
