import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/note5x.dart';
import '../models/notebook_model.dart';
import 'local_storage_datasource.dart';

/// Ngoại lệ chuyên biệt khi phát hiện trùng tên Thư mục hoặc trùng tên File
class DuplicateDriveItemException implements Exception {
  final String message;
  const DuplicateDriveItemException(this.message);

  @override
  String toString() => message;
}

/// Model đại diện cho một Mục (Thư mục hoặc File JSON ghi chú) trên Google Drive
class DriveFolderItem {
  final String id;
  final String name;
  final DateTime? createdTime;
  final bool isFolder;
  final String? parentFolderId;
  final String paperTemplate;

  const DriveFolderItem({
    required this.id,
    required this.name,
    this.createdTime,
    this.isFolder = true,
    this.parentFolderId,
    this.paperTemplate = Note5x.templateId,
  });

  /// Tên hiển thị sạch (ẩn đuôi .json đối với tệp ghi chú)
  String get displayName {
    if (!isFolder && name.toLowerCase().endsWith('.json')) {
      return name.substring(0, name.length - 5);
    }
    return name;
  }
}

/// Node đại diện cho 1 thư mục trong Cây thư mục (Folder Tree) kiểu Google Drive khi Di chuyển
class DriveFolderTreeNode {
  final DriveFolderItem folder;
  final List<DriveFolderTreeNode> children;
  final bool isCurrentParent;

