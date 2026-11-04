import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

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

  // Danh sách thông báo cập nhật giao diện khi có thư mục mới được tạo
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

  /// Đảm bảo `_driveApi` đã sẵn sàng (nếu vừa mở lại app mà phiên ngầm chưa nối xong thì nối lại)
  Future<drive.DriveApi> _requireDriveApi() async {
    if (_driveApi != null) {
      return _driveApi!;
    }
    final GoogleSignInAccount? account =
        _currentUser ?? await _googleSignIn.signInSilently() ?? await _googleSignIn.signIn();
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
  // 5. HÀM TẠO THƯ MỤC MỚI THEO TAB ("Ghi_Chu" HOẶC "So_Du_Gio")
  // ===========================================================================
  Future<DriveFolderItem> createFolderInTab({
    required int tabIndex,
    required String folderName,
  }) async {
    final api = await _requireDriveApi();
    await ensureAppFolderStructure();

    final String targetParentId =
        tabIndex == 0 ? _notesTabFolderId! : _observationTabFolderId!;

    final drive.File folderMetadata = drive.File()
      ..name = folderName.trim()
      ..mimeType = _folderMimeType
      ..parents = <String>[targetParentId];

    final drive.File created = await api.files.create(
      folderMetadata,
      $fields: 'id, name, createdTime',
    );

    final newItem = DriveFolderItem(
      id: created.id ?? '',
      name: created.name ?? folderName.trim(),
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
  // 6. HÀM ĐÓNG GÓI & GHI ĐÈ FILE JSON LÊN GOOGLE DRIVE
  // - Nếu file đã tồn tại trên Drive -> Ghi đè nội dung mới (files.update).
  // - Nếu file chưa tồn tại -> Tạo mới file .json trong thư mục đích (files.create).
  // ===========================================================================
  Future<String> uploadOrOverwriteJsonFile({
    required int tabIndex,
    String? customParentFolderId,
    String? existingDriveFileId,
    required String fileName,
    required Map<String, dynamic> jsonData,
  }) async {
    final api = await _requireDriveApi();
    await ensureAppFolderStructure();

    final String targetParentId = customParentFolderId ??
        (tabIndex == 0 ? _notesTabFolderId! : _observationTabFolderId!);

    final String normalizedFileName =
        fileName.endsWith('.json') ? fileName : '$fileName.json';
    final List<int> utf8Bytes = utf8.encode(
      const JsonEncoder.withIndent('  ').convert(jsonData),
    );
    final drive.Media media = drive.Media(
      Stream<List<int>>.value(utf8Bytes),
      utf8Bytes.length,
      contentType: _jsonMimeType,
    );

    // Kiểm tra xem đã có ID file trên Drive chưa; nếu chưa có thì thử tìm theo tên trong thư mục đích
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
  // 7. HÀM TẢI DANH SÁCH THƯ MỤC TỪ GOOGLE DRIVE THEO TỪNG TAB
  // ===========================================================================
  Future<void> refreshAllTabFolders() async {
    isSyncingFoldersNotifier.value = true;
    try {
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
  // 8. HÀM LƯU THÔNG TIN DUY TRÌ ĐĂNG NHẬP & ĐĂNG XUẤT
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
