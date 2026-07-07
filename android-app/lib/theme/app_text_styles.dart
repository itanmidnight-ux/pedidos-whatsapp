import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTextStyles {
  AppTextStyles._();

  static TextStyle display(Color color) => GoogleFonts.manrope(
        fontSize: 28, fontWeight: FontWeight.w700, color: color, height: 1.2);

  static TextStyle h1(Color color) => GoogleFonts.manrope(
        fontSize: 22, fontWeight: FontWeight.w700, color: color, height: 1.25);

  static TextStyle h2(Color color) => GoogleFonts.manrope(
        fontSize: 18, fontWeight: FontWeight.w600, color: color, height: 1.3);

  static TextStyle body(Color color) => GoogleFonts.inter(
        fontSize: 14, fontWeight: FontWeight.w400, color: color, height: 1.4);

  static TextStyle bodyStrong(Color color) => GoogleFonts.inter(
        fontSize: 14, fontWeight: FontWeight.w600, color: color, height: 1.4);

  static TextStyle caption(Color color) => GoogleFonts.inter(
        fontSize: 12, fontWeight: FontWeight.w500, color: color, height: 1.3);

  static TextStyle statValue(Color color) => GoogleFonts.manrope(
        fontSize: 24, fontWeight: FontWeight.w700, color: color,
        fontFeatures: const [FontFeature.tabularFigures()]);
}
