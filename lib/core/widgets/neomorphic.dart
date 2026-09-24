import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

List<BoxShadow> _neoShadow({
  required bool inset,
  required Color darkColor,
  required Color lightColor,
  bool small = false,
  bool hover = false,
}) {
  if (inset) {
    final distance = small ? 3.0 : 6.0;
    final blur = small ? 6.0 : 10.0;
    return [
      BoxShadow(
        color: darkColor.withValues(alpha: 0.34),
        offset: Offset(distance, distance),
        blurRadius: blur,
        blurStyle: BlurStyle.inner,
      ),
      BoxShadow(
        color: lightColor.withValues(alpha: 0.98),
        offset: Offset(-distance, -distance),
        blurRadius: blur,
        blurStyle: BlurStyle.inner,
      ),
    ];
  }

  final distance = hover ? 12.0 : (small ? 5.0 : 9.0);
  final blur = hover ? 20.0 : (small ? 10.0 : 16.0);

  return [
    BoxShadow(
      color: darkColor.withValues(alpha: 0.58),
      offset: Offset(distance, distance),
      blurRadius: blur,
    ),
    BoxShadow(
      color: lightColor.withValues(alpha: 0.98),
      offset: Offset(-distance, -distance),
      blurRadius: blur,
    ),
  ];
}

class NeomorphicPanel extends StatelessWidget {
  const NeomorphicPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
    this.borderRadius = AppColors.radiusContainer,
    this.margin,
    this.color,
    this.gradient,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: color ?? AppColors.surfaceRaised,
        gradient: gradient,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: AppColors.borderSoft.withValues(alpha: 0.94),
          width: 1,
        ),
        boxShadow: _neoShadow(
          inset: false,
          darkColor: AppColors.shadowSoft,
          lightColor: AppColors.highlight,
        ),
      ),
      child: Padding(
        padding: padding,
        child: child,
      ),
    );
  }
}

class NeomorphicInset extends StatelessWidget {
  const NeomorphicInset({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    this.borderRadius = AppColors.radiusBase,
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? AppColors.surfacePressed,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: AppColors.borderSoft.withValues(alpha: 0.95),
        ),
        boxShadow: _neoShadow(
          inset: true,
          darkColor: AppColors.shadowDark,
          lightColor: AppColors.highlight,
        ),
      ),
      child: Padding(
        padding: padding,
        child: child,
      ),
    );
  }
}

class NeomorphicBadge extends StatelessWidget {
  const NeomorphicBadge({
    super.key,
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return NeomorphicPanel(
      borderRadius: 18,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: colorScheme.primary),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: AppColors.inkMuted,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class NeomorphicIconWell extends StatelessWidget {
  const NeomorphicIconWell({
    super.key,
    required this.icon,
    this.size = 56,
    this.iconSize = 24,
    this.color,
  });

  final IconData icon;
  final double size;
  final double iconSize;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color ?? AppColors.background,
        borderRadius: BorderRadius.circular(AppColors.radiusBase),
        border: Border.all(color: AppColors.borderSoft),
        boxShadow: _neoShadow(
          inset: false,
          small: true,
          darkColor: AppColors.shadowDark,
          lightColor: AppColors.shadowLight,
        ),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: iconSize, color: AppColors.primary),
    );
  }
}

enum NeomorphicButtonVariant { primary, secondary, ghost }

class NeomorphicButton extends StatefulWidget {
  const NeomorphicButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.variant = NeomorphicButtonVariant.primary,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final NeomorphicButtonVariant variant;
  final bool expand;

  @override
  State<NeomorphicButton> createState() => _NeomorphicButtonState();
}

class _NeomorphicButtonState extends State<NeomorphicButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final isPrimary = widget.variant == NeomorphicButtonVariant.primary;
    final isGhost = widget.variant == NeomorphicButtonVariant.ghost;
    final surfaceColor = isPrimary ? AppColors.primary : AppColors.background;
    final foregroundColor = isPrimary ? Colors.white : AppColors.primary;
    final button = Semantics(
      container: true,
      button: true,
      enabled: widget.onPressed != null,
      label: widget.label,
      child: ExcludeSemantics(
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          cursor: widget.onPressed == null
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
          child: GestureDetector(
            onTap: widget.onPressed,
            onTapDown: widget.onPressed == null
                ? null
                : (_) => setState(() => _pressed = true),
            onTapUp: widget.onPressed == null
                ? null
                : (_) => setState(() => _pressed = false),
            onTapCancel: () => setState(() => _pressed = false),
            child: AnimatedContainer(
              duration: AppColors.motion,
              curve: AppColors.motionCurve,
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: isGhost ? Colors.transparent : surfaceColor,
                borderRadius: BorderRadius.circular(AppColors.radiusBase),
                border: Border.all(
                  color: isPrimary
                      ? Colors.transparent
                      : AppColors.primary.withValues(alpha: 0.55),
                ),
                boxShadow: isGhost || _pressed
                    ? null
                    : _neoShadow(
                        inset: false,
                        small: true,
                        hover: _hovered,
                        darkColor: isPrimary
                            ? AppColors.shadowDarkStrong
                            : AppColors.shadowDark,
                        lightColor: AppColors.shadowLightStrong,
                      ),
              ),
              child: Row(
                mainAxisSize:
                    widget.expand ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (widget.icon != null) ...[
                    Icon(widget.icon, size: 18, color: foregroundColor),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    widget.label,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: foregroundColor,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    return widget.expand
        ? SizedBox(width: double.infinity, child: button)
        : button;
  }
}

class NeomorphicBackdrop extends StatelessWidget {
  const NeomorphicBackdrop({
    super.key,
    this.child,
    this.topOrb = true,
    this.bottomOrb = true,
  });

  final Widget? child;
  final bool topOrb;
  final bool bottomOrb;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.surfaceBase,
            ),
          ),
        ),
        if (topOrb)
          const Positioned(
            top: -120,
            right: -120,
            child: _AmbientPlate(
              width: 340,
              height: 340,
              color: Color.fromRGBO(255, 255, 255, 0.84),
            ),
          ),
        if (bottomOrb)
          const Positioned(
            bottom: -150,
            left: -90,
            child: _AmbientPlate(
              width: 280,
              height: 280,
              color: Color.fromRGBO(59, 200, 180, 0.10),
            ),
          ),
        if (child != null) child!,
      ],
    );
  }
}

class _AmbientPlate extends StatelessWidget {
  const _AmbientPlate({
    required this.width,
    required this.height,
    required this.color,
  });

  final double width;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(width / 2),
        boxShadow: [
          BoxShadow(
            color: AppColors.highlight.withValues(alpha: 0.85),
            offset: const Offset(-18, -18),
            blurRadius: 44,
          ),
          BoxShadow(
            color: AppColors.shadowSoft.withValues(alpha: 0.18),
            offset: const Offset(24, 28),
            blurRadius: 48,
          ),
        ],
      ),
      child: SizedBox(width: width, height: height),
    );
  }
}
