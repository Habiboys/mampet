import 'package:flutter/material.dart';

import '../domain/enums.dart';

/// Grade badge (C/B/A/S/SS) visually distinct from Rarity badges.
class GradeBadge extends StatelessWidget {
  final CategoryGrade grade;
  final bool compact;

  const GradeBadge({
    super.key,
    required this.grade,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final isS = grade == CategoryGrade.s;
    final isSS = grade == CategoryGrade.ss;

    return Semantics(
      label: 'Grade ${grade.code} ${grade.title}',
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 7 : 10,
          vertical: compact ? 3 : 5,
        ),
        decoration: BoxDecoration(
          color: grade.surfaceColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: grade.color,
            width: isSS ? 2.2 : (isS ? 1.8 : 1.3),
          ),
          boxShadow: (isS || isSS)
              ? [
                  BoxShadow(
                    color: grade.color.withValues(alpha: isSS ? 0.35 : 0.2),
                    blurRadius: isSS ? 10 : 6,
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSS) ...[
              Icon(Icons.workspace_premium_rounded,
                  size: compact ? 12 : 14, color: grade.color),
              const SizedBox(width: 3),
            ] else if (isS) ...[
              Icon(Icons.auto_awesome_rounded,
                  size: compact ? 11 : 13, color: grade.color),
              const SizedBox(width: 3),
            ],
            Text(
              'Grade ${grade.code}',
              style: TextStyle(
                fontSize: compact ? 10 : 12,
                fontWeight: FontWeight.w800,
                color: grade.color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
