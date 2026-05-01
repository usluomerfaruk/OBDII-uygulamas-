
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:fl_chart/fl_chart.dart'; // Grafik kütüphanesi
import 'bluetooth.dart';

class SimulasyonSayfasi extends StatefulWidget {
  final BluetoothConnection? connection;
  const SimulasyonSayfasi({super.key, this.connection});

  @override
  State<SimulasyonSayfasi> createState() => _SimulasyonSayfasiState();
}

class _SimulasyonSayfasiState extends State<SimulasyonSayfasi> {
  // --- Değişkenler ---
  BluetoothConnection? connection;
  List<String> hataKodlari = [];
  String rpm = "---";
  String speed = "---";
  String temp = "---";

  // Grafik Veri Listeleri
  List<FlSpot> rpmSpots = [const FlSpot(0, 0)];
  List<FlSpot> speedSpots = [
    const FlSpot(0, 0)
  ]; // verileri biriktirerek çizgi grafik
  double timerCount = 0;

  Timer? pidTimer;
  bool bagli = false;
  String buffer = "";
  bool elmInitialized = false;

  final List<String> elmCommands = [
    "ATZ\r", "ATE0\r", "ATL0\r", "ATS0\r", "ATH0\r",
    "ATSP0\r" //aracın iletişim dili , resetleme komutları felan
  ];
  int commandIndex = 0;
  
@override
void initState() {
  super.initState();
  if (widget.connection != null) {
    connection = widget.connection;
    bagli = true;
    startListener();
    sendNextElmCommand();
  }

  // Simülasyon verisi - cihaz yokken test için
  if (widget.connection == null) {
    Timer.periodic(const Duration(milliseconds: 300), (t) {
      if (!mounted) { t.cancel(); return; }
      timerCount += 0.3;
      setState(() {
        double fakeRpm = 800 + (timerCount * 100) % 3000;
        double fakeSpeed = (timerCount * 10) % 120;
        rpmSpots.add(FlSpot(timerCount, fakeRpm));
        speedSpots.add(FlSpot(timerCount, fakeSpeed));
        if (rpmSpots.length > 30) rpmSpots.removeAt(0);
        if (speedSpots.length > 30) speedSpots.removeAt(0);
      });
    });
  }
}

  void startListener() {
    // verileri yakaladığımız yer
    connection!.input!.listen((Uint8List data) {
      String gelenParca = utf8.decode(data, allowMalformed: true);
      buffer += gelenParca;

      if (buffer.contains(">")) {
        // paket bitti şimidi işleyebiliriz ksımı
        String cleanData = buffer
            .replaceAll(RegExp(r'[\r\n> ]'), '')
            .trim(); // satır başı boşlukları temizleriz
        if (!elmInitialized) {
          sendNextElmCommand();
        } else {
          // Hata Kodu Kontrolü
          if (cleanData.contains("43") ||
              cleanData.contains("47") ||
              cleanData.contains("4A")) {
            _parseDTC(cleanData);
          }
          // Canlı Veri Kontrolü
          else if (cleanData.contains("41")) {
            _parseData(cleanData);
          } // gelen verinin mod tanımlayıcısına bakıyoruz
        }
        buffer = "";
      }
    }).onDone(() {
      setState(() => bagli = false);
      pidTimer?.cancel();
    });
  }

  void _send(String cmd) {
    //gönderilecek metinleri bluetoothun anlayacağı dile çevirir
    if (connection == null || !bagli) return;
    try {
      connection!.output.add(utf8.encode(cmd));
    } catch (e) {
      debugPrint("Gönderim hatası: $e");
    }
  }

  void sendNextElmCommand() {
    // akıllı kommut kuyruğu
    if (commandIndex < elmCommands.length) {
      //komutları her seferinde tek tek gönderir
      _send(elmCommands[commandIndex]);
      commandIndex++;
    } else if (!elmInitialized) {
      elmInitialized = true; // cihaz hazır mı değil mi ona da bakılır
      startPidLoop();
    }
  }

void startPidLoop() {
  pidTimer = Timer.periodic(const Duration(milliseconds: 200), (Timer t) {
    if (!bagli) {
      t.cancel();
      return;
    }
    timerCount += 0.2; // Buraya taşındı, her tick'te artar
    switch (t.tick % 3) {
      case 0: _send("010C\r"); break;
      case 1: _send("010D\r"); break;
      case 2: _send("0105\r"); break;
    }
  });
}

