import 'package:flutter/material.dart';

import '../models/candle.dart';
import '../theme/app_theme.dart';

class CandlestickChart extends StatelessWidget {
  const CandlestickChart({
    super.key,
    required this.candles,
    this.height = 280,
    this.showVolume = true,
    this.entry,
    this.stop,
    this.target,
  });

  final List<Candle> candles;
  final double height;
  final bool showVolume;
  final double? entry;
  final double? stop;
  final double? target;

  @override
  Widget build(BuildContext context) {
    if (candles.isEmpty) {
      return SizedBox(
        height: height,
        child: const Center(child: Text('No candle data', style: TextStyle(color: AppColors.textMuted))),
      );
    }

    final display = candles.length > 80 ? candles.sublist(candles.length - 80) : candles;
    final chartH = showVolume ? height * 0.72 : height;

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SizedBox(
            height: chartH,
            width: double.infinity,
            child: CustomPaint(
              painter: _CandlePainter(
                candles: display,
                entry: entry,
                stop: stop,
                target: target,
              ),
            ),
          ),
          if (showVolume)
            SizedBox(
              height: height - chartH,
              width: double.infinity,
              child: CustomPaint(
                painter: _VolumePainter(candles: display),
              ),
            ),
        ],
      ),
    );
  }
}

class _CandlePainter extends CustomPainter {
  _CandlePainter({
    required this.candles,
    this.entry,
    this.stop,
    this.target,
  });

  final List<Candle> candles;
  final double? entry;
  final double? stop;
  final double? target;

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.isEmpty) return;

    final pad = 8.0;
    final w = size.width - pad * 2;
    final h = size.height - pad * 2;

    double minY = candles.first.low;
    double maxY = candles.first.high;
    for (final c in candles) {
      if (c.low < minY) minY = c.low;
      if (c.high > maxY) maxY = c.high;
    }
    for (final level in [entry, stop, target]) {
      if (level != null) {
        if (level < minY) minY = level;
        if (level > maxY) maxY = level;
      }
    }
    final range = (maxY - minY).abs() < 1 ? 1.0 : maxY - minY;
    minY -= range * 0.05;
    maxY += range * 0.05;

    double yOf(double price) => pad + h * (1 - (price - minY) / (maxY - minY));

    final gridPaint = Paint()
      ..color = AppColors.border.withValues(alpha: 0.5)
      ..strokeWidth = 0.5;
    for (var i = 1; i < 4; i++) {
      final gy = pad + h * i / 4;
      canvas.drawLine(Offset(pad, gy), Offset(pad + w, gy), gridPaint);
    }

    final slot = w / candles.length;
    final bodyW = (slot * 0.55).clamp(2.0, 10.0);

    for (var i = 0; i < candles.length; i++) {
      final c = candles[i];
      final cx = pad + slot * i + slot / 2;
      final bullish = c.close >= c.open;
      final color = bullish ? AppColors.profit : AppColors.loss;

      final wick = Paint()
        ..color = color
        ..strokeWidth = 1.2;
      canvas.drawLine(Offset(cx, yOf(c.high)), Offset(cx, yOf(c.low)), wick);

      final top = yOf(bullish ? c.close : c.open);
      final bottom = yOf(bullish ? c.open : c.close);
      final rect = Rect.fromCenter(
        center: Offset(cx, (top + bottom) / 2),
        width: bodyW,
        height: (bottom - top).abs().clamp(1.5, h),
      );
      canvas.drawRect(rect, Paint()..color = color);
    }

    void drawLevel(double? price, Color color, String label) {
      if (price == null) return;
      final y = yOf(price);
      final p = Paint()
        ..color = color
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke;
      canvas.drawLine(Offset(pad, y), Offset(pad + w, y), p);
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w600),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(pad + 4, y - 12));
    }

    drawLevel(entry, AppColors.accent, 'ENTRY');
    drawLevel(stop, AppColors.loss, 'SL');
    drawLevel(target, AppColors.profit, 'TGT');
  }

  @override
  bool shouldRepaint(covariant _CandlePainter old) =>
      old.candles != candles || old.entry != entry;
}

class _VolumePainter extends CustomPainter {
  _VolumePainter({required this.candles});
  final List<Candle> candles;

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.isEmpty) return;
    final maxVol = candles.map((c) => c.volume).reduce((a, b) => a > b ? a : b);
    if (maxVol <= 0) return;

    final pad = 8.0;
    final w = size.width - pad * 2;
    final h = size.height - 4;
    final slot = w / candles.length;
    final barW = (slot * 0.5).clamp(1.5, 8.0);

    for (var i = 0; i < candles.length; i++) {
      final c = candles[i];
      final bullish = c.close >= c.open;
      final barH = (c.volume / maxVol) * h;
      final cx = pad + slot * i + slot / 2;
      final rect = Rect.fromLTWH(cx - barW / 2, size.height - barH, barW, barH);
      canvas.drawRect(
        rect,
        Paint()..color = (bullish ? AppColors.profit : AppColors.loss).withValues(alpha: 0.35),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _VolumePainter old) => old.candles != candles;
}

class MiniSparkline extends StatelessWidget {
  const MiniSparkline({super.key, required this.candles, this.height = 40});
  final List<Candle> candles;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (candles.length < 2) return SizedBox(height: height);
    final slice = candles.length > 30 ? candles.sublist(candles.length - 30) : candles;
    final first = slice.first.close;
    final last = slice.last.close;
    final up = last >= first;

    return SizedBox(
      height: height,
      width: 88,
      child: CustomPaint(
        painter: _SparkPainter(
          closes: slice.map((c) => c.close).toList(),
          color: up ? AppColors.profit : AppColors.loss,
        ),
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter({required this.closes, required this.color});
  final List<double> closes;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (closes.length < 2) return;
    final min = closes.reduce((a, b) => a < b ? a : b);
    final max = closes.reduce((a, b) => a > b ? a : b);
    final range = (max - min).abs() < 0.01 ? 1.0 : max - min;

    final path = Path();
    for (var i = 0; i < closes.length; i++) {
      final x = size.width * i / (closes.length - 1);
      final y = size.height * (1 - (closes[i] - min) / range);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 1.8
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) => old.closes != closes;
}
