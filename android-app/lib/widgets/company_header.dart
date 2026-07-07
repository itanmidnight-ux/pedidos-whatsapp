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
  Size get preferredSize => const Size.fromHeight(92);

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (_, theme, __) {
        // Franja superior un tono mas oscuro que el primario de marca (no
        // hardcodeado) -- si el admin cambia la paleta, el header cambia con
        // ella en vez de quedarse pegado al verde original.
        final stripColor = Color.alphaBlend(
          Colors.black.withValues(alpha: 0.22),
          theme.primary,
        );
        return Container(
          decoration: BoxDecoration(
            boxShadow: [
              BoxShadow(
                color: theme.primary.withValues(alpha: 0.18),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                color: stripColor,
                padding: const EdgeInsets.symmetric(vertical: 8),
                width: double.infinity,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (theme.logoFilename != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: Image.network(
                            ApiService.logoUrl(theme.logoFilename!),
                            width: 18, height: 18, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Icon(
                              Icons.storefront_rounded, size: 16, color: theme.accent),
                          ),
                        ),
                      )
                    else
                      Icon(Icons.storefront_rounded, size: 16, color: theme.accent),
                    const SizedBox(width: 8),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          theme.brandName.toUpperCase(),
                          style: TextStyle(
                            color: theme.accent,
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
              AppBar(
                primary: false,
                backgroundColor: theme.primary,
                foregroundColor: Colors.white,
                title: Text(
                  pageTitle,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
                ),
                elevation: 0,
                toolbarHeight: 56,
                actions: actions,
              ),
            ],
          ),
        );
      },
    );
  }
}
