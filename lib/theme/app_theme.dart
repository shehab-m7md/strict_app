import 'package:flutter/material.dart';
import 'colors.dart';

class AppTheme {

  static final ThemeData lightTheme = ThemeData(
    brightness: Brightness.light,
    scaffoldBackgroundColor: AppColors.backgroundLight,
    primaryColor: AppColors.primary1,
    colorScheme: ColorScheme.light(
      primary: AppColors.primary1,
      secondary: AppColors.inputFillLight,
      surface: AppColors.backgroundLight,
      error: AppColors.textErrorLight,
      onPrimary: Colors.white,
      onSecondary: AppColors.textBoldLight,
      onSurface: AppColors.textBoldLight,
      onError: Colors.white,
    ),
  );


  static final ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.backgroundDark,
    primaryColor: AppColors.primary1Dark,
    colorScheme: ColorScheme.dark(
      primary: AppColors.primary1Dark,
      secondary: AppColors.inputFillDark,
      surface: AppColors.backgroundDark,
      error: AppColors.textErrorDark,
      onPrimary: Colors.white,
      onSecondary: AppColors.textBoldDark,
      onSurface: AppColors.textBoldDark,
      onError: Colors.white,
    ),
  );
}
