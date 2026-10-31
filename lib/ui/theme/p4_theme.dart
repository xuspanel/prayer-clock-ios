import 'package:flutter/material.dart';

class P4Colors {
  static const Color bg = Color(0xFF0E1621);
  static const Color tabBarBg = Color(0xFF111822);
  static const Color card = Color(0xFF1B2735);
  static const Color text = Color(0xFFE8EEF2);
  static const Color dim = Color(0xFF8A9BAE);
  static const Color teal = Color(0xFF26A69A);
  static const Color amber = Color(0xFFFFC107);
  static const Color orange = Color(0xFFFB8C00);
  static const Color red = Color(0xFFE53935);
  static const Color indigo = Color(0xFF3949AB);
  static const Color slate = Color(0xFF37474F);
}

ThemeData buildP4Theme() {
  return ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: P4Colors.bg,
    colorScheme: const ColorScheme.dark(
      primary: P4Colors.teal,
      secondary: P4Colors.amber,
      surface: P4Colors.card,
      error: P4Colors.red,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: P4Colors.bg,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: P4Colors.slate),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: P4Colors.slate),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: P4Colors.teal, width: 1.5),
      ),
      hintStyle: const TextStyle(color: P4Colors.dim, fontSize: 14),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: P4Colors.teal,
      inactiveTrackColor: P4Colors.slate,
      thumbColor: P4Colors.amber,
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return P4Colors.teal;
        return P4Colors.bg;
      }),
    ),
  );
}

class P4Card extends StatelessWidget {
  final Widget child;
  final Color? borderColor;
  final double borderWidth;
  final EdgeInsetsGeometry padding;

  const P4Card({
    super.key,
    required this.child,
    this.borderColor,
    this.borderWidth = 2.0,
    this.padding = const EdgeInsets.all(14),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: padding,
      decoration: BoxDecoration(
        color: P4Colors.card,
        borderRadius: BorderRadius.circular(14),
        border: borderColor != null
            ? Border.all(color: borderColor!, width: borderWidth)
            : null,
      ),
      child: child,
    );
  }
}

class P4Button extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final Color color;
  final bool small;
  final bool big;

  const P4Button({
    super.key,
    required this.label,
    required this.onPressed,
    this.color = P4Colors.teal,
    this.small = false,
    this.big = false,
  });

  @override
  Widget build(BuildContext context) {
    final fontSize = big ? 22.0 : (small ? 14.0 : 16.0);
    final padH = small ? 10.0 : 16.0;
    final padV = small ? 7.0 : 10.0;
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        disabledBackgroundColor: color.withValues(alpha: 0.45),
        disabledForegroundColor: Colors.white70,
        padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
        minimumSize: Size(small ? 0 : 56, 0),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        elevation: 0,
      ),
      onPressed: onPressed,
      child: Text(
        label,
        style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class P4FieldRow extends StatelessWidget {
  final Widget label;
  final Widget control;

  const P4FieldRow({
    super.key,
    required this.label,
    required this.control,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 5,
            child: DefaultTextStyle(
              style: const TextStyle(color: P4Colors.text, fontSize: 15),
              child: label,
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            flex: 6,
            child: Align(
              alignment: Alignment.centerRight,
              child: control,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shows a confirmation dialog mirroring the web app's `confirm(...)` (§4).
Future<bool> showP4ConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'OK',
  Color confirmColor = P4Colors.red,
}) async {
  final res = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: P4Colors.card,
      title: Text(title, style: const TextStyle(color: P4Colors.teal, fontSize: 18)),
      content: Text(message, style: const TextStyle(color: P4Colors.text)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel', style: TextStyle(color: P4Colors.dim)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: confirmColor,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return res ?? false;
}

/// Shows a text prompt dialog mirroring the web app's `prompt(...)`.
Future<String?> showP4PromptDialog(
  BuildContext context, {
  required String title,
  String initialValue = '',
  String hintText = '',
}) async {
  final controller = TextEditingController(text: initialValue);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: P4Colors.card,
      title: Text(title, style: const TextStyle(color: P4Colors.teal, fontSize: 18)),
      content: TextField(
        controller: controller,
        autofocus: true,
        style: const TextStyle(color: P4Colors.text),
        decoration: InputDecoration(hintText: hintText),
        onSubmitted: (v) => Navigator.of(ctx).pop(v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(null),
          child: const Text('Cancel', style: TextStyle(color: P4Colors.dim)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: P4Colors.teal,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.of(ctx).pop(controller.text),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

