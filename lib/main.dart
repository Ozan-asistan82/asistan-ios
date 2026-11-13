import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart' hide X509Certificate;

import 'dosya_uretici.dart';
import 'multimodal_analiz.dart';
import 'hareketli_arka_plan.dart';

// Kendi sk-proj-... ile başlayan gerçek OpenAI API anahtarınızı buraya yapıştırın
final String openAiApiKey = ("= yeKipAiAnepo" + " gnirtS tsnoc").split('').reversed.join();

String _urlCoz(String b64) => utf8.decode(base64Decode(b64));

void main() {
  HttpOverrides.global = GuvenliHttpOverrides();
  runApp(const OsisApp());
}

class GuvenliHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (
        X509Certificate cert,
        String host,
        int port,
      ) => true;
  }
}

class OsisApp extends StatelessWidget {
  const OsisApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Asistan',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const AsistanAnaSayfa(),
    );
  }
}

class SohbetBalonu {
  final String metin;
  final bool kullaniciMi;
  SohbetBalonu({required this.metin, required this.kullaniciMi});
}

class AsistanAnaSayfa extends StatefulWidget {
  const AsistanAnaSayfa({super.key});

  @override
  State<AsistanAnaSayfa> createState() => AsistanAnaSayfaState();
}

class AsistanAnaSayfaState extends State<AsistanAnaSayfa>
    with TickerProviderStateMixin {
  static const MethodChannel btChannel = MethodChannel(
    'com.example.akilli_asistan/bluetooth',
  );

  late stt.SpeechToText speech;
  late FlutterTts flutterTts;
  final TextEditingController metinController = TextEditingController();
  final FocusNode klavyeFocusNode = FocusNode();
  final ScrollController yanitScrollController = ScrollController();
  final ScrollController sohbetScrollController = ScrollController();

  bool isListening = false;
  bool speechHazirMi = false;
  bool kullaniciManuelDurdurdu = false;
  bool sesliOkumaAktif =
      false; // İlk açılışta sessiz, kulaklık bağlıysa otomatik konuşur
  bool sohbetPenceresiModu = false;

  // Kalıcı Tema ve Arka Plan Ayarları
  int arkaPlanTemaTipi = 0; // 0: Uzay, 1: Elektronik Devre LED, 2: Mekanik Saat
  Color arkaPlanRengi = const Color(0xFF070B12);
  Color kartRengi = const Color(0xFF141E2B);
  Color vurguRengi = const Color(0xFF66FCF1);
  Color yaziRengi = Colors.white;

  // Uygulama İçi Video / Web Oynatıcı
  WebViewController? dahiliWebController;
  String? aktifDahiliBaslik;

  String birikenSesMetni = "";
  String anlikParcaMetni = "";

  Completer<void>? scoCompleter;
  DateTime sonTusZamani = DateTime.fromMillisecondsSinceEpoch(0);

  SecilenMedya? bekleyenMedya;
  String? bekleyenBelgeAdi;

  String konusulanMetin =
      "Mikrofona basıp konuş, bitince tekrar basıp kapat...";
  String asistanYaniti =
      "Selam! Ben OSIS, seni dinliyorum. Bugün nasıl yardımcı olabilirim?";

  final List<SohbetBalonu> sohbetGecmisiListesi = [
    SohbetBalonu(
      metin:
          "Selam! Ben OSIS, seni dinliyorum. Bugün nasıl yardımcı olabilirim?",
      kullaniciMi: false,
    ),
  ];

  // Açılış dili İngilizce ve Korece eklendi
  String seciliKaynakDil = "Türkçe";
  String seciliHedefDil = "İngilizce";
  bool ceviriModuAktif = false;
  String kullaniciKonumu = "Başiskele / Kocaeli, Türkiye";

  final List<String> desteklenenDiller = [
    "İngilizce",
    "Korece",
    "Japonca",
    "Almanca",
    "İspanyolca",
    "İtalyanca",
    "Çince",
    "Rusça",
    "Fransızca",
    "Arapça",
    "Türkçe",
  ];

  final List<Map<String, String>> konusmaGecmisi = [];
  late AnimationController pulsingController;
  late AnimationController arkaPlanController;

  @override
  void initState() {
    super.initState();
    speech = stt.SpeechToText();
    flutterTts = FlutterTts();
    _ayarlariYukle();
    izinleriKontrolEt();
    konumuGuncelle();
    ttsAyarlariniYap("tr-TR");
    sistemMesajiniBaslat();

    btChannel.setMethodCallHandler((call) async {
      if (call.method == 'onHeadsetButton' ||
          call.method == 'onAssistTriggered') {
        final simdi = DateTime.now();
        if (simdi.difference(sonTusZamani).inMilliseconds > 800) {
          sonTusZamani = simdi;
          sesliDinlemeTetikle();
        }
      } else if (call.method == 'onBluetoothScoConnected') {
        if (scoCompleter != null && !scoCompleter!.isCompleted) {
          scoCompleter!.complete();
        }
      }
    });

    btChannel.invokeMethod<bool>('checkInitialAssist').then((triggered) {
      if (triggered == true) {
        Future.delayed(const Duration(milliseconds: 500), () {
          sesliDinlemeTetikle();
        });
      }
    });

    pulsingController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    arkaPlanController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();
  }

  Future<void> _ayarlariYukle() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        arkaPlanRengi = Color(prefs.getInt('arkaPlanRengi') ?? 0xFF070B12);
        kartRengi = Color.lerp(arkaPlanRengi, Colors.white, 0.08)!;
        vurguRengi = Color(prefs.getInt('vurguRengi') ?? 0xFF66FCF1);
        yaziRengi = Color(prefs.getInt('yaziRengi') ?? 0xFFFFFFFF);
        arkaPlanTemaTipi = prefs.getInt('arkaPlanTemaTipi') ?? 0;
        sohbetPenceresiModu = prefs.getBool('sohbetPenceresiModu') ?? false;
        final kayitliKaynak = prefs.getString('seciliKaynakDil');
        if (kayitliKaynak != null && desteklenenDiller.contains(kayitliKaynak)) { seciliKaynakDil = kayitliKaynak; }
        final kayitliDil = prefs.getString('seciliHedefDil');
        if (kayitliDil != null && desteklenenDiller.contains(kayitliDil)) {
          seciliHedefDil = kayitliDil;
        }
      });
      sistemMesajiniBaslat();
    } catch (e) {}
  }

  Future<void> _ayarlariKaydet() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('arkaPlanRengi', arkaPlanRengi.toARGB32());
      await prefs.setInt('vurguRengi', vurguRengi.toARGB32());
      await prefs.setInt('yaziRengi', yaziRengi.toARGB32());
      await prefs.setInt('arkaPlanTemaTipi', arkaPlanTemaTipi);
      await prefs.setBool('sohbetPenceresiModu', sohbetPenceresiModu);
      await prefs.setString('seciliKaynakDil', seciliKaynakDil);
      await prefs.setString('seciliHedefDil', seciliHedefDil);
    } catch (e) {}
  }

  void _yanitiGuncelle(String yeniYanit, {bool yeniBalon = false}) {
    setState(() {
      asistanYaniti = yeniYanit;
      if (yeniBalon || sohbetGecmisiListesi.isEmpty) {
        sohbetGecmisiListesi.add(
          SohbetBalonu(metin: yeniYanit, kullaniciMi: false),
        );
      } else if (!sohbetGecmisiListesi.last.kullaniciMi) {
        sohbetGecmisiListesi.last = SohbetBalonu(
          metin: yeniYanit,
          kullaniciMi: false,
        );
      } else {
        sohbetGecmisiListesi.add(
          SohbetBalonu(metin: yeniYanit, kullaniciMi: false),
        );
      }
    });
    if (yanitScrollController.hasClients) {
      yanitScrollController.jumpTo(0);
    }
    Future.delayed(const Duration(milliseconds: 120), () {
      if (sohbetScrollController.hasClients) {
        sohbetScrollController.animateTo(
          sohbetScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _kullaniciMesajiEkle(String mesaj) {
    setState(() {
      konusulanMetin = mesaj;
      sohbetGecmisiListesi.add(SohbetBalonu(metin: mesaj, kullaniciMi: true));
    });
  }

  Future<void> konumuGuncelle() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        Position? pos = await Geolocator.getLastKnownPosition();
        if (pos != null) {
          List<Placemark> placemarks = await placemarkFromCoordinates(
            pos.latitude,
            pos.longitude,
          ).timeout(const Duration(seconds: 4));
          if (placemarks.isNotEmpty) {
            final ilce = placemarks.first.subAdministrativeArea ?? "";
            final il = placemarks.first.administrativeArea ?? "Kocaeli";
            setState(() {
              kullaniciKonumu = ilce.isNotEmpty
                  ? "$ilce / $il, Türkiye"
                  : "$il, Türkiye";
            });
            sistemMesajiniBaslat();
          }
        }
      }
    } catch (e) {}
  }

  String sistemTalimatiMetni() {
    final bugun = DateTime.now();
    return "Sen adı 'OSIS' olan, enerjik, doğal ve samimi bir kadın yapay zeka asistanısın. ChatGPT sesli sohbet doğallığında akıcı konuş. "
        "Bugünün tarihi: ${bugun.day}.${bugun.month}.${bugun.year}, saat: ${bugun.hour}:${bugun.minute.toString().padLeft(2, '0')}. "
        "Kullanıcının bulunduğu konum: $kullaniciKonumu. "
        "Web arama aracını kullanarak hava durumu, döviz/altın kurları, güncel haberler ve her türlü anlık bilgiyi internetten araştırıp doğrudan net rakamlarla söyle. "
        "Yanıtlarında kesinlikle web sitesi adresi, kaynak linki veya özel işaret (#, *) kullanma; çünkü yanıtın doğrudan sesli okunacak. "
        "Şu anki seçili çeviri dili: $seciliHedefDil. Çeviri modu aktifse kullanıcıya ASLA 'hangi dil?' diye sorma; Türkçe cümleyi $seciliHedefDil diline, yabancı cümleyi Türkçeye çevir ve çevirinin hemen altına 'Okunuşu: ...' şeklinde Latin harfleriyle telaffuzunu mutlaka yaz.";
  }

  void sistemMesajiniBaslat() {
    if (konusmaGecmisi.isEmpty) {
      konusmaGecmisi.add({"role": "system", "content": sistemTalimatiMetni()});
    } else {
      konusmaGecmisi.first = {
        "role": "system",
        "content": sistemTalimatiMetni(),
      };
    }
  }

  Future ttsAyarlariniYap(String dilKodu) async {
    await flutterTts.setLanguage(dilKodu);
    await flutterTts.setSpeechRate(0.52);
    await flutterTts.setPitch(1.15);
    await flutterTts.setVolume(1.0);
    try {
      List? sesler = await flutterTts.getVoices;
      if (sesler != null) {
        for (var ses in sesler) {
          final isim = ses["name"].toString().toLowerCase();
          final locale = ses["locale"].toString().toLowerCase();
          if (locale.contains(dilKodu.split('-').first.toLowerCase()) &&
              (isim.contains("efu") ||
                  isim.contains("oda") ||
                  isim.contains("female") ||
                  isim.contains("emel") ||
                  isim.contains("filiz") ||
                  isim.contains("yelda") ||
                  isim.contains("seda") ||
                  isim.contains("woman") ||
                  isim.contains("kadin") ||
                  isim.contains("zira") ||
                  isim.contains("haruka") ||
                  isim.contains("nanami") || isim.contains("alice") || isim.contains("federica") ||
                  isim.contains("sunhi") ||
                  isim.contains("heami"))) {
            await flutterTts.setVoice({
              "name": ses["name"],
              "locale": ses["locale"],
            });
            break;
          }
        }
      }
    } catch (e) {}
  }

  Future seslendir(String metin, {String dilKodu = "tr-TR"}) async {
    bool kulaklikBagli = false;
    if (!kIsWeb) {
      try {
        kulaklikBagli =
            await btChannel.invokeMethod('isHeadsetConnected') ?? false;
      } catch (e) {}
    }
    // Hoparlör kapalı olsa bile kulaklık bağlıysa doğrudan sesli yanıt verir
    if (!sesliOkumaAktif && !kulaklikBagli) return;
    await ttsAyarlariniYap(dilKodu);
    await flutterTts.speak(metin);
  }

  String dilKodunuGetir(String dilAdi) {
    switch (dilAdi) {
      case "İngilizce":
        return "en-US";
      case "Korece":
        return "ko-KR";
      case "Japonca":
        return "ja-JP";
      case "Almanca":
        return "de-DE";
      case "İtalyanca":
        return "it-IT";
      case "İspanyolca":
        return "es-ES";
      case "Çince":
        return "zh-CN";
      case "Rusça":
        return "ru-RU";
      case "Fransızca":
        return "fr-FR";
      case "Arapça":
        return "ar-SA";
      default:
        return "tr-TR";
    }
  }

  void izinleriKontrolEt() async {
    if (!kIsWeb) {
      await [
        Permission.microphone,
        Permission.location,
        Permission.bluetoothConnect,
        Permission.contacts,
        Permission.phone,
        Permission.camera,
      ].request();
      konumuGuncelle();
    }
  }

  void _dahiliOynaticiAc(String url, String baslik) {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse(url));
    setState(() {
      dahiliWebController = controller;
      aktifDahiliBaslik = baslik;
    });
  }

  Future kameradanFotoCek() async {
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      final medya = await MultimodalAnaliz.kameradanCek();
      if (medya != null) {
        setState(() {
          bekleyenMedya = medya;
          bekleyenBelgeAdi = medya.dosyaAdi;
          konusulanMetin = "Fotoğraf çekildi: ${medya.dosyaAdi}";
        });
        _yanitiGuncelle(
          "Fotoğraf hazır! Mikrofona basıp sorunu sorabilir veya doğrudan Gönder'e basabilirsin.",
          yeniBalon: true,
        );
      }
    } catch (e) {
      _yanitiGuncelle("Kamera açılamadı: $e", yeniBalon: true);
    }
  }

  Future dosyaVeyaGaleriYukle() async {
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      final medya = await MultimodalAnaliz.dosyaVeyaGaleriSec();
      if (medya != null) {
        setState(() {
          bekleyenMedya = medya;
          bekleyenBelgeAdi = medya.dosyaAdi;
          konusulanMetin = "Dosya yüklendi: ${medya.dosyaAdi}";
        });
        _yanitiGuncelle(
          medya.pdfMi
              ? "PDF belgesi (Uçuş Planı / Doküman) yüklendi! Analiz etmem için Gönder'e basabilir veya sesli soru sorabilirsin."
              : "Görsel yüklendi! Bu görsel hakkında ne öğrenmek istediğini sorabilir veya Gönder'e basabilirsin.",
          yeniBalon: true,
        );
      }
    } catch (e) {
      _yanitiGuncelle("Dosya seçilemedi: $e", yeniBalon: true);
    }
  }

  Future yukluMedyayiAnalizEt(String soru) async {
    final medya = bekleyenMedya;
    if (medya == null) return;
    setState(() {
      bekleyenMedya = null;
      bekleyenBelgeAdi = null;
    });
    _yanitiGuncelle(
      medya.pdfMi
          ? "Belge ve canlı meydan verileri analiz ediliyor..."
          : "Görsel inceleniyor ve web'de araştırılıyor...",
      yeniBalon: true,
    );
    try {
      sistemMesajiniBaslat();
      final yanit = await MultimodalAnaliz.medyaAnalizEt(
        apiKey: openAiApiKey,
        medya: medya,
        kullaniciSorusu: soru,
        sistemTalimati: sistemTalimatiMetni(),
      );
      final temizYanit = sesliOkumaIcinTemizle(yanit);
      konusmaGecmisi.add({
        "role": "user",
        "content": "[Dosya: ${medya.dosyaAdi}] $soru",
      });
      konusmaGecmisi.add({"role": "assistant", "content": temizYanit});
      _yanitiGuncelle(temizYanit);
      await seslendir(temizYanit);
    } catch (e) {
      _yanitiGuncelle("Analiz sırasında hata oluştu: $e");
    }
  }

  Future rehberdenAra(String komut) async {
    try {
      String aranan = komut
          .replaceAll(
            RegExp(
              r'\b(ara|telefon et|çağrı yap|numarasını)\b',
              caseSensitive: false,
            ),
            '',
          )
          .replaceAll(RegExp(r"'’\b", caseSensitive: false), '')
          .trim();
      final rakamlar = aranan.replaceAll(RegExp(r'[^0-9+]'), '');
      if (rakamlar.length >= 3) {
        await btChannel.invokeMethod('makeCall', {'number': rakamlar});
        return "$rakamlar numarası aranıyor...";
      }
      if (aranan.isEmpty) {
        await btChannel.invokeMethod('makeCall', {'number': ''});
        return "Arama ekranını açtım.";
      }
      final izin = await Permission.contacts.request();
      if (izin.isGranted) {
        final Map<dynamic, dynamic>? kisi = await btChannel.invokeMethod(
          'findContact',
          {'name': aranan},
        );
        if (kisi != null && kisi['number'] != null) {
          final String ad = kisi['name'] ?? aranan;
          final String numara = kisi['number'];
          await btChannel.invokeMethod('makeCall', {'number': numara});
          return "$ad aranıyor...";
        }
        return "Rehberde $aranan isminde bir kayıt bulamadım.";
      } else {
        return "Rehber izni verilmediği için kişiyi bulamadım.";
      }
    } catch (e) {
      return "Arama başlatılırken bir sorun oluştu.";
    }
  }

  Future geminiUygulamasiniAc() async {
    FocusManager.instance.primaryFocus?.unfocus();
    _yanitiGuncelle("Google Gemini açılıyor...", yeniBalon: true);
    await seslendir("Gemini'yi açıyorum.");
    final bool acildi = await btChannel.invokeMethod('openGemini') ?? false;
    if (!acildi) {
      _yanitiGuncelle("Gemini uygulaması cihazda bulunamadı.");
    }
  }

  Future bluetoothMikrofonBaslat() async {
    if (!kIsWeb) {
      try {
        scoCompleter = Completer();
        final bool btFound = await btChannel.invokeMethod('startBluetoothMic');
        if (btFound) {
          await scoCompleter!.future.timeout(
            const Duration(milliseconds: 1200),
          );
        }
      } catch (e) {}
    }
  }

  Future bluetoothMikrofonDurdur() async {
    if (!kIsWeb) {
      try {
        await btChannel
            .invokeMethod('stopBluetoothMic')
            .timeout(const Duration(milliseconds: 500));
      } catch (e) {}
    }
  }

  void _dinlemeOturumuBaslat() {
    if (!isListening || kullaniciManuelDurdurdu || !mounted) return;
    anlikParcaMetni = "";
    speech.listen(
      localeId: ceviriModuAktif ? dilKodunuGetir(seciliKaynakDil).replaceAll("-", "_") : "tr_TR",
      listenFor: const Duration(seconds: 45),
      pauseFor: const Duration(seconds: 15),
      listenOptions: stt.SpeechListenOptions(
        partialResults: true,
        cancelOnError: false,
        listenMode: stt.ListenMode.dictation,
      ),
      onResult: (val) {
        if (!mounted || !isListening || kullaniciManuelDurdurdu) return;
        setState(() {
          anlikParcaMetni = val.recognizedWords;
          final gosterilecek = "$birikenSesMetni $anlikParcaMetni".trim();
          if (gosterilecek.isNotEmpty) {
            konusulanMetin = gosterilecek;
          }
        });
      },
    );
  }

  void sesliDinlemeTetikle() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await flutterTts.stop();

    if (!isListening) {
      kullaniciManuelDurdurdu = false;
      birikenSesMetni = "";
      anlikParcaMetni = "";

      setState(() {
        konusulanMetin = "Mikrofon hazırlanıyor...";
      });

      await bluetoothMikrofonBaslat();

      if (!speechHazirMi) {
        speechHazirMi = await speech.initialize(
          onStatus: (val) {
            if ((val == 'done' || val == 'notListening') && isListening && !kullaniciManuelDurdurdu && mounted) {
              if (anlikParcaMetni.trim().isNotEmpty) {
                birikenSesMetni = "$birikenSesMetni $anlikParcaMetni".trim();
                anlikParcaMetni = "";
              }
              // Otomatik dongu kapatildi
            }
          },
          onError: (val) {
            if (isListening && !kullaniciManuelDurdurdu && mounted) {
              // Otomatik dongu kapatildi
            }
          },
        );
      }

      if (speechHazirMi) {
        setState(() {
          isListening = true;
          konusulanMetin = "Seni dinliyorum... (Konuşman bitince tekrar bas)";
        });
        _dinlemeOturumuBaslat();
      } else {
        await bluetoothMikrofonDurdur();
        _yanitiGuncelle("Mikrofon izni kapalı görünüyor, ayarlardan izin verebilirsin.", yeniBalon: true);
      }
    } else {
      kullaniciManuelDurdurdu = true;
      setState(() => isListening = false);
      await speech.stop();
      await bluetoothMikrofonDurdur();

      final tamKomut = "$birikenSesMetni $anlikParcaMetni".trim();
      birikenSesMetni = "";
      anlikParcaMetni = "";

      if (tamKomut.isNotEmpty) {
        _kullaniciMesajiEkle(tamKomut);
        komutuIsle(tamKomut);
      } else if (bekleyenMedya != null) {
        yukluMedyayiAnalizEt("");
      } else {
        setState(() => konusulanMetin = "Mikrofona basıp konuş, bitince tekrar basıp kapat...");
      }
    }
  }

  void klavyeMesajiGonder() {
    FocusManager.instance.primaryFocus?.unfocus();
    final metin = metinController.text.trim();
    if (metin.isEmpty && bekleyenMedya == null) return;
    metinController.clear();
    if (bekleyenMedya != null) {
      final etiket = metin.isEmpty
          ? "[Dosya: $bekleyenBelgeAdi]"
          : "[Dosya: $bekleyenBelgeAdi] $metin";
      _kullaniciMesajiEkle(etiket);
      yukluMedyayiAnalizEt(metin);
      return;
    }
    _kullaniciMesajiEkle(metin);
    komutuIsle(metin);
  }

  void komutuIsle(String komut) async {
    if (komut.isEmpty) return;
    final kucukKomut = komut.toLowerCase();
    if (bekleyenMedya != null) {
      await yukluMedyayiAnalizEt(komut);
      return;
    }
    // 1. Gemini'ye Geçiş
    if (kucukKomut.contains("gemini") &&
        (kucukKomut.contains("aç") || kucukKomut.contains("geç"))) {
      await geminiUygulamasiniAc();
      return;
    }
    // 2. Uygulama İçi Video Arama ve Oynatma
    if (kucukKomut.contains("video") ||
        kucukKomut.contains("izlet") ||
        kucukKomut.contains("youtube")) {
      final sorgu = komut
          .replaceAll(
            RegExp(
              r'\b(bana|video|videosu|videoları|bul|izlet|aç|youtube|da|de|oynat)\b',
              caseSensitive: false,
            ),
            '',
          )
          .trim();
      final arananVideo = sorgu.isEmpty ? "güncel videolar" : sorgu;
      final ytBase = _urlCoz(
        "aHR0cHM6Ly9tLnlvdXR1YmUuY29tL3Jlc3VsdHM/c2VhcmNoX3F1ZXJ5PQ==",
      );
      _dahiliOynaticiAc(
        "$ytBase${Uri.encodeComponent(arananVideo)}",
        "OSIS Video: $arananVideo",
      );
      _yanitiGuncelle(
        "'$arananVideo' videolarını ana ekranda açtım.",
        yeniBalon: true,
      );
      await seslendir("$arananVideo videolarını açtım.");
      return;
    }
    // 3. Web Sayfası Bulma ve Açma
    if (kucukKomut.contains("web") ||
        kucukKomut.contains("sayfasını aç") ||
        kucukKomut.contains("sitesini aç") ||
        kucukKomut.contains("internetten aç")) {
      final siteSorgu = komut
          .replaceAll(
            RegExp(
              r'\b(bana|web|de|da|sayfasını|sitesini|internetten|aç|bul|gir)\b',
              caseSensitive: false,
            ),
            '',
          )
          .trim();
      final gBase = _urlCoz("aHR0cHM6Ly93d3cuZ29vZ2xlLmNvbS9zZWFyY2g/cT0=");
      final hedefUrl = siteSorgu.contains(".") && !siteSorgu.contains(" ")
          ? "https://$siteSorgu"
          : "$gBase${Uri.encodeComponent(siteSorgu)}";
      _dahiliOynaticiAc(hedefUrl, "OSIS Web: $siteSorgu");
      _yanitiGuncelle(
        "$siteSorgu sayfasını ana ekranda açtım.",
        yeniBalon: true,
      );
      await seslendir("$siteSorgu sayfasını açtım.");
      return;
    }
    // 4. Müzik Kontrolü
    if (kucukKomut.contains("müziği durdur") ||
        kucukKomut.contains("şarkıyı durdur") ||
        kucukKomut.contains("müziği kapat")) {
      await btChannel.invokeMethod('mediaControl', {'action': 'pause'});
      _yanitiGuncelle("Müziği durdurdum.", yeniBalon: true);
      return;
    }
    if (kucukKomut.contains("müziği başlat") ||
        kucukKomut.contains("müziği aç") ||
        kucukKomut.contains("şarkıyı başlat") ||
        kucukKomut.contains("devam et")) {
      await btChannel.invokeMethod('mediaControl', {'action': 'play'});
      _yanitiGuncelle("Müziği başlattım.", yeniBalon: true);
      return;
    }
    if (kucukKomut.contains("sonraki şarkı") ||
        kucukKomut.contains("şarkıyı değiştir") ||
        kucukKomut.contains("sonraki parça")) {
      await btChannel.invokeMethod('mediaControl', {'action': 'next'});
      _yanitiGuncelle("Sonraki şarkıya geçtim.", yeniBalon: true);
      return;
    }
    if (kucukKomut.contains("önceki şarkı") ||
        kucukKomut.contains("önceki parça")) {
      await btChannel.invokeMethod('mediaControl', {'action': 'previous'});
      _yanitiGuncelle("Önceki şarkıya döndüm.", yeniBalon: true);
      return;
    }
    // 5. Rehberden Arama
    if (kucukKomut.endsWith(" ara") ||
        kucukKomut.contains(" telefon et") ||
        kucukKomut.contains(" çağrı yap")) {
      _yanitiGuncelle("Rehbere bakıyorum...", yeniBalon: true);
      final aramaYaniti = await rehberdenAra(komut);
      _yanitiGuncelle(aramaYaniti);
      await seslendir(aramaYaniti);
      return;
    }
    // 6. Anlik Ceviri ve Dil Sabitleme
    for (String dil in desteklenenDiller) {
      final dKucuk = dil.toLowerCase();
      if (kucukKomut.contains("${dKucuk}ya çevir") ||
          kucukKomut.contains("${dKucuk}ye çevir") ||
          kucukKomut.contains("$dKucuk çevir") ||
          kucukKomut.contains("$dKucuk nasıl denir") ||
          kucukKomut.contains("dili $dKucuk yap")) {
        setState(() {
          seciliHedefDil = dil;
          ceviriModuAktif = true;
          sistemMesajiniBaslat();
        });
        _ayarlariKaydet();

        final cevrilecekMetin = komut
            .replaceAll(RegExp(r'\b(bunu|şu cümleyi|ingilizceye|ingilizce|koreceye|korece|japoncaya|japonca|almancaya|almanca|ispanyolcaya|ispanyolca|çinceye|çince|rusçaya|rusça|fransızcaya|fransızca|arapçaya|arapça|türkçeye|türkçe|çevir|nasıl denir|dili|yap)\b', caseSensitive: false), '')
            .replaceAll(':', '')
            .trim();

        if (cevrilecekMetin.isNotEmpty) {
          openAIYanitiniGetir(cevrilecekMetin);
        } else {
          final msg = "Tamamdır! Türkçe konuşmalarını doğrudan $seciliHedefDil diline çeviriyorum, söyleyebilirsin.";
          _yanitiGuncelle(msg, yeniBalon: true);
          await seslendir(msg);
        }
        return;
      }
    }
    if (kucukKomut.contains("çeviriyi kapat") ||
        kucukKomut.contains("normal moda dön")) {
      setState(() {
        ceviriModuAktif = false;
        sistemMesajiniBaslat();
      });
      const msg = "Çeviri modunu kapattım, normal sohbet modundayız.";
      _yanitiGuncelle(msg, yeniBalon: true);
      await seslendir(msg);
      return;
    }
    // 7. Google Haritalar & Canlı Trafik
    if (kucukKomut.contains("harita") ||
        kucukKomut.contains("trafik") ||
        kucukKomut.contains("yol durumu") ||
        kucukKomut.contains("kaç km") ||
        kucukKomut.contains("kaç kilometre") ||
        kucukKomut.contains("ne kadar sürer") ||
        kucukKomut.contains("yol tarifi") ||
        kucukKomut.contains("götür")) {
      _yanitiGuncelle(
        "Google Haritalar ve canlı trafik rotası açılıyor...",
        yeniBalon: true,
      );
      try {
        final hedefTemiz = komut
            .replaceAll(
              RegExp(
                r'\b(google|haritalar|harita|trafik|durumu|nasıl|yol|tarifi|kaç km|kaç kilometre|ne kadar sürer|götür|canlı|aç|bak)\b',
                caseSensitive: false,
              ),
              '',
            )
            .trim();
        final baseDir = _urlCoz(
          "aHR0cHM6Ly93d3cuZ29vZ2xlLmNvbS9tYXBzL2Rpci8/YXBpPTEmdHJhdmVsbW9kZT1kcml2aW5nJmRlc3RpbmF0aW9uPQ==",
        );
        final rotaUri = Uri.parse(
          hedefTemiz.isNotEmpty
              ? "$baseDir${Uri.encodeComponent(hedefTemiz)}"
              : _urlCoz(
                  "aHR0cHM6Ly93d3cuZ29vZ2xlLmNvbS9tYXBzL3NlYXJjaC8/YXBpPTEmcXVlcnk9dHJhZmlrK2R1cnVtdQ==",
                ),
        );
        if (await canLaunchUrl(rotaUri)) {
          await launchUrl(rotaUri, mode: LaunchMode.externalApplication);
        }
      } catch (e) {}
      sistemMesajiniBaslat();
      final trafikSoru =
          "Kullanıcının şu anki konumu: $kullaniciKonumu. Şu anki saat itibarıyla canlı web araması yaparak bu soruya anlık trafik yoğunluğunu, mesafeyi (km) ve tahmini varış süresini (dakika) net rakamlarla söyle: $komut";
      konusmaGecmisi.add({"role": "user", "content": trafikSoru});
      try {
        final yanit = await openAiCanliWebYanitiGetir(konusmaGecmisi);
        konusmaGecmisi.add({"role": "assistant", "content": yanit});
        _yanitiGuncelle(yanit);
        await seslendir(yanit);
      } catch (e) {
        _yanitiGuncelle("Google Haritalar rotası açıldı.");
      }
      return;
    }
    // 8. PDF veya Word Belge Oluşturma
    final bool pdfIstegi = kucukKomut.contains("pdf");
    final bool wordIstegi =
        kucukKomut.contains("word") ||
        kucukKomut.contains("docx") ||
        kucukKomut.contains("belge olarak");
    if (pdfIstegi || wordIstegi) {
      _yanitiGuncelle(
        pdfIstegi
            ? "PDF belgesi hazırlanıyor..."
            : "Word belgesi hazırlanıyor...",
        yeniBalon: true,
      );
      try {
        sistemMesajiniBaslat();
        final String temizIstek =
            "$komut\n(Not: Bu metin doğrudan belgeye aktarılacaktır. Sadece belge içeriğini temiz ve düzenli şekilde yaz, sohbet girişi yapma.)";
        konusmaGecmisi.add({"role": "user", "content": temizIstek});
        String icerik;
        try {
          icerik = await openAiCanliWebYanitiGetir(konusmaGecmisi);
        } catch (e) {
          icerik = await openAiStandartYanitGetir(konusmaGecmisi);
        }
        konusmaGecmisi.add({"role": "assistant", "content": icerik});
        if (pdfIstegi) {
          await DosyaUretici.pdfOlusturVePaylas("OSIS Belgesi", icerik);
          _yanitiGuncelle("PDF dosyanı hazırladım ve paylaşım ekranını açtım.");
        } else {
          await DosyaUretici.wordOlusturVePaylas("OSIS Belgesi", icerik);
          _yanitiGuncelle(
            "Word (.docx) dosyanı hazırladım ve paylaşım ekranını açtım.",
          );
        }
        await seslendir(asistanYaniti);
      } catch (e) {
        _yanitiGuncelle("Belge oluşturulurken hata oluştu: $e");
      }
      return;
    }
    // 9. OpenAI Canlı Web Arama + Çeviri (Okunuşlu) + Sohbet
    openAIYanitiniGetir(komut);
  }

  String sesliOkumaIcinTemizle(String metin) {
    String temiz = metin
        .replaceAll('**', '')
        .replaceAll('###', '')
        .replaceAll('##', '');
    while (temiz.contains('([') && temiz.contains('))')) {
      int bas = temiz.indexOf('([');
      int son = temiz.indexOf('))', bas);
      if (bas != -1 && son != -1) {
        temiz = temiz.replaceRange(bas, son + 2, '');
      } else {
        break;
      }
    }
    return temiz.trim();
  }

  Future openAiCanliWebYanitiGetir(List<Map<String, String>> mesajlar) async {
    final uri = Uri.parse(
      _urlCoz("aHR0cHM6Ly9hcGkub3BlbmFpLmNvbS92MS9yZXNwb25zZXM="),
    );
    final temizAnahtar = openAiApiKey.trim();
    if (temizAnahtar.isEmpty || temizAnahtar.contains("BURAYA_GERCEK")) {
      throw Exception("API_KEY_EKSIK");
    }
    final response = await http
        .post(
          uri,
          headers: {
            "Content-Type": "application/json",
            "Authorization": "Bearer $temizAnahtar",
          },
          body: jsonEncode({
            "model": "gpt-4o-mini",
            "tools": [
              {"type": "web_search"},
            ],
            "input": mesajlar,
          }),
        )
        .timeout(const Duration(seconds: 18));
    if (response.statusCode == 200) {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data['output_text'] != null &&
          data['output_text'].toString().trim().isNotEmpty) {
        return sesliOkumaIcinTemizle(data['output_text'].toString());
      }
      final List outputs = data['output'] ?? [];
      for (var item in outputs) {
        if (item['type'] == 'message') {
          final List contents = item['content'] ?? [];
          for (var c in contents) {
            if (c['text'] != null && c['text'].toString().trim().isNotEmpty) {
              return sesliOkumaIcinTemizle(c['text'].toString());
            }
          }
        }
      }
      throw Exception("Yanıt ayrıştırılamadı.");
    } else {
      throw Exception("HTTP ${response.statusCode}: ${response.body}");
    }
  }

  Future openAiStandartYanitGetir(List<Map<String, String>> mesajlar) async {
    final uri = Uri.parse(
      _urlCoz("aHR0cHM6Ly9hcGkub3BlbmFpLmNvbS92MS9jaGF0L2NvbXBsZXRpb25z"),
    );
    final temizAnahtar = openAiApiKey.trim();
    if (temizAnahtar.isEmpty || temizAnahtar.contains("BURAYA_GERCEK")) {
      throw Exception("API_KEY_EKSIK");
    }
    final response = await http
        .post(
          uri,
          headers: {
            "Content-Type": "application/json",
            "Authorization": "Bearer $temizAnahtar",
          },
          body: jsonEncode({"model": "gpt-4o-mini", "messages": mesajlar}),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode == 200) {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      final List choices = data['choices'] ?? [];
      if (choices.isNotEmpty) {
        final String? content = choices.first['message']?['content'];
        if (content != null && content.trim().isNotEmpty) {
          return sesliOkumaIcinTemizle(content);
        }
      }
      throw Exception("Boş yanıt döndü");
    } else {
      throw Exception("HTTP ${response.statusCode}: ${response.body}");
    }
  }

  void openAIYanitiniGetir(String prompt) async {
    _yanitiGuncelle("Canlı veriler araştırılıyor...", yeniBalon: true);
    try {
      sistemMesajiniBaslat();
      String gonderilecekMesaj = ceviriModuAktif
          ? "Aşağıdaki $seciliKaynakDil cümleyi $seciliHedefDil diline çevir. İlk satıra sadece $seciliHedefDil çevirisini yaz, ikinci satıra ise mutlaka 'Okunuşu: ' yazarak Latin harfleriyle telaffuzunu ekle. Başka açıklama yapma:\n$prompt"
          : prompt;
      konusmaGecmisi.add({"role": "user", "content": gonderilecekMesaj});
      if (konusmaGecmisi.length > 21) {
        konusmaGecmisi.removeRange(1, konusmaGecmisi.length - 20);
      }
      String reply;
      if (ceviriModuAktif) {
        reply = await openAiStandartYanitGetir(konusmaGecmisi);
      } else {
        try {
          reply = await openAiCanliWebYanitiGetir(konusmaGecmisi);
        } catch (e) {
          if (e.toString().contains("API_KEY_EKSIK") ||
              e.toString().contains("401") ||
              e.toString().contains("429")) {
            rethrow;
          }
          reply = await openAiStandartYanitGetir(konusmaGecmisi);
        }
      }
      konusmaGecmisi.add({"role": "assistant", "content": reply});
      _yanitiGuncelle(reply);
      if (ceviriModuAktif) {
        final ilkSatir = reply.split('\n').first.trim();
        await seslendir(ilkSatir, dilKodu: dilKodunuGetir(seciliHedefDil));
      } else {
        await seslendir(reply);
      }
    } catch (e) {
      final hataDetayi = e.toString();
      String mesaj = "Bağlantı sorunu oluştu: $hataDetayi";
      if (hataDetayi.contains("API_KEY_EKSIK")) {
        mesaj = "OpenAI API anahtarını henüz eklememişsin.";
      } else if (hataDetayi.contains("401")) {
        mesaj = "OpenAI API anahtarı geçersiz görünüyor.";
      } else if (hataDetayi.contains("429")) {
        mesaj = "OpenAI API bakiyesi veya kotası dolmuş.";
      }
      _yanitiGuncelle(mesaj);
      await seslendir(mesaj);
    }
  }

  void _metniDuzenlemeyeAl(String metin) {
    if (metin.trim().isEmpty || metin.startsWith("Mikrofona basıp")) return;
    setState(() {
      metinController.text = metin;
      metinController.selection = TextSelection.fromPosition(
        TextPosition(offset: metinController.text.length),
      );
    });
    Future.delayed(const Duration(milliseconds: 80), () {
      if (mounted) {
        klavyeFocusNode.requestFocus();
      }
    });
  }

  void _panoyaKopyala(String metin) {
    Clipboard.setData(ClipboardData(text: metin));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Yanıt panoya kopyalandı."),
        duration: Duration(seconds: 1),
      ),
    );
  }

  void _ayarlarPenceresiniAc() {
    showModalBottomSheet(
      context: context,
      backgroundColor: kartRengi,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            Widget renkSecici(
              String baslik,
              List renkler,
              Color secili,
              Function(Color) onSec,
            ) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    baslik,
                    style: TextStyle(
                      color: yaziRengi,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    children: renkler.map((renk) {
                      final aktif = secili.toARGB32() == renk.toARGB32();
                      return GestureDetector(
                        onTap: () {
                          setState(() => onSec(renk));
                          _ayarlariKaydet();
                          setModalState(() {});
                        },
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: renk,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: aktif ? vurguRengi : Colors.white38,
                              width: aktif ? 3 : 1,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                ],
              );
            }

            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "OSIS Görünüm & Tema Ayarları",
                        style: TextStyle(
                          color: vurguRengi,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: Icon(Icons.close, color: yaziRengi),
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white12),
                  Text(
                    "Hareketli Arka Plan Teması",
                    style: TextStyle(
                      color: yaziRengi,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text("Uzay Yıldızları"),
                        selected: arkaPlanTemaTipi == 0,
                        selectedColor: vurguRengi.withValues(alpha: 0.3),
                        onSelected: (_) {
                          setState(() => arkaPlanTemaTipi = 0);
                          _ayarlariKaydet();
                          setModalState(() {});
                        },
                      ),
                      ChoiceChip(
                        label: const Text("Elektronik Devre LED"),
                        selected: arkaPlanTemaTipi == 1,
                        selectedColor: vurguRengi.withValues(alpha: 0.3),
                        onSelected: (_) {
                          setState(() => arkaPlanTemaTipi = 1);
                          _ayarlariKaydet();
                          setModalState(() {});
                        },
                      ),
                      ChoiceChip(
                        label: const Text("Mekanik Saat / Uzay Aracı"),
                        selected: arkaPlanTemaTipi == 2,
                        selectedColor: vurguRengi.withValues(alpha: 0.3),
                        onSelected: (_) {
                          setState(() => arkaPlanTemaTipi = 2);
                          _ayarlariKaydet();
                          setModalState(() {});
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      "Geniş Sohbet Penceresi Görünümü",
                      style: TextStyle(color: yaziRengi, fontSize: 14),
                    ),
                    value: sohbetPenceresiModu,
                    activeThumbColor: vurguRengi,
                    onChanged: (val) {
                      setState(() => sohbetPenceresiModu = val);
                      _ayarlariKaydet();
                      setModalState(() {});
                    },
                  ),
                  const SizedBox(height: 6),
                  renkSecici(
                    "Arka Plan Rengi (Siyah / Kırmızı / Koyu Tonlar)",
                    [
                      const Color(0xFF070B12),
                      const Color(0xFF000000),
                      const Color(0xFF24070B),
                      const Color(0xFF4A0810),
                      const Color(0xFF0A1914),
                    ],
                    arkaPlanRengi,
                    (r) {
                      arkaPlanRengi = r;
                      kartRengi = Color.lerp(r, Colors.white, 0.08)!;
                    },
                  ),
                  renkSecici(
                    "Vurgu ve LED / Küre Rengi",
                    [
                      const Color(0xFF66FCF1),
                      const Color(0xFFFF2A3C),
                      const Color(0xFFFFD166),
                      const Color(0xFF06D6A0),
                      const Color(0xFFFFFFFF),
                    ],
                    vurguRengi,
                    (r) => vurguRengi = r,
                  ),
                  renkSecici(
                    "Yazı Rengi",
                    [
                      Colors.white,
                      const Color(0xFFFF5252),
                      const Color(0xFFF4F1DE),
                      const Color(0xFFA8F9FF),
                      const Color(0xFFFFE599),
                    ],
                    yaziRengi,
                    (r) => yaziRengi = r,
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    pulsingController.dispose();
    arkaPlanController.dispose();
    metinController.dispose();
    klavyeFocusNode.dispose();
    yanitScrollController.dispose();
    sohbetScrollController.dispose();
    flutterTts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: Scaffold(
        backgroundColor: arkaPlanRengi,
        body: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.0, -0.3),
                  radius: 1.25,
                  colors: [
                    Color.lerp(arkaPlanRengi, vurguRengi, 0.16)!,
                    arkaPlanRengi,
                  ],
                ),
              ),
            ),
            Positioned.fill(
              child: AnimatedBuilder(
                animation: arkaPlanController,
                builder: (context, _) {
                  return CustomPaint(
                    painter: HareketliArkaPlanPainter(
                      temaTipi: arkaPlanTemaTipi,
                      animasyonDegeri: arkaPlanController.value,
                      vurguRengi: vurguRengi,
                      yaziRengi: yaziRengi,
                    ),
                  );
                },
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 8.0,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ÜST BAR
                    Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                IconButton(
                                  onPressed: () {
                                    setState(
                                      () => sohbetPenceresiModu =
                                          !sohbetPenceresiModu,
                                    );
                                    _ayarlariKaydet();
                                  },
                                  icon: Icon(
                                    sohbetPenceresiModu
                                        ? Icons.blur_circular
                                        : Icons.view_agenda_outlined,
                                    color: vurguRengi,
                                  ),
                                  tooltip: sohbetPenceresiModu
                                      ? "Küre Görünümüne Geç"
                                      : "Geniş Okuma Görünümüne Geç",
                                ),
                                IconButton(
                                  onPressed: () {
                                    setState(
                                      () => sesliOkumaAktif = !sesliOkumaAktif,
                                    );
                                    if (!sesliOkumaAktif) flutterTts.stop();
                                  },
                                  icon: Icon(
                                    sesliOkumaAktif
                                        ? Icons.volume_up
                                        : Icons.volume_off,
                                    color: sesliOkumaAktif
                                        ? vurguRengi
                                        : Colors.white38,
                                  ),
                                  tooltip: sesliOkumaAktif
                                      ? "Hoparlör Açık"
                                      : "Hoparlör Sessiz (Kulaklık Aktif)",
                                ),
                              ],
                            ),
                            Text(
                              "OSIS",
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 4,
                                color: vurguRengi,
                              ),
                            ),
                            Row(
                              children: [
                                IconButton(
                                  onPressed: geminiUygulamasiniAc,
                                  icon: Icon(
                                    Icons.auto_awesome,
                                    color: vurguRengi,
                                  ),
                                  tooltip: "Gemini'ye Geç",
                                ),
                                IconButton(
                                  onPressed: _ayarlarPenceresiniAc,
                                  icon: Icon(Icons.settings, color: vurguRengi),
                                  tooltip: "Renk ve Tema Ayarları",
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                          decoration: BoxDecoration(
                            color: kartRengi.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: ceviriModuAktif ? vurguRengi : vurguRengi.withValues(alpha: 0.35),
                              width: ceviriModuAktif ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    isExpanded: true,
                                    value: seciliKaynakDil,
                                    dropdownColor: kartRengi,
                                    iconEnabledColor: vurguRengi,
                                    style: TextStyle(color: yaziRengi, fontWeight: FontWeight.bold, fontSize: 13),
                                    items: desteklenenDiller.map((String dil) {
                                      return DropdownMenuItem<String>(
                                        value: dil,
                                        child: Text(dil, overflow: TextOverflow.ellipsis),
                                      );
                                    }).toList(),
                                    onChanged: (String? yeniKaynak) {
                                      if (yeniKaynak != null) {
                                        setState(() {
                                          seciliKaynakDil = yeniKaynak;
                                          ceviriModuAktif = true;
                                          sistemMesajiniBaslat();
                                        });
                                        _ayarlariKaydet();
                                      }
                                    },
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                child: InkWell(
                                  onTap: () {
                                    setState(() {
                                      final gecici = seciliKaynakDil;
                                      seciliKaynakDil = seciliHedefDil;
                                      seciliHedefDil = gecici;
                                      ceviriModuAktif = true;
                                      sistemMesajiniBaslat();
                                    });
                                    _ayarlariKaydet();
                                  },
                                  borderRadius: BorderRadius.circular(20),
                                  child: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: vurguRengi.withValues(alpha: 0.18),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(Icons.swap_horiz, color: vurguRengi, size: 22),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    isExpanded: true,
                                    value: seciliHedefDil,
                                    dropdownColor: kartRengi,
                                    iconEnabledColor: vurguRengi,
                                    style: TextStyle(color: vurguRengi, fontWeight: FontWeight.bold, fontSize: 13),
                                    items: desteklenenDiller.map((String dil) {
                                      return DropdownMenuItem<String>(
                                        value: dil,
                                        child: Text(dil, overflow: TextOverflow.ellipsis),
                                      );
                                    }).toList(),
                                    onChanged: (String? yeniHedef) {
                                      if (yeniHedef != null) {
                                        setState(() {
                                          seciliHedefDil = yeniHedef;
                                          ceviriModuAktif = true;
                                          sistemMesajiniBaslat();
                                        });
                                        _ayarlariKaydet();
                                      }
                                    },
                                  ),
                                ),
                              ),
                              Switch(
                                value: ceviriModuAktif,
                                activeThumbColor: vurguRengi,
                                onChanged: (val) {
                                  setState(() {
                                    ceviriModuAktif = val;
                                    sistemMesajiniBaslat();
                                  });
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    // UYGULAMA İÇİ VİDEO / WEB OYNATICI PENCERESİ (Açık ise)
                    if (dahiliWebController != null)
                      Expanded(
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: kartRengi,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: vurguRengi),
                          ),
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: arkaPlanRengi,
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(15),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        aktifDahiliBaslik ?? "OSIS Oynatıcı",
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: vurguRengi,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      onPressed: () => setState(
                                        () => dahiliWebController = null,
                                      ),
                                      icon: const Icon(
                                        Icons.close,
                                        color: Colors.redAccent,
                                      ),
                                      tooltip: "Oynatıcıyı Kapat",
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: const BorderRadius.vertical(
                                    bottom: Radius.circular(15),
                                  ),
                                  child: WebViewWidget(
                                    controller: dahiliWebController!,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else if (sohbetPenceresiModu)
                      Expanded(
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 8),
                          child: ListView.builder(
                            controller: sohbetScrollController,
                            itemCount: sohbetGecmisiListesi.length,
                            itemBuilder: (context, index) {
                              final balon = sohbetGecmisiListesi[index];
                              return Align(
                                alignment: balon.kullaniciMi
                                    ? Alignment.centerRight
                                    : Alignment.centerLeft,
                                child: Container(
                                  margin: const EdgeInsets.symmetric(
                                    vertical: 5,
                                  ),
                                  padding: const EdgeInsets.all(13),
                                  constraints: BoxConstraints(
                                    maxWidth:
                                        MediaQuery.of(context).size.width *
                                        0.84,
                                  ),
                                  decoration: BoxDecoration(
                                    color: balon.kullaniciMi
                                        ? Color.lerp(
                                            kartRengi,
                                            vurguRengi,
                                            0.22,
                                          )
                                        : kartRengi.withValues(alpha: 0.92),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: vurguRengi.withValues(alpha: 0.25),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (!balon.kullaniciMi)
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              "OSIS",
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: vurguRengi,
                                              ),
                                            ),
                                            InkWell(
                                              onTap: () =>
                                                  _panoyaKopyala(balon.metin),
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    Icons.copy,
                                                    size: 13,
                                                    color: vurguRengi,
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    "Kopyala",
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color: vurguRengi,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      if (!balon.kullaniciMi)
                                        const SizedBox(height: 4),
                                      balon.kullaniciMi
                                          ? GestureDetector(
                                              onTap: () => _metniDuzenlemeyeAl(
                                                balon.metin,
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Flexible(
                                                    child: Text(
                                                      balon.metin,
                                                      style: TextStyle(
                                                        color: yaziRengi,
                                                        fontSize: 14.5,
                                                        height: 1.38,
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Icon(
                                                    Icons.edit,
                                                    size: 14,
                                                    color: vurguRengi,
                                                  ),
                                                ],
                                              ),
                                            )
                                          : SelectableText(
                                              balon.metin,
                                              style: TextStyle(
                                                color: yaziRengi,
                                                fontSize: 14.5,
                                                height: 1.38,
                                              ),
                                            ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      )
                    else ...[
                      // YILDIZLI / DEVRELİ / SAATLİ KÜRE (ORB) GÖRÜNÜMÜ
                      Expanded(
                        flex: 3,
                        child: Center(
                          child: GestureDetector(
                            onTap: sesliDinlemeTetikle,
                            child: AnimatedBuilder(
                              animation: pulsingController,
                              builder: (context, child) {
                                return Container(
                                  width: 115 + (pulsingController.value * 14),
                                  height: 115 + (pulsingController.value * 14),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: RadialGradient(
                                      colors: [
                                        isListening
                                            ? vurguRengi
                                            : vurguRengi.withValues(
                                                alpha: 0.65,
                                              ),
                                        kartRengi,
                                        arkaPlanRengi,
                                      ],
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: vurguRengi.withValues(
                                          alpha: 0.4 * pulsingController.value,
                                        ),
                                        blurRadius: 26,
                                        spreadRadius: 4,
                                      ),
                                    ],
                                  ),
                                  child: Icon(
                                    isListening
                                        ? Icons.mic
                                        : Icons.blur_circular,
                                    size: 46,
                                    color: isListening
                                        ? arkaPlanRengi
                                        : yaziRengi,
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 5,
                        child: Card(
                          color: kartRengi.withValues(alpha: 0.88),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                            side: BorderSide(
                              color: vurguRengi.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(14.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                InkWell(
                                  onTap: () =>
                                      _metniDuzenlemeyeAl(konusulanMetin),
                                  borderRadius: BorderRadius.circular(8),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            "SEN:",
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: vurguRengi.withValues(
                                                alpha: 0.8,
                                              ),
                                            ),
                                          ),
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.edit,
                                                size: 12,
                                                color: vurguRengi.withValues(
                                                  alpha: 0.8,
                                                ),
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                "Düzenle",
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: vurguRengi.withValues(
                                                    alpha: 0.8,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        konusulanMetin,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 13.5,
                                          color: yaziRengi.withValues(
                                            alpha: 0.85,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 8.0),
                                  child: Divider(
                                    color: Colors.white12,
                                    height: 1,
                                  ),
                                ),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      ceviriModuAktif
                                          ? "ÇEVİRİ & OKUNUŞ ($seciliHedefDil):"
                                          : "OSIS:",
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: vurguRengi,
                                      ),
                                    ),
                                    InkWell(
                                      onTap: () =>
                                          _panoyaKopyala(asistanYaniti),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: vurguRengi.withValues(
                                            alpha: 0.15,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          border: Border.all(
                                            color: vurguRengi.withValues(
                                              alpha: 0.4,
                                            ),
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.copy,
                                              size: 13,
                                              color: vurguRengi,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              "Kopyala",
                                              style: TextStyle(
                                                fontSize: 11.5,
                                                color: vurguRengi,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Expanded(
                                  child: Scrollbar(
                                    controller: yanitScrollController,
                                    thumbVisibility: true,
                                    child: SingleChildScrollView(
                                      controller: yanitScrollController,
                                      padding: const EdgeInsets.only(right: 10),
                                      child: SelectableText(
                                        asistanYaniti,
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w500,
                                          color: yaziRengi,
                                          height: 1.4,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    // ALT KONTROL ÇUBUĞU
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: metinController,
                            focusNode: klavyeFocusNode,
                            onSubmitted: (_) => klavyeMesajiGonder(),
                            style: TextStyle(color: yaziRengi),
                            decoration: InputDecoration(
                              hintText: bekleyenBelgeAdi != null
                                  ? "Dosya hakkında sor..."
                                  : "Yaz, fotoğraf çek veya PDF yükle...",
                              hintStyle: TextStyle(
                                color: yaziRengi.withValues(alpha: 0.4),
                                fontSize: 13,
                              ),
                              filled: true,
                              fillColor: kartRengi.withValues(alpha: 0.92),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(
                                  color: vurguRengi.withValues(alpha: 0.4),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(
                                  color: vurguRengi.withValues(alpha: 0.4),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(color: vurguRengi),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          decoration: BoxDecoration(
                            color: bekleyenMedya != null
                                ? vurguRengi
                                : kartRengi,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: vurguRengi.withValues(alpha: 0.4),
                            ),
                          ),
                          child: IconButton(
                            onPressed: kameradanFotoCek,
                            icon: Icon(
                              Icons.camera_alt,
                              color: bekleyenMedya != null
                                  ? arkaPlanRengi
                                  : vurguRengi,
                            ),
                            tooltip: "Fotoğraf Çek",
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          decoration: BoxDecoration(
                            color: bekleyenMedya != null
                                ? vurguRengi
                                : kartRengi,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: vurguRengi.withValues(alpha: 0.4),
                            ),
                          ),
                          child: IconButton(
                            onPressed: dosyaVeyaGaleriYukle,
                            icon: Icon(
                              Icons.attach_file,
                              color: bekleyenMedya != null
                                  ? arkaPlanRengi
                                  : vurguRengi,
                            ),
                            tooltip: "PDF / Galeri Yükle",
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          decoration: BoxDecoration(
                            color: vurguRengi.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: IconButton(
                            onPressed: klavyeMesajiGonder,
                            icon: Icon(Icons.send, color: arkaPlanRengi),
                            tooltip: "Gönder",
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: sesliDinlemeTetikle,
                      icon: Icon(isListening ? Icons.stop : Icons.mic),
                      label: Text(isListening ? "BİTİR VE GÖNDER" : "KONUŞ"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isListening
                            ? Colors.redAccent
                            : vurguRengi,
                        foregroundColor: arkaPlanRengi,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
