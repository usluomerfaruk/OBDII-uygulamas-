import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'simulasyon.dart';
import 'bluetooth.dart';

void main() async {
  // Flutter binding'in hazır olduğundan emin oluyoruz
  WidgetsFlutterBinding.ensureInitialized();
  
  // Uygulama başlamadan önce gerekli izinleri istiyoruz
  await _izinleriIste();

  runApp(const MyApp());
}

/// Bluetooth ve Konum izinlerini toplu olarak isteyen fonksiyon
Future<void> _izinleriIste() async {
  await [
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
    Permission.location, // Android'de BT taraması için zorunludur
  ].request();
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OBD-II Veri Monitörü',
      debugShowCheckedModeBanner: false,
      
      // Tema ayarlarını Dashboard'a uygun hale getiriyoruz
      theme: ThemeData(
        brightness: Brightness.dark, 
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: const Color(0xFF0F172A), // Dashboard ile aynı zemin
      ),

      // Uygulama artık direkt Gösterge Paneli ile açılıyor
      home: const SimulasyonSayfasi(),

      // Sayfa yönlendirmelerini (Routes) burada tanımlıyoruz
      routes: {
        '/dashboard': (context) => const SimulasyonSayfasi(),
        '/bluetoothListesi': (context) => const BluetoothPage(),
      },
    );
  }
}