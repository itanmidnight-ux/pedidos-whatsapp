import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'app_card.dart';

class StatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;
  final String? delta;
  final bool deltaPositive;

  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.delta,
    this.deltaPositive = true,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (icon != null) Icon(icon, size: 18, color: scheme.primary),
          if (icon != null) const SizedBox(width: 6),
          Expanded(child: Text(label, style: Theme.of(context).textTheme.labelSmall)),
        ]),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(value, style: Theme.of(context).textTheme.headlineSmall),
          if (delta != null) ...[
            const SizedBox(width: 8),
            Icon(deltaPositive ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                size: 14, color: deltaPositive ? AppTheme.successColor : AppTheme.errorColor),
            Text(delta!, style: TextStyle(
                fontSize: 12,
                color: deltaPositive ? AppTheme.successColor : AppTheme.errorColor)),
          ],
        ]),
      ]),
    );
  }
}
