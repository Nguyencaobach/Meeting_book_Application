// ===========================================================================
// NGUỒN DỮ LIỆU LƯU TẠM TRÊN BỘ NHỚ RAM (LOCAL RAM DATASOURCE)
// Công dụng:
// - Chỉ lưu tức thì (0ms) mọi thay đổi khi người dùng đang viết vào bộ nhớ RAM (_ramCache)
//   để màn hình gõ chữ / vẽ bút cảm ứng đạt 60-120fps hoàn toàn không bị trễ.
// - Không ghi nội dung vở xuống ổ cứng máy; dữ liệu từ RAM sẽ được đồng bộ
//   trực tiếp lên Google Drive ở 3 thời điểm (sau 30s dừng viết, khi thoát trang,
//   hoặc khi ẩn ứng dụng) và khi bấm nút Lưu.
// ===========================================================================
class LocalStorageDatasource {
  LocalStorageDatasource._internal();
  static final LocalStorageDatasource instance =
      LocalStorageDatasource._internal();

  /// Bộ nhớ RAM siêu tốc lưu trữ nội dung JSON đang soạn thảo theo documentId
  final Map<String, Map<String, dynamic>> _ramCache =
      <String, Map<String, dynamic>>{};

  /// Ghi đè dữ liệu ngay lập tức vào RAM (0ms - chỉ lưu trên RAM, không ghi ổ cứng máy)
  Future<void> saveToRamAndLocalBuffer({
    required String documentId,
    required Map<String, dynamic> jsonData,
  }) async {
    _ramCache[documentId] = Map<String, dynamic>.from(jsonData);
  }

  /// Đọc dữ liệu mới nhất trực tiếp từ RAM
  Future<Map<String, dynamic>?> getFromRamOrLocalBuffer(
      String documentId) async {
    if (_ramCache.containsKey(documentId)) {
      return _ramCache[documentId];
    }
    return null;
  }

  /// Đánh dấu đã đẩy lên Google Drive thành công (giữ bản RAM để đọc nhanh trong phiên)
  Future<void> markSyncedToDrive(String documentId) async {
    // Dữ liệu đã được lưu an toàn trên Google Drive, giữ bản RAM để truy xuất 0ms
  }
}