  void _parseData(String raw) {
    //araçtan gelen karmaşık kodları sürücünün anlayabileceği şekile döndürür
    raw = raw.replaceAll(RegExp(r'[\r\n> ]'), '').trim();
    if (!raw.startsWith("41")) return;
    String pidData = raw.substring(raw.indexOf("41") + 2).trim();
    if (pidData.length < 4) return;

    String pid = pidData.substring(0, 2);
    String dataBytes = pidData.substring(2);

    try {
      timerCount += 0.2; // Zaman eksenini ilerlet

      if (pid == "0C" && dataBytes.length >= 4) {
        //devir
        int a = int.parse(dataBytes.substring(0, 2), radix: 16);
        int b = int.parse(dataBytes.substring(2, 4), radix: 16);
        double val = ((a * 256) + b) / 4;
        setState(() {
          rpm = val.round().toString();
          rpmSpots.add(FlSpot(timerCount, val));
          if (rpmSpots.length > 30) rpmSpots.removeAt(0);
        });
      } else if (pid == "0D" && dataBytes.length >= 2) {
        //hız
        double val = int.parse(dataBytes.substring(0, 2), radix: 16).toDouble();
        setState(() {
          speed = val.toInt().toString();
          speedSpots.add(FlSpot(timerCount, val));
          if (speedSpots.length > 30) speedSpots.removeAt(0);
        });
      } else if (pid == "05" && dataBytes.length >= 2) {
        //sıcaklık
        int val = int.parse(dataBytes.substring(0, 2), radix: 16) - 40;
        setState(() => temp = val.toString());
      }
    } catch (e) {
      debugPrint("Parse Hatası: $e");
    } //try catch hatalı komut gönderilirse terminale yazıyor
  }

  // --- Hata Kodları İşlemleri ---
  void dtcGetir() async {
    pidTimer?.cancel();
    pidTimer = null;
    await Future.delayed(const Duration(milliseconds: 600));
    _send("ATAR\r");
    await Future.delayed(const Duration(milliseconds: 300));
    _send("ATSH 7E0\r"); //7E0 motor beynine bağlantı sağlanır
    await Future.delayed(const Duration(milliseconds: 600));
    _send("03\r"); //mode3 hafızada kayıtlı hata kodlarını bana gönder diyo
    await Future.delayed(const Duration(seconds: 2));
    startPidLoop();
  }

  void hataKodlariniSil() async {
    pidTimer?.cancel(); //motor arıza lambasını söndürmeye yarar
    pidTimer = null;
    await Future.delayed(const Duration(milliseconds: 500));
    _send("04\r");
    setState(() => hataKodlari = ["Komut Gönderildi..."]);
    await Future.delayed(const Duration(seconds: 2));
    _send("ATAR\r"); //adaptörü varsayılan konumuna geri getirir
    setState(() => hataKodlari = ["Sistem Sıfırlandı"]);
    startPidLoop(); // canlı göstergelere geri dönüyoruz
  }

  void _parseDTC(String raw) {
    raw = raw
        .replaceAll(RegExp(r'[\r\n> ]'), '')
        .trim(); //OBD cihazından veri gelirken aralara boşluklar, satır başları veya > gibi işaretler eklenir. Bu satır, tüm bu "gürültüyü" siler. Elinde sadece 4301010000 gibi saf bir sayı dizisi kalır. beni en çok uğraştıran kısım
    int startPos = raw.indexOf(
        "43"); //hata kodunun başının 43 ile başlamak zorunda diğer gelen verileri istemiyoruz
    if (startPos == -1) return;

    // Sayı olmayan her şeyi (SEARCHING vb.) temizle
    String targetData =
        raw.substring(startPos).replaceAll(RegExp(r'[^0-9A-Fa-f]'), '');

    if (targetData.length < 6 || targetData.substring(2, 4) == "00") {
      setState(() => hataKodlari = ["Sistem Temiz (Hata Yok)"]);
      return; //min 43 + 4 karakterden oluşmalı daha aşağısı ise hatalıdır
    }

    String dtcData = targetData.substring(2);
    List<String> bulunanlar = [];
    for (int i = 0; i < dtcData.length; i += 4) {
      if (i + 4 <= dtcData.length) {
        String hex = dtcData.substring(i,
            i + 4); //hata  kodları genelde 4erli bulunduğu için burda parçalıyoruz
        if (hex != "0000" && hex.length == 4) {
          String sonuc = _hexToDTC(hex);
          if (sonuc != "GECERSIZ") bulunanlar.add(sonuc);
        }
      }
    }
    setState(() => hataKodlari = bulunanlar);
  }

