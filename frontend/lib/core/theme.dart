import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Wait for dismissal animation before callers dispose form controllers.
Future<T?> showSafeDialog<T>(
    {required BuildContext context, required WidgetBuilder builder}) async {
  final route = DialogRoute<T>(
      context: context, builder: builder, barrierDismissible: false);
  final result = await Navigator.of(context, rootNavigator: true).push(route);
  await route.completed;
  return result;
}

const background = Color(0xFF101718),
    surface = Color(0xFF1C2728),
    mint = Color(0xFF8DE9BB),
    muted = Color(0xFFA8B5AF),
    amber = Color(0xFFF4C378),
    ink = Color(0xFFF3F7F5),
    danger = Color(0xFFFFA7A7);
String money(dynamic paise) =>
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0)
        .format((paise as num? ?? 0) / 100);
String preciseMoney(dynamic paise) =>
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2)
        .format((paise as num? ?? 0) / 100);
String timestamp(dynamic value) => value is num
    ? DateFormat('d MMM, HH:mm')
        .format(DateTime.fromMillisecondsSinceEpoch(value.toInt() * 1000))
    : '—';
String human(String value) => value.replaceAll('_', ' ').toLowerCase();
ThemeData gatewayTheme() => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
        seedColor: mint,
        brightness: Brightness.dark,
        surface: background,
        primary: mint),
    scaffoldBackgroundColor: background,
    fontFamily: 'Arial',
    textTheme: const TextTheme(
        bodyMedium: TextStyle(fontSize: 15, color: ink, height: 1.45),
        bodyLarge: TextStyle(fontSize: 16, color: ink),
        titleLarge:
            TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: ink)),
    inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF131D1E),
        contentPadding: const EdgeInsets.all(17),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Colors.white12)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Colors.white12)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: mint)),
        labelStyle: const TextStyle(color: muted, fontSize: 14)),
    filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
            backgroundColor: mint,
            foregroundColor: background,
            minimumSize: const Size(48, 48),
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
            textStyle:
                const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13)))),
    outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
            foregroundColor: ink,
            minimumSize: const Size(48, 48),
            side: const BorderSide(color: Colors.white12),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13)))),
    dividerColor: Colors.white10,
    snackBarTheme: const SnackBarThemeData(
        backgroundColor: surface, contentTextStyle: TextStyle(color: ink)));

class GlassCard extends StatelessWidget {
  const GlassCard(
      {super.key, required this.child, this.padding = 24, this.accent = false});
  final Widget child;
  final double padding;
  final bool accent;
  @override
  Widget build(BuildContext context) => Container(
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(23),
          boxShadow: const [
            BoxShadow(
                color: Color(0x55000000),
                offset: Offset(8, 10),
                blurRadius: 26),
            BoxShadow(
                color: Color(0x082FFFFF),
                offset: Offset(-3, -3),
                blurRadius: 12)
          ]),
      child: ClipRRect(
          borderRadius: BorderRadius.circular(23),
          child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                  padding: EdgeInsets.all(padding),
                  decoration: BoxDecoration(
                      gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: accent
                              ? const [Color(0xFF27473C), Color(0xCC1B2D29)]
                              : const [Color(0xEA222F30), Color(0xCB192223)]),
                      borderRadius: BorderRadius.circular(23),
                      border: Border.all(
                          color: accent
                              ? mint.withValues(alpha: .25)
                              : Colors.white.withValues(alpha: .08))),
                  child: child))));
}

class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, this.color = mint});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
          color: color.withValues(alpha: .10),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: .15))),
      child: Text(text,
          style: TextStyle(
              color: color, fontSize: 12, fontWeight: FontWeight.w600)));
}

class PageHeading extends StatelessWidget {
  const PageHeading(this.title, this.subtitle, {super.key, this.action});
  final String title, subtitle;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: LayoutBuilder(builder: (_, box) {
        final heading =
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -1)),
          const SizedBox(height: 8),
          Text(subtitle, style: const TextStyle(color: muted, fontSize: 14))
        ]);
        return box.maxWidth < 600
            ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                heading,
                if (action != null) ...[const SizedBox(height: 18), action!]
              ])
            : Row(children: [
                Expanded(child: heading),
                if (action != null) action!
              ]);
      }));
}

class EmptyState extends StatelessWidget {
  const EmptyState(this.title, this.description,
      {super.key, this.action, this.icon = Icons.inbox_outlined});
  final String title, description;
  final Widget? action;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 38, horizontal: 12),
      child: Center(
          child: Column(children: [
        Icon(icon, size: 36, color: mint.withValues(alpha: .6)),
        const SizedBox(height: 18),
        Text(title,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Text(description,
            textAlign: TextAlign.center, style: const TextStyle(color: muted)),
        if (action != null) ...[const SizedBox(height: 20), action!]
      ])));
}

void toast(BuildContext context, String message, {bool error = false}) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: error ? const Color(0xFF553638) : surface));

class Metric extends StatelessWidget {
  const Metric(this.label, this.value, this.note, this.icon,
      {super.key, this.highlight = false});
  final String label, value, note;
  final IconData icon;
  final bool highlight;
  @override
  Widget build(BuildContext context) => GlassCard(
      accent: highlight,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text(label,
                  style: const TextStyle(color: muted, fontSize: 14))),
          Icon(icon, color: highlight ? mint : muted, size: 20)
        ]),
        const SizedBox(height: 24),
        Text(value,
            style: const TextStyle(
                fontSize: 31, fontWeight: FontWeight.w600, letterSpacing: -.8)),
        const SizedBox(height: 10),
        Text(note,
            style: TextStyle(color: highlight ? mint : muted, fontSize: 12))
      ]));
}

class ResponsiveGrid extends StatelessWidget {
  const ResponsiveGrid(
      {super.key, required this.children, this.minWidth = 230});
  final List<Widget> children;
  final double minWidth;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (_, box) {
        final count = (box.maxWidth / minWidth)
            .floor()
            .clamp(1, children.length.clamp(1, 12));
        final width = (box.maxWidth - (count - 1) * 18) / count;
        return Wrap(
            spacing: 18,
            runSpacing: 18,
            children: children
                .map((child) => SizedBox(width: width, child: child))
                .toList());
      });
}
