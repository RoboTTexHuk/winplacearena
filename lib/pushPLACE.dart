import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:appsflyer_sdk/appsflyer_sdk.dart'
    show AppsFlyerOptions, AppsflyerSdk;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show MethodCall, MethodChannel, SystemUiOverlayStyle;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'main.dart'
    show
    MainHandler,
    WebPage,
    PortalView,
    ScreenPortal,
    GateVortex,
    ZxHubView,
    hvViewModel,
    crHarbor,
    MafiaHarbor,
    ControlTower;

/// LEGION FCM Background Handler — фоновая обработка сообщений
@pragma('vm:entry-point')
Future<void> LEGION_BG_COMMS(RemoteMessage pitMsg) async {
  print("Bottle ID: ${pitMsg.messageId}");
  print("Bottle Data: ${pitMsg.data}");
}

/// LEGION_WAVE_LOADER — текст LEGION с волновой анимацией по буквам
class LEGION_WAVE_LOADER extends StatefulWidget {
  const LEGION_WAVE_LOADER({Key? key}) : super(key: key);

  @override
  State<LEGION_WAVE_LOADER> createState() => _LEGION_WAVE_LOADER_State();
}

class _LEGION_WAVE_LOADER_State extends State<LEGION_WAVE_LOADER>
    with SingleTickerProviderStateMixin {
  late AnimationController _legionController;
  final String _legionText = "WIN";

  @override
  void initState() {
    super.initState();
    _legionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _legionController.dispose();
    super.dispose();
  }

  Widget _LEGION_BUILD_LETTER(int index, String letter) {
    return AnimatedBuilder(
      animation: _legionController,
      builder: (_, __) {
        final value = (_legionController.value * 2 * 3.1415926535) +
            (index * 3.1415926535 / 6);
        final dy = (0.5 * (1 + sin(value))) * -6;
        return Transform.translate(
          offset: Offset(0, dy),
          child: Text(
            letter,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.w700,
              letterSpacing: 3,
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final chars = _legionText.split('');
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < chars.length; i++)
            _LEGION_BUILD_LETTER(i, chars[i]),
        ],
      ),
    );
  }
}

/// Экран с веб-вью — основной экран с InAppWebView
class LEGION_TABLE extends StatefulWidget with WidgetsBindingObserver {
  String route;
  LEGION_TABLE(this.route, {super.key});

  @override
  State<LEGION_TABLE> createState() => _LEGION_TABLE_STATE(route);
}

