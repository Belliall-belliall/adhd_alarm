import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
// Importuj swoje istniejące ekrany oraz plik firebase_options.dart (jeśli używasz)
// import 'firebase_options.dart';

void main() async {
  // 1. Wymagane przed inicjalizacją jakichkolwiek wtyczek natywnych (Firebase, Alarmy itp.)
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Bezpieczna inicjalizacja Firebase z obsługą błędów
  try {
    await Firebase.initializeApp(
      // options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('Błąd podczas inicjalizacji Firebase: $e');
  }

  // 3. Globalne wyłapywanie błędów UI (zapobiega "czerwonemu ekranowi błędu" u użytkownika)
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('Błąd Flutter UI: ${details.exception}');
  };

  runApp(const AdhdHelperApp());
}

class AdhdHelperApp extends StatelessWidget {
  const AdhdHelperApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ADHD Helper',
      debugShowCheckedModeBanner: false,
      
      // Spójny motyw zapobiegający przebodźcowaniu (Low-arousal Design)
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4C6EF5),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF8F9FA),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4C6EF5),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF121212),
      ),
      themeMode: ThemeMode.system, // Automatyczne dostosowanie do systemu

      // Tutaj wskaż swój główny ekran startowy
      home: const MainHomeScreen(), 
    );
  }
}

// Zastąp poniższy zaślepkę swoim właściwym ekranem głównym z istniejącego projektu
class MainHomeScreen extends StatelessWidget {
  const MainHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text('ADHD Helper - Ekran Główny'),
      ),
    );
  }
}