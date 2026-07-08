/// Breakpoints únicos para toda la app (móvil / tablet / desktop-TV).
/// Debajo de [kTabletBreakpoint] el layout es el móvil de siempre (nav
/// inferior, columna única). A partir de [kTabletBreakpoint] las pantallas
/// con lista+detalle cambian a NavigationRail + panel lateral en vez de
/// apretar el mismo layout de teléfono en una tarjeta angosta.
const double kTabletBreakpoint = 600.0;
const double kDesktopBreakpoint = 1024.0;
