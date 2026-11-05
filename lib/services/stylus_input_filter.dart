import 'package:flutter/gestures.dart';

// ===========================================================================
// BỘ LỌC TÍN HIỆU BÚT CẢM ỨNG, CHUỘT & CẢM ỨNG TRÊN BẢNG VIẾT (STYLUS INPUT FILTER)
// Công dụng:
// - Nhận đầy đủ tín hiệu từ Chuột (trên máy ảo Android Emulator chuột được giả lập
//   dưới dạng PointerDeviceKind.touch hoặc mouse), Bút cảm ứng (Stylus) và Ngón tay.
// - Chỉ chặn điểm chạm thứ 2 nếu bút cảm ứng chuyên dụng (Stylus) đang chạm mặt kính.
// ===========================================================================
class StylusInputFilter {
  StylusInputFilter._();

  /// Kiểm tra sự kiện có phải từ Bút cảm ứng chuyên dụng không
  static bool isHardwareStylus(PointerEvent event) {
    return event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus;
  }

  /// Kiểm tra sự kiện có phải từ Bút cảm ứng hoặc Chuột máy tính không
  static bool isStylusOrMouse(PointerEvent event) {
    return isHardwareStylus(event) || event.kind == PointerDeviceKind.mouse;
  }

  /// Kiểm tra điểm chạm có hợp lệ để vẽ nét chữ trên bảng viết Bottom Sheet không:
  /// - Cho phép mọi thao tác kéo chuột (mouse / touch giả lập trên máy ảo) và bút cảm ứng
  ///   vẽ nét ngay lập tức như ứng dụng Paint.
  static bool isValidWritingPointer(
    PointerEvent event, {
    required bool isStylusActive,
  }) {
    // Nếu bút cảm ứng phần cứng (Stylus) đang đặt trên màn hình thì chặn cảm ứng tì tay (touch)
    if (isStylusActive && event.kind == PointerDeviceKind.touch) {
      return false;
    }
    return true;
  }
}
