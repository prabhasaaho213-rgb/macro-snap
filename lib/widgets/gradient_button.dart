import 'package:flutter/material.dart';
import '../core/theme.dart';

class GradientButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Gradient? gradient;
  final VoidCallback? onPressed;
  final double height;
  final double? width;
  final bool loading;
  final bool disabled;

  const GradientButton({
    super.key,
    required this.label,
    this.icon,
    this.gradient,
    this.onPressed,
    this.height = 56,
    this.width,
    this.loading = false,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveGradient = gradient ?? MacroSnapTheme.accentGradient;
    final isDisabled = disabled || loading || onPressed == null;
    return SizedBox(
      width: width ?? double.infinity,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: isDisabled
              ? const LinearGradient(
                  colors: [Color(0xFFCBD5E1), Color(0xFFCBD5E1)],
                )
              : effectiveGradient,
          borderRadius: BorderRadius.circular(18),
          boxShadow: isDisabled
              ? []
              : [
                  BoxShadow(
                    color: effectiveGradient.colors.first.withValues(
                      alpha: 0.3,
                    ),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: isDisabled ? null : onPressed,
            child: Center(
              child: loading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.black,
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (icon != null) ...[
                          Icon(
                            icon,
                            color: isDisabled
                                ? const Color(0xFF64748B)
                                : Colors.black,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                        ],
                        // Flexible + FittedBox(scaleDown): a label longer
                        // than the button shrinks to fit instead of being
                        // cut with an ellipsis — the CTA always reads fully.
                        Flexible(
                          child: Tooltip(
                            message: label,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                label,
                                maxLines: 1,
                                softWrap: false,
                                style: TextStyle(
                                  color: isDisabled
                                      ? const Color(0xFF64748B)
                                      : Colors.black,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
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
