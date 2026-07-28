import 'package:flutter/material.dart';

class AppColors {
  static const Color primary = Color(0xFF0D2B4D);
  static const Color secondary = Color(0xFF2563EB);
  static const Color lightBlue = Color(0xFFA7C7F5);
  static const Color background = Color(0xFFFEFAF2);
  static const Color accent = Color(0xFFFFD166);
  static const Color surface = Colors.white;
  static const Color border = Color(0xFFD9E7F8);
  static const Color mutedText = Color(0xFF64748B);
}

class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color backgroundColor;
  final bool isLoading;
  final double height;
  final double borderRadius;

  const PrimaryButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.backgroundColor = AppColors.secondary,
    this.isLoading = false,
    this.height = 54,
    this.borderRadius = 18,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: height,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.lightBlue.withValues(alpha: 0.55),
          disabledForegroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadius),
          ),
          elevation: 0,
          shadowColor: Colors.transparent,
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLoading)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: Colors.white,
                ),
              )
            else if (icon != null)
              Icon(icon, size: 21),
            if (isLoading || icon != null) const SizedBox(width: 10),
            Text(isLoading ? 'Carregando...' : label),
          ],
        ),
      ),
    );
  }
}

class SecondaryTextButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  const SecondaryTextButton({
    required this.label,
    required this.onPressed,
    this.icon,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final style = TextButton.styleFrom(
      foregroundColor: AppColors.secondary,
      disabledForegroundColor: AppColors.mutedText.withValues(alpha: 0.45),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
    );

    if (icon == null) {
      return TextButton(
        onPressed: onPressed,
        style: style,
        child: Text(label, textAlign: TextAlign.center),
      );
    }

    return TextButton.icon(
      onPressed: onPressed,
      style: style,
      icon: Icon(icon, size: 19),
      label: Text(label),
    );
  }
}

class ShortcutCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback? onTap;
  final Color? backgroundColor;
  final Color iconColor;
  final Color? textColor;

  const ShortcutCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.backgroundColor,
    this.iconColor = AppColors.secondary,
    this.textColor,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveTextColor = textColor ?? AppColors.primary;
    final effectiveBackground = backgroundColor == AppColors.accent
        ? AppColors.accent.withValues(alpha: 0.22)
        : backgroundColor ?? AppColors.surface;

    return Semantics(
      button: true,
      enabled: onTap != null,
      label: '$title. $subtitle',
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0D0D2B4D),
              blurRadius: 16,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Material(
          color: effectiveBackground,
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            overlayColor: WidgetStatePropertyAll(
              AppColors.secondary.withValues(alpha: 0.08),
            ),
            child: Ink(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              decoration: BoxDecoration(
                color: effectiveBackground,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: backgroundColor == AppColors.accent
                      ? AppColors.accent.withValues(alpha: 0.75)
                      : AppColors.border,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, size: 25, color: iconColor),
                  ),
                  const SizedBox(height: 9),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      title,
                      maxLines: 1,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: effectiveTextColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: effectiveTextColor.withValues(alpha: 0.74),
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