  const DriveFolderTreeNode({
    required this.folder,
    this.children = const <DriveFolderTreeNode>[],
    this.isCurrentParent = false,
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
// ├── Ghi_Chu/       (Tab 0: Ghi chú - chứa cả Thư mục con và File .json)
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

  // Ngăn xếp (Stack) điều hướng thư mục nhiều cấp (cho phép mở thư mục con nằm trong thư mục cha)
  final List<DriveFolderItem> _notesFolderStack = <DriveFolderItem>[];
  final List<DriveFolderItem> _observationFolderStack = <DriveFolderItem>[];

  /// Thư mục con đang được chọn mở trong Tab Ghi chú (null = đang ở ngoài màn hình gốc Ghi_Chu)
  final ValueNotifier<DriveFolderItem?> activeNotesFolderNotifier =
      ValueNotifier<DriveFolderItem?>(null);

  /// Thư mục con đang được chọn mở trong Tab Sổ dự giờ (null = đang ở ngoài màn hình gốc So_Du_Gio)
  final ValueNotifier<DriveFolderItem?> activeObservationFolderNotifier =
      ValueNotifier<DriveFolderItem?>(null);

  /// Danh sách các mục (Thư mục + File ghi chú) hiển thị ở Tab Ghi chú hiện tại
  final ValueNotifier<List<DriveFolderItem>> notesFoldersNotifier =
      ValueNotifier<List<DriveFolderItem>>([]);

  /// Danh sách các mục hiển thị ở Tab Sổ dự giờ
  final ValueNotifier<List<DriveFolderItem>> observationFoldersNotifier =
      ValueNotifier<List<DriveFolderItem>>([]);

  /// Trạng thái đang tải/đồng bộ danh sách từ Google Drive
  final ValueNotifier<bool> isSyncingFoldersNotifier =
      ValueNotifier<bool>(false);

  /// Từ khóa tìm kiếm hiện tại ở Tab Ghi chú
  final ValueNotifier<String> notesSearchKeywordNotifier =
      ValueNotifier<String>('');

  /// Từ khóa tìm kiếm hiện tại ở Tab Sổ dự giờ
  final ValueNotifier<String> observationSearchKeywordNotifier =
      ValueNotifier<String>('');

  /// Lấy email đang đăng nhập (từ phiên Google hoặc bộ nhớ duy trì đăng nhập)
  String get currentEmail => _currentUser?.email ?? _cachedEmail ?? '';

  /// Lấy tên hiển thị của người dùng
  String get currentDisplayName =>
      _currentUser?.displayName ?? _cachedDisplayName ?? 'Tài khoản Google Drive';

  /// Lấy ảnh đại diện (nếu có)
  String? get currentPhotoUrl => _currentUser?.photoUrl ?? _cachedPhotoUrl;

  /// Đối tượng DriveApi đã liên kết sẵn sàng để tạo thư mục / ghi đè file JSON
  drive.DriveApi? get driveApi => _driveApi;

  /// Đường dẫn hiển thị hiện tại của Tab Ghi chú (hỗ trợ hiển thị nhiều cấp thư mục)
  String get currentNotesPathLabel {
    if (_notesFolderStack.isEmpty) {
      return 'MeetingBook / Ghi_Chu';
    }
    final String subPath =
        _notesFolderStack.map((f) => f.displayName).join(' / ');
    return 'MeetingBook / Ghi_Chu / $subPath';
  }

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
        // Xóa token cũ đã hết hạn trong bộ đệm Android để lấy Access Token mới
        await account.clearAuthCache();
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

  /// Đảm bảo `_driveApi` luôn sẵn sàng; nếu chưa có thì khởi tạo từ phiên GoogleSignIn
  Future<drive.DriveApi> _requireDriveApi({bool forceRefreshToken = false}) async {
    if (!forceRefreshToken && _driveApi != null) {
      return _driveApi!;
    }

    if (forceRefreshToken && _currentUser != null) {
      try {
        await _currentUser!.clearAuthCache();
      } catch (_) {}
    }

    GoogleSignInAccount? account = await _googleSignIn.signInSilently(
      reAuthenticate: forceRefreshToken,
    );
    account ??= _currentUser ?? await _googleSignIn.signIn();
    if (account == null) {
      throw Exception('Chưa đăng nhập tài khoản Google Drive.');
    }

    if (forceRefreshToken) {
      try {
        await account.clearAuthCache();
      } catch (_) {}
    }

    _currentUser = account;
    final authHeaders = await account.authHeaders;
    _driveApi = drive.DriveApi(GoogleAuthClient(authHeaders));
    return _driveApi!;
  }

  /// Thực thi lệnh gọi Google Drive API kèm cơ chế tự động làm mới Access Token nếu gặp lỗi 401
  Future<T> _executeDriveCall<T>(
    Future<T> Function(drive.DriveApi api) action,
  ) async {
    try {
      final api = await _requireDriveApi();
      return await action(api);
    } on drive.DetailedApiRequestError catch (e) {
      if (e.status == 401) {
        debugPrint(
          'Token Google Drive hết hạn (401), đang tự động làm mới Access Token...',
        );
        final refreshedApi = await _requireDriveApi(forceRefreshToken: true);
        return await action(refreshedApi);
      }
      rethrow;
    } catch (e) {
      if (e.toString().contains('401') ||
          e.toString().contains('invalid authentication credentials')) {
        debugPrint(
          'Phát hiện lỗi xác thực 401, đang tự động cấp lại Access Token...',
        );
        final refreshedApi = await _requireDriveApi(forceRefreshToken: true);
        return await action(refreshedApi);
      }
      rethrow;
    }
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

    await _executeDriveCall((api) async {
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
    });

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
  // 5. HÀM ĐIỀU HƯỚNG BẤM SỬ DỤNG THƯ MỤC NHIỀU CẤP TRONG TAB GHI CHÚ & SỔ DỰ GIỜ
  // Công dụng:
  // - Khi bấm vào một thư mục -> Mở vào bên trong thư mục đó (hỗ trợ cả thư mục con
  //   nằm trong thư mục cha nhiều cấp).
  // - Khi bấm nút "Quay lại" -> Lùi về thư mục cha ngay trước đó hoặc màn hình gốc.
  // ===========================================================================
  Future<void> openNotesFolder(DriveFolderItem folder) async {
    if (!folder.isFolder) return;
    if (_notesFolderStack.isEmpty || _notesFolderStack.last.id != folder.id) {
      _notesFolderStack.add(folder);
    }
    activeNotesFolderNotifier.value = _notesFolderStack.last;
    await refreshCurrentNotesView();
  }

  /// Thoát khỏi thư mục đang mở để lùi về thư mục cha trước đó (hoặc màn hình chính Ghi chú)
  Future<void> exitCurrentNotesFolder() async {
    if (_notesFolderStack.isNotEmpty) {
      _notesFolderStack.removeLast();
    }
    activeNotesFolderNotifier.value =
        _notesFolderStack.isEmpty ? null : _notesFolderStack.last;
    await refreshCurrentNotesView();
  }

  /// Làm mới danh sách các mục trong khung nhìn hiện tại của Tab Ghi chú
  Future<void> refreshCurrentNotesView() async {
    isSyncingFoldersNotifier.value = true;
    try {
      await ensureAppFolderStructure();
      final String targetParentId =
          activeNotesFolderNotifier.value?.id ?? _notesTabFolderId!;
      final items = await _fetchItemsInParent(targetParentId);
      notesFoldersNotifier.value = items;
    } catch (e) {
      debugPrint('Lỗi tải danh sách mục trong Tab Ghi chú: $e');
      rethrow;
    } finally {
      isSyncingFoldersNotifier.value = false;
    }
  }

  /// Mở vào bên trong 1 thư mục ở Tab Sổ dự giờ (hỗ trợ nhiều cấp thư mục)
  Future<void> openObservationFolder(DriveFolderItem folder) async {
    if (!folder.isFolder) return;
    if (_observationFolderStack.isEmpty ||
        _observationFolderStack.last.id != folder.id) {
      _observationFolderStack.add(folder);
    }
    activeObservationFolderNotifier.value = _observationFolderStack.last;
    await refreshCurrentObservationView();
  }

  /// Lùi khỏi thư mục đang mở ở Tab Sổ dự giờ về thư mục cha trước đó
  Future<void> exitCurrentObservationFolder() async {
    if (_observationFolderStack.isNotEmpty) {
      _observationFolderStack.removeLast();
    }
    activeObservationFolderNotifier.value =
        _observationFolderStack.isEmpty ? null : _observationFolderStack.last;
    await refreshCurrentObservationView();
  }

  /// Làm mới danh sách các mục trong khung nhìn hiện tại của Tab Sổ dự giờ
  Future<void> refreshCurrentObservationView() async {
    isSyncingFoldersNotifier.value = true;
    try {
      await ensureAppFolderStructure();
      final String targetParentId =
          activeObservationFolderNotifier.value?.id ?? _observationTabFolderId!;
      final items = await _fetchItemsInParent(targetParentId);
      observationFoldersNotifier.value = items;
    } catch (e) {
      debugPrint('Lỗi tải danh sách mục trong Tab Sổ dự giờ: $e');
      rethrow;
    } finally {
      isSyncingFoldersNotifier.value = false;
    }
  }

  // ===========================================================================
  // 6. HÀM KIỂM TRA CHỐNG TRÙNG TÊN THƯ MỤC & TRÙNG TÊN FILE
  // ===========================================================================
  Future<bool> isItemNameDuplicate({
    required String parentFolderId,
    required String itemName,
    required bool isFolder,
    String? excludeItemId,
  }) async {
    return _executeDriveCall((api) async {
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
        if (excludeItemId != null && file.id == excludeItemId) {
          continue;
        }
        final String existingName = (file.name ?? '').trim();
        final String existingWithoutJson =
            existingName.toLowerCase().endsWith('.json')
                ? existingName.substring(0, existingName.length - 5)
                : existingName;
        if (existingName.toLowerCase() == lowerTarget ||
            existingWithoutJson.toLowerCase() == lowerTarget) {
          return true;
        }
      }
      return false;
    });
  }

  // ===========================================================================
  // 7. HÀM TẠO THƯ MỤC MỚI THEO TAB (CÓ KIỂM TRA CHỐNG TRÙNG TÊN THƯ MỤC)
  // ===========================================================================
  Future<DriveFolderItem> createFolderInTab({
    required int tabIndex,
    required String folderName,
  }) async {
    await ensureAppFolderStructure();

    final String trimmedName = folderName.trim();
    // Nếu đang mở 1 thư mục con thì tạo thư mục mới ngay trong thư mục đang mở, ngược lại tạo ở gốc Tab
    final String targetParentId = tabIndex == 0
        ? (activeNotesFolderNotifier.value?.id ?? _notesTabFolderId!)
        : (activeObservationFolderNotifier.value?.id ??
            _observationTabFolderId!);

    // Bước 1: Kiểm tra nhanh ngay trên danh sách RAM đang hiển thị
    final currentRamList = tabIndex == 0
        ? notesFoldersNotifier.value
        : observationFoldersNotifier.value;
    final bool existsInRam = currentRamList.any(
      (f) =>
          f.isFolder &&
          f.displayName.trim().toLowerCase() == trimmedName.toLowerCase(),
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

    final drive.File created = await _executeDriveCall(
      (api) => api.files.create(
        folderMetadata,
        $fields: 'id, name, createdTime',
      ),
    );

    final newItem = DriveFolderItem(
      id: created.id ?? '',
      name: created.name ?? trimmedName,
      createdTime: created.createdTime ?? DateTime.now(),
      isFolder: true,
      parentFolderId: targetParentId,
    );

    // Đưa thư mục mới lên đầu danh sách hiển thị hiện tại
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
  // 8. HÀM TẠO FILE GHI CHÚ JSON MỚI (Ở MÀN HÌNH CHÍNH HOẶC TRONG THƯ MỤC ĐÃ CHỌN)
  // Công dụng:
  // - Cho phép tạo file ghi chú (.json) ở ngoài màn hình chính (MeetingBook/Ghi_Chu)
  //   hoặc bên trong thư mục đang mở (MeetingBook/Ghi_Chu/<Tên thư mục>).
  // - Lưu định dạng mẫu vở đã chọn ('note5x' hoặc 'note4x') vào cấu trúc JSON
  //   và appProperties của file trên Google Drive.
  // ===========================================================================
  Future<({DriveFolderItem fileItem, NotebookModel notebook})>
      createNoteFileInNotesTab({
    required String fileName,
    required String paperTemplate,
  }) async {
    await ensureAppFolderStructure();

    final String cleanBaseName = fileName.trim().endsWith('.json')
        ? fileName.trim().substring(0, fileName.trim().length - 5)
        : fileName.trim();

    // Xác định vị trí lưu: Nếu đang mở 1 thư mục con thì lưu vào thư mục đó, ngược lại lưu ở gốc Ghi_Chu
    final String targetParentId =
        activeNotesFolderNotifier.value?.id ?? _notesTabFolderId!;

    // Kiểm tra nhanh trùng tên file ngay trên danh sách hiện tại
    final bool existsInRam = notesFoldersNotifier.value.any(
      (item) =>
          !item.isFolder &&
          item.displayName.trim().toLowerCase() == cleanBaseName.toLowerCase(),
    );
    if (existsInRam) {
      throw DuplicateDriveItemException(
        'Tên tệp "$cleanBaseName" đã tồn tại! Vui lòng đặt tên khác.',
      );
    }

    // Khởi tạo dữ liệu JSON ban đầu cho file ghi chú với loại vở đã chọn (note5x hoặc note4x)
    final String tempDocId = 'note_${DateTime.now().millisecondsSinceEpoch}';
    final NotebookModel initialNotebook = NotebookModel.createInitial(
      id: tempDocId,
      title: cleanBaseName,
      paperTemplate: paperTemplate,
    );

    // Đẩy file .json lên Google Drive (có kiểm tra chống trùng tên trên Drive)
    final String createdDriveFileId = await uploadOrOverwriteJsonFile(
      tabIndex: 0,
      customParentFolderId: targetParentId,
      fileName: cleanBaseName,
      jsonData: initialNotebook.toJson(),
      checkDuplicateOnCreate: true,
      paperTemplate: paperTemplate,
    );

    // Đồng bộ ID thực tế của Google Drive vào NotebookModel và lưu vào RAM
    final NotebookModel syncedNotebook = initialNotebook.copyWith(
      id: createdDriveFileId,
    );
    await LocalStorageDatasource.instance.saveToRamAndLocalBuffer(
      documentId: createdDriveFileId,
      jsonData: syncedNotebook.toJson(),
    );
    await LocalStorageDatasource.instance.markSyncedToDrive(createdDriveFileId);

    final DriveFolderItem newFileItem = DriveFolderItem(
      id: createdDriveFileId,
      name: '$cleanBaseName.json',
      createdTime: DateTime.now(),
      isFolder: false,
      parentFolderId: targetParentId,
      paperTemplate: paperTemplate,
    );

    // Đưa file mới vào danh sách hiển thị (nằm ngay sau nhóm thư mục)
    final currentItems = List<DriveFolderItem>.from(notesFoldersNotifier.value);
    final int firstFileIndex =
        currentItems.indexWhere((element) => !element.isFolder);
    if (firstFileIndex == -1) {
      currentItems.add(newFileItem);
    } else {
      currentItems.insert(firstFileIndex, newFileItem);
    }
    notesFoldersNotifier.value = currentItems;

    return (fileItem: newFileItem, notebook: syncedNotebook);
  }

  // ===========================================================================
  // 9. HÀM TẢI NỘI DUNG JSON CỦA FILE GHI CHÚ ĐỂ RENDER LÊN GIAO DIỆN VỞ
  // Công dụng:
  // - Ưu tiên đọc từ bộ nhớ đệm RAM (nếu người dùng vừa viết xong và không bấm Làm mới).
  // - Nếu chưa có trong RAM hoặc khi bấm nút "Làm mới" (forceRefreshFromDrive = true)
  //   thì tải trực tiếp nội dung file .json mới nhất từ Google Drive về.
  // ===========================================================================
  Future<NotebookModel> loadNoteJsonFile(
    DriveFolderItem fileItem, {
    bool forceRefreshFromDrive = false,
  }) async {
    // 1. Kiểm tra trong RAM trước (bỏ qua nếu người dùng chủ động bấm "Làm mới")
    if (!forceRefreshFromDrive) {
      final Map<String, dynamic>? cachedJson =
          await LocalStorageDatasource.instance.getFromRamOrLocalBuffer(
        fileItem.id,
      );
      if (cachedJson != null) {
        return NotebookModel.fromJson(cachedJson);
      }
    }

    // 2. Gọi Google Drive API để tải nội dung file JSON về
    final Object response = await _executeDriveCall(
      (api) => api.files.get(
        fileItem.id,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ),
    );

    if (response is drive.Media) {
      final String jsonString = await utf8.decodeStream(response.stream);
      if (jsonString.trim().isNotEmpty) {
        final Map<String, dynamic> decoded =
            jsonDecode(jsonString) as Map<String, dynamic>;
        final NotebookModel notebook = NotebookModel.fromJson(decoded).copyWith(
          id: fileItem.id,
          title: fileItem.displayName,
        );

        // Lưu vào RAM để lần mở tiếp theo đọc tức thì 0ms
        await LocalStorageDatasource.instance.saveToRamAndLocalBuffer(
          documentId: fileItem.id,
          jsonData: notebook.toJson(),
        );
        await LocalStorageDatasource.instance.markSyncedToDrive(fileItem.id);
        return notebook;
      }
    }

    // Nếu file rỗng -> Khởi tạo cấu trúc mặc định theo loại giấy của fileItem
    return NotebookModel.createInitial(
      id: fileItem.id,
      title: fileItem.displayName,
      paperTemplate: fileItem.paperTemplate,
    );
  }

  // ===========================================================================
  // HÀM ĐỔI TÊN, XÓA, DI CHUYỂN (CÂY THƯ MỤC) & HOÀN TÁC TRÊN GOOGLE DRIVE
  // ===========================================================================

  /// 1. Đổi tên Thư mục hoặc Tệp ghi chú (.json) - Có kiểm tra chống trùng tên
  Future<void> renameItemInTab({
    required int tabIndex,
    required DriveFolderItem item,
    required String newName,
  }) async {
    await ensureAppFolderStructure();

    final String cleanBaseName = newName.trim().endsWith('.json')
        ? newName.trim().substring(0, newName.trim().length - 5)
        : newName.trim();

    // Nếu người dùng giữ nguyên tên hiện tại (không phân biệt hoa thường) -> Báo trùng tên
    if (cleanBaseName.toLowerCase() == item.displayName.trim().toLowerCase()) {
      throw DuplicateDriveItemException(
        item.isFolder
            ? 'Tên thư mục "$cleanBaseName" trùng với tên hiện tại! Vui lòng đặt tên khác.'
            : 'Tên tệp "$cleanBaseName" trùng với tên hiện tại! Vui lòng đặt tên khác.',
      );
    }

    final String targetParentId = item.parentFolderId ??
        (tabIndex == 0
            ? (activeNotesFolderNotifier.value?.id ?? _notesTabFolderId!)
            : (activeObservationFolderNotifier.value?.id ??
                _observationTabFolderId!));

    // Bước 1: Kiểm tra nhanh trùng tên ngay trong danh sách RAM hiện tại
    final notifier =
        tabIndex == 0 ? notesFoldersNotifier : observationFoldersNotifier;
    final bool duplicateInRam = notifier.value.any(
      (current) =>
          current.id != item.id &&
          current.isFolder == item.isFolder &&
          current.displayName.trim().toLowerCase() ==
              cleanBaseName.toLowerCase(),
    );
    if (duplicateInRam) {
      throw DuplicateDriveItemException(
        item.isFolder
            ? 'Tên thư mục "$cleanBaseName" đã tồn tại! Vui lòng đặt tên khác.'
            : 'Tên tệp "$cleanBaseName" đã tồn tại! Vui lòng đặt tên khác.',
      );
    }

    // Bước 2: Kiểm tra trùng tên trực tiếp trên Google Drive
    final bool isDuplicate = await isItemNameDuplicate(
      parentFolderId: targetParentId,
      itemName: cleanBaseName,
      isFolder: item.isFolder,
      excludeItemId: item.id,
    );
    if (isDuplicate) {
      throw DuplicateDriveItemException(
        item.isFolder
            ? 'Tên thư mục "$cleanBaseName" đã tồn tại! Vui lòng đặt tên khác.'
            : 'Tên tệp "$cleanBaseName" đã tồn tại! Vui lòng đặt tên khác.',
      );
    }

    final String updatedDriveName =
        item.isFolder ? cleanBaseName : '$cleanBaseName.json';
    final drive.File updateMeta = drive.File()..name = updatedDriveName;
    await _executeDriveCall(
      (api) => api.files.update(updateMeta, item.id, $fields: 'id, name'),
    );

    // Nếu là tệp JSON và đang có trong bộ nhớ đệm RAM -> Cập nhật luôn title trong JSON
    if (!item.isFolder) {
      final cachedJson = await LocalStorageDatasource.instance
          .getFromRamOrLocalBuffer(item.id);
      if (cachedJson != null) {
        final updatedJson = Map<String, dynamic>.from(cachedJson);
        updatedJson['title'] = cleanBaseName;
        await LocalStorageDatasource.instance.saveToRamAndLocalBuffer(
          documentId: item.id,
          jsonData: updatedJson,
        );
      }
    }

    notifier.value = notifier.value
        .map(
          (current) => current.id == item.id
              ? DriveFolderItem(
                  id: current.id,
                  name: updatedDriveName,
                  createdTime: current.createdTime,
                  isFolder: current.isFolder,
                  parentFolderId: current.parentFolderId,
                  paperTemplate: current.paperTemplate,
                )
              : current,
        )
        .toList();
  }

  /// 2. Xóa Thư mục hoặc Tệp ghi chú (Đưa vào thùng rác Google Drive)
  Future<void> deleteItemInTab({
    required int tabIndex,
    required DriveFolderItem item,
  }) async {
    final drive.File trashMeta = drive.File()..trashed = true;
    await _executeDriveCall(
      (api) => api.files.update(trashMeta, item.id),
    );

    final notifier =
        tabIndex == 0 ? notesFoldersNotifier : observationFoldersNotifier;
    notifier.value =
        notifier.value.where((current) => current.id != item.id).toList();
  }

  /// 2b. Hoàn tác Xóa (Khôi phục Thư mục hoặc Tệp từ thùng rác Google Drive về lại danh sách)
  Future<void> restoreDeletedItemInTab({
    required int tabIndex,
    required DriveFolderItem item,
  }) async {
    final drive.File restoreMeta = drive.File()..trashed = false;
    await _executeDriveCall(
      (api) => api.files.update(restoreMeta, item.id),
    );

    _insertItemBackIntoRamList(tabIndex: tabIndex, item: item);
  }

  /// Chèn mục vừa hoàn tác về lại đúng vị trí trong danh sách RAM (Thư mục đứng trước, Tệp đứng sau)
  void _insertItemBackIntoRamList({
    required int tabIndex,
    required DriveFolderItem item,
  }) {
    final String currentViewParentId = tabIndex == 0
        ? (activeNotesFolderNotifier.value?.id ?? (_notesTabFolderId ?? ''))
        : (activeObservationFolderNotifier.value?.id ??
            (_observationTabFolderId ?? ''));

    final String itemParentId = item.parentFolderId ?? currentViewParentId;
    if (currentViewParentId.isNotEmpty && itemParentId != currentViewParentId) {
      return;
    }

    final notifier =
        tabIndex == 0 ? notesFoldersNotifier : observationFoldersNotifier;
    if (notifier.value.any((e) => e.id == item.id)) {
      return;
    }

    final List<DriveFolderItem> currentList =
        List<DriveFolderItem>.from(notifier.value);
    if (item.isFolder) {
      currentList.insert(0, item);
    } else {
      final int firstFileIdx =
          currentList.indexWhere((element) => !element.isFolder);
      if (firstFileIdx == -1) {
        currentList.add(item);
      } else {
        currentList.insert(firstFileIdx, item);
      }
    }
    notifier.value = currentList;
  }

  /// 3. Xây dựng Cây thư mục đa cấp (Folder Tree) kiểu Google Drive để người dùng chọn nơi Di chuyển
  /// - Cho phép chuyển Thư mục này vào Thư mục khác (nhiều cấp) hoặc chuyển Tệp vào bất kỳ Thư mục nào.
  /// - Tự động loại bỏ chính thư mục đang di chuyển và toàn bộ thư mục con của nó.
  Future<DriveFolderTreeNode> fetchFolderTreeForMove({
    required int tabIndex,
    required DriveFolderItem itemToMove,
  }) async {
    await ensureAppFolderStructure();

    final String rootTabId =
        tabIndex == 0 ? _notesTabFolderId! : _observationTabFolderId!;
    final String currentParentId = itemToMove.parentFolderId ??
        (tabIndex == 0
            ? (activeNotesFolderNotifier.value?.id ?? rootTabId)
            : (activeObservationFolderNotifier.value?.id ?? rootTabId));

    // Tải toàn bộ danh sách thư mục không nằm trong thùng rác bằng 1 lần gọi API duy nhất
    final List<drive.File> allDriveFolders =
        await _executeDriveCall((api) async {
      final List<drive.File> collected = <drive.File>[];
      String? pageToken;
      do {
        final drive.FileList list = await api.files.list(
          q: "mimeType = '$_folderMimeType' and trashed = false",
          spaces: 'drive',
          orderBy: 'createdTime desc',
          pageSize: 500,
          pageToken: pageToken,
          $fields: 'nextPageToken, files(id, name, parents, createdTime)',
        );
        if (list.files != null) {
          collected.addAll(list.files!);
        }
        pageToken = list.nextPageToken;
      } while (pageToken != null && pageToken.isNotEmpty);
      return collected;
    });

    // Gom nhóm các thư mục con theo ID thư mục cha
    final Map<String, List<DriveFolderItem>> childrenByParentId =
        <String, List<DriveFolderItem>>{};
    for (final f in allDriveFolders) {
      final String folderId = f.id ?? '';
      if (folderId.isEmpty) continue;
      // Không cho phép chuyển một thư mục vào chính nó hoặc vào các thư mục con bên trong nó
      if (itemToMove.isFolder && folderId == itemToMove.id) {
        continue;
      }

      final List<String> parents = f.parents ?? const <String>[];
      for (final String pId in parents) {
        final folderItem = DriveFolderItem(
          id: folderId,
          name: f.name ?? 'Thư mục không tên',
          createdTime: f.createdTime,
          isFolder: true,
          parentFolderId: pId,
        );
        childrenByParentId
            .putIfAbsent(pId, () => <DriveFolderItem>[])
            .add(folderItem);
      }
    }

    // Hàm đệ quy dựng cây thư mục nhiều cấp (chống vòng lặp bằng visitedIds)
    final Set<String> visitedIds = <String>{};
    DriveFolderTreeNode buildSubtree(DriveFolderItem currentFolder) {
      visitedIds.add(currentFolder.id);
      final List<DriveFolderItem> rawChildren =
          childrenByParentId[currentFolder.id] ?? const <DriveFolderItem>[];
      final List<DriveFolderTreeNode> childNodes = <DriveFolderTreeNode>[];

      for (final child in rawChildren) {
        if (visitedIds.contains(child.id)) continue;
        if (itemToMove.isFolder && child.id == itemToMove.id) continue;
        childNodes.add(buildSubtree(child));
      }

      return DriveFolderTreeNode(
        folder: currentFolder,
        children: childNodes,
        isCurrentParent: currentFolder.id == currentParentId,
      );
    }

    final DriveFolderItem rootFolderItem = DriveFolderItem(
      id: rootTabId,
      name: tabIndex == 0
          ? 'Thư mục gốc (MeetingBook / Ghi_Chu)'
          : 'Thư mục gốc (MeetingBook / So_Du_Gio)',
      isFolder: true,
    );

    return buildSubtree(rootFolderItem);
  }

  /// 4. Thực thi di chuyển Tệp hoặc Thư mục sang thư mục đích trên Google Drive
  /// Trả về `oldParentId` để hỗ trợ nút "Hoàn tác" khôi phục về vị trí cũ.
  Future<String> moveItemInTab({
    required int tabIndex,
    required DriveFolderItem item,
    required String targetFolderId,
  }) async {
    await ensureAppFolderStructure();

    final String rootTabId =
        tabIndex == 0 ? _notesTabFolderId! : _observationTabFolderId!;
    final String oldParentId = item.parentFolderId ??
        (tabIndex == 0
            ? (activeNotesFolderNotifier.value?.id ?? rootTabId)
            : (activeObservationFolderNotifier.value?.id ?? rootTabId));

    if (oldParentId == targetFolderId) {
      throw const DuplicateDriveItemException(
        'Mục này đang nằm sẵn trong thư mục đã chọn! Vui lòng chọn thư mục khác.',
      );
    }

    // Kiểm tra chống trùng tên trong thư mục đích trước khi di chuyển
    final bool isDuplicateInTarget = await isItemNameDuplicate(
      parentFolderId: targetFolderId,
      itemName: item.displayName,
      isFolder: item.isFolder,
      excludeItemId: item.id,
    );
    if (isDuplicateInTarget) {
      throw DuplicateDriveItemException(
        item.isFolder
            ? 'Thư mục đích đã có thư mục tên "${item.displayName}"!'
            : 'Thư mục đích đã có tệp tên "${item.displayName}"!',
      );
    }

    await _executeDriveCall(
      (api) => api.files.update(
        drive.File(),
        item.id,
        addParents: targetFolderId,
        removeParents: oldParentId,
        $fields: 'id, parents',
      ),
    );

    // Loại bỏ mục vừa di chuyển khỏi danh sách khung nhìn hiện tại
    final notifier =
        tabIndex == 0 ? notesFoldersNotifier : observationFoldersNotifier;
    notifier.value =
        notifier.value.where((current) => current.id != item.id).toList();

    return oldParentId;
  }

  /// 4b. Hoàn tác Di chuyển (Chuyển Tệp hoặc Thư mục ngược về lại thư mục cha ban đầu)
  Future<void> undoMoveItemInTab({
    required int tabIndex,
    required DriveFolderItem item,
    required String currentTargetFolderId,
    required String previousParentId,
  }) async {
    if (currentTargetFolderId == previousParentId) return;

    await _executeDriveCall(
      (api) => api.files.update(
        drive.File(),
        item.id,
        addParents: previousParentId,
        removeParents: currentTargetFolderId,
        $fields: 'id, parents',
      ),
    );

    final DriveFolderItem restoredItem = DriveFolderItem(
      id: item.id,
      name: item.name,
      createdTime: item.createdTime,
      isFolder: item.isFolder,
      parentFolderId: previousParentId,
      paperTemplate: item.paperTemplate,
    );

    _insertItemBackIntoRamList(tabIndex: tabIndex, item: restoredItem);
  }

  // ===========================================================================
  // 10. HÀM TẠO MỚI HOẶC GHI ĐÈ FILE JSON LÊN GOOGLE DRIVE
  // ===========================================================================
  Future<String> uploadOrOverwriteJsonFile({
    required int tabIndex,
    String? customParentFolderId,
    String? existingDriveFileId,
    required String fileName,
    required Map<String, dynamic> jsonData,
    bool checkDuplicateOnCreate = false,
    String? paperTemplate,
  }) async {
    await ensureAppFolderStructure();

    final String targetParentId = customParentFolderId ??
        (tabIndex == 0
            ? (activeNotesFolderNotifier.value?.id ?? _notesTabFolderId!)
            : _observationTabFolderId!);

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

    return _executeDriveCall((api) async {
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

      final String resolvedTemplate = paperTemplate ??
          (jsonData['paperTemplate'] as String?) ??
          Note5x.templateId;

      if (fileIdToUpdate != null && fileIdToUpdate.isNotEmpty) {
        // Ghi đè (Overwrite) trực tiếp lên file JSON đang lưu sẵn trên Google Drive
        final drive.File updateMeta = drive.File()
          ..name = normalizedFileName
          ..modifiedTime = DateTime.now().toUtc()
          ..appProperties = <String, String>{
            'paperTemplate': resolvedTemplate,
          };
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
          ..parents = <String>[targetParentId]
          ..appProperties = <String, String>{
            'paperTemplate': resolvedTemplate,
          };
        final drive.File createdFile = await api.files.create(
          createMeta,
          uploadMedia: media,
          $fields: 'id',
        );
        return createdFile.id ?? '';
      }
    });
  }

  // ===========================================================================
  // 11. HÀM TẢI / LÀM MỚI DANH SÁCH THƯ MỤC & FILE TỪ GOOGLE DRIVE THEO TỪNG TAB
  // ===========================================================================
  Future<void> refreshAllTabFolders() async {
    isSyncingFoldersNotifier.value = true;
    try {
      _rootMeetingBookFolderId = null;
      _notesTabFolderId = null;
      _observationTabFolderId = null;

      await ensureAppFolderStructure();

      final String notesParentId =
          activeNotesFolderNotifier.value?.id ?? _notesTabFolderId!;
      final String observationParentId =
          activeObservationFolderNotifier.value?.id ?? _observationTabFolderId!;

      final results = await Future.wait([
        _fetchItemsInParent(notesParentId),
        _fetchItemsInParent(observationParentId),
      ]);
      notesFoldersNotifier.value = results[0];
      observationFoldersNotifier.value = results[1];
    } catch (e) {
      debugPrint('Lỗi tải danh sách từ Google Drive: $e');
    } finally {
      isSyncingFoldersNotifier.value = false;
    }
  }

  /// Tải danh sách cả Thư mục và File .json bên trong 1 thư mục cha trên Google Drive
  Future<List<DriveFolderItem>> _fetchItemsInParent(
    String parentId, {
    bool foldersOnly = false,
  }) async {
    return _executeDriveCall((api) async {
      final String query = foldersOnly
          ? "mimeType = '$_folderMimeType' and '$parentId' in parents and trashed = false"
          : "'$parentId' in parents and trashed = false";

      final drive.FileList fileList = await api.files.list(
        q: query,
        spaces: 'drive',
        orderBy: 'createdTime desc',
        $fields: 'files(id, name, mimeType, createdTime, appProperties)',
      );

      final files = fileList.files ?? <drive.File>[];
      final List<DriveFolderItem> folders = <DriveFolderItem>[];
      final List<DriveFolderItem> noteFiles = <DriveFolderItem>[];

      for (final f in files) {
        final bool isFolderItem = f.mimeType == _folderMimeType;
        final String template =
            f.appProperties?['paperTemplate'] ?? Note5x.templateId;
        final item = DriveFolderItem(
          id: f.id ?? '',
          name: f.name ?? (isFolderItem ? 'Thư mục không tên' : 'Ghi chú.json'),
          createdTime: f.createdTime,
          isFolder: isFolderItem,
          parentFolderId: parentId,
          paperTemplate: template,
        );
        if (isFolderItem) {
          folders.add(item);
        } else {
          noteFiles.add(item);
        }
      }

      // Hiển thị các Thư mục trước, sau đó đến các File ghi chú
      return <DriveFolderItem>[...folders, ...noteFiles];
    });
  }

  // ===========================================================================
  // 12. HÀM LƯU THÔNG TIN DUY TRÌ ĐĂNG NHẬP & ĐĂNG XUẤT
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
    _notesFolderStack.clear();
    _observationFolderStack.clear();
    activeNotesFolderNotifier.value = null;
    activeObservationFolderNotifier.value = null;
    notesFoldersNotifier.value = [];
    observationFoldersNotifier.value = [];

    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
