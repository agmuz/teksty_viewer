import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/file_list_screen.dart';
import 'utils/colors.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Wymuś klasyczny układ z paskiem statusu i nawigacji NAD treścią
  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.manual,
    overlays: SystemUiOverlay.values,
  );
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Color(0xFF132845),
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Colors.black,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Teksty',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.tileDefault,
        ),
      ),
      home: const FileListScreen(),
    );
  }
}
