import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Circular budget-progress ring. Painting is untested (no golden tests in
/// v1); the fields it renders (`progress`, `amountText`, etc.) are plain
/// values so widget tests can assert on the rendered text and read the
/// widget's `progress` directly.
class MonthRing extends StatelessWidget {
  const MonthRing({
    super.key,
    required this.progress,
    required this.amountText,
    required this.descriptor,
    this.hint,
    this.footer,
    this.size = 220,
  });

  /// Signed fill fraction in `[-1, 1]` — see `budgetRingProgress` in
  /// providers/summary.dart. Positive fills gold clockwise from the top
  /// (money still within budget); negative fills red counter-clockwise from
  /// the top (overspent, magnitude = overspend / budget).
  final double progress;
  /// The big bold figure, e.g. "₹5,180" — only this is bold, per the
  /// mockup. Shrinks to fit the ring via [FittedBox] instead of overflowing.
  final String amountText;
  /// e.g. "left to spend" / "over budget" / "spent" — same style as [hint].
  final String descriptor;
  /// Extra line shown only when relevant, e.g. "Set a budget".
  final String? hint;
  final String? footer;
  final double size;

  @override
  Widget build(BuildContext context) {
    final descriptorStyle = Theme.of(context)
        .textTheme
        .bodyMedium
        ?.copyWith(color: kTextSecondary);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(progress),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: size * 0.72,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  // Same metallic gold treatment as the ring itself — the
                  // mockup's amount is gradient gold, not white.
                  child: ShaderMask(
                    shaderCallback: (bounds) =>
                        kPremiumGoldGradient.createShader(bounds),
                    blendMode: BlendMode.srcIn,
                    child: Text(
                      amountText,
                      maxLines: 1,
                      style:
                          Theme.of(context).textTheme.headlineMedium?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(descriptor, style: descriptorStyle, textAlign: TextAlign.center),
              if (hint != null) ...[
                const SizedBox(height: 2),
                Text(hint!, style: descriptorStyle, textAlign: TextAlign.center),
              ],
              if (footer != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: kSurfaceBlack,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: kCardBorder),
                  ),
                  child: Text(
                    footer!,
                    style: Theme.of(context)
                        .textTheme
                        .labelMedium
                        ?.copyWith(color: kTextSecondary),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.progress);

  final double progress;

  static const _strokeWidth = 14.0;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - _strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Layer 1: base track — very dark bronze, vertical gradient (not flat).
    final track = Paint()
      ..shader = kRingTrackGradient.createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth;
    canvas.drawCircle(center, radius, track);

    if (progress > 0) {
      const startAngle = -1.5707963267948966; // -90deg, clock-top start
      const tau = 6.283185307179586; // 2*pi
      final sweepAngle = tau * progress;

      // Layer 2: progress arc. The gradient's 6 stops span the FULL circle
      // (as in the mockup) and the arc simply reveals the first `progress`
      // portion of it — so a part-filled ring stays bright pale gold for
      // most of its length instead of compressing the whole bright→bronze
      // range into a short arc and going dark immediately.
      final sweep = SweepGradient(
        startAngle: 0,
        endAngle: tau,
        transform: const GradientRotation(startAngle),
        colors: kRingProgressColors,
        stops: kRingProgressStops,
      );

      // Layer 3: glow — barely visible on OLED (spec: ~10%, blur 16–20).
      final glow = Paint()
        ..color = kRingGlow.withValues(alpha: 0.10)
        ..style = PaintingStyle.stroke
        ..strokeWidth = _strokeWidth + 14
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
      canvas.drawArc(rect, startAngle, sweepAngle, false, glow);

      // Butt-capped arc + hand-drawn round end caps: a round StrokeCap on a
      // sweep-gradient arc samples the gradient at wrapped angles *outside*
      // the sweep, which rendered as a wrong-colour blob at the seam.
      final arc = Paint()
        ..shader = sweep.createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = _strokeWidth
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(rect, startAngle, sweepAngle, false, arc);

      Offset onRing(double angle) => Offset(
            center.dx + radius * math.cos(angle),
            center.dy + radius * math.sin(angle),
          );
      canvas.drawCircle(
        onRing(startAngle),
        _strokeWidth / 2,
        Paint()..color = kRingProgressColors.first,
      );
      canvas.drawCircle(
        onRing(startAngle + sweepAngle),
        _strokeWidth / 2,
        Paint()..color = _ringColorAt(progress),
      );
    } else if (progress < 0) {
      // Overspent: fill red in the opposite direction from the same
      // top start point. `Canvas.drawArc` accepts a negative sweep angle
      // directly, so a negative `progress` just draws counter-clockwise —
      // no separate geometry needed.
      const startAngle = -1.5707963267948966; // -90deg, clock-top start
      const tau = 6.283185307179586; // 2*pi
      final sweepAngle = tau * progress; // negative

      final glow = Paint()
        ..color = kExpenseRed.withValues(alpha: 0.10)
        ..style = PaintingStyle.stroke
        ..strokeWidth = _strokeWidth + 14
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
      canvas.drawArc(rect, startAngle, sweepAngle, false, glow);

      final arc = Paint()
        ..color = kExpenseRed
        ..style = PaintingStyle.stroke
        ..strokeWidth = _strokeWidth
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(rect, startAngle, sweepAngle, false, arc);

      Offset onRing(double angle) => Offset(
            center.dx + radius * math.cos(angle),
            center.dy + radius * math.sin(angle),
          );
      final capPaint = Paint()..color = kExpenseRed;
      canvas.drawCircle(onRing(startAngle), _strokeWidth / 2, capPaint);
      canvas.drawCircle(
          onRing(startAngle + sweepAngle), _strokeWidth / 2, capPaint);
    }
  }

  /// The gradient colour at fraction [t] of the full circle — used to paint
  /// the tip cap the same colour the arc has where it ends.
  static Color _ringColorAt(double t) {
    final clamped = t.clamp(0.0, 1.0);
    for (var i = 0; i < kRingProgressStops.length - 1; i++) {
      final lo = kRingProgressStops[i];
      final hi = kRingProgressStops[i + 1];
      if (clamped <= hi) {
        final f = hi == lo ? 0.0 : (clamped - lo) / (hi - lo);
        return Color.lerp(
            kRingProgressColors[i], kRingProgressColors[i + 1], f)!;
      }
    }
    return kRingProgressColors.last;
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
