import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Ngoại lệ chuyên biệt khi phát hiện trùng tên Thư mục hoặc trùng tên File
class DuplicateDriveItemException implements Exception {
  final String message;
  const DuplicateDriveItemException(this.message);

  @override
  String toString() => message;
}

/// Model đại diện cho một Thư mục trên Google Drive
class DriveFolderItem {
  final String id;
  final String name;
  final DateTime? createdTime;

  const DriveFolderItem({
    required this.id,
    required this.name,
    this.createdTime,
  });
}

/// HTTP Client đính kèm Header xác thực của Google để gọi Google Drive API
class GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client = http.Client();

  GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _client.send(request);
  }
}

// ===========================================================================
// NGUỒN DỮ LIỆU KẾT NỐI GOOGLE DRIVE CÁ NHÂN & QUẢN LÝ CÂY THƯ MỤC / FILE JSON
// Cấu trúc tự động tạo trên Google Drive của người dùng:
// MeetingBook/
// ├── Ghi_Chu/       (Tab 0: Ghi chú)
// └── So_Du_Gio/     (Tab 1: Sổ dự giờ)
// ===========================================================================
class GoogleDriveDatasource {
  GoogleDriveDatasource._internal();
  static final GoogleDriveDatasource instance = GoogleDriveDatasource._internal();

  static const String _keyIsLoggedIn = 'is_logged_in';
  static const String _keyUserEmail = 'user_email';
  static const String _keyUserDisplayName = 'user_display_name';
  static const String _keyUserPhotoUrl = 'user_photo_url';
  static const String _keyRootFolderId = 'drive_root_folder_id';
  static const String _keyNotesFolderId = 'drive_notes_folder_id';
  static const String _keyObservationFolderId = 'drive_observation_folder_id';