class _LEGION_TABLE_STATE extends State<LEGION_TABLE>
    with WidgetsBindingObserver {
  _LEGION_TABLE_STATE(this._legionCurrentRoute);

  late InAppWebViewController _legionWebView;
  String? _legionFcmToken;
  String? _legionDeviceId;
  String? _legionOsBuild;
  String? _legionPlatform;
  String? _legionLocale;
  String? _legionTimezone;
  bool _legionPushEnabled = true;
  bool _legionLoading = false;
  var _legionGateOpen = true;
  String _legionCurrentRoute;
  DateTime? _legionPausedAt;

  // Внешние «хабы» (tg/wa/bnl)
  final Set<String> _legionHubHosts = {
    't.me',
    'telegram.me',
    'telegram.dog',
    'wa.me',
    'api.whatsapp.com',
    'chat.whatsapp.com',
    'bnl.com',
    'www.bnl.com',
  };
  final Set<String> _legionHubSchemes = {'tg', 'telegram', 'whatsapp', 'bnl'};

  AppsflyerSdk? _legionAfSdk;
  String _legionAfPayload = "";
  String _legionAfUid = "";

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState legionPhase) {
    if (legionPhase == AppLifecycleState.paused) {
      _legionPausedAt = DateTime.now();
    }
    if (legionPhase == AppLifecycleState.resumed) {
      if (Platform.isIOS && _legionPausedAt != null) {
        final now = DateTime.now();
        final drift = now.difference(_legionPausedAt!);
        if (drift > const Duration(minutes: 25)) {
          LEGION_HARD_RELOAD();
        }
      }
      _legionPausedAt = null;
    }
  }

  void LEGION_HARD_RELOAD() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (context) => LEGION_TABLE(""),
        ),
            (route) => false,
      );
    });
  }

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    FirebaseMessaging.onBackgroundMessage(LEGION_BG_COMMS);

    LEGION_INIT_FCM();
    LEGION_SCAN_DEVICE();
    LEGION_WIRE_FCM_FOREGROUND();
    LEGION_BIND_NOTIFICATION_BELL();

    // можно удалить, если не используется
    Future.delayed(const Duration(seconds: 2), () {});
    Future.delayed(const Duration(seconds: 6), () {});
  }

  void LEGION_WIRE_FCM_FOREGROUND() {
    FirebaseMessaging.onMessage.listen((RemoteMessage msg) {
      if (msg.data['uri'] != null) {
        LEGION_NAVIGATE(msg.data['uri'].toString());
      } else {
        LEGION_RETURN_TO_ROUTE();
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage msg) {
      if (msg.data['uri'] != null) {
        LEGION_NAVIGATE(msg.data['uri'].toString());
      } else {
        LEGION_RETURN_TO_ROUTE();
      }
    });
  }

  void LEGION_NAVIGATE(String newLeg) async {
    if (_legionWebView != null) {
      await _legionWebView.loadUrl(
        urlRequest: URLRequest(url: WebUri(newLeg)),
      );
    }
    _legionCurrentRoute = newLeg;
  }

  void LEGION_RETURN_TO_ROUTE() async {
    Future.delayed(const Duration(seconds: 3), () {
      if (_legionWebView != null) {
        _legionWebView.loadUrl(
          urlRequest: URLRequest(url: WebUri(_legionCurrentRoute)),
        );
      }
    });
  }

  Future<void> LEGION_INIT_FCM() async {
    FirebaseMessaging tower = FirebaseMessaging.instance;
    NotificationSettings perm =
    await tower.requestPermission(alert: true, badge: true, sound: true);
    _legionFcmToken = await tower.getToken();
    debugPrint("LEGION FCM token: $_legionFcmToken");
  }

  Future<void> LEGION_SCAN_DEVICE() async {
    try {
      final dev = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final a = await dev.androidInfo;
        _legionDeviceId = a.id;
        _legionPlatform = "android";
        _legionOsBuild = a.version.release;
      } else if (Platform.isIOS) {
        final i = await dev.iosInfo;
        _legionDeviceId = i.identifierForVendor;
        _legionPlatform = "ios";
        _legionOsBuild = i.systemVersion;
      }
      final pkg = await PackageInfo.fromPlatform();
      _legionLocale = Platform.localeName.split('_')[0];
      _legionTimezone = timezone.local.name;

      debugPrint(
        "LEGION Device: id=$_legionDeviceId; platform=$_legionPlatform; "
            "os=$_legionOsBuild; locale=$_legionLocale; tz=$_legionTimezone; "
            "app=${pkg.packageName} ${pkg.version}",
      );
    } catch (e) {
      debugPrint("Avionics Scan Error: $e");
    }
  }

  /// Колокол уведомлений из нативного слоя
  void LEGION_BIND_NOTIFICATION_BELL() {
    MethodChannel('com.example.fcm/notification')
        .setMethodCallHandler((MethodCall call) async {
      if (call.method == "onNotificationTap") {
        final Map<String, dynamic> payload =
        Map<String, dynamic>.from(call.arguments);
        print("URI from mast: ${payload['uri']}");
        if (payload["uri"] != null &&
            !payload["uri"].toString().contains("Нет URI")) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
              builder: (context) => LEGION_TABLE(payload["uri"]),
            ),
                (route) => false,
          );
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // при каждом build мы дополнительно убеждаемся, что канал привязан
    LEGION_BIND_NOTIFICATION_BELL();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: Stack(
          children: [
            InAppWebView(
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                disableDefaultErrorPage: true,
                mediaPlaybackRequiresUserGesture: false,
                allowsInlineMediaPlayback: true,
                allowsPictureInPictureMediaPlayback: true,
                useOnDownloadStart: true,
                javaScriptCanOpenWindowsAutomatically: true,
                useShouldOverrideUrlLoading: true,
                supportMultipleWindows: true,
              ),
              initialUrlRequest: URLRequest(
                url: WebUri.uri(Uri.parse(_legionCurrentRoute)),
              ),
              onWebViewCreated: (controller) {
                _legionWebView = controller;

                _legionWebView.addJavaScriptHandler(
                  handlerName: 'onServerResponse',
                  callback: (args) {
                    try {
                      final saved = args.isNotEmpty &&
                          args[0] is Map &&
                          args[0]['savedata'].toString() == "false";

                      print("Load True " + args[0].toString());
                      if (saved) {
                        // здесь можно обработать savedata == false
                      }
                    } catch (_) {}
                    if (args.isEmpty) return null;
                    try {
                      return args.reduce((curr, next) => curr + next);
                    } catch (_) {
                      return args.first;
                    }
                  },
                );
              },
              onLoadStart: (controller, uri) async {
                setState(() => _legionLoading = true);

                if (uri != null) {
                  if (LEGION_LOOKS_LIKE_BARE_MAIL(uri)) {
                    try {
                      await controller.stopLoading();
                    } catch (_) {}
                    final mailto = LEGION_TO_MAILTO(uri);
                    await LEGION_OPEN_MAIL_VIA_WEB(mailto);
                    setState(() => _legionLoading = false);
                    return;
                  }
                  final s = uri.scheme.toLowerCase();
                  if (s != 'http' && s != 'https') {
                    try {
                      await controller.stopLoading();
                    } catch (_) {}
                  }
                }
              },
              onLoadStop: (controller, uri) async {
                await controller.evaluateJavascript(
                  source: "console.log('Ahoy from JS!');",
                );
                setState(() => _legionLoading = false);
              },
              onLoadError: (controller, uri, code, message) async {
                setState(() => _legionLoading = false);
              },
              shouldOverrideUrlLoading: (controller, nav) async {
                final uri = nav.request.url;
                if (uri == null) return NavigationActionPolicy.ALLOW;

                if (LEGION_LOOKS_LIKE_BARE_MAIL(uri)) {
                  final mailto = LEGION_TO_MAILTO(uri);
                  await LEGION_OPEN_MAIL_VIA_WEB(mailto);
                  return NavigationActionPolicy.CANCEL;
                }

                final sch = uri.scheme.toLowerCase();
                if (sch == 'mailto') {
                  await LEGION_OPEN_MAIL_VIA_WEB(uri);
                  return NavigationActionPolicy.CANCEL;
                }

                if (LEGION_IS_EXTERNAL_HUB(uri)) {
                  await LEGION_OPEN_EXTERNAL(LEGION_MAP_EXTERNAL_TO_HTTP(uri));
                  return NavigationActionPolicy.CANCEL;
                }

                if (sch != 'http' && sch != 'https') {
                  return NavigationActionPolicy.CANCEL;
                }

                return NavigationActionPolicy.ALLOW;
              },
              onCreateWindow: (controller, req) async {
                final u = req.request.url;
                if (u == null) return false;

                if (LEGION_LOOKS_LIKE_BARE_MAIL(u)) {
                  final m = LEGION_TO_MAILTO(u);
                  await LEGION_OPEN_MAIL_VIA_WEB(m);
                  return false;
                }

                final sch = u.scheme.toLowerCase();
                if (sch == 'mailto') {
                  await LEGION_OPEN_MAIL_VIA_WEB(u);
                  return false;
                }

                if (LEGION_IS_EXTERNAL_HUB(u)) {
                  await LEGION_OPEN_EXTERNAL(LEGION_MAP_EXTERNAL_TO_HTTP(u));
                  return false;
                }

                if (sch == 'http' || sch == 'https') {
                  controller.loadUrl(urlRequest: URLRequest(url: u));
                }
                return false;
              },
            ),

            if (_legionLoading)
              Positioned.fill(
                child: Container(
                  color: Colors.black87,
                  child: const LEGION_WAVE_LOADER(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // =========================
  // LEGION-утилиты навигации/почты
  // =========================

  bool LEGION_LOOKS_LIKE_BARE_MAIL(Uri u) {
    final s = u.scheme;
    if (s.isNotEmpty) return false;
    final raw = u.toString();
    return raw.contains('@') && !raw.contains(' ');
  }

  Uri LEGION_TO_MAILTO(Uri u) {
    final full = u.toString();
    final bits = full.split('?');
    final who = bits.first;
    final qp =
    bits.length > 1 ? Uri.splitQueryString(bits[1]) : <String, String>{};
    return Uri(
      scheme: 'mailto',
      path: who,
      queryParameters: qp.isEmpty ? null : qp,
    );
  }

  bool LEGION_IS_EXTERNAL_HUB(Uri u) {
    final sch = u.scheme.toLowerCase();
    if (_legionHubSchemes.contains(sch)) return true;

    if (sch == 'http' || sch == 'https') {
      final h = u.host.toLowerCase();
      if (_legionHubHosts.contains(h)) return true;
    }
    return false;
  }

  Uri LEGION_MAP_EXTERNAL_TO_HTTP(Uri u) {
    final sch = u.scheme.toLowerCase();

    if (sch == 'tg' || sch == 'telegram') {
      final qp = u.queryParameters;
      final domain = qp['domain'];
      if (domain != null && domain.isNotEmpty) {
        return Uri.https('t.me', '/$domain', {
          if (qp['start'] != null) 'start': qp['start']!,
        });
      }
      final path = u.path.isNotEmpty ? u.path : '';
      return Uri.https(
        't.me',
        '/$path',
        u.queryParameters.isEmpty ? null : u.queryParameters,
      );
    }

    if (sch == 'whatsapp') {
      final qp = u.queryParameters;
      final phone = qp['phone'];
      final text = qp['text'];
      if (phone != null && phone.isNotEmpty) {
        return Uri.https(
          'wa.me',
          '/${LEGION_DIGITS_ONLY(phone)}',
          {if (text != null && text.isNotEmpty) 'text': text},
        );
      }
      return Uri.https(
        'wa.me',
        '/',
        {if (text != null && text.isNotEmpty) 'text': text},
      );
    }

    if (sch == 'bnl') {
      final newPath = u.path.isNotEmpty ? u.path : '';
      return Uri.https(
        'bnl.com',
        '/$newPath',
        u.queryParameters.isEmpty ? null : u.queryParameters,
      );
    }

    return u;
  }

  Future<bool> LEGION_OPEN_MAIL_VIA_WEB(Uri m) async {
    final g = LEGION_GMAIL_COMPOSER(m);
    return await LEGION_OPEN_EXTERNAL(g);
  }

  Uri LEGION_GMAIL_COMPOSER(Uri m) {
    final qp = m.queryParameters;
    final params = <String, String>{
      'view': 'cm',
      'fs': '1',
      if (m.path.isNotEmpty) 'to': m.path,
      if ((qp['subject'] ?? '').isNotEmpty) 'su': qp['subject']!,
      if ((qp['body'] ?? '').isNotEmpty) 'body': qp['body']!,
      if ((qp['cc'] ?? '').isNotEmpty) 'cc': qp['cc']!,
      if ((qp['bcc'] ?? '').isNotEmpty) 'bcc': qp['bcc']!,
    };
    return Uri.https('mail.google.com', '/mail/', params);
  }

  Future<bool> LEGION_OPEN_EXTERNAL(Uri u) async {
    try {
      if (await launchUrl(u, mode: LaunchMode.inAppBrowserView)) {
        return true;
      }
      return await launchUrl(u, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('openExternal error: $e; url=$u');
      try {
        return await launchUrl(u, mode: LaunchMode.externalApplication);
      } catch (_) {
        return false;
      }
    }
  }

  String LEGION_DIGITS_ONLY(String s) =>
      s.replaceAll(RegExp(r'[^0-9+]'), '');
}