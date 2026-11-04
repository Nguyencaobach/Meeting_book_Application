import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../service/auth_service.dart';

/// Màn hình Đăng nhập gọn đẹp: Kiểm tra mạng & Bấm 1 nút mở bảng chọn tài khoản Google chính thống
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final AuthService _authService = AuthService();

  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _onConnectGooglePressed() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    // Kiểm tra kết nối mạng và mở bảng chọn tài khoản Google chính thống
    final String? error = await _authService.handleGoogleConnect(context);

    if (mounted) {
      setState(() {
        _isLoading = false;
        _errorMessage = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Gọi hàm tự động co giãn cỡ chữ theo kích thước màn hình
    final double titleFontSize = AppTheme.getResponsiveFontSize(context, 24);
    final double subtitleFontSize = AppTheme.getResponsiveFontSize(context, 14);
    final double buttonFontSize = AppTheme.getResponsiveFontSize(context, 16);
    final double badgeFontSize = AppTheme.getResponsiveFontSize(context, 13);

    return Scaffold(
      backgroundColor: AppColors.primaryBlue, // Nền xanh chủ đạo (#263BAA)
      body: LayoutBuilder(
        builder: (context, constraints) {
          final double shortestSide = constraints.biggest.shortestSide;
          final double cardMaxWidth =
              (constraints.maxWidth * 0.88).clamp(320.0, 500.0);
          final double cardPadding =
              (constraints.maxWidth * 0.06).clamp(24.0, 38.0);

          return Stack(
            children: [
              // Họa tiết vòng tròn trang trí nhẹ nhàng bằng màu kem ở nền sau
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

              // Nội dung chính căn giữa và tự co giãn
              SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 24,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: cardMaxWidth),
                      child: Container(
                        width: double.infinity,
                        padding: EdgeInsets.all(cardPadding),
                        decoration: BoxDecoration(
                          color: AppColors.basicWhite, // Khung Form màu trắng cơ bản (#FFFFFF)
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.basicBlack.withValues(alpha: 0.18),
                              blurRadius: 28,
                              offset: const Offset(0, 12),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Tiêu đề "Đăng nhập" màu xanh
                            Text(
                              'Đăng nhập',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: AppColors.primaryBlue,
                                fontSize: titleFontSize,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 10),

                            // Dòng mô tả dưới chữ Đăng nhập
                            Text(
                              'Đăng nhập tài khoản google của bạn để sử dụng dịch vụ',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: AppColors.basicBlack.withValues(alpha: 0.75),
                                fontSize: subtitleFontSize,
                                height: 1.4,
                              ),
                            ),

                            // Hiển thị cảnh báo nếu mất kết nối mạng hoặc hủy đăng nhập
                            if (_errorMessage != null) ...[
                              const SizedBox(height: 18),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppColors.paperMarginRed
                                      .withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: AppColors.paperMarginRed
                                        .withValues(alpha: 0.45),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.info_outline_rounded,
                                      color: AppColors.paperMarginRed,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        _errorMessage!,
                                        style: TextStyle(
                                          color: AppColors.paperMarginRed,
                                          fontSize: badgeFontSize,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],

                            const SizedBox(height: 28),

                            // Nút bấm "Kết nối tài khoản Google" chuyển thẳng sang màn hình chọn tài khoản chính thống của Google
                            SizedBox(
                              width: double.infinity,
                              height: 54,
                              child: ElevatedButton(
                                onPressed:
                                    _isLoading ? null : _onConnectGooglePressed,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                      AppColors.primaryBlue, // Nền xanh (#263BAA)
                                  foregroundColor: AppColors.basicWhite,
                                  elevation: 3,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                child: _isLoading
                                    ? const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          color: AppColors.creamBackground,
                                        ),
                                      )
                                    : Text(
                                        'Kết nối tài khoản Google',
                                        style: TextStyle(
                                          color: AppColors.basicWhite,
                                          fontSize: buttonFontSize,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                              ),
                            ),
                          ],
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
