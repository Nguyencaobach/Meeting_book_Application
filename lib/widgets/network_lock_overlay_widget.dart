import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';
import '../core/theme/app_theme.dart';

// ===========================================================================
// LỚP BẢO VỆ & KHÓA MÀN HÌNH TOÀN CỤC KHI MẤT KẾT NỐI MẠNG
// Công dụng:
// - Kiểm tra mạng ngay khi vào App, lắng nghe sự kiện phần cứng Wi-Fi/4G
//   và kiểm tra Internet thực tế định kỳ mỗi 3 giây.
// - Hễ mất mạng: Lập tức hiện bảng thông báo giữa màn hình (giống form thông báo
//   Thành công/Thất bại) và KHÓA TOÀN BỘ THAO TÁC trên màn hình cho đến khi
//   có mạng trở lại.
// ===========================================================================
class NetworkLockOverlayWidget extends StatefulWidget {
  final Widget child;

  const NetworkLockOverlayWidget({
    super.key,
    required this.child,
  });

  @override
  State<NetworkLockOverlayWidget> createState() =>
      _NetworkLockOverlayWidgetState();
}

class _NetworkLockOverlayWidgetState extends State<NetworkLockOverlayWidget>
    with WidgetsBindingObserver {
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  Timer? _periodicCheckTimer;

  bool _isOnline = true;
  bool _isChecking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // 1. Kiểm tra mạng ngay lập tức khi vừa vào App
    _verifyInternetConnection();

    // 2. Lắng nghe ngay khi người dùng bật/tắt Wi-Fi hoặc 4G
    _subscription = _connectivity.onConnectivityChanged.listen((results) {
      if (results.isEmpty || results.contains(ConnectivityResult.none)) {
        if (mounted && _isOnline) {
          setState(() => _isOnline = false);
        }
      } else {
        _verifyInternetConnection();
      }
    });

    // 3. Kiểm tra thực tế mỗi 3 giây (bắt chính xác cả trên máy ảo Android khi tắt mạng)
    _periodicCheckTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _verifyInternetConnection(),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _verifyInternetConnection();
    }
  }

  Future<void> _verifyInternetConnection() async {
    if (_isChecking) return;
    _isChecking = true;

    bool hasNet = false;
    try {
      final results = await _connectivity.checkConnectivity();
      if (results.isNotEmpty && !results.contains(ConnectivityResult.none)) {
        final lookup = await InternetAddress.lookup('google.com')
            .timeout(const Duration(seconds: 2));
        hasNet = lookup.isNotEmpty && lookup.first.rawAddress.isNotEmpty;
      }
    } catch (_) {
      hasNet = false;
    } finally {
      _isChecking = false;
    }

    if (mounted && _isOnline != hasNet) {
      setState(() {
        _isOnline = hasNet;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    _periodicCheckTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Size screenSize = MediaQuery.sizeOf(context);
    final double dialogWidth = (screenSize.width * 0.46).clamp(220.0, 340.0);
    final double iconSize =
        (screenSize.shortestSide * 0.11).clamp(48.0, 68.0);
    final double textFontSize = AppTheme.getResponsiveFontSize(context, 18);

    return Stack(
      children: [
        // Khóa toàn bộ thao tác phía dưới khi mất mạng
        AbsorbPointer(
          absorbing: !_isOnline,
          child: widget.child,
        ),

        // Nếu không có mạng -> Hiện bảng thông báo khóa chính giữa màn hình (giống form Thành công/Thất bại)
        if (!_isOnline)
          Positioned.fill(
            child: Material(
              color: AppColors.basicBlack.withValues(alpha: 0.55),
              child: Center(
                child: Container(
                  width: dialogWidth,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 28,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.basicWhite,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.basicBlack.withValues(alpha: 0.25),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Icon không có kết nối mạng (wifi_off_rounded)
                      Container(
                        width: iconSize,
                        height: iconSize,
                        decoration: BoxDecoration(
                          color: AppColors.paperMarginRed.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.wifi_off_rounded,
                          color: AppColors.paperMarginRed,
                          size: iconSize * 0.62,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Dòng chữ thông báo: "Vui lòng kết nối mạng"
                      Text(
                        'Vui lòng kết nối mạng',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.paperMarginRed,
                          fontSize: textFontSize,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
