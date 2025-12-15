import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform, HttpHeaders, HttpClient;

import 'package:appsflyer_sdk/appsflyer_sdk.dart' as af_core;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show MethodChannel, SystemChrome, SystemUiOverlayStyle;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' as wprov;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as whttp;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart' as wprov_old;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as wtz_data;
import 'package:timezone/timezone.dart' as wtz_zone;
import 'package:url_launcher/url_launcher.dart';
import 'package:winplacearea/pushPLACE.dart';



// ============================================================================
// Константы
// ============================================================================
const String w_loaded_event_sent_once = "loaded_event_sent_once";
const String w_ship_stat_endpoint = "https://app.globalchell.blog/stat";
const String w_cached_fcm_token = "cached_fcm_token";

const Duration w_savedata_timeout = Duration(seconds: 8);
const String w_external_fallback_url = "https://www.facebook.com/";

// ============================================================================
// Сервисы/синглтоны (logger убран, вместо него debugPrint/print)
// ============================================================================
class win_singletons {
  static final win_singletons w_instance = win_singletons._internal();
  win_singletons._internal();
  factory win_singletons() => w_instance;

  final FlutterSecureStorage w_secure_box = const FlutterSecureStorage();
  final Connectivity w_connectivity = Connectivity();
}

// ============================================================================
// Сеть/данные
// ============================================================================
class win_net {
  final win_singletons w_sx = win_singletons();

  Future<bool> w_is_online() async {
    final wState = await w_sx.w_connectivity.checkConnectivity();
    return wState != ConnectivityResult.none;
  }

  Future<void> w_post_json(String wUrl, Map<String, dynamic> wBody) async {
    try {
      await whttp.post(
        Uri.parse(wUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(wBody),
      );
    } catch (e) {
      debugPrint("w_post_json error: $e");
    }
  }
}

// ============================================================================
// Досье устройства
// ============================================================================
class win_device_card {
  String? w_device_id;
  String? w_session_id = "mafia-one-off";
  String? w_platform;
  String? w_os_version;
  String? w_app_version;
  String? w_language;
  String? w_timezone;
  bool w_push_enabled = true;

  Future<void> w_collect() async {
    final wInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final wAndroid = await wInfo.androidInfo;
      w_device_id = wAndroid.id;
      w_platform = "android";
      w_os_version = wAndroid.version.release;
    } else if (Platform.isIOS) {
      final wIos = await wInfo.iosInfo;
      w_device_id = wIos.identifierForVendor;
      w_platform = "ios";
      w_os_version = wIos.systemVersion;
    }
    final wPackage = await PackageInfo.fromPlatform();
    w_app_version = wPackage.version;
    w_language = Platform.localeName.split('_')[0];
    w_timezone = wtz_zone.local.name;
    w_session_id = "voyage-${DateTime.now().millisecondsSinceEpoch}";
  }

  Map<String, dynamic> w_to_map({String? w_fcm_token}) => {
    "fcm_token": w_fcm_token ?? 'missing_token',
    "device_id": w_device_id ?? 'missing_id',
    "app_name": "winpl",
    "instance_id": w_session_id ?? 'missing_session',
    "platform": w_platform ?? 'missing_system',
    "os_version": w_os_version ?? 'missing_build',
    "app_version": w_app_version ?? 'missing_app',
    "language": w_language ?? 'en',
    "timezone": w_timezone ?? 'UTC',
    "push_enabled": w_push_enabled,
  };
}

// ============================================================================
// AppsFlyer
// ============================================================================
class win_af_tracker with ChangeNotifier {
  af_core.AppsFlyerOptions? w_af_options;
  af_core.AppsflyerSdk? w_af_sdk;

  String w_af_uid = "";
  String w_af_data = "";

  void w_init_af(VoidCallback wOnChange) {
    final wCfg = af_core.AppsFlyerOptions(
      afDevKey: "qsBLmy7dAXDQhowM8V3ca4",
      appId: "6756575493",
      showDebug: true,
      timeToWaitForATTUserAuthorization: 0,
    );
    w_af_options = wCfg;
    w_af_sdk = af_core.AppsflyerSdk(wCfg);

    w_af_sdk?.initSdk(
      registerConversionDataCallback: true,
      registerOnAppOpenAttributionCallback: true,
      registerOnDeepLinkingCallback: true,
    );
    w_af_sdk?.startSDK(
      onSuccess: () => debugPrint("AppsFlyer started"),
      onError: (int wCode, String wMsg) =>
          debugPrint("AppsFlyer error $wCode: $wMsg"),
    );
    w_af_sdk?.onInstallConversionData((wData) {
      w_af_data = wData.toString();
      wOnChange();
      notifyListeners();
    });
    w_af_sdk?.getAppsFlyerUID().then((wVal) {
      w_af_uid = wVal.toString();
      wOnChange();
      notifyListeners();
    });
  }
}

// ============================================================================
// Riverpod/Provider
// ============================================================================
final win_device_provider =
wprov.FutureProvider<win_device_card>((w_ref) async {
  final wCard = win_device_card();
  await wCard.w_collect();
  return wCard;
});

final win_af_provider = wprov_old.ChangeNotifierProvider<win_af_tracker>(
  create: (_) => win_af_tracker(),
);

// ============================================================================
// FCM Background
// ============================================================================
@pragma('vm:entry-point')
Future<void> win_bg_fcm(RemoteMessage wMsg) async {
  debugPrint("win_bg_fcm: ${wMsg.messageId}");
  debugPrint("win_bg_fcm data: ${wMsg.data}");
}

// ============================================================================
// Мост для FCM токена
// ============================================================================
class win_fcm_bridge extends ChangeNotifier {
  final win_singletons w_sx = win_singletons();
  String? w_token;
  final List<void Function(String)> w_waiters = [];

  win_fcm_bridge() {
    const MethodChannel('com.example.fcm/token')
        .setMethodCallHandler((w_call) async {
      if (w_call.method == 'setToken') {
        final String wVal = w_call.arguments as String;
        if (wVal.isNotEmpty) {
          w_apply_token(wVal);
        }
      }
    });
    w_restore_token();
  }

  Future<void> w_restore_token() async {
    try {
      final wPrefs = await SharedPreferences.getInstance();
      final wCached = wPrefs.getString(w_cached_fcm_token);
      if (wCached != null && wCached.isNotEmpty) {
        w_apply_token(wCached, w_notify_native: false);
      } else {
        final wSecure =
        await w_sx.w_secure_box.read(key: w_cached_fcm_token);
        if (wSecure != null && wSecure.isNotEmpty) {
          w_apply_token(wSecure, w_notify_native: false);
        }
      }
    } catch (_) {}
  }

  void w_apply_token(String wVal, {bool w_notify_native = true}) async {
    w_token = wVal;
    try {
      final wPrefs = await SharedPreferences.getInstance();
      await wPrefs.setString(w_cached_fcm_token, wVal);
      await w_sx.w_secure_box.write(key: w_cached_fcm_token, value: wVal);
    } catch (_) {}
    for (final w_cb in List.of(w_waiters)) {
      try {
        w_cb(wVal);
      } catch (e) {
        debugPrint("win_fcm waiter error: $e");
      }
    }
    w_waiters.clear();
    notifyListeners();
  }

  Future<void> w_await_token(Function(String) wOnToken) async {
    try {
      await FirebaseMessaging.instance
          .requestPermission(alert: true, badge: true, sound: true);
      if (w_token != null && w_token!.isNotEmpty) {
        wOnToken(w_token!);
        return;
      }
      w_waiters.add(wOnToken);
    } catch (e) {
      debugPrint("win_fcm_bridge awaitToken error: $e");
    }
  }
}

// ============================================================================
// WIN Loader — разноцветные «W I N» пульсируют по очереди
// ============================================================================
class win_loader extends StatefulWidget {
  const win_loader({super.key});

  @override
  State<win_loader> createState() => win_loader_state();
}

class win_loader_state extends State<win_loader>
    with SingleTickerProviderStateMixin {
  late AnimationController w_anim_ctrl;

  @override
  void initState() {
    super.initState();
    w_anim_ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void dispose() {
    w_anim_ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const wChars = ['W', 'I', 'N'];
    const wColors = [
      Colors.red,
      Colors.green,
      Colors.blue,
    ];

    return Container(
      color: Colors.black,
      child: Center(
        child: AnimatedBuilder(
          animation: w_anim_ctrl,
          builder: (context, _) {
            final wT = w_anim_ctrl.value; // 0..1
            final wWidgets = <Widget>[];

            for (int i = 0; i < wChars.length; i++) {
              // Фаза для каждой буквы (сдвиг)
              final wPhase = (wT + i / wChars.length) % 1.0;
              // Плавная пульсация размера 0..1..0
              final wScale = 0.7 + 0.6 * (1 - (2 * (wPhase - 0.5)).abs());
              final wColorMix = Color.lerp(
                wColors[i],
                Colors.white,
                0.4 * (1 - (2 * (wPhase - 0.5)).abs()),
              )!;

              wWidgets.add(Transform.scale(
                scale: wScale,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    wChars[i],
                    style: TextStyle(
                      fontSize: 42,
                      fontWeight: FontWeight.w900,
                      color: wColorMix,
                      shadows: [
                        Shadow(
                          color: wColorMix.withOpacity(0.5),
                          blurRadius: 18 * wScale,
                        ),
                      ],
                    ),
                  ),
                ),
              ));
            }

            return Row(
              mainAxisSize: MainAxisSize.min,
              children: wWidgets,
            );
          },
        ),
      ),
    );
  }
}

// ============================================================================
// Splash
// ============================================================================
class win_splash_page extends StatefulWidget {
  const win_splash_page({super.key});

  @override
  State<win_splash_page> createState() => win_splash_page_state();
}

