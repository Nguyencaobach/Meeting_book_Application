import 'package:flutter/material.dart';
import 'core/constants/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/service/auth_service.dart';
import 'features/auth/views/login_screen.dart';
import 'features/home/views/home_screen.dart';
import 'widgets/network_lock_overlay_widget.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Meeting Book',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      // Bọc lớp kiểm tra mạng toàn cục: Hễ mất mạng là hiện thông báo giữa màn hình và khóa mọi thao tác
      builder: (context, child) {
        return NetworkLockOverlayWidget(
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const AuthGateScreen(),
    );
  }
}

/// Màn hình Splash Screen khởi chạy ứng dụng:
/// - Nền giống hệt màn hình Đăng nhập (AppColors.primaryBlue kèm họa tiết vòng tròn kem nhẹ)
/// - Chính giữa hiển thị chữ "Meeting Book" màu trắng (AppColors.basicWhite) tự co giãn
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final double titleFontSize = AppTheme.getResponsiveFontSize(context, 38);

    return Scaffold(
      backgroundColor: AppColors.primaryBlue,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final double shortestSide = constraints.biggest.shortestSide;

          return Stack(
            children: [
              // Họa tiết vòng tròn trang trí nhẹ nhàng bằng màu kem ở nền sau (đồng bộ với LoginScreen)
              Positioned(
                top: -constraints.maxHeight * 0.12,
                right: -constraints.maxWidth * 0.15,
                child: Container(
                  width: shortestSide * 0.55,
                  height: shortestSide * 0.55,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.creamBackground.withValues(alpha: 0.08),
                  ),
                ),
              ),
              Positioned(
                bottom: -constraints.maxHeight * 0.15,
                left: -constraints.maxWidth * 0.15,
                child: Container(
                  width: shortestSide * 0.65,
                  height: shortestSide * 0.65,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.creamBackground.withValues(alpha: 0.06),
                  ),
                ),
              ),

              // Chữ "Meeting Book" màu trắng nằm chính giữa màn hình
              SafeArea(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'Meeting Book',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.basicWhite,
                          fontSize: titleFontSize,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Cổng hiển thị Splash Screen & kiểm tra phiên đăng nhập tự động khi mở ứng dụng
/// - Hiển thị SplashScreen ("Meeting Book") khi khởi động
/// - Nếu đã đăng nhập trước đó -> Vào thẳng HomeScreen (duy trì đăng nhập)
/// - Nếu chưa đăng nhập hoặc đã bấm Đăng xuất -> Hiển thị LoginScreen
class AuthGateScreen extends StatefulWidget {
  const AuthGateScreen({super.key});

  @override
  State<AuthGateScreen> createState() => _AuthGateScreenState();
}

class _AuthGateScreenState extends State<AuthGateScreen> {
  final AuthService _authService = AuthService();
  late final Future<bool> _sessionFuture = _initializeAppWithSplash();

  Future<bool> _initializeAppWithSplash() async {
    final List<Object?> results = await Future.wait<Object?>(<Future<Object?>>[
      _authService.checkSavedLoginSession(),
      Future<void>.delayed(const Duration(milliseconds: 1400)),
    ]);
    return (results.first as bool?) ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _sessionFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SplashScreen();
        }

        final bool isLoggedIn = snapshot.data ?? false;
        if (isLoggedIn) {
          return const HomeScreen();
        }
        return const LoginScreen();
      },
    );
  }
}
