import 'dart:ui';

// ===========================================================================
// MÔ HÌNH ĐIỂM TỌA ĐỘ NÉT BÚT TẠM TRÊN RAM (STROKE POINT MODEL)
// Công dụng:
// - Lưu tọa độ (x, y), thời gian thực (timestampMs) và lực nhấn (pressure)
//   của từng điểm khi người dùng viết trên Bottom Sheet Viết bút.
// - Tích hợp sẵn bộ đệm đường cong Bezier (cachedPath) trong InkStrokeModel
//   để CustomPainter vẽ ở tốc độ 60-120fps hoàn toàn không bị lag.
// ===========================================================================
class StrokePointModel {
  final double x;
  final double y;
  final int timestampMs;
  final double pressure;

  const StrokePointModel({
    required this.x,
    required this.y,
    required this.timestampMs,
    this.pressure = 0.5,
  });
}

/// Đại diện cho 1 nét bút hoàn chỉnh (từ lúc đặt bút xuống đến lúc nhấc bút lên)
class InkStrokeModel {
  final List<StrokePointModel> points = <StrokePointModel>[];
  final Path path = Path();

  double minX = double.infinity;
  double maxX = double.negativeInfinity;
  double minY = double.infinity;
  double maxY = double.negativeInfinity;

  /// Thêm điểm mới vào nét vẽ và nối mượt bằng đường cong bậc 2 (Quadratic Bezier)
  /// ngay lập tức để khi vẽ lại không phải tính toán lại từ đầu (0ms lag)
  void addPoint(StrokePointModel pt) {
    if (pt.x < minX) minX = pt.x;
    if (pt.x > maxX) maxX = pt.x;
    if (pt.y < minY) minY = pt.y;
    if (pt.y > maxY) maxY = pt.y;

    final int len = points.length;
    if (len == 0) {
      path.moveTo(pt.x, pt.y);
      // Vẽ chấm nhỏ ngay khi vừa chạm bút xuống
      path.lineTo(pt.x + 0.1, pt.y + 0.1);
    } else if (len == 1) {
      final StrokePointModel p0 = points[0];
      final double midX = (p0.x + pt.x) * 0.5;
      final double midY = (p0.y + pt.y) * 0.5;
      path.lineTo(midX, midY);
    } else {
      final StrokePointModel prev = points[len - 1];
      final double midX = (prev.x + pt.x) * 0.5;
      final double midY = (prev.y + pt.y) * 0.5;
      path.quadraticBezierTo(prev.x, prev.y, midX, midY);
    }
    points.add(pt);
  }

  /// Hoàn tất nét vẽ khi nhấc bút
  void finishStroke() {
    if (points.length >= 2) {
      final StrokePointModel last = points.last;
      path.lineTo(last.x, last.y);
    }
  }
}
