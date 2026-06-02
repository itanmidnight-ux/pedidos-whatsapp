import 'package:flutter/material.dart';

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
        // Banda superior - nombre empresa (estático)
        Container(
          color: const Color(0xFF1A3009),
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('🌾', style: TextStyle(fontSize: 13)),
              const SizedBox(width: 6),
              const Text(
                'CONCENTRADOS MONSERRATH',
                style: TextStyle(
                  color: Color(0xFFD4800A),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(width: 6),
              const Text('🌾', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
        // AppBar normal con título de página
        AppBar(
          backgroundColor: const Color(0xFF2D5016),
          foregroundColor: Colors.white,
          title: Text(
            pageTitle,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 17,
            ),
          ),
          elevation: 0,
          toolbarHeight: 52,
          actions: actions,
        ),
      ],
    );
  }
}
