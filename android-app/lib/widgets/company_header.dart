import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../services/api_service.dart';

class CompanyHeader extends StatelessWidget implements PreferredSizeWidget {
  final String pageTitle;
  final List<Widget>? actions;

  const CompanyHeader({
    super.key,
    required this.pageTitle,
    this.actions,
  });

  @override
  Size get preferredSize => const Size.fromHeight(88);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Consumer<ThemeProvider>(
          builder: (_, theme, __) => Container(
            color: const Color(0xFF1A3009),
            padding: const EdgeInsets.symmetric(vertical: 6),
            width: double.infinity,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (theme.logoFilename != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image.network(
                        ApiService.logoUrl(theme.logoFilename!),
                        width: 16, height: 16, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Text('🌾', style: TextStyle(fontSize: 12)),
                      ),
                    ),
                  )
                else
                  const Text('🌾', style: TextStyle(fontSize: 12)),
                const SizedBox(width: 6),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      theme.brandName.toUpperCase(),
                      style: const TextStyle(
                        color: Color(0xFFD4800A),
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        AppBar(
          primary: false,
          backgroundColor: const Color(0xFF2D5016),
          foregroundColor: Colors.white,
          title: Text(
            pageTitle,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
          ),
          elevation: 0,
          toolbarHeight: 52,
          actions: actions,
        ),
      ],
    );
  }
}
