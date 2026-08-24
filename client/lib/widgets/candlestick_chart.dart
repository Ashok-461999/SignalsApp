import 'package:flutter/material.dart';

import '../models/candle.dart';
import '../theme/app_theme.dart';

class CandlestickChart extends StatefulWidget {
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
  State<CandlestickChart> createState() => _CandlestickChartState();
}

class _CandlestickChartState extends State<CandlestickChart> {
  final _transform = TransformationController();
  double _scale = 1;

  @override
  void initState() {
    super.initState();
    _transform.addListener(_onTransform);
  }

  void _onTransform() {
    final next = _transform.value.getMaxScaleOnAxis();
    if ((next - _scale).abs() > 0.02 && mounted) {
      setState(() => _scale = next);
    }
  }

  @override
  void dispose() {
    _transform.removeListener(_onTransform);
    _transform.dispose();
    super.dispose();
  }

  void _resetZoom() {
    _transform.value = Matrix4.identity();
    setState(() => _scale = 1);
  }

  double _chartWidth(BoxConstraints constraints, int candleCount) {
    final ideal = candleCount * 11.0;
    final viewport = constraints.maxWidth.isFinite && constraints.maxWidth > 0
        ? constraints.maxWidth
        : ideal;
    return ideal > viewport ? ideal : viewport;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.candles.isEmpty) {
      return SizedBox(
        height: widget.height,
        child: const Center(child: Text('No candle data', style: TextStyle(color: AppColors.textMuted))),
      );
    }

    final display = widget.candles.length > 120
        ? widget.candles.sublist(widget.candles.length - 120)
        : widget.candles;

    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
            child: Row(
              children: [
                Text(
                  _scale > 1.05 ? 'Drag to pan · tap reset' : 'Pinch to zoom · scroll page to move',
                  style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
                ),
                const Spacer(),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  tooltip: 'Reset zoom',
                  onPressed: _resetZoom,
                  icon: const Icon(Icons.fit_screen_rounded, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              children: [
                Expanded(
                  flex: widget.showVolume ? 72 : 100,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final chartWidth = _chartWidth(constraints, display.length);
                      return InteractiveViewer(
                        transformationController: _transform,
                        minScale: 0.8,
                        maxScale: 5,
                        panEnabled: _scale > 1.05,
                        boundaryMargin: const EdgeInsets.all(24),
                        clipBehavior: Clip.hardEdge,
                        child: SizedBox(
                          width: chartWidth,
                          height: constraints.maxHeight,
                          child: CustomPaint(
                            size: Size(chartWidth, constraints.maxHeight),
                            painter: _CandlePainter(
                              candles: display,
                              entry: widget.entry,
                              stop: widget.stop,
                              target: widget.target,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (widget.showVolume)
                  Expanded(
                    flex: 28,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final chartWidth = _chartWidth(constraints, display.length);
                        return SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          physics: const NeverScrollableScrollPhysics(),
                          child: SizedBox(
                            width: chartWidth,
                            height: constraints.maxHeight,
                            child: CustomPaint(
                              size: Size(chartWidth, constraints.maxHeight),
                              painter: _VolumePainter(candles: display),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
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
    if (candles.isEmpty || size.width <= 0 || size.height <= 0) return;

    final pad = 8.0;
    final w = size.width - pad * 2;
    final h = size.height - pad * 2;
    if (w <= 0 || h <= 0) return;

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
      if (price == null || price <= 0) return;
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
    if (candles.isEmpty || size.width <= 0 || size.height <= 0) return;
    final maxVol = candles.map((c) => c.volume).fold<double>(0, (a, b) => a > b ? a : b);
    if (maxVol <= 0) return;

    final pad = 8.0;
    final w = size.width - pad * 2;
    final h = size.height - 4;
    if (w <= 0 || h <= 0) return;
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
    if (closes.length < 2 || size.width <= 0 || size.height <= 0) return;
    final min = closes.fold<double>(closes.first, (a, b) => a < b ? a : b);
    final max = closes.fold<double>(closes.first, (a, b) => a > b ? a : b);
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
