import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import '../datasources/google_drive_datasource.dart';
import '../datasources/local_storage_datasource.dart';

// ===========================================================================
// TRUNG GIAN QUẢN LÝ LƯU TRỮ RAM & ĐỒNG BỘ GOOGLE DRIVE DÙNG CHUNG
// (DATA SYNC REPOSITORY - Áp dụng chung cho cả Ghi chú & Sổ dự giờ)
//
// Nguyên lý hoạt động theo đúng kế hoạch:
// 1. Khi người dùng đang viết/thao tác:
//    - Lưu tức thì dữ liệu vào RAM (LocalStorageDatasource) với độ trễ 0ms.
//    - Đặt cờ isDirty = true (đánh dấu có dữ liệu mới chưa đẩy lên Drive).
//    - Khởi động bộ đếm chờ 30 giây (_syncDebounceTimer).
//    - Nếu bộ đếm 30 giây đang chạy mà người dùng viết/thao tác tiếp:
//      HỦY bộ đếm 30 giây cũ, cập nhật dữ liệu mới vào RAM và ĐẾM LẠI 30 giây
//      từ đầu kể từ lúc người dùng dừng bút hẳn.
//
// 2. Chỉ gọi Google Drive API để ghi đè file JSON ở đúng 3 thời điểm:
//    - Thời điểm 1 (Định kỳ khi dừng bút đủ 30 giây): Bộ đếm 30s hoàn tất
//      và có thay đổi mới (isDirty == true).
//    - Thời điểm 2 (Khi đóng trang): Người dùng bấm nút Quay lại (Back)
//      để thoát khỏi trang về màn hình Home -> gọi syncOnPageExit().
//    - Thời điểm 3 (Khi tắt màn hình / ẩn App): Khi hệ điều hành báo
//      AppLifecycleState.paused -> tự động đẩy ngay gói JSON đang chờ lên Drive.
// ===========================================================================
class DataSyncRepository with WidgetsBindingObserver {
  DataSyncRepository._internal() {
    WidgetsBinding.instance.addObserver(this);
    _initNetworkListener();
  }

  static final DataSyncRepository instance = DataSyncRepository._internal();

  /// Thời gian chờ sau khi người dùng dừng bút hẳn mới đẩy lên Google Drive (30 giây)
  static const Duration driveSyncDelay = Duration(seconds: 30);

  final LocalStorageDatasource _localDatasource =
      LocalStorageDatasource.instance;
  final GoogleDriveDatasource _driveDatasource = GoogleDriveDatasource.instance;
  final Connectivity _connectivity = Connectivity();

  Timer? _syncDebounceTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  // Thông tin tài liệu đang mở soạn thảo hiện tại
  String? _activeDocumentId;
  String? _activeDriveFileId;
  String? _activeFileName;
  int _activeTabIndex = 0;
  String? _activeParentFolderId;
  Map<String, dynamic>? _latestJsonInRam;
  bool _isDirty = false;
  bool _isUploading = false;

  /// Trạng thái kết nối mạng (nếu false -> giao diện soạn thảo sẽ bật khóa thao tác ngay)
  final ValueNotifier<bool> isNetworkAvailableNotifier =
      ValueNotifier<bool>(true);

  /// Trạng thái đang đồng bộ ngầm lên Google Drive
  final ValueNotifier<bool> isSyncingDriveNotifier =
      ValueNotifier<bool>(false);

  /// Trạng thái lỗi bộ nhớ RAM/Local (nếu true -> chặn chọn dòng viết và báo "Có lỗi bộ nhớ" màu đỏ)
  final ValueNotifier<bool> hasRamErrorNotifier =
      ValueNotifier<bool>(false);

