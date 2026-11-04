import 'package:flutter/material.dart';
import 'core/constants/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/service/auth_service.dart';
import 'features/auth/views/login_screen.dart';
import 'features/home/views/home_screen.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Meeting Book Application',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const AuthGateScreen(),
    );
  }
}

/// Cổng kiểm tra phiên đăng nhập tự động khi mở ứng dụng
/// - Nếu đã đăng nhập trước đó -> Vào thẳng HomeScreen (duy trì đăng nhập)
/// - Nếu chưa đăng nhập hoặc đã bấm Đăng xuất -> Hiển thị LoginScreen
class AuthGateScreen extends StatefulWidget {
  const AuthGateScreen({super.key});

  @override
  State<AuthGateScreen> createState() => _AuthGateScreenState();
}

class _AuthGateScreenState extends State<AuthGateScreen> {
  final AuthService _authService = AuthService();
  late final Future<bool> _sessionFuture = _authService.checkSavedLoginSession();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _sessionFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: AppColors.primaryBlue,
            body: Center(
              child: CircularProgressIndicator(
                color: AppColors.creamBackground,
              ),
            ),
          );
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
