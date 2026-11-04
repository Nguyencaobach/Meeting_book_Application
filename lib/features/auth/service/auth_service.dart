import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import '../../../data/datasources/google_drive_datasource.dart';
import '../../home/views/home_screen.dart';
import '../views/login_screen.dart';

// ===========================================================================
// DỊCH VỤ XỬ LÝ LOGIC ĐĂNG NHẬP / KIỂM TRA MẠNG / ĐĂNG XUẤT (AUTH SERVICE)
// Công dụng:
// - Kiểm tra kết nối mạng Internet thực tế trước khi cho phép đăng nhập.
// - Mở màn hình chọn tài khoản Google chính thống và liên kết Google Drive API.
// - Duy trì phiên đăng nhập cho đến khi người dùng chủ động bấm Đăng xuất.
// ===========================================================================
class AuthService {
  final GoogleDriveDatasource _driveDatasource = GoogleDriveDatasource.instance;
  final Connectivity _connectivity = Connectivity();

  /// Lấy địa chỉ email đang đăng nhập hiện tại
  String get currentUserEmail => _driveDatasource.currentEmail;

  /// Lấy tên hiển thị của người dùng hiện tại
  String get currentUserName => _driveDatasource.currentDisplayName;

  /// Lấy ảnh đại diện của người dùng (nếu có)
  String? get currentUserPhotoUrl => _driveDatasource.currentPhotoUrl;

  /// Kiểm tra xem người dùng đã đăng nhập từ lần trước chưa
  Future<bool> checkSavedLoginSession() async {
    return await _driveDatasource.restoreSession();
  }

  // ===========================================================================
  // 1. HÀM KIỂM TRA KẾT NỐI MẠNG INTERNET
  // ===========================================================================
  Future<bool> hasNetworkConnection() async {
    try {
      final List<ConnectivityResult> results =
          await _connectivity.checkConnectivity();
      if (results.isEmpty || results.contains(ConnectivityResult.none)) {
        return false;
      }

      // Kiểm tra phân giải DNS thực tế để chắc chắn có Internet
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 4));
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  // ===========================================================================
  // 2. HÀM KẾT NỐI TÀI KHOẢN GOOGLE CHÍNH THỐNG & LIÊN KẾT DRIVE
  // ===========================================================================
  Future<String?> handleGoogleConnect(BuildContext context) async {
    // Bước 1: Kiểm tra kết nối mạng trước tiên
    final bool isOnline = await hasNetworkConnection();
    if (!isOnline) {
      return 'Không có kết nối mạng! Vui lòng bật Wi-Fi hoặc dữ liệu di động để kết nối.';
    }

    // Bước 2: Mở bảng chọn tài khoản Google chính thống và liên kết Drive API
    final result = await _driveDatasource.signInAndLinkDrive();
    if (!result.success) {
      return result.errorMessage;
    }

    // Bước 3: Điều hướng vào màn hình Home khi đăng nhập thành công
    if (context.mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    }

    return null;
  }

  /// Thực hiện đăng xuất tài khoản và đưa người dùng về màn hình Đăng nhập
  Future<void> handleLogout(BuildContext context) async {
    await _driveDatasource.signOut();
    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }
}