  // ===========================================================================
  // LẮNG NGHE KẾT NỐI MẠNG LIÊN TỤC (ĐỂ KHÓA THAO TÁC KHI ĐỨT MẠNG GIỮA CHỪNG)
  // ===========================================================================
  void _initNetworkListener() {
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      (List<ConnectivityResult> results) {
        final bool hasNet =
            results.isNotEmpty && !results.contains(ConnectivityResult.none);
        isNetworkAvailableNotifier.value = hasNet;

        // Ngay khi có mạng trở lại, nếu còn dữ liệu chưa đẩy lên Drive thì tự động đẩy bù
        if (hasNet && _isDirty) {
          _triggerDriveOverwriteNow();
        }
      },
    );
  }

  // ===========================================================================
  // CẬP NHẬT NỘI DUNG KHI NGƯỜI DÙNG ĐANG VIẾT (LƯU RAM + RESET BỘ ĐẾM 30 GIÂY)
  // ===========================================================================
  Future<void> onUserWritingChanged({
    required String documentId,
    required String fileName,
    required int tabIndex,
    String? parentFolderId,
    String? existingDriveFileId,
    required Map<String, dynamic> updatedJsonData,
  }) async {
    _activeDocumentId = documentId;
    _activeFileName = fileName;
    _activeTabIndex = tabIndex;
    _activeParentFolderId = parentFolderId;
    if (existingDriveFileId != null && existingDriveFileId.isNotEmpty) {
      _activeDriveFileId = existingDriveFileId;
    }
    _latestJsonInRam = Map<String, dynamic>.from(updatedJsonData);
    _isDirty = true;

    // 1. Lưu ngay lập tức vào RAM và bộ đệm Local của máy (0ms)
    try {
      await _localDatasource.saveToRamAndLocalBuffer(
        documentId: documentId,
        jsonData: _latestJsonInRam!,
      );
      if (hasRamErrorNotifier.value) {
        hasRamErrorNotifier.value = false;
      }
    } catch (e) {
      debugPrint('Lỗi lưu vào bộ nhớ RAM/Local: $e');
      hasRamErrorNotifier.value = true;
      rethrow;
    }

    // 2. Nếu bộ đếm 30 giây đang chạy mà chưa hết -> Hủy bộ đếm cũ và đếm lại 30 giây từ đầu
    _syncDebounceTimer?.cancel();
    _syncDebounceTimer = Timer(driveSyncDelay, () {
      // THỜI ĐIỂM 1: Đã dừng bút đủ 30 giây -> Đóng gói JSON gửi ghi đè lên Google Drive
      if (_isDirty) {
        _triggerDriveOverwriteNow();
      }
    });
  }

  // ===========================================================================
  // TẠM DỪNG BỘ ĐẾM ĐỒNG BỘ KHI CHUYỂN SANG CHẾ ĐỘ "CHỈ XEM" (TIẾT KIỆM API)
  // ===========================================================================
  void cancelPendingSyncTimer() {
    _syncDebounceTimer?.cancel();
    _syncDebounceTimer = null;
  }

  // ===========================================================================
  // THỜI ĐIỂM 2: KHI NGƯỜI DÙNG BẤM QUAY LẠI (ĐÓNG TRANG VỀ MÀN HÌNH HOME)
  // ===========================================================================
  Future<void> syncOnPageExit() async {
    _syncDebounceTimer?.cancel();
    if (_isDirty && _latestJsonInRam != null) {
      await _triggerDriveOverwriteNow();
    }
  }

  // ===========================================================================
  // THỜI ĐIỂM 3: KHI NGƯỜI DÙNG TẮT MÀN HÌNH HOẶC ẨN ỨNG DỤNG (PAUSED)
  // ===========================================================================
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _syncDebounceTimer?.cancel();
      if (_isDirty && _latestJsonInRam != null) {
        _triggerDriveOverwriteNow();
      }
    }
  }

  // ===========================================================================
  // HÀM THỰC THI GỬI ĐÈ GÓI JSON TỪ RAM LÊN GOOGLE DRIVE
  // ===========================================================================
  Future<void> _triggerDriveOverwriteNow() async {
    if (!_isDirty ||
        _isUploading ||
        _latestJsonInRam == null ||
        _activeDocumentId == null ||
        _activeFileName == null) {
      return;
    }

    _isUploading = true;
    isSyncingDriveNotifier.value = true;

    try {
      final String driveFileId =
          await _driveDatasource.uploadOrOverwriteJsonFile(
        tabIndex: _activeTabIndex,
        customParentFolderId: _activeParentFolderId,
        existingDriveFileId: _activeDriveFileId,
        fileName: _activeFileName!,
        jsonData: _latestJsonInRam!,
      );

      _activeDriveFileId = driveFileId;
      _isDirty = false;
      await _localDatasource.markSyncedToDrive(_activeDocumentId!);
    } catch (e) {
      debugPrint('Chưa thể ghi đè lên Google Drive (giữ trong RAM/Local chờ gửi lại): $e');
    } finally {
      _isUploading = false;
      isSyncingDriveNotifier.value = false;
    }
  }

  void dispose() {
    _syncDebounceTimer?.cancel();
    _connectivitySubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
  }
}
