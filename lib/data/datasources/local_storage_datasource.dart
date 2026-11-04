import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

// ===========================================================================
// NGUỒN DỮ LIỆU LƯU TẠM TRÊN RAM & BỘ ĐỆM MÁY LOCAL (LOCAL STORAGE DATASOURCE)
// Công dụng:
// - Lưu tức thì (0ms) mọi thay đổi khi người dùng đang viết vào RAM (_ramCache)
//   để màn hình vẽ bút cảm ứng đạt 60-120fps không bị trễ.
// - Giữ bản sao JSON nhẹ trong bộ nhớ máy (SharedPreferences) cho các file
//   đang chờ bộ đếm 30 giây đẩy lên Google Drive (tránh mất chữ nếu tắt máy đột ngột).
// ===========================================================================
class LocalStorageDatasource {
  LocalStorageDatasource._internal();
  static final LocalStorageDatasource instance =
      LocalStorageDatasource._internal();

  static const String _pendingSyncPrefix = 'pending_drive_json_';

  /// Bộ nhớ RAM siêu tốc lưu trữ nội dung JSON đang soạn thảo theo documentId
  final Map<String, Map<String, dynamic>> _ramCache =
      <String, Map<String, dynamic>>{};

  /// Ghi đè dữ liệu ngay lập tức vào RAM (và lưu đệm ngầm xuống máy)
  Future<void> saveToRamAndLocalBuffer({
    required String documentId,
    required Map<String, dynamic> jsonData,
  }) async {
    // 1. Cập nhật tức thì trên RAM (0ms)
    _ramCache[documentId] = Map<String, dynamic>.from(jsonData);

    // 2. Lưu đệm chuỗi JSON nhẹ vào bộ nhớ máy để phòng trường hợp mất mạng/tắt nguồn
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_pendingSyncPrefix$documentId',
      jsonEncode(jsonData),
    );
  }

  /// Đọc dữ liệu mới nhất từ RAM (hoặc từ bộ đệm máy nếu vừa khởi động lại)
  Future<Map<String, dynamic>?> getFromRamOrLocalBuffer(
      String documentId) async {
    if (_ramCache.containsKey(documentId)) {
      return _ramCache[documentId];
    }

    final prefs = await SharedPreferences.getInstance();
    final String? rawJson = prefs.getString('$_pendingSyncPrefix$documentId');
    if (rawJson != null && rawJson.isNotEmpty) {
      final decoded = jsonDecode(rawJson) as Map<String, dynamic>;
      _ramCache[documentId] = decoded;
      return decoded;
    }
    return null;
  }

  /// Đánh dấu đã đẩy lên Google Drive thành công (xóa cờ chờ đồng bộ dưới máy, giữ bản RAM để đọc nhanh)
  Future<void> markSyncedToDrive(String documentId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_pendingSyncPrefix$documentId');
  }
}