  String _hexToDTC(String hexCode) {
    try {
      if (!RegExp(r'^[0-9A-Fa-f]+$').hasMatch(hexCode)) return "GECERSIZ";
      int firstDigit = int.parse(hexCode[0], radix: 16);
      String prefix = ["P", "C", "B", "U"][firstDigit ~/ 4];
      return prefix + (firstDigit % 4).toString() + hexCode.substring(1);
      //0 - 3 arası ise: P (Powertrain - Motor ve Şanzıman)
      //4 - 7 arası ise: C (Chassis - Şasi, ABS, ESP)
      //8 - B arası ise: B (Body - Gövde, Klima, Hava Yastığı)
      //C - F arası ise: U (Network - İletişim, CAN-BUS hatları)// bunlardan sadece  motor ve şanzuman bilgisini alabiliyoruz cihazdan kaynaklı bu şekilde
    } catch (e) {
      return "GECERSIZ";
    }
  }

  // --- Arayüz Tasarımı ---

  // Değişkenlerin altına bunu eklediğinden emin ol:
  int _seciliSayfa = 0; 

  @override
  Widget build(BuildContext context) {
    // Sayfalar listesi
    final List<Widget> sayfalar = [
      _anaSayfaContent(),   // İndeks 0
      _grafikSayfasi(),     // İndeks 1
      _arizaSayfasiIcerik(),// İndeks 2 sayfaları böldüm 
    ];

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: Text(_seciliSayfa == 0 ? "OBD-II MONİTÖR" : (_seciliSayfa == 1 ? "ANALİZ" : "ARIZA KODLARI")),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: IndexedStack(//şuan _seçilisayfada yazan numaralı sayfayı göster geri kalanını bellekte tut 
        index: _seciliSayfa,
        children: sayfalar,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _seciliSayfa,//hangi iconun yandığını belirler
        onTap: (index) => setState(() => _seciliSayfa = index),//güncelleme yapıyor
        backgroundColor: const Color(0xFF1E293B),
        selectedItemColor: Colors.cyan,
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: "Panel"),
          BottomNavigationBarItem(icon: Icon(Icons.show_chart), label: "Grafikler"),
          BottomNavigationBarItem(icon: Icon(Icons.error_outline), label: "Arıza"),
        ],
      ),
    );
  }

  // --- SAYFA GÖVDELERİ (Fonksiyon isimlerine dikkat) ---

  Widget _anaSayfaContent() {
    return SingleChildScrollView(//telefon ekranından büyükse aşağı doğru kaydırma imkanı sağlıyor
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          _durumCubugu(),
          GridView.count(
            shrinkWrap: true,//sadece içindeki elemanlar kadar yer kapla
            physics: const NeverScrollableScrollPhysics(),//kendi kaydırmasını kapattık zaten var dışta
            crossAxisCount: 2,//ekranı ikiye böldük ve yanyana yazıyoruz
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            children: [
              _gostergeKarti("DEVİR", rpm, "RPM", Colors.cyan),
              _gostergeKarti("HIZ", speed, "KM/H", Colors.greenAccent),
              _gostergeKarti("HARARET", temp, "°C", Colors.orangeAccent),
              _gostergeKarti("DURUM", bagli ? "AKTİF" : "PASİF", "", Colors.purpleAccent),
            ],
          ),
          const SizedBox(height: 20),
          _altButonlar(), // Bağlan butonu burada durabilir
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _grafikSayfasi() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _grafikBolumu("DETAYLI DEVİR ANALİZİ", rpmSpots, Colors.cyan, 8000),
          const SizedBox(height: 24),
          _grafikBolumu("DETAYLI HIZ ANALİZİ", speedSpots, Colors.greenAccent, 220),
          const SizedBox(height: 100),
        ],
      ),
    );
  }
  // speedSports aracın hız geçmişini çizer rpmSports da rpm çizelgesini 

  Widget _arizaSayfasiIcerik() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _ozelButon(label: "TARA", icon: Icons.search, color: Colors.blueAccent, onPressed: dtcGetir)),
              const SizedBox(width: 12),
              Expanded(child: _ozelButon(label: "SİL", icon: Icons.delete, color: Colors.redAccent, onPressed: hataKodlariniSil)),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: hataKodlari.isEmpty
                ? const Center(child: Text("Hata yok.", style: TextStyle(color: Colors.white38)))
                : ListView.builder(
                    itemCount: hataKodlari.length,
                    itemBuilder: (context, index) => ListTile(
                      leading: const Icon(Icons.warning, color: Colors.orange),
                      title: Text(hataKodlari[index], style: const TextStyle(color: Colors.white)),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _durumCubugu() {//sistem bağlı veya bağlantı yok kısmı
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      decoration: BoxDecoration(
        color:
            bagli ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
              radius: 4, backgroundColor: bagli ? Colors.green : Colors.red),
          const SizedBox(width: 8),
          Text(bagli ? "SİSTEM BAĞLI" : "BAĞLANTI YOK",
              style: TextStyle(
                  color: bagli ? Colors.green : Colors.red,
                  fontSize: 11,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _gostergeKarti(String label, String value, String unit, Color color) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.bold, fontSize: 10)),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold)),
          if (unit.isNotEmpty)
            Text(unit,
                style: const TextStyle(color: Colors.white38, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _grafikBolumu(
    String title, List<FlSpot> spots, Color color, double maxY) {
  
  // En az 2 nokta yoksa grafik çizme
  if (spots.length < 2) {
    return Container(
      height: 180,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Center(
        child: Text("Veri bekleniyor...",
            style: TextStyle(color: color.withOpacity(0.5))),
      ),
    );
  }

  double minX = spots.first.x;
  double maxX = spots.last.x;
  if (maxX <= minX) maxX = minX + 1; // sıfır aralık koruması

  return Container(
    height: 180,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.03),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Expanded(
          child: LineChart(
            LineChartData(
              minX: minX,
              maxX: maxX,
              minY: 0,
              maxY: maxY,
              gridData: const FlGridData(show: false),
              titlesData: const FlTitlesData(show: false),
              borderData: FlBorderData(show: false),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  color: color,
                  barWidth: 2,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                      show: true, color: color.withOpacity(0.1)),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

  Widget _altButonlar() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ozelButon(
              label: "BAĞLAN",
              icon: Icons.bluetooth,
              color: Colors.blueAccent,
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const BluetoothPage())),
            ),
          ),
          // Arıza butonu ve SizedBox buradan kaldırıldı.
        ],
      ),
    );
  }
  Widget _ozelButon(
      {required String label,
      required IconData icon,
      required Color color,
      required VoidCallback onPressed}) {
    return SizedBox(
      height: 50,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label, style: const TextStyle(fontSize: 13)),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
      ),
    );
  }

  @override
  void dispose() {
    pidTimer?.cancel();
    connection?.close();
    super.dispose();
  }
}

// --- ARIZA SAYFASI  ---
class HataSayfasi extends StatelessWidget {
  final List<String> hataListesi;
  final VoidCallback onScan;
  final VoidCallback onClear;
  const HataSayfasi(
      {super.key,
      required this.hataListesi,
      required this.onScan,
      required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
          title: const Text("Arıza Teşhis"),
          backgroundColor: Colors.transparent),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                    child: ElevatedButton.icon(
                        onPressed: onScan,
                        icon: const Icon(Icons.search),
                        label: const Text("TARA"))),
                const SizedBox(width: 12),
                Expanded(
                    child: ElevatedButton.icon(
                        onPressed: onClear,
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.redAccent),
                        icon: const Icon(Icons.delete),
                        label: const Text("SİL"))),
              ],
            ),
            const SizedBox(height: 20),
            Expanded(
              child: hataListesi.isEmpty
                  ? const Center(
                      child: Text("Hata yok.",
                          style: TextStyle(color: Colors.white38)))
                  : ListView.builder(
                      itemCount: hataListesi.length,
                      itemBuilder: (context, index) => ListTile(
                        leading:
                            const Icon(Icons.warning, color: Colors.orange),
                        title: Text(hataListesi[index],
                            style: const TextStyle(color: Colors.white)),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
