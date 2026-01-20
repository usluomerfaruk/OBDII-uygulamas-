import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'dart:convert';
import 'simulasyon.dart';

class BluetoothPage extends StatefulWidget {
  const BluetoothPage({super.key});

  @override
  State<BluetoothPage> createState() => _BluetoothPageState();
}

class _BluetoothPageState extends State<BluetoothPage> {
  List<BluetoothDevice> cihazlar = [];
  bool taraniyor = false;

  @override
  void initState() {
    super.initState();
    taramaBaslat();
  }

  Future<void> taramaBaslat() async {
    setState(() => taraniyor = true);
    List<BluetoothDevice> bonded = await FlutterBluetoothSerial.instance.getBondedDevices();
    setState(() {
      cihazlar = bonded;
      taraniyor = false;
    });
  }
  void cihazaBaglan(BluetoothDevice device) async {
    try {
      BluetoothConnection connection = await BluetoothConnection.toAddress(device.address);
      debugPrint('Bağlantı başarılı: ${device.name}');

      Navigator.push(
      context,
      MaterialPageRoute(
        // 'SimulasyonSayfasi'na bağlantı nesnesini gönderiyoruz.
        builder: (context) => SimulasyonSayfasi(connection: connection), 
      ),
    );
     
     connection.output.add(utf8.encode("ATZ\r")); // Test komutu

// Test komutu
      // Burada istersen bağlantıyı Simülasyon sayfasına geçirebilirsin
    } catch (e) {
      debugPrint("Bağlantı hatası: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("OBD-II Cihaz Seçimi")),
      body: Column(
        children: [
          taraniyor
              ? const CircularProgressIndicator()
              : ElevatedButton(
                  onPressed: taramaBaslat,
                  child: const Text("Yeniden Tara"),
                ),
          Expanded(
            child: ListView.builder(
              itemCount: cihazlar.length,
              itemBuilder: (context, index) {
                var device = cihazlar[index];
                return ListTile(
                  title: Text(device.name ?? "Bilinmeyen"),
                  subtitle: Text(device.address),
                  trailing: const Icon(Icons.bluetooth),
                  onTap: () => cihazaBaglan(device),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
