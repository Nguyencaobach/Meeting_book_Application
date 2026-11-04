import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

/// Giao diện màn hình Ghi chú (Tự co giãn theo kích thước màn hình)
class NotesScreen extends StatelessWidget {
  const NotesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: AppColors.basicWhite, // Nền trắng cơ bản theo theme
    );
  }
}