class win_splash_page_state extends State<win_splash_page> {
  final win_fcm_bridge w_bridge = win_fcm_bridge();
  bool w_done = false;
  Timer? w_timeout;

  @override
  void initState() {
    super.initState();

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.black,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ));

    w_bridge.w_await_token((wSig) => w_go_next(wSig));
    w_timeout = Timer(const Duration(seconds: 8), () => w_go_next(''));
  }

  void w_go_next(String wSig) {
    if (w_done) return;
    w_done = true;
    w_timeout?.cancel();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => win_main_web(signal: wSig),
      ),
    );
  }

  @override
  void dispose() {
    w_timeout?.cancel();
    w_bridge.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(child: win_loader()),
    );
  }
}

// ============================================================================
// MVVM
// ============================================================================
class win_view_model with ChangeNotifier {
  final win_device_card w_device;
  final win_af_tracker w_af;

  win_view_model({required this.w_device, required this.w_af});

  Map<String, dynamic> w_device_payload(String? wToken) =>
      w_device.w_to_map(w_fcm_token: wToken);

  Map<String, dynamic> w_af_payload(String? wToken) => {
    "content": {
      "af_data": w_af.w_af_data,
      "af_id": w_af.w_af_uid,
      "fb_app_name": "winpl",
      "app_name": "winpl",
      "deep": null,
      "bundle_identifier": "com.qiwinpla.winpl.winplplpl",
      "app_version": "1.0.0",
      "apple_id": "6756575493",
      "fcm_token": wToken ?? "no_token",
      "device_id": w_device.w_device_id ?? "no_device",
      "instance_id": w_device.w_session_id ?? "no_instance",
      "platform": w_device.w_platform ?? "no_type",
      "os_version": w_device.w_os_version ?? "no_os",
      "app_version": w_device.w_app_version ?? "no_app",
      "language": w_device.w_language ?? "en",
      "timezone": w_device.w_timezone ?? "UTC",
      "push_enabled": w_device.w_push_enabled,
      "useruid": w_af.w_af_uid,
    },
  };
}

class win_courier {
  final win_view_model w_model;
  final InAppWebViewController Function() w_get_web;

  win_courier({required this.w_model, required this.w_get_web});

  Future<void> w_put_device_to_local_storage(String? wToken) async {
    final wMap = w_model.w_device_payload(wToken);

    await w_get_web().evaluateJavascript(
      source:
      "localStorage.setItem('app_data', JSON.stringify(${jsonEncode(wMap)}));",
    );
  }

  Future<void> w_send_raw_to_js(String? wToken) async {
    final wPayload = w_model.w_af_payload(wToken);
    final wJson = jsonEncode(wPayload);
    print("SendRawData: $wJson");
    await w_get_web().evaluateJavascript(
      source: "sendRawData(${jsonEncode(wJson)});",
    );
  }
}

// ============================================================================
// Переходы/статистика
// ============================================================================
Future<String> w_resolve_final_url(String wStart,
    {int w_max_hops = 10}) async {
  final wClient = HttpClient();

  try {
    var wCurrent = Uri.parse(wStart);
    for (int i = 0; i < w_max_hops; i++) {
      final wReq = await wClient.getUrl(wCurrent);
      wReq.followRedirects = false;
      final wRes = await wReq.close();
      if (wRes.isRedirect) {
        final wLoc = wRes.headers.value(HttpHeaders.locationHeader);
        if (wLoc == null || wLoc.isEmpty) break;
        final wNext = Uri.parse(wLoc);
        wCurrent = wNext.hasScheme ? wNext : wCurrent.resolveUri(wNext);
        continue;
      }
      return wCurrent.toString();
    }
    return wCurrent.toString();
  } catch (e) {
    debugPrint("w_resolve_final_url error: $e");
    return wStart;
  } finally {
    wClient.close(force: true);
  }
}

Future<void> w_post_stat({
  required String w_event,
  required int w_time_start,
  required String w_url,
  required int w_time_finish,
  required String w_app_sid,
  int? w_first_page_load_ts,
}) async {
  try {
    final wFinal = await w_resolve_final_url(w_url);
    final wPayload = {
      "event": w_event,
      "timestart": w_time_start,
      "timefinsh": w_time_finish,
      "url": wFinal,
      "appleID": "6756575493",
      "open_count": "$w_app_sid/$w_time_start",
    };

    debugPrint("loadingstatinsic $wPayload");
    final wRes = await whttp.post(
      Uri.parse("$w_ship_stat_endpoint/$w_app_sid"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode(wPayload),
    );
    debugPrint(" ur _loaded$w_ship_stat_endpoint/$w_app_sid");
    debugPrint("_postStat status=${wRes.statusCode} body=${wRes.body}");
  } catch (e) {
    debugPrint("_postStat error: $e");
  }
}

// ============================================================================
// Экран внешнего URL (фолбэк)
// ============================================================================
class win_external_web extends StatefulWidget {
  final String w_url;

  const win_external_web({super.key, required this.w_url});

  @override
  State<win_external_web> createState() => win_external_web_state();
}

class win_external_web_state extends State<win_external_web> {
  InAppWebViewController? w_ctrl;
  double w_progress = 0.0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: InAppWebView(
          initialUrlRequest: URLRequest(url: WebUri(widget.w_url)),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            mediaPlaybackRequiresUserGesture: false,
            allowsInlineMediaPlayback: true,
            useOnDownloadStart: true,
          ),
          onWebViewCreated: (c) => w_ctrl = c,
          onProgressChanged: (c, p) {
            setState(() => w_progress = p / 100);
          },
        ),
      ),
    );
  }
}