  static const String _folderMimeType = 'application/vnd.google-apps.folder';
  static const String _jsonMimeType = 'application/json';
  static const String rootAppFolderName = 'MeetingBook';
  static const String notesTabFolderName = 'Ghi_Chu';
  static const String observationTabFolderName = 'So_Du_Gio';

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: <String>[
      drive.DriveApi.driveFileScope,
    ],
  );

  GoogleSignInAccount? _currentUser;
  drive.DriveApi? _driveApi;
  String? _cachedEmail;
  String? _cachedDisplayName;
  String? _cachedPhotoUrl;

  // Bộ nhớ đệm ID của 3 thư mục gốc trên Google Drive để truy xuất nhanh
  String? _rootMeetingBookFolderId;
  String? _notesTabFolderId;
  String? _observationTabFolderId;

  // Danh sách thông báo cập nhật giao diện khi có thư mục mới được tạo hoặc làm mới
  final ValueNotifier<List<DriveFolderItem>> notesFoldersNotifier =
      ValueNotifier<List<DriveFolderItem>>([]);
  final ValueNotifier<List<DriveFolderItem>> observationFoldersNotifier =
      ValueNotifier<List<DriveFolderItem>>([]);
  final ValueNotifier<bool> isSyncingFoldersNotifier =
      ValueNotifier<bool>(false);

  /// Lấy email đang đăng nhập (từ phiên Google hoặc bộ nhớ duy trì đăng nhập)
  String get currentEmail => _currentUser?.email ?? _cachedEmail ?? '';

  /// Lấy tên hiển thị của người dùng
  String get currentDisplayName =>
      _currentUser?.displayName ?? _cachedDisplayName ?? 'Tài khoản Google Drive';

  /// Lấy ảnh đại diện (nếu có)
  String? get currentPhotoUrl => _currentUser?.photoUrl ?? _cachedPhotoUrl;

  /// Đối tượng DriveApi đã liên kết sẵn sàng để tạo thư mục / ghi đè file JSON
  drive.DriveApi? get driveApi => _driveApi;

  // ===========================================================================
  // 1. HÀM KHÔI PHỤC PHIÊN ĐĂNG NHẬP TỰ ĐỘNG KHI MỞ APP
  // ===========================================================================
  Future<bool> restoreSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final bool wasLoggedIn = prefs.getBool(_keyIsLoggedIn) ?? false;
      if (!wasLoggedIn) {
        return false;
      }

      _cachedEmail = prefs.getString(_keyUserEmail);
      _cachedDisplayName = prefs.getString(_keyUserDisplayName);
      _cachedPhotoUrl = prefs.getString(_keyUserPhotoUrl);

      final GoogleSignInAccount? account = await _googleSignIn.signInSilently();
      if (account != null) {
        _currentUser = account;
        await _connectDriveApi(account);
        await _saveUserToPrefs(account);
        return true;
      }

      return _cachedEmail != null && _cachedEmail!.isNotEmpty;
    } catch (e) {
      debugPrint('Lỗi khôi phục phiên đăng nhập Google Drive: $e');
      return _cachedEmail != null && _cachedEmail!.isNotEmpty;
    }
  }

  // ===========================================================================
  // 2. HÀM MỞ BẢNG ĐĂNG NHẬP GOOGLE CHÍNH THỐNG & LIÊN KẾT DRIVE API
  // ===========================================================================
  Future<({bool success, String? errorMessage})> signInAndLinkDrive() async {
    try {
      final GoogleSignInAccount? account = await _googleSignIn.signIn();
      if (account == null) {
        return (
          success: false,
          errorMessage: 'Bạn đã hủy chọn tài khoản Google.',
        );
      }

      _currentUser = account;
      await _connectDriveApi(account);
      await _saveUserToPrefs(account);
      return (success: true, errorMessage: null);
    } catch (e) {
      debugPrint('Lỗi khi kết nối Google Drive: $e');
      return (
        success: false,
        errorMessage: 'Không thể kết nối Google Drive. Vui lòng thử lại.',
      );
    }
  }

  // ===========================================================================
  // 3. HÀM KIỂM TRA & LIÊN KẾT VỚI GOOGLE DRIVE API
  // ===========================================================================
  Future<void> _connectDriveApi(GoogleSignInAccount account) async {
    final authHeaders = await account.authHeaders;
    final authenticateClient = GoogleAuthClient(authHeaders);
    _driveApi = drive.DriveApi(authenticateClient);

    // Kiểm tra kết nối API và khởi tạo sẵn cấu trúc thư mục MeetingBook/
    await _driveApi!.about.get($fields: 'user');
    await ensureAppFolderStructure();
    await refreshAllTabFolders();
  }

  /// Đảm bảo `_driveApi` đã sẵn sàng
  Future<drive.DriveApi> _requireDriveApi() async {
    if (_driveApi != null) {
      return _driveApi!;
    }
    final GoogleSignInAccount? account = _currentUser ??
        await _googleSignIn.signInSilently() ??
        await _googleSignIn.signIn();
    if (account == null) {
      throw Exception('Chưa đăng nhập tài khoản Google Drive.');
    }
    _currentUser = account;
    final authHeaders = await account.authHeaders;
    _driveApi = drive.DriveApi(GoogleAuthClient(authHeaders));
    return _driveApi!;
  }

  // ===========================================================================
  // 4. HÀM TỰ ĐỘNG TẠO CẤU TRÚC THƯ MỤC GỐC TRÊN GOOGLE DRIVE:
  // MeetingBook/
  // ├── Ghi_Chu/
  // └── So_Du_Gio/
  // ===========================================================================
  Future<void> ensureAppFolderStructure() async {
    final prefs = await SharedPreferences.getInstance();
    _rootMeetingBookFolderId ??= prefs.getString(_keyRootFolderId);
    _notesTabFolderId ??= prefs.getString(_keyNotesFolderId);
    _observationTabFolderId ??= prefs.getString(_keyObservationFolderId);

    // Nếu cả 3 ID thư mục gốc đã có sẵn trong bộ nhớ đệm -> Tốn 0 lượt gọi API!
    if (_rootMeetingBookFolderId != null &&
        _notesTabFolderId != null &&
        _observationTabFolderId != null) {
      return;
    }

    final api = await _requireDriveApi();

    // Bước 1: Tìm hoặc tạo thư mục gốc "MeetingBook"
    _rootMeetingBookFolderId ??= await _findOrCreateFolder(
      api: api,
      folderName: rootAppFolderName,
      parentId: null,
    );

    // Bước 2: Tìm hoặc tạo 2 thư mục con "Ghi_Chu" và "So_Du_Gio" bên trong "MeetingBook"
    _notesTabFolderId ??= await _findOrCreateFolder(
      api: api,
      folderName: notesTabFolderName,
      parentId: _rootMeetingBookFolderId,
    );

    _observationTabFolderId ??= await _findOrCreateFolder(
      api: api,
      folderName: observationTabFolderName,
      parentId: _rootMeetingBookFolderId,
    );

    // Lưu ID vào bộ nhớ máy để những lần sau không phải gọi API tìm lại nữa
    await prefs.setString(_keyRootFolderId, _rootMeetingBookFolderId!);
    await prefs.setString(_keyNotesFolderId, _notesTabFolderId!);
    await prefs.setString(_keyObservationFolderId, _observationTabFolderId!);
  }

  /// Hàm tìm một thư mục trên Google Drive theo tên và thư mục cha; nếu chưa có thì tạo mới
  Future<String> _findOrCreateFolder({
    required drive.DriveApi api,
    required String folderName,
    String? parentId,
  }) async {
    final String escapedName = folderName.replaceAll("'", "\\'");
    String query =
        "mimeType = '$_folderMimeType' and name = '$escapedName' and trashed = false";
    if (parentId != null) {
      query += " and '$parentId' in parents";
    }

    final drive.FileList existingList = await api.files.list(
      q: query,
      spaces: 'drive',
      $fields: 'files(id, name)',
      pageSize: 1,
    );

    if (existingList.files != null && existingList.files!.isNotEmpty) {
      return existingList.files!.first.id!;
    }

    // Nếu chưa tồn tại trên Google Drive -> Tạo mới thư mục
    final drive.File folderMetadata = drive.File()
      ..name = folderName
      ..mimeType = _folderMimeType
      ..parents = parentId != null ? <String>[parentId] : null;

    final drive.File createdFolder = await api.files.create(
      folderMetadata,
      $fields: 'id, name',
    );
    return createdFolder.id!;
  }

  // ===========================================================================
  // 5. HÀM KIỂM TRA CHỐNG TRÙNG TÊN THƯ MỤC & TRÙNG TÊN FILE KHI TẠO MỚI
  // Công dụng:
  // - Kiểm tra cả trên danh sách hiện tại và truy vấn trực tiếp trên Google Drive
  //   (không phân biệt chữ hoa/thường) để đảm bảo không tạo trùng tên.
  // ===========================================================================
  Future<bool> isItemNameDuplicate({
    required String parentFolderId,
    required String itemName,
    required bool isFolder,
  }) async {
    final api = await _requireDriveApi();
    final String trimmedName = itemName.trim();
    final String lowerTarget = trimmedName.toLowerCase();

    final String mimeCondition = isFolder
        ? "mimeType = '$_folderMimeType'"
        : "mimeType != '$_folderMimeType'";
    final String query =
        "$mimeCondition and '$parentFolderId' in parents and trashed = false";

    final drive.FileList fileList = await api.files.list(
      q: query,
      spaces: 'drive',
      $fields: 'files(id, name)',
    );

    final files = fileList.files ?? <drive.File>[];
    for (final file in files) {
      final String existingName = (file.name ?? '').trim();
      final String existingWithoutJson = existingName.endsWith('.json')
          ? existingName.substring(0, existingName.length - 5)
          : existingName;
      if (existingName.toLowerCase() == lowerTarget ||
          existingWithoutJson.toLowerCase() == lowerTarget) {
        return true;
      }
    }
    return false;
  }

  // ===========================================================================
  // 6. HÀM TẠO THƯ MỤC MỚI THEO TAB (CÓ KIỂM TRA CHỐNG TRÙNG TÊN THƯ MỤC)
  // ===========================================================================
  Future<DriveFolderItem> createFolderInTab({
    required int tabIndex,
    required String folderName,
  }) async {
    final api = await _requireDriveApi();
    await ensureAppFolderStructure();

    final String trimmedName = folderName.trim();
    final String targetParentId =
        tabIndex == 0 ? _notesTabFolderId! : _observationTabFolderId!;

    // Bước 1: Kiểm tra nhanh ngay trên danh sách RAM đang hiển thị (Tốn 0 lượt gọi API)
    final currentRamList = tabIndex == 0
        ? notesFoldersNotifier.value
        : observationFoldersNotifier.value;
    final bool existsInRam = currentRamList.any(
      (f) => f.name.trim().toLowerCase() == trimmedName.toLowerCase(),
    );
    if (existsInRam) {
      throw DuplicateDriveItemException(
        'Tên thư mục "$trimmedName" đã tồn tại! Vui lòng đặt tên khác.',
      );
    }

    // Bước 2: Kiểm tra trên Google Drive phòng trường hợp tạo từ thiết bị khác
    final bool isDuplicate = await isItemNameDuplicate(
      parentFolderId: targetParentId,
      itemName: trimmedName,
      isFolder: true,
    );
    if (isDuplicate) {
      throw DuplicateDriveItemException(
        'Tên thư mục "$trimmedName" đã tồn tại! Vui lòng đặt tên khác.',
      );
    }

    final drive.File folderMetadata = drive.File()
      ..name = trimmedName
      ..mimeType = _folderMimeType
      ..parents = <String>[targetParentId];

    final drive.File created = await api.files.create(
      folderMetadata,
      $fields: 'id, name, createdTime',
    );

    final newItem = DriveFolderItem(
      id: created.id ?? '',
      name: created.name ?? trimmedName,
      createdTime: created.createdTime ?? DateTime.now(),
    );

    // Cập nhật ngay vào danh sách hiển thị của Tab tương ứng
    if (tabIndex == 0) {
      notesFoldersNotifier.value = <DriveFolderItem>[
        newItem,
        ...notesFoldersNotifier.value,
      ];
    } else {
      observationFoldersNotifier.value = <DriveFolderItem>[
        newItem,
        ...observationFoldersNotifier.value,
      ];
    }

    return newItem;
  }

  // ===========================================================================
  // HÀM CẬP NHẬT TÊN THƯ MỤC (ĐỔI TÊN) & XÓA THƯ MỤC TRÊN GOOGLE DRIVE
  // ===========================================================================
  Future<void> renameFolderInTab({
    required int tabIndex,
    required String folderId,
    required String newFolderName,
  }) async {
    final api = await _requireDriveApi();
    await ensureAppFolderStructure();

    final String trimmedName = newFolderName.trim();
    final String targetParentId =
        tabIndex == 0 ? _notesTabFolderId! : _observationTabFolderId!;

    final bool isDuplicate = await isItemNameDuplicate(
      parentFolderId: targetParentId,
      itemName: trimmedName,
      isFolder: true,
    );
    if (isDuplicate) {
      throw DuplicateDriveItemException(
        'Tên thư mục "$trimmedName" đã tồn tại! Vui lòng đặt tên khác.',
      );
    }

    final drive.File updateMeta = drive.File()..name = trimmedName;
    await api.files.update(updateMeta, folderId, $fields: 'id, name');

    final notifier =
        tabIndex == 0 ? notesFoldersNotifier : observationFoldersNotifier;
    notifier.value = notifier.value
        .map(
          (item) => item.id == folderId
              ? DriveFolderItem(
                  id: item.id,
                  name: trimmedName,
                  createdTime: item.createdTime,
                )
              : item,
        )
        .toList();
  }

  Future<void> deleteFolderInTab({
    required int tabIndex,
    required String folderId,
  }) async {
    final api = await _requireDriveApi();
    final drive.File trashMeta = drive.File()..trashed = true;
    await api.files.update(trashMeta, folderId);

    final notifier =
        tabIndex == 0 ? notesFoldersNotifier : observationFoldersNotifier;
    notifier.value =
        notifier.value.where((item) => item.id != folderId).toList();
  }

  // ===========================================================================
  // 7. HÀM TẠO MỚI HOẶC GHI ĐÈ FILE JSON LÊN GOOGLE DRIVE
  // - Khi tạo mới lần đầu (isCreatingNew == true): Kiểm tra chống trùng tên file.
  // - Khi tự động lưu ghi đè (existingDriveFileId != null): Ghi đè trực tiếp.
  // ===========================================================================
  Future<String> uploadOrOverwriteJsonFile({
    required int tabIndex,
    String? customParentFolderId,
    String? existingDriveFileId,
    required String fileName,
    required Map<String, dynamic> jsonData,
    bool checkDuplicateOnCreate = false,
  }) async {
    final api = await _requireDriveApi();
    await ensureAppFolderStructure();

    final String targetParentId = customParentFolderId ??
        (tabIndex == 0 ? _notesTabFolderId! : _observationTabFolderId!);

    final String cleanBaseName = fileName.trim().endsWith('.json')
        ? fileName.trim().substring(0, fileName.trim().length - 5)
        : fileName.trim();
    final String normalizedFileName = '$cleanBaseName.json';

    // Nếu là tạo file mới lần đầu -> Kiểm tra chống trùng tên file
    if (checkDuplicateOnCreate &&
        (existingDriveFileId == null || existingDriveFileId.isEmpty)) {
      final bool isDuplicate = await isItemNameDuplicate(
        parentFolderId: targetParentId,
        itemName: cleanBaseName,
        isFolder: false,
      );
      if (isDuplicate) {
        throw DuplicateDriveItemException(
          'Tên tệp "$cleanBaseName" đã tồn tại! Vui lòng đặt tên khác.',
        );
      }
    }

    final List<int> utf8Bytes = utf8.encode(
      const JsonEncoder.withIndent('  ').convert(jsonData),
    );
    final drive.Media media = drive.Media(
      Stream<List<int>>.value(utf8Bytes),
      utf8Bytes.length,
      contentType: _jsonMimeType,
    );

    String? fileIdToUpdate = existingDriveFileId;
    if (fileIdToUpdate == null || fileIdToUpdate.isEmpty) {
      final String escapedFileName = normalizedFileName.replaceAll("'", "\\'");
      final String query =
          "name = '$escapedFileName' and '$targetParentId' in parents and trashed = false";
      final existingFiles = await api.files.list(
        q: query,
        spaces: 'drive',
        $fields: 'files(id)',
        pageSize: 1,
      );
      if (existingFiles.files != null && existingFiles.files!.isNotEmpty) {
        fileIdToUpdate = existingFiles.files!.first.id;
      }
    }

    if (fileIdToUpdate != null && fileIdToUpdate.isNotEmpty) {
      // Ghi đè (Overwrite) trực tiếp lên file JSON đang lưu sẵn trên Google Drive
      final drive.File updateMeta = drive.File()
        ..name = normalizedFileName
        ..modifiedTime = DateTime.now().toUtc();
      final drive.File updatedFile = await api.files.update(
        updateMeta,
        fileIdToUpdate,
        uploadMedia: media,
        $fields: 'id',
      );
      return updatedFile.id ?? fileIdToUpdate;
    } else {
      // Tạo mới file JSON lần đầu tiên trên Google Drive
      final drive.File createMeta = drive.File()
        ..name = normalizedFileName
        ..mimeType = _jsonMimeType
        ..parents = <String>[targetParentId];
      final drive.File createdFile = await api.files.create(
        createMeta,
        uploadMedia: media,
        $fields: 'id',
      );
      return createdFile.id ?? '';
    }
  }

  // ===========================================================================
  // 8. HÀM TẢI / LÀM MỚI DANH SÁCH THƯ MỤC TỪ GOOGLE DRIVE THEO TỪNG TAB
  // Tự động đồng bộ lại nếu thư mục bị xóa trên Google Drive hoặc mạng lag
  // ===========================================================================
  Future<void> refreshAllTabFolders() async {
    isSyncingFoldersNotifier.value = true;
    try {
      // Đặt lại ID bộ đệm để kiểm tra lại từ gốc phòng trường hợp thư mục gốc trên Drive bị xóa
      _rootMeetingBookFolderId = null;
      _notesTabFolderId = null;
      _observationTabFolderId = null;

      await ensureAppFolderStructure();
      final results = await Future.wait([
        _fetchFoldersInParent(_notesTabFolderId!),
        _fetchFoldersInParent(_observationTabFolderId!),
      ]);
      notesFoldersNotifier.value = results[0];
      observationFoldersNotifier.value = results[1];
    } catch (e) {
      debugPrint('Lỗi tải danh sách thư mục từ Google Drive: $e');
    } finally {
      isSyncingFoldersNotifier.value = false;
    }
  }

  Future<List<DriveFolderItem>> _fetchFoldersInParent(String parentId) async {
    final api = await _requireDriveApi();
    final String query =
        "mimeType = '$_folderMimeType' and '$parentId' in parents and trashed = false";

    final drive.FileList fileList = await api.files.list(
      q: query,
      spaces: 'drive',
      orderBy: 'createdTime desc',
      $fields: 'files(id, name, createdTime)',
    );

    final files = fileList.files ?? <drive.File>[];
    return files
        .map(
          (f) => DriveFolderItem(
            id: f.id ?? '',
            name: f.name ?? 'Thư mục không tên',
            createdTime: f.createdTime,
          ),
        )
        .toList();
  }

  // ===========================================================================
  // 9. HÀM LƯU THÔNG TIN DUY TRÌ ĐĂNG NHẬP & ĐĂNG XUẤT
  // ===========================================================================
  Future<void> _saveUserToPrefs(GoogleSignInAccount account) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyIsLoggedIn, true);
    await prefs.setString(_keyUserEmail, account.email);
    await prefs.setString(_keyUserDisplayName, account.displayName ?? '');
    if (account.photoUrl != null) {
      await prefs.setString(_keyUserPhotoUrl, account.photoUrl!);
    }
    _cachedEmail = account.email;
    _cachedDisplayName = account.displayName;
    _cachedPhotoUrl = account.photoUrl;
  }

  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } catch (e) {
      debugPrint('Lỗi khi gọi googleSignIn.signOut: $e');
    }
    _currentUser = null;
    _driveApi = null;
    _cachedEmail = null;
    _cachedDisplayName = null;
    _cachedPhotoUrl = null;
    _rootMeetingBookFolderId = null;
    _notesTabFolderId = null;
    _observationTabFolderId = null;
    notesFoldersNotifier.value = [];
    observationFoldersNotifier.value = [];

    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
