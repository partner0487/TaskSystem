import 'dart:math';

import 'package:flutter/material.dart';

import '../theme.dart';

/// 新手指引的一個步驟。[target] 是要亮起來的元件；null = 不指向任何東西，說明框放在中間。
class TourStep {
  const TourStep(this.target, this.title, this.text);

  final GlobalKey? target;
  final String title;
  final String text;
}

/// 顯示新手指引：畫面變暗、目標亮起來、箭頭指向它。
/// 點右半邊 → 下一步，點左半邊 → 上一步，右上角「略過」。結束（或略過）時回傳。
Future<void> showTour(BuildContext context, List<TourStep> steps) {
  return Navigator.of(context).push(PageRouteBuilder<void>(
    opaque: false,
    transitionDuration: const Duration(milliseconds: 250),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (_, animation, _) =>
        FadeTransition(opacity: animation, child: _TourOverlay(steps: steps)),
  ));
}

class _TourOverlay extends StatefulWidget {
  const _TourOverlay({required this.steps});

  final List<TourStep> steps;

  @override
  State<_TourOverlay> createState() => _TourOverlayState();
}

class _TourOverlayState extends State<_TourOverlay> {
  late final List<TourStep> _steps;
  int _i = 0;

  @override
  void initState() {
    super.initState();
    // 找不到目標的步驟跳過（例如這個分頁沒有大事件）
    _steps = widget.steps.where((s) => s.target == null || _rectOf(s.target!) != null).toList();
  }

  /// 目標在畫面上的位置（找不到 = null）。
  static Rect? _rectOf(GlobalKey key) {
    final box = key.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  void _next() {
    if (_i >= _steps.length - 1) {
      Navigator.pop(context);
    } else {
      setState(() => _i++);
    }
  }

  void _prev() {
    if (_i > 0) setState(() => _i--);
  }

  @override
  Widget build(BuildContext context) {
    if (_steps.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => Navigator.pop(context));
      return const SizedBox.shrink();
    }
    final step = _steps[_i];
    final size = MediaQuery.of(context).size;
    final padding = MediaQuery.of(context).padding;
    final target = step.target == null ? null : _rectOf(step.target!)?.inflate(6);

    // 說明框放在目標的另一邊：目標在上半部 → 框在下面；在下半部 → 框在上面
    const gap = 72.0; // 箭頭的長度空間
    final below = target != null && target.center.dy < size.height * 0.55;
    final boxAnchorY = target == null
        ? null
        : (below ? target.bottom + gap : target.top - gap); // 框的上緣（below）或下緣（above）

    // 箭頭：從說明框的邊緣（靠近目標的水平位置）指到目標的邊緣
    Offset? arrowFrom, arrowTo;
    if (target != null && boxAnchorY != null) {
      final x = target.center.dx.clamp(56.0, size.width - 56.0);
      arrowFrom = Offset(x, boxAnchorY + (below ? -6 : 6));
      arrowTo = Offset(target.center.dx, below ? target.bottom + 6 : target.top - 6);
    }

    final isLast = _i == _steps.length - 1;
    final box = _TourCard(
      index: _i,
      total: _steps.length,
      title: step.title,
      text: step.text,
      isFirst: _i == 0,
      isLast: isLast,
    );

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // 整個畫面：變暗 + 目標挖空亮起來 + 箭頭；點右半邊下一步、左半邊上一步
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) => d.localPosition.dx > size.width / 2 ? _next() : _prev(),
              child: CustomPaint(painter: _TourPainter(hole: target, from: arrowFrom, to: arrowTo)),
            ),
          ),
          // 說明框（不攔截點擊：點在框上也是依左右半邊切換）
          if (target == null)
            Positioned.fill(child: IgnorePointer(child: Center(child: box)))
          else if (below)
            Positioned(left: 20, right: 20, top: boxAnchorY, child: IgnorePointer(child: box))
          else
            Positioned(
                left: 20,
                right: 20,
                bottom: size.height - boxAnchorY!,
                child: IgnorePointer(child: box)),
          // 略過：放左下角（右上角是 🎮 和 ⋮、左上角是標題，都會被擋到；右下角是 ＋）
          Positioned(
            bottom: padding.bottom + 20,
            left: 16,
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: GColors.text,
                backgroundColor: GColors.header,
                side: const BorderSide(color: Colors.white24),
              ),
              child: const Text('略過指引'),
            ),
          ),
        ],
      ),
    );
  }
}

/// 說明框：步驟編號、標題、說明、左右提示。
class _TourCard extends StatelessWidget {
  const _TourCard({
    required this.index,
    required this.total,
    required this.title,
    required this.text,
    required this.isFirst,
    required this.isLast,
  });

  final int index;
  final int total;
  final String title;
  final String text;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
      decoration: BoxDecoration(
        color: GColors.header,
        border: Border.all(color: GColors.gold, width: 1.5),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 16)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${index + 1} / $total', style: const TextStyle(color: GColors.sub, fontSize: 12)),
          const SizedBox(height: 4),
          Text(title,
              style: const TextStyle(
                  color: GColors.gold, fontSize: 19, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(text, style: const TextStyle(color: GColors.text, fontSize: 15, height: 1.5)),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(isFirst ? '' : '‹ 點左邊上一步',
                  style: const TextStyle(color: GColors.sub, fontSize: 13)),
              const Spacer(),
              Text(isLast ? '點右邊開始使用 ›' : '點右邊下一步 ›',
                  style: const TextStyle(
                      color: GColors.goldBright, fontSize: 14, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }
}

/// 畫變暗的遮罩（目標處挖空 + 金框）和彎曲的金色箭頭。
class _TourPainter extends CustomPainter {
  _TourPainter({required this.hole, required this.from, required this.to});

  final Rect? hole;
  final Offset? from;
  final Offset? to;

  @override
  void paint(Canvas canvas, Size size) {
    final dim = Path()..addRect(Offset.zero & size);
    final h = hole;
    if (h != null) {
      dim
        ..addRRect(RRect.fromRectAndRadius(h, const Radius.circular(10)))
        ..fillType = PathFillType.evenOdd;
    }
    canvas.drawPath(dim, Paint()..color = Colors.black.withValues(alpha: 0.78));

    if (h != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(h, const Radius.circular(10)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = GColors.goldBright,
      );
    }

    final a = from, b = to;
    if (a == null || b == null) return;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = GColors.goldBright;
    // 彎曲的線：控制點往旁邊偏一點，看起來比較像手畫的箭頭
    final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
    final bend = (b.dx - a.dx).abs() < 30 ? 36.0 : 0.0;
    final control = Offset(mid.dx + bend, mid.dy);
    canvas.drawPath(
      Path()
        ..moveTo(a.dx, a.dy)
        ..quadraticBezierTo(control.dx, control.dy, b.dx, b.dy),
      line,
    );
    // 箭頭頭：沿著曲線最後的方向
    final angle = atan2(b.dy - control.dy, b.dx - control.dx);
    const len = 14.0;
    Offset wing(double da) => Offset(b.dx - len * cos(angle + da), b.dy - len * sin(angle + da));
    canvas.drawPath(
      Path()
        ..moveTo(wing(0.5).dx, wing(0.5).dy)
        ..lineTo(b.dx, b.dy)
        ..lineTo(wing(-0.5).dx, wing(-0.5).dy),
      line,
    );
  }

  @override
  bool shouldRepaint(_TourPainter old) => old.hole != hole || old.from != from || old.to != to;
}
