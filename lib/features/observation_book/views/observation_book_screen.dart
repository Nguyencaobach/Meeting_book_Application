import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

/// Giao diện màn hình Sổ dự giờ (Tự co giãn theo kích thước màn hình)
class ObservationBookScreen extends StatelessWidget {
  const ObservationBookScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: AppColors.basicWhite, // Nền trắng cơ bản theo theme
    );
  }
}