// ============================================================================
// Главный WebView
// ============================================================================
class win_main_web extends StatefulWidget {
  final String? signal;
  const win_main_web({super.key, required this.signal});

  @override
  State<win_main_web> createState() => win_main_web_state();
}

class win_main_web_state extends State<win_main_web>
    with WidgetsBindingObserver {
  late InAppWebViewController w_web_ctrl;
  bool w_busy = false;
  final String w_home_url = "https://app.globalchell.blog/";
  final win_device_card w_device = win_device_card();
  final win_af_tracker w_af = win_af_tracker();

  int w_reload_key = 0;
  DateTime? w_paused_at;
  bool w_veil = false;
  double w_progress_rel = 0.0;
  late Timer w_progress_timer;
  final int w_warmup_secs = 6;
  bool w_cover = true;

  bool w_loaded_event_sent = false;
  int? w_first_page_stamp;

  win_courier? w_courier;
  win_view_model? w_vm;

  String w_current_url = "";
  int w_start_load_ts = 0;

  Timer? w_savedata_timer;
  bool w_savedata_arrived = false;
  bool w_navigated_fallback = false;

  final Set<String> w_schemes = {
    'tg',
    'telegram',
    'whatsapp',
    'viber',
    'skype',
    'fb-messenger',
    'sgnl',
    'tel',
    'mailto',
    'bnl',
    'fb',
    'instagram',
    'twitter',
    'x',
  };

  final Set<String> w_external_hosts = {
    't.me',
    'telegram.me',
    'telegram.dog',
    'wa.me',
    'api.whatsapp.com',
    'chat.whatsapp.com',
    'm.me',
    'signal.me',
    'bnl.com',
    'www.bnl.com',
    'x.com',
    'www.x.com',
    'twitter.com',
    'www.twitter.com',
    'facebook.com',
    'www.facebook.com',
    'm.facebook.com',
    'instagram.com',
    'www.instagram.com',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    w_first_page_stamp = DateTime.now().millisecondsSinceEpoch;

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => w_cover = false);
    });
    Future.delayed(const Duration(seconds: 7), () {
      if (!mounted) return;
      setState(() => w_veil = true);
    });
    Future.delayed(const Duration(seconds: 7), () {
    w_push_device_data();
    w_push_af_data();
    });

    w_boot();
  }

  Future<void> w_load_flag() async {
    final wPrefs = await SharedPreferences.getInstance();
    w_loaded_event_sent = wPrefs.getBool(w_loaded_event_sent_once) ?? false;
  }

  Future<void> w_save_flag() async {
    final wPrefs = await SharedPreferences.getInstance();
    await wPrefs.setBool(w_loaded_event_sent_once, true);
    w_loaded_event_sent = true;
  }

  Future<void> w_send_loaded_once(
      {required String w_url, required int w_timestart}) async {
    if (w_loaded_event_sent) {
      debugPrint("Loaded already sent, skipping");
      return;
    }
    final wNow = DateTime.now().millisecondsSinceEpoch;
    await w_post_stat(
      w_event: "Loaded",
      w_time_start: w_timestart,
      w_time_finish: wNow,
      w_url: w_url,
      w_app_sid: w_af.w_af_uid,
      w_first_page_load_ts: w_first_page_stamp,
    );
    await w_save_flag();
  }

  void w_boot() {
    w_start_progress();
    w_wire_fcm();
    w_af.w_init_af(() => setState(() {}));
    w_bind_notification_channel();
    w_prepare_device();
  }

  void w_wire_fcm() {
    FirebaseMessaging.onMessage.listen((wMsg) {
      final wLink = wMsg.data['uri'];
      if (wLink != null) {
        w_navigate(wLink.toString());
      } else {
        w_reset_home();
      }
    });
    FirebaseMessaging.onMessageOpenedApp.listen((wMsg) {
      final wLink = wMsg.data['uri'];
      if (wLink != null) {
        w_navigate(wLink.toString());
      } else {
        w_reset_home();
      }
    });
  }

  void w_bind_notification_channel() {
    MethodChannel('com.example.fcm/notification')
        .setMethodCallHandler((wCall) async {
      if (wCall.method == "onNotificationTap") {
        final Map<String, dynamic> wPayload =
        Map<String, dynamic>.from(wCall.arguments);
        if (wPayload["uri"] != null &&
            !wPayload["uri"].toString().contains("Нет URI")) {
          if (!mounted) return;
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  LEGION_TABLE(wPayload["uri"].toString()),
            ),
                (route) => false,
          );
        }
      }
    });
  }

  Future<void> w_prepare_device() async {
    try {
      await w_device.w_collect();
      await w_request_push_perm();
      w_vm ??= win_view_model(w_device: w_device, w_af: w_af);
      w_courier ??=
          win_courier(w_model: w_vm!, w_get_web: () => w_web_ctrl);
      await w_load_flag();
    } catch (e) {
      debugPrint("prepare-device error: $e");
    }
  }

  Future<void> w_request_push_perm() async {
    await FirebaseMessaging.instance
        .requestPermission(alert: true, badge: true, sound: true);
  }

  void w_navigate(String wLink) async {
    try {
      await w_web_ctrl.loadUrl(urlRequest: URLRequest(url: WebUri(wLink)));
    } catch (_) {}
  }

  void w_reset_home() async {
    Future.delayed(const Duration(seconds: 3), () {
      try {
        w_web_ctrl.loadUrl(urlRequest: URLRequest(url: WebUri(w_home_url)));
      } catch (_) {}
    });
  }

  Future<void> w_push_device_data() async {
    debugPrint("TOKEN ship ${widget.signal}");
    try {
      await w_courier?.w_put_device_to_local_storage(widget.signal);
    } catch (e) {
      debugPrint("putDeviceToLocalStorage failed: $e");
    }
  }

  Future<void> w_push_af_data() async {
    try {
      await w_courier?.w_send_raw_to_js(widget.signal);
    } catch (e) {
      debugPrint("sendRawToWeb failed: $e");
    }
  }

  void w_start_progress() {
    int wCnt = 0;
    w_progress_rel = 0.0;
    w_progress_timer =
        Timer.periodic(const Duration(milliseconds: 100), (wT) {
          if (!mounted) return;
          setState(() {
            wCnt++;
            w_progress_rel = wCnt / (w_warmup_secs * 10);
            if (w_progress_rel >= 1.0) {
              w_progress_rel = 1.0;
              w_progress_timer.cancel();
            }
          });
        });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState wState) {
    if (wState == AppLifecycleState.paused) {
      w_paused_at = DateTime.now();
    }
    if (wState == AppLifecycleState.resumed) {
      if (Platform.isIOS && w_paused_at != null) {
        final wNow = DateTime.now();
        final wDiff = wNow.difference(w_paused_at!);
        if (wDiff > const Duration(minutes: 25)) {
          w_full_reload();
        }
      }
      w_paused_at = null;
    }
  }

  void w_full_reload() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (context) => win_main_web(signal: widget.signal),
        ),
            (route) => false,
      );
    });
  }

  bool w_is_bare_mail(Uri wU) {
    final wScheme = wU.scheme;
    if (wScheme.isNotEmpty) return false;
    final wRaw = wU.toString();
    return wRaw.contains('@') && !wRaw.contains(' ');
  }

  Uri w_to_mailto(Uri wU) {
    final wFull = wU.toString();
    final wParts = wFull.split('?');
    final wEmail = wParts.first;
    final wQp =
    wParts.length > 1 ? Uri.splitQueryString(wParts[1]) : <String, String>{};
    return Uri(
      scheme: 'mailto',
      path: wEmail,
      queryParameters: wQp.isEmpty ? null : wQp,
    );
  }

  bool w_is_platformish(Uri wU) {
    final wS = wU.scheme.toLowerCase();
    if (w_schemes.contains(wS)) return true;

    if (wS == 'http' || wS == 'https') {
      final wH = wU.host.toLowerCase();
      if (w_external_hosts.contains(wH)) return true;
      if (wH.endsWith('t.me')) return true;
      if (wH.endsWith('wa.me')) return true;
      if (wH.endsWith('m.me')) return true;
      if (wH.endsWith('signal.me')) return true;
      if (wH.endsWith('x.com')) return true;
      if (wH.endsWith('twitter.com')) return true;
      if (wH.endsWith('facebook.com')) return true;
      if (wH.endsWith('instagram.com')) return true;
    }
    return false;
  }

  Uri w_normalize_http(Uri wU) {
    final wS = wU.scheme.toLowerCase();

    if (wS == 'tg' || wS == 'telegram') {
      final wQp = wU.queryParameters;
      final wDomain = wQp['domain'];
      if (wDomain != null && wDomain.isNotEmpty) {
        return Uri.https(
          't.me',
          '/$wDomain',
          {if (wQp['start'] != null) 'start': wQp['start']!},
        );
      }
      final wPath = wU.path.isNotEmpty ? wU.path : '';
      return Uri.https(
        't.me',
        '/$wPath',
        wU.queryParameters.isEmpty ? null : wU.queryParameters,
      );
    }

    if ((wS == 'http' || wS == 'https') &&
        wU.host.toLowerCase().endsWith('t.me')) {
      return wU;
    }

    if (wS == 'viber') return wU;

    if (wS == 'whatsapp') {
      final wQp = wU.queryParameters;
      final wPhone = wQp['phone'];
      final wText = wQp['text'];
      if (wPhone != null && wPhone.isNotEmpty) {
        return Uri.https(
          'wa.me',
          '/${w_digits(wPhone)}',
          {if (wText != null && wText.isNotEmpty) 'text': wText},
        );
      }
      return Uri.https(
        'wa.me',
        '/',
        {if (wText != null && wText.isNotEmpty) 'text': wText},
      );
    }

    if ((wS == 'http' || wS == 'https') &&
        (wU.host.toLowerCase().endsWith('wa.me') ||
            wU.host.toLowerCase().endsWith('whatsapp.com'))) {
      return wU;
    }

    if (wS == 'skype') return wU;

    if (wS == 'fb-messenger') {
      final wPath =
      wU.pathSegments.isNotEmpty ? wU.pathSegments.join('/') : '';
      final wQp = wU.queryParameters;
      final wId = wQp['id'] ?? wQp['user'] ?? wPath;
      if (wId.isNotEmpty) {
        return Uri.https(
          'm.me',
          '/$wId',
          wU.queryParameters.isEmpty ? null : wU.queryParameters,
        );
      }
      return Uri.https(
        'm.me',
        '/',
        wU.queryParameters.isEmpty ? null : wU.queryParameters,
      );
    }

    if (wS == 'sgnl') {
      final wQp = wU.queryParameters;
      final wPh = wQp['phone'];
      final wUn = wU.queryParameters['username'];
      if (wPh != null && wPh.isNotEmpty) {
        return Uri.https('signal.me', '/#p/${w_digits(wPh)}');
      }
      if (wUn != null && wUn.isNotEmpty) {
        return Uri.https('signal.me', '/#u/$wUn');
      }
      final wPath = wU.pathSegments.join('/');
      if (wPath.isNotEmpty) {
        return Uri.https(
          'signal.me',
          '/$wPath',
          wU.queryParameters.isEmpty ? null : wU.queryParameters,
        );
      }
      return wU;
    }

    if (wS == 'tel') {
      return Uri.parse('tel:${w_digits(wU.path)}');
    }

    if (wS == 'mailto') return wU;

    if (wS == 'bnl') {
      final wNewPath = wU.path.isNotEmpty ? wU.path : '';
      return Uri.https(
        'bnl.com',
        '/$wNewPath',
        wU.queryParameters.isEmpty ? null : wU.queryParameters,
      );
    }

    if ((wS == 'http' || wS == 'https')) {
      final wHost = wU.host.toLowerCase();
      if (wHost.endsWith('x.com') ||
          wHost.endsWith('twitter.com') ||
          wHost.endsWith('facebook.com') ||
          wHost.startsWith('m.facebook.com') ||
          wHost.endsWith('instagram.com')) {
        return wU;
      }
    }

    if (wS == 'fb' || wS == 'instagram' || wS == 'twitter' || wS == 'x') {
      return wU;
    }

    return wU;
  }

  Future<bool> w_open_mail_web(Uri wMailto) async {
    final wUri = w_gmail_like(wMailto);
    return await w_open_web(wUri);
  }

  Uri w_gmail_like(Uri wM) {
    final wQp = wM.queryParameters;
    final wParams = <String, String>{
      'view': 'cm',
      'fs': '1',
      if (wM.path.isNotEmpty) 'to': wM.path,
      if ((wQp['subject'] ?? '').isNotEmpty) 'su': wQp['subject']!,
      if ((wQp['body'] ?? '').isNotEmpty) 'body': wQp['body']!,
      if ((wQp['cc'] ?? '').isNotEmpty) 'cc': wQp['cc']!,
      if ((wQp['bcc'] ?? '').isNotEmpty) 'bcc': wQp['bcc']!,
    };
    return Uri.https('mail.google.com', '/mail/', wParams);
  }

  Future<bool> w_open_web(Uri wU) async {
    try {
      if (await launchUrl(wU, mode: LaunchMode.inAppBrowserView)) {
        return true;
      }
      return await launchUrl(wU, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('openInAppBrowser error: $e; url=$wU');
      try {
        return await launchUrl(wU, mode: LaunchMode.externalApplication);
      } catch (_) {
        return false;
      }
    }
  }

  String w_digits(String wS) =>
      wS.replaceAll(RegExp(r'[^0-9+]'), '');

  void w_start_savedata_timer() {
    w_cancel_savedata_timer();
    w_savedata_arrived = false;
    w_navigated_fallback = false;


  }

  void w_cancel_savedata_timer() {
    w_savedata_timer?.cancel();
    w_savedata_timer = null;
  }



  void w_go_fallback(String wUrl) {
    if (w_navigated_fallback || !mounted) return;
    w_navigated_fallback = true;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => win_external_web(w_url: wUrl),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    w_progress_timer.cancel();
    w_cancel_savedata_timer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    w_bind_notification_channel();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            if (w_cover)
              const win_loader()
            else
              Container(
                color: Colors.black,
                child: Stack(
                  children: [
                    InAppWebView(
                      key: ValueKey(w_reload_key),
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
                        transparentBackground: true,
                      ),
                      initialUrlRequest:
                      URLRequest(url: WebUri(w_home_url)),
                      onWebViewCreated: (c) {
                        w_web_ctrl = c;
                        w_vm ??=
                            win_view_model(w_device: w_device, w_af: w_af);
                        w_courier ??= win_courier(
                          w_model: w_vm!,
                          w_get_web: () => w_web_ctrl,
                        );

                        w_web_ctrl.addJavaScriptHandler(
                          handlerName: 'onServerResponse',
                          callback: (wArgs) {

                            print("save data $wArgs");
                            try {
                              final String wS = (wArgs.isNotEmpty
                                  ? (wArgs[0]?.toString() ?? '')
                                  : '')
                                  .trim();
                              debugPrint("onServerResponse raw: '$wS'");
                              if (wS.isNotEmpty) {
                                //w_mark_savedata_arrived();
                              }
                            } catch (e) {
                              debugPrint(
                                  "onServerResponse parse error: $e");
                            }
                            if (wArgs.isEmpty) return null;
                            try {
                              return wArgs
                                  .reduce((wCurr, wNext) => wCurr + wNext);
                            } catch (_) {
                              return wArgs.first;
                            }
                          },
                        );
                      },
                      onLoadStart: (c, u) async {
                        setState(() {
                          w_start_load_ts =
                              DateTime.now().millisecondsSinceEpoch;
                          w_busy = true;
                        });

                        if ((u?.toString() ?? '').startsWith(w_home_url)) {
                          w_start_savedata_timer();
                        }

                        final wUri = u;
                        if (wUri != null) {
                          if (w_is_bare_mail(wUri)) {
                            try {
                              await c.stopLoading();
                            } catch (_) {}
                            final wMailto = w_to_mailto(wUri);
                            await w_open_mail_web(wMailto);
                            return;
                          }
                          final wSch = wUri.scheme.toLowerCase();
                          if (wSch != 'http' && wSch != 'https') {
                            try {
                              await c.stopLoading();
                            } catch (_) {}
                          }
                        }
                      },
                      onLoadError: (controller, url, code, message) async {
                        final wNow =
                            DateTime.now().millisecondsSinceEpoch;
                        final wEv =
                            "InAppWebViewError(code=$code, message=$message)";
                        await w_post_stat(
                          w_event: wEv,
                          w_time_start: wNow,
                          w_time_finish: wNow,
                          w_url: url?.toString() ?? '',
                          w_app_sid: w_af.w_af_uid,
                          w_first_page_load_ts: w_first_page_stamp,
                        );
                        if (mounted) setState(() => w_busy = false);
                      },
                      onReceivedHttpError:
                          (controller, request, errorResponse) async {
                        final wNow =
                            DateTime.now().millisecondsSinceEpoch;
                        final wEv =
                            "HTTPError(status=${errorResponse.statusCode}, reason=${errorResponse.reasonPhrase})";
                        await w_post_stat(
                          w_event: wEv,
                          w_time_start: wNow,
                          w_time_finish: wNow,
                          w_url: request.url.toString() ?? '',
                          w_app_sid: w_af.w_af_uid,
                          w_first_page_load_ts: w_first_page_stamp,
                        );
                      },
                      onReceivedError:
                          (controller, request, error) async {
                        final wNow =
                            DateTime.now().millisecondsSinceEpoch;
                        final wDesc =
                        (error.description ?? '').toString();
                        final wEv =
                            "WebResourceError(code=$error, message=$wDesc)";
                        await w_post_stat(
                          w_event: wEv,
                          w_time_start: wNow,
                          w_time_finish: wNow,
                          w_url: request.url.toString() ?? '',
                          w_app_sid: w_af.w_af_uid,
                          w_first_page_load_ts: w_first_page_stamp,
                        );
                      },
                      onLoadStop: (c, u) async {
                        await c.evaluateJavascript(
                            source: "console.log('Harbor up!');");

                        await w_push_device_data();
                        await w_push_af_data();

                        setState(() => w_current_url = u.toString());

                        Future.delayed(const Duration(seconds: 20), () {
                          w_send_loaded_once(
                            w_url: w_current_url.toString(),
                            w_timestart: w_start_load_ts,
                          );
                        });

                        if (mounted) setState(() => w_busy = false);
                      },
                      shouldOverrideUrlLoading:
                          (controller, action) async {
                        final wUri = action.request.url;
                        if (wUri == null) {
                          return NavigationActionPolicy.ALLOW;
                        }

                        if (w_is_bare_mail(wUri)) {
                          final wMailto = w_to_mailto(wUri);
                          await w_open_mail_web(wMailto);
                          return NavigationActionPolicy.CANCEL;
                        }

                        final wSch = wUri.scheme.toLowerCase();

                        if (wSch == 'mailto') {
                          await w_open_mail_web(wUri);
                          return NavigationActionPolicy.CANCEL;
                        }

                        if (wSch == 'tel') {
                          await launchUrl(wUri,
                              mode: LaunchMode.externalApplication);
                          return NavigationActionPolicy.CANCEL;
                        }

                        if (w_is_platformish(wUri)) {
                          final wWebUri = w_normalize_http(wUri);

                          final wHost =
                          (wWebUri.host.isNotEmpty
                              ? wWebUri.host
                              : wUri.host)
                              .toLowerCase();
                          final wIsSocial = wHost.endsWith('x.com') ||
                              wHost.endsWith('twitter.com') ||
                              wHost.endsWith('facebook.com') ||
                              wHost.startsWith('m.facebook.com') ||
                              wHost.endsWith('instagram.com') ||
                              wHost.endsWith('t.me') ||
                              wHost.endsWith('telegram.me') ||
                              wHost.endsWith('telegram.dog');

                          if (wIsSocial) {
                            await w_open_web(
                              wWebUri.scheme == 'http' ||
                                  wWebUri.scheme == 'https'
                                  ? wWebUri
                                  : wUri,
                            );
                            return NavigationActionPolicy.CANCEL;
                          }

                          if (wWebUri.scheme == 'http' ||
                              wWebUri.scheme == 'https') {
                            await w_open_web(wWebUri);
                          } else {
                            try {
                              if (await canLaunchUrl(wUri)) {
                                await launchUrl(wUri,
                                    mode:
                                    LaunchMode.externalApplication);
                              } else if (wWebUri != wUri &&
                                  (wWebUri.scheme == 'http' ||
                                      wWebUri.scheme == 'https')) {
                                await w_open_web(wWebUri);
                              }
                            } catch (_) {}
                          }
                          return NavigationActionPolicy.CANCEL;
                        }

                        if (wSch != 'http' && wSch != 'https') {
                          return NavigationActionPolicy.CANCEL;
                        }

                        return NavigationActionPolicy.ALLOW;
                      },
                      onCreateWindow: (controller, request) async {
                        final wUri = request.request.url;
                        if (wUri == null) return false;

                        if (w_is_bare_mail(wUri)) {
                          final wMailto = w_to_mailto(wUri);
                          await w_open_mail_web(wMailto);
                          return false;
                        }

                        final wSch = wUri.scheme.toLowerCase();

                        if (wSch == 'mailto') {
                          await w_open_mail_web(wUri);
                          return false;
                        }

                        if (wSch == 'tel') {
                          await launchUrl(wUri,
                              mode: LaunchMode.externalApplication);
                          return false;
                        }

                        if (w_is_platformish(wUri)) {
                          final wWebUri = w_normalize_http(wUri);

                          final wHost =
                          (wWebUri.host.isNotEmpty
                              ? wWebUri.host
                              : wUri.host)
                              .toLowerCase();
                          final wIsSocial = wHost.endsWith('x.com') ||
                              wHost.endsWith('twitter.com') ||
                              wHost.endsWith('facebook.com') ||
                              wHost.startsWith('m.facebook.com') ||
                              wHost.endsWith('instagram.com') ||
                              wHost.endsWith('t.me') ||
                              wHost.endsWith('telegram.me') ||
                              wHost.endsWith('telegram.dog');

                          if (wIsSocial) {
                            await w_open_web(
                              wWebUri.scheme == 'http' ||
                                  wWebUri.scheme == 'https'
                                  ? wWebUri
                                  : wUri,
                            );
                            return false;
                          }

                          if (wWebUri.scheme == 'http' ||
                              wWebUri.scheme == 'https') {
                            await w_open_web(wWebUri);
                          } else {
                            try {
                              if (await canLaunchUrl(wUri)) {
                                await launchUrl(wUri,
                                    mode:
                                    LaunchMode.externalApplication);
                              } else if (wWebUri != wUri &&
                                  (wWebUri.scheme == 'http' ||
                                      wWebUri.scheme == 'https')) {
                                await w_open_web(wWebUri);
                              }
                            } catch (_) {}
                          }
                          return false;
                        }

                        if (wSch == 'http' || wSch == 'https') {
                          controller.loadUrl(
                            urlRequest: URLRequest(url: wUri),
                          );
                        }
                        return false;
                      },
                      onDownloadStartRequest:
                          (controller, request) async {
                        await w_open_web(request.url);
                      },
                    ),
                    Visibility(
                      visible: !w_veil,
                      child: const win_loader(),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}




// ============================================================================
// main()
// ============================================================================
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(win_bg_fcm);

  if (Platform.isAndroid) {
    await InAppWebViewController.setWebContentsDebuggingEnabled(true);
  }
  wtz_data.initializeTimeZones();

  runApp(
    wprov_old.MultiProvider(
      providers: [
        win_af_provider,
      ],
      child: wprov.ProviderScope(
        child: const MaterialApp(
          debugShowCheckedModeBanner: false,
          home: win_splash_page(),
        ),
      ),
    ),
  );
}