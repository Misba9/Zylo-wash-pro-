// Zylo Customer App — Flutter (PRD §5) · UI matched to approved design mockups.
// Demo mode mirrors Firestore/Functions; production: replace DemoStore calls
// with cloud_functions callables (createBooking / createPaymentOrder / verifyPayment).
import 'dart:async';
import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:app_links/app_links.dart';
import 'firebase_options.dart';
import 'firebase_options_prod.dart';
import 'data/app_data.dart';
export 'data/app_data.dart';
import 'data/repository.dart';
import 'services/app_services.dart';
import 'services/phone_auth.dart';
import 'theme/washpro_theme.dart';
import 'widgets/curved_nav_bar.dart';
import 'widgets/vehicle_sheet.dart';
import 'screens/location_picker_page.dart';
import 'pricing/booking_price.dart';
import 'widgets/upcoming_booking_card.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Environment switch: default = pilot (wash-pro-7f3b1).
  // Production build: flutter build apk --dart-define=ENV=prod  (washpro-prod)
  const env = String.fromEnvironment('ENV', defaultValue: 'pilot');
  try {
    await Firebase.initializeApp(
        options: env == 'prod'
            ? ProdFirebaseOptions.currentPlatform
            : DefaultFirebaseOptions.currentPlatform);
    fbLive = true;
    // Explicit offline cache: reads keep working on poor networks and
    // queued writes sync when connectivity returns.
    // Web uses IndexedDB persistence; unlimited cache is mobile-oriented.
    FirebaseFirestore.instance.settings = Settings(
        persistenceEnabled: true,
        cacheSizeBytes:
            kIsWeb ? 40 * 1024 * 1024 : Settings.CACHE_SIZE_UNLIMITED);
    // Crashlytics + FCM background handlers are not supported on Flutter web.
    // Registering them there aborts startup and leaves a blank Hosting page.
    if (!kIsWeb) {
      FlutterError.onError =
          FirebaseCrashlytics.instance.recordFlutterFatalError;
      PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };
      FirebaseMessaging.onBackgroundMessage(fcmBackgroundHandler);
    } else {
      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        debugPrint('FlutterError: ${details.exceptionAsString()}');
      };
      PlatformDispatcher.instance.onError = (error, stack) {
        debugPrint('Uncaught: $error\n$stack');
        return true;
      };
    }
  } catch (e, st) {
    debugPrint('Firebase init failed: $e\n$st');
    fbLive = false;
  }
  await AppTheme.load();
  NetStatus.init();
  WashProRepository.onWriteError = (msg) {
    final ctx = appNavKey.currentContext;
    if (ctx != null) toast(ctx, msg);
  };
  runApp(const WashProApp());
}

// ---------- Design tokens (Zylo brand) ----------
const dark = WpColors.primary;
const dark2 = Color(0xFF0B2C26);
const green = WpColors.secondary;
const bright = Color(0xFF39C98B);
const mint = WpColors.mint;
const mintBg = WpColors.mintBg;
const ink = WpColors.ink;
const muted = WpColors.muted;
const line = WpColors.line;
const accentGold = WpColors.accent;
String inr(int paise) => '₹${(paise / 100).round()}';
String inrFull(int paise) => '₹${paise ~/ 100}';
const months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec'
];
const weekdays = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
const weekdaysFull = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday'
];
String fmtDate(DateTime d) =>
    '${weekdaysFull[d.weekday - 1]}, ${d.day} ${months[d.month - 1]}';
String fmtShort(DateTime d) =>
    '${weekdays[d.weekday - 1].substring(0, 1)}${weekdays[d.weekday - 1].substring(1).toLowerCase()}, ${d.day} ${months[d.month - 1]}';

// ---------- Shared UI ----------
/// New users (no saved name yet) complete basic details first;
/// returning users go straight to the app with their details loaded.
Widget afterLoginDestination() => WashProRepository.isProfileComplete
    ? const Shell()
    : const OnboardingPage();

// Restores an existing Firebase session on launch: signed-in users go
// straight to the app with their data loaded; everyone else sees login.
class SplashGate extends StatefulWidget {
  const SplashGate({super.key});
  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> {
  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    await WashProRepository.loadCatalog();
    final u = fbLive ? FirebaseAuth.instance.currentUser : null;
    if (u != null) {
      await WashProRepository.loadFor(u.uid, authUser: u);
      initPushForCustomer(u.uid);
    }
    if (!mounted) return;
    Navigator.pushReplacement(
        context,
        MaterialPageRoute(
            builder: (_) =>
                u != null ? afterLoginDestination() : const AuthPage()));
  }

  @override
  Widget build(BuildContext context) => const Scaffold(
          body: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
        CircularProgressIndicator(color: green),
        SizedBox(height: 14),
        Text('Loading Zylo…',
            style: TextStyle(color: muted, fontWeight: FontWeight.w600))
      ])));
}

class WashProApp extends StatelessWidget {
  const WashProApp({super.key});
  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<ThemeMode>(
          valueListenable: AppTheme.mode,
          builder: (_, mode, __) => MaterialApp(
              title: 'Zylo',
              debugShowCheckedModeBanner: false,
              navigatorKey: appNavKey,
              themeMode: mode,
              theme: WashProTheme.light,
              darkTheme: WashProTheme.dark,
              // Global offline banner — visible on every screen.
              builder: (ctx, child) => Stack(children: [
                    child ?? const SizedBox.shrink(),
                    ValueListenableBuilder<bool>(
                        valueListenable: NetStatus.online,
                        builder: (_, online, __) => online
                            ? const SizedBox.shrink()
                            : Positioned(
                                top: 0,
                                left: 0,
                                right: 0,
                                child: SafeArea(
                                    bottom: false,
                                    child: Container(
                                        margin: const EdgeInsets.all(10),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 14, vertical: 9),
                                        decoration: BoxDecoration(
                                            color: const Color(0xFF7C2D12),
                                            borderRadius:
                                                BorderRadius.circular(12)),
                                        child: const Row(children: [
                                          Icon(Icons.wifi_off,
                                              color: Colors.white, size: 16),
                                          SizedBox(width: 8),
                                          Expanded(
                                              child: Text(
                                                  'You are offline. Showing saved data — changes will sync when you reconnect.',
                                                  style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w600)))
                                        ]))))),
                  ]),
              home: const SplashGate()));
}

void toast(BuildContext c, String m) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(
        content: Text(m),
        backgroundColor: dark,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))));
Widget wpCard(
        {required Widget child,
        EdgeInsets p = const EdgeInsets.all(18),
        Color? color,
        VoidCallback? onTap,
        bool selected = false,
        BuildContext? context}) {
  final ctx = context ?? appNavKey.currentContext;
  final isDark = ctx != null && Theme.of(ctx).brightness == Brightness.dark;
  final bg = color ?? (isDark ? WpColors.darkSurface : Colors.white);
  final border = selected
      ? green
      : (isDark ? WpColors.darkLine : line);
  return GestureDetector(
      onTap: onTap,
      child: Container(
          padding: p,
          decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: border, width: selected ? 1.6 : 1),
              boxShadow: [
                BoxShadow(
                    color: dark.withValues(alpha: isDark ? .25 : .04),
                    blurRadius: 14,
                    offset: const Offset(0, 4))
              ]),
          child: child));
}
/// Error state with Retry — shown when a live load failed (poor network,
/// rules, …) instead of leaving a silently empty/stale screen.
Widget loadErrorBanner(BuildContext c, Future<void> Function() retry) =>
    Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: const Color(0xFFFDECEC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFF3C2C2))),
        child: Row(children: [
          const Icon(Icons.cloud_off_outlined,
              color: Color(0xFFB42318), size: 20),
          const SizedBox(width: 10),
          Expanded(
              child: Text(AppState.loadError,
                  style: const TextStyle(
                      color: Color(0xFF7A271A),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600))),
          TextButton(
              onPressed: () async {
                await retry();
              },
              child: const Text('Retry',
                  style: TextStyle(
                      color: Color(0xFFB42318), fontWeight: FontWeight.w800)))
        ]));

Widget pill(String t, {Color bg = mint, Color fg = dark}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration:
        BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
    child: Text(t,
        style: TextStyle(
            color: fg,
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            letterSpacing: .7)));
Widget _whyRow(IconData icon, String title, String body) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: green, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
              Text(body, style: const TextStyle(color: muted, fontSize: 12.5)),
            ],
          ),
        ),
      ],
    );

Widget statusPill(String s) {
  if (s == 'completed') return pill('COMPLETED', bg: mint, fg: dark);
  if (s == 'cancelled')
    return pill('CANCELLED',
        bg: const Color(0xFFFDE8E8), fg: const Color(0xFFB42318));
  if (s == 'pending_verification')
    return pill('VERIFY',
        bg: const Color(0xFFFFF1D6), fg: const Color(0xFF9A6B12));
  return pill((statusLabel[s] ?? s).toUpperCase());
}

class PrimaryBtn extends StatelessWidget {
  const PrimaryBtn(
      {super.key, required this.label, required this.onTap, this.icon});
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => SizedBox(
      width: double.infinity,
      height: 56,
      child: FilledButton(
          onPressed: onTap,
          style: FilledButton.styleFrom(
              backgroundColor: dark,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16))),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white)),
            if (icon != null) ...[
              const SizedBox(width: 8),
              Icon(icon, size: 19)
            ]
          ])));
}

Widget iconBtn(IconData i, VoidCallback onTap) => Container(
    decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: line),
        borderRadius: BorderRadius.circular(13)),
    child: IconButton(
        icon: Icon(i, size: 21),
        onPressed: onTap,
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44)));
Widget backBtn(BuildContext c) =>
    iconBtn(Icons.arrow_back, () => Navigator.pop(c));
Widget bellBtn(BuildContext c) => iconBtn(
    Icons.notifications_none,
    () => Navigator.push(
        c, MaterialPageRoute(builder: (_) => const NotificationsPage())));
Widget sectionLabel(String t) => Text(t,
    style: const TextStyle(
        color: green,
        fontSize: 11.5,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.4));
Widget logoRow({bool light = false}) =>
    Row(mainAxisSize: MainAxisSize.min, children: [
      ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.asset(
            'assets/images/zylo-logo.jpeg',
            width: 36,
            height: 36,
            fit: BoxFit.cover,
          )),
      const SizedBox(width: 9),
      Text('Zylo',
          style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: light ? Colors.white : ink,
              letterSpacing: -.4))
    ]);
Widget checkCircle(bool on) => Container(
    width: 26,
    height: 26,
    decoration: BoxDecoration(
        color: on ? green : Colors.transparent,
        shape: BoxShape.circle,
        border: Border.all(
            color: on ? green : const Color(0xFFCBDCD1), width: 1.6)),
    child: on ? const Icon(Icons.check, color: Colors.white, size: 16) : null);
Widget mintIcon(IconData i) => Container(
    width: 42,
    height: 42,
    decoration:
        BoxDecoration(color: mint, borderRadius: BorderRadius.circular(12)),
    child: Icon(i, color: dark, size: 21));

/// Wire FCM for the signed-in customer: foreground pushes become snackbars,
/// taps (foreground/background/terminated) open the related booking.
void initPushForCustomer(String uid) {
  PushService.initForUser(uid, onMessage: (m) {
    final ctx = appNavKey.currentContext;
    if (ctx == null) return;
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
        content: Text(
            '${m.notification?.title ?? 'Zylo'} — ${m.notification?.body ?? ''}'),
        backgroundColor: dark,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        action: SnackBarAction(
            label: 'View',
            textColor: bright,
            onPressed: () => routePushTap(m))));
  }, onTap: routePushTap);
}

void routePushTap(dynamic m) {
  final ctx = appNavKey.currentContext;
  if (ctx == null) return;
  final bookingId = (m.data?['bookingId'] ?? m.data?['refId'])?.toString();
  final bk = AppState.bookings.where((x) => x.id == bookingId);
  if (bk.isNotEmpty) {
    Navigator.push(
        ctx, MaterialPageRoute(builder: (_) => BookingDetail(b: bk.first)));
  } else {
    Navigator.push(
        ctx, MaterialPageRoute(builder: (_) => const NotificationsPage()));
  }
}

// ---------- AUTH SERVICE ----------
// firebase-auth-basics skill (Flutter): google_sign_in 7.x — initialize() once,
// authenticate() (signIn() removed), web uses signInWithPopup to avoid DWDS hangs.
// Phone OTP uses Firebase Auth verifyPhoneNumber / signInWithPhoneNumber (web reCAPTCHA).
class AuthService {
  static bool _googleReady = false;
  static Future<void> _initGoogle() async {
    if (!_googleReady && !kIsWeb) {
      await GoogleSignIn.instance.initialize();
      _googleReady = true;
    }
  }

  static Future<User?> signInWithGoogle() async {
    if (!fbLive) return null;
    if (kIsWeb) {
      final cred =
          await FirebaseAuth.instance.signInWithPopup(GoogleAuthProvider());
      return cred.user;
    }
    await _initGoogle();
    final account = await GoogleSignIn.instance.authenticate();
    final auth = account.authentication;
    final cred = await FirebaseAuth.instance.signInWithCredential(
        GoogleAuthProvider.credential(idToken: auth.idToken));
    return cred.user;
  }

  static Future<User?> signInWithEmail(String email, String pass) async {
    final c = await FirebaseAuth.instance
        .signInWithEmailAndPassword(email: email.trim(), password: pass);
    return c.user;
  }

  static Future<User?> signUpWithEmail(String email, String pass) async {
    final c = await FirebaseAuth.instance
        .createUserWithEmailAndPassword(email: email.trim(), password: pass);
    return c.user;
  }

  /// Forgot password: Firebase emails a secure reset link.
  static Future<void> sendPasswordReset(String email) =>
      FirebaseAuth.instance.sendPasswordResetEmail(email: email.trim());

  /// Change password (Settings): re-authenticates, then updates.
  /// Google/phone accounts have no password — handled by the caller.
  static bool get hasPasswordProvider =>
      FirebaseAuth.instance.currentUser?.providerData
          .any((p) => p.providerId == 'password') ??
      false;

  static bool get hasPhoneProvider =>
      FirebaseAuth.instance.currentUser?.providerData
          .any((p) => p.providerId == 'phone') ??
      (FirebaseAuth.instance.currentUser?.phoneNumber?.isNotEmpty ?? false);

  static Future<void> changePassword(String current, String next) async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null || u.email == null) throw 'Not signed in';
    await u.reauthenticateWithCredential(
        EmailAuthProvider.credential(email: u.email!, password: current));
    await u.updatePassword(next);
  }

  /// Automatic account deletion: the deleteMyAccount Cloud Function erases
  /// profile/vehicles/addresses/subscriptions/notifications and the Auth
  /// user server-side (financial records are anonymised, kept per law).
  static Future<void> deleteAccountPermanently() async {
    try {
      await FirebaseFunctions.instance
          .httpsCallable('deleteMyAccount')
          .call({});
    } on FirebaseFunctionsException catch (e) {
      throw PaymentUnavailable(e.message ??
          'Automatic deletion is not live yet — a deletion request has been recorded instead.');
    } catch (_) {
      throw PaymentUnavailable(
          'Automatic deletion is not live yet — a deletion request has been recorded instead.');
    }
  }

  static Future<void> signOut() async {
    try {
      if (!kIsWeb && _googleReady) await GoogleSignIn.instance.signOut();
    } catch (_) {}
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
    fbUid = null;
    AppState.reset();
  }
}

Future<void> enterAuthenticated(BuildContext context, User u,
    {bool popOnly = false, bool fromOtp = false}) async {
  guestBrowsing = false;
  fbUid = u.uid;
  await WashProRepository.loadFor(u.uid, authUser: u);
  initPushForCustomer(u.uid);
  if (!context.mounted) return;
  if (popOnly) {
    // OTP sits on top of Auth — pop both so requireLogin gets the result.
    // Capture Navigator before the first pop (OTP context unmounts after it).
    final nav = Navigator.of(context);
    if (fromOtp) nav.pop();
    nav.pop(true);
    return;
  }
  Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => afterLoginDestination()),
      (_) => false);
}

/// Prompts login when a guest tries to book / save data. Returns true if signed in.
Future<bool> requireLogin(BuildContext context,
    {String message = 'Sign in to continue your booking'}) async {
  if (isSignedIn) return true;
  if (context.mounted) toast(context, message);
  final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
          builder: (_) => const AuthPage(returnAfterLogin: true)));
  return ok == true && isSignedIn;
}

Future<void> enterGuestBrowse(BuildContext context) async {
  guestBrowsing = true;
  fbUid = null;
  AppState.profileLoaded = true;
  await WashProRepository.loadCatalog();
  if (!context.mounted) return;
  Navigator.pushReplacement(
      context, MaterialPageRoute(builder: (_) => const Shell()));
}

// ---------- AUTH (simple phone OTP) ----------
class AuthPage extends StatefulWidget {
  const AuthPage({
    super.key,
    this.allowSkip = true,
    this.returnAfterLogin = false,
  });

  /// Top-right Skip — browse services without signing in.
  final bool allowSkip;

  /// When opened from booking, pop back after successful login.
  final bool returnAfterLogin;

  @override
  State<AuthPage> createState() => _AuthState();
}

class _AuthState extends State<AuthPage> {
  final phone = TextEditingController();
  bool busy = false;
  String err = '';
  DateTime? _lastOtpRequest;

  @override
  void dispose() {
    phone.dispose();
    super.dispose();
  }

  Future<void> _finish(User u) =>
      enterAuthenticated(context, u, popOnly: widget.returnAfterLogin);

  Future<void> _sendOtp() async {
    if (!fbLive) {
      setState(() => err =
          'Firebase is unavailable. Check your connection and try again.');
      return;
    }
    final e164 = toIndianE164(phone.text);
    if (e164 == null) {
      setState(() => err = 'Enter a valid 10-digit mobile number');
      return;
    }
    if (_lastOtpRequest != null &&
        DateTime.now().difference(_lastOtpRequest!) <
            const Duration(seconds: 30)) {
      final left =
          30 - DateTime.now().difference(_lastOtpRequest!).inSeconds;
      setState(() => err = 'Please wait ${left}s before requesting another OTP');
      return;
    }
    if (!NetStatus.online.value) {
      setState(() =>
          err = 'You are offline. Connect to the internet to continue.');
      return;
    }
    setState(() {
      busy = true;
      err = '';
    });
    try {
      if (kIsWeb) {
        final session = await PhoneAuthService.signInWithPhoneNumberWeb(e164);
        _lastOtpRequest = DateTime.now();
        if (!mounted) return;
        await Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => OtpVerificationPage(
                      e164: e164,
                      webSession: session,
                      returnAfterLogin: widget.returnAfterLogin,
                    )));
      } else {
        final sent = await PhoneAuthService.verifyPhoneNumber(
          e164: e164,
          onAutoVerified: (user) async {
            if (!mounted) return;
            await _finish(user);
          },
        );
        _lastOtpRequest = DateTime.now();
        if (!mounted) return;
        if (FirebaseAuth.instance.currentUser != null) return;
        await Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => OtpVerificationPage(
                      e164: e164,
                      codeSent: sent,
                      returnAfterLogin: widget.returnAfterLogin,
                    )));
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => err = friendlyPhoneAuthError(e));
    } catch (e) {
      debugPrint('[PhoneAuth] sendOtp.unexpected type=${e.runtimeType}');
      if (mounted) {
        setState(() => err =
            'Could not send OTP. Check network and try again.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _google() async {
    if (!fbLive) {
      setState(() => err = 'Firebase is unavailable. Check your connection.');
      return;
    }
    setState(() {
      busy = true;
      err = '';
    });
    try {
      final u = await AuthService.signInWithGoogle();
      if (u != null && mounted) {
        await _finish(u);
        return;
      }
      if (mounted) setState(() => err = 'Google sign-in was cancelled.');
    } on FirebaseAuthException catch (e) {
      setState(() => err = 'Google sign-in failed (${e.code}). Try again.');
    } catch (_) {
      if (mounted) setState(() => err = 'Google sign-in failed. Please try again.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final digits = phone.text.replaceAll(RegExp(r'\D'), '');
    final preview =
        digits.length == 10 ? formatIndianDisplay('+91$digits') : null;
    return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: SafeArea(
            child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 22),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [
                        logoRow(),
                        const Spacer(),
                        if (widget.allowSkip && !widget.returnAfterLogin)
                          TextButton(
                              onPressed: busy
                                  ? null
                                  : () => enterGuestBrowse(context),
                              child: Text('Skip login',
                                  style: TextStyle(
                                      color: context.wpMuted,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13))),
                        if (widget.returnAfterLogin)
                          IconButton(
                              onPressed: () => Navigator.pop(context, false),
                              icon: const Icon(Icons.close)),
                      ]),
                      const SizedBox(height: 28),
                      Text(
                          widget.returnAfterLogin
                              ? 'Sign in to book'
                              : 'Sign in to Zylo',
                          style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              color: context.wpInk,
                              letterSpacing: -.4)),
                      const SizedBox(height: 8),
                      Text(
                          widget.returnAfterLogin
                              ? 'Use your mobile number to confirm your booking.'
                              : 'Enter your mobile number. We’ll send a one-time code.',
                          style: TextStyle(
                              color: context.wpMuted,
                              fontSize: 14.5,
                              height: 1.35)),
                      const SizedBox(height: 28),
                      Text('Mobile number',
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: context.wpInk,
                              fontSize: 13)),
                      const SizedBox(height: 8),
                      TextField(
                          controller: phone,
                          keyboardType: TextInputType.phone,
                          maxLength: 10,
                          autofillHints: const [AutofillHints.telephoneNumber],
                          onChanged: (_) => setState(() => err = ''),
                          onSubmitted: (_) => busy ? null : _sendOtp(),
                          decoration: InputDecoration(
                              hintText: '10-digit number',
                              counterText: '',
                              prefixIcon: Padding(
                                  padding: const EdgeInsets.only(
                                      left: 14, right: 8),
                                  child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Text('🇮🇳',
                                            style: TextStyle(fontSize: 18)),
                                        const SizedBox(width: 6),
                                        Text('+91',
                                            style: TextStyle(
                                                fontWeight: FontWeight.w800,
                                                color: context.wpInk)),
                                        const SizedBox(width: 8),
                                        SizedBox(
                                            height: 22,
                                            child: VerticalDivider(
                                                width: 1,
                                                color: context.wpLine)),
                                      ])),
                              prefixIconConstraints: const BoxConstraints(
                                  minWidth: 0, minHeight: 0))),
                      if (preview != null)
                        Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text('OTP will be sent to $preview',
                                style: TextStyle(
                                    color: context.wpMuted, fontSize: 12.5))),
                      if (err.isNotEmpty)
                        Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text(err,
                                style: const TextStyle(
                                    color: Color(0xFFB42318),
                                    fontWeight: FontWeight.w600))),
                      const SizedBox(height: 20),
                      PrimaryBtn(
                          label: busy ? 'Sending OTP…' : 'Send OTP',
                          icon: Icons.arrow_forward,
                          onTap: busy ? null : _sendOtp),
                      const SizedBox(height: 18),
                      Row(children: [
                        Expanded(child: Divider(color: context.wpLine)),
                        Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 10),
                            child: Text('or',
                                style: TextStyle(color: context.wpMuted))),
                        Expanded(child: Divider(color: context.wpLine)),
                      ]),
                      const SizedBox(height: 14),
                      OutlinedButton.icon(
                          onPressed: busy ? null : _google,
                          icon: const Text('G',
                              style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF4285F4),
                                  fontSize: 17)),
                          label: Text('Continue with Google',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: context.wpInk)),
                          style: OutlinedButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                              side: BorderSide(color: context.wpLine),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16)))),
                      const SizedBox(height: 28),
                      Text(
                          'By continuing you agree to Terms & Privacy Policy.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: context.wpMuted, fontSize: 12)),
                      if (widget.allowSkip && !widget.returnAfterLogin) ...[
                        const SizedBox(height: 10),
                        Text(
                            'Skip to explore services — sign in when you book.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: context.wpMuted, fontSize: 12)),
                      ],
                    ]))));
  }
}

/// Six-digit OTP verification. Never displays or logs the OTP value.
class OtpVerificationPage extends StatefulWidget {
  const OtpVerificationPage({
    super.key,
    required this.e164,
    this.codeSent,
    this.webSession,
    this.returnAfterLogin = false,
  });
  final String e164;
  final PhoneOtpSession? codeSent;
  final WebPhoneSession? webSession;
  final bool returnAfterLogin;

  @override
  State<OtpVerificationPage> createState() => _OtpVerificationState();
}

class _OtpVerificationState extends State<OtpVerificationPage> {
  final otp = TextEditingController();
  bool busy = false;
  String err = '';
  String? verificationId;
  int? resendToken;
  WebPhoneSession? webSession;
  Timer? _timer;
  int _secondsLeft = 45;

  @override
  void initState() {
    super.initState();
    verificationId = widget.codeSent?.verificationId;
    resendToken = widget.codeSent?.resendToken;
    webSession = widget.webSession;
    _startCountdown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    otp.dispose();
    super.dispose();
  }

  void _startCountdown() {
    _timer?.cancel();
    setState(() => _secondsLeft = 45);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_secondsLeft <= 1) {
        t.cancel();
        setState(() => _secondsLeft = 0);
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  Future<void> _verify() async {
    final code = otp.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() => err = 'Enter the 6-digit OTP');
      return;
    }
    if (!NetStatus.online.value) {
      setState(() => err = 'You are offline. Connect to verify your OTP.');
      return;
    }
    setState(() {
      busy = true;
      err = '';
    });
    try {
      User? user;
      if (webSession != null) {
        user = await PhoneAuthService.confirmWebCode(webSession!.confirmation, code);
      } else if (verificationId != null) {
        user = await PhoneAuthService.confirmCode(
            verificationId: verificationId!, smsCode: code);
      } else {
        setState(() => err = 'Verification session missing. Go back and resend OTP.');
        return;
      }
      if (user != null && mounted) {
        await enterAuthenticated(context, user,
            popOnly: widget.returnAfterLogin, fromOtp: true);
      } else if (mounted) {
        setState(() => err = 'Verification failed. Please try again.');
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => err = friendlyPhoneAuthError(e));
    } catch (_) {
      if (mounted) {
        setState(() => err = 'Could not verify OTP. Check network and retry.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _resend() async {
    if (_secondsLeft > 0 || busy) return;
    setState(() {
      busy = true;
      err = '';
    });
    try {
      if (kIsWeb) {
        webSession =
            await PhoneAuthService.signInWithPhoneNumberWeb(widget.e164);
      } else {
        final sent = await PhoneAuthService.verifyPhoneNumber(
          e164: widget.e164,
          forceResendingToken: resendToken,
          onAutoVerified: (user) async {
            if (!mounted) return;
            await enterAuthenticated(context, user,
                popOnly: widget.returnAfterLogin, fromOtp: true);
          },
        );
        verificationId = sent.verificationId;
        resendToken = sent.resendToken;
      }
      if (mounted) {
        otp.clear();
        _startCountdown();
        toast(context, 'A new OTP has been sent');
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => err = friendlyPhoneAuthError(e));
    } catch (_) {
      if (mounted) {
        setState(() => err = 'Could not resend OTP. Please try again.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
          title: const Text('Verify OTP'),
          leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: busy ? null : () => Navigator.pop(context))),
      body: SafeArea(
          child: SingleChildScrollView(
              padding: const EdgeInsets.all(22),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 12),
                    const Text('Enter verification code',
                        style: TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Text(
                        'OTP sent to ${formatIndianDisplay(widget.e164)}',
                        style: const TextStyle(color: muted)),
                    Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                            onPressed: busy
                                ? null
                                : () => Navigator.pop(context),
                            child: const Text('Change mobile number',
                                style: TextStyle(
                                    color: green,
                                    fontWeight: FontWeight.w700)))),
                    const SizedBox(height: 8),
                    TextField(
                        controller: otp,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        autofillHints: const [AutofillHints.oneTimeCode],
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 10),
                        onChanged: (_) => setState(() => err = ''),
                        decoration: InputDecoration(
                            labelText: '6-digit OTP',
                            counterText: '',
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(15),
                                borderSide: const BorderSide(color: line)))),
                    if (err.isNotEmpty)
                      Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(err,
                              style: const TextStyle(
                                  color: Color(0xFFB42318)))),
                    const SizedBox(height: 18),
                    PrimaryBtn(
                        label: busy ? 'Verifying…' : 'Verify OTP',
                        icon: Icons.verified_user_outlined,
                        onTap: busy ? null : _verify),
                    const SizedBox(height: 14),
                    Center(
                        child: _secondsLeft > 0
                            ? Text('Resend OTP in ${_secondsLeft}s',
                                style: const TextStyle(color: muted))
                            : TextButton(
                                onPressed: busy ? null : _resend,
                                child: const Text('Resend OTP',
                                    style: TextStyle(
                                        color: green,
                                        fontWeight: FontWeight.w800)))),
                    if (kIsWeb)
                      const Padding(
                          padding: EdgeInsets.only(top: 18),
                          child: Text(
                              'Web sign-in uses Firebase reCAPTCHA for security.',
                              textAlign: TextAlign.center,
                              style:
                                  TextStyle(color: muted, fontSize: 12))),
                  ]))));
}

// ---------- BASIC DETAILS (shown once, right after a first login) ----------
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});
  @override
  State<OnboardingPage> createState() => _OnboardingState();
}

class _OnboardingState extends State<OnboardingPage> {
  final name = TextEditingController(text: AppState.userName);
  final phoneC = TextEditingController(
      text: AppState.userPhone.replaceAll(RegExp(r'\D'), '').length >= 10
          ? AppState.userPhone
              .replaceAll(RegExp(r'\D'), '')
              .substring(AppState.userPhone.replaceAll(RegExp(r'\D'), '').length - 10)
          : '');
  final email = TextEditingController(text: AppState.userEmail);
  String err = '';
  bool saving = false;

  /// Verified Firebase phone login — number is locked to the Auth credential.
  bool get _phoneLogin =>
      AuthService.hasPhoneProvider ||
      (FirebaseAuth.instance.currentUser?.phoneNumber?.isNotEmpty ?? false);

  Future<void> _save() async {
    final n = name.text.trim();
    if (n.length < 3) {
      setState(() => err = 'Please enter your full name');
      return;
    }
    final authPhone = FirebaseAuth.instance.currentUser?.phoneNumber;
    String phoneOut;
    if (_phoneLogin && authPhone != null && authPhone.isNotEmpty) {
      phoneOut = formatIndianDisplay(authPhone);
    } else {
      final e164 = phoneC.text.trim().isEmpty ? null : toIndianE164(phoneC.text);
      if (phoneC.text.trim().isNotEmpty && e164 == null) {
        setState(() => err = 'Enter a valid 10-digit mobile number');
        return;
      }
      phoneOut = e164 == null ? '' : formatIndianDisplay(e164);
    }
    final em = email.text.trim();
    if (em.isNotEmpty && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(em)) {
      setState(() => err = 'Enter a valid email address');
      return;
    }
    setState(() {
      saving = true;
      err = '';
    });
    await WashProRepository.saveBasicDetails(
      name: n,
      phone: phoneOut,
      email: em,
    );
    if (!mounted) return;
    Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => const Shell()));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      body: SafeArea(
          child: SingleChildScrollView(
              padding: const EdgeInsets.all(22),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 18),
                    logoRow(),
                    const SizedBox(height: 30),
                    Container(
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                            gradient: const LinearGradient(
                                colors: [dark, Color(0xFF11543C)]),
                            borderRadius: BorderRadius.circular(24)),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              pill('ALMOST THERE', bg: mint.withOpacity(.9)),
                              const SizedBox(height: 12),
                              const Text('Tell us a little\nabout you.',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 25,
                                      fontWeight: FontWeight.w800,
                                      height: 1.15)),
                              const SizedBox(height: 6),
                              const Text(
                                  'We use this to personalise your bookings and receipts.',
                                  style: TextStyle(color: Colors.white70)),
                            ])),
                    const SizedBox(height: 24),
                    const Text('Basic details',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w800)),
                    const Text(
                        'Takes 20 seconds — you can edit anytime in Profile.',
                        style: TextStyle(color: muted)),
                    const SizedBox(height: 16),
                    TextField(
                        controller: name,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                            labelText: 'Full name *',
                            prefixIcon: const Icon(Icons.person_outline),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(15),
                                borderSide: const BorderSide(color: line)))),
                    const SizedBox(height: 12),
                    TextField(
                        controller: phoneC,
                        enabled: !_phoneLogin,
                        readOnly: _phoneLogin,
                        keyboardType: TextInputType.phone,
                        maxLength: 10,
                        decoration: InputDecoration(
                            labelText: _phoneLogin
                                ? 'Verified mobile (from login)'
                                : 'Mobile number',
                            prefixText: '+91  ',
                            prefixIcon: const Icon(Icons.phone_outlined),
                            filled: true,
                            fillColor: Colors.white,
                            counterText: '',
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(15),
                                borderSide: const BorderSide(color: line)))),
                    const SizedBox(height: 12),
                    TextField(
                        controller: email,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                            labelText: 'Email (for invoices & offers)',
                            prefixIcon: const Icon(Icons.mail_outline),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(15),
                                borderSide: const BorderSide(color: line)))),
                    if (err.isNotEmpty)
                      Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(err,
                              style:
                                  const TextStyle(color: Color(0xFFB42318)))),
                    const SizedBox(height: 18),
                    PrimaryBtn(
                        label: saving ? 'Saving…' : 'Continue',
                        icon: Icons.arrow_forward,
                        onTap: saving ? null : _save),
                    const SizedBox(height: 8),
                    const Text(
                        'Next: add your car and parking address from Home — only when you book.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: muted, fontSize: 12)),
                  ]))));
}

// ---------- SHELL ----------
class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int tab = 0;
  dynamic _sub;
  dynamic _linkSub;
  @override
  void initState() {
    super.initState();
    if (fbUid != null)
      _sub = WashProRepository.watchBookings().listen((_) {
        if (mounted) setState(() {});
      });
    _initDeepLinks();
  }

  /// Deep links: washpro://booking/<id>, washpro://notifications,
  /// https://wash-pro-customer.web.app/booking/<id> (see AndroidManifest).
  Future<void> _initDeepLinks() async {
    final links = AppLinks();
    try {
      final initial = await links.getInitialLink();
      if (initial != null) _handleLink(initial);
    } catch (_) {}
    _linkSub = links.uriLinkStream.listen(_handleLink, onError: (_) {});
  }

  void _handleLink(Uri uri) {
    if (!mounted) return;
    final parts = [
      if (uri.host.isNotEmpty) uri.host,
      ...uri.pathSegments.where((s) => s.isNotEmpty),
    ];
    if (parts.isEmpty) return;
    if (parts.first == 'notifications') {
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => const NotificationsPage()));
    } else if (parts.first == 'booking' && parts.length > 1) {
      final bk = AppState.bookings.where((x) => x.id == parts[1]);
      if (bk.isNotEmpty) {
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => BookingDetail(b: bk.first)));
      } else {
        setState(() => tab = 1);
        toast(context, 'Opening your bookings…');
      }
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _linkSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomePage(go: (i) => setState(() => tab = i)),
      const BookingsPage(),
      PlansPage(go: (i) => setState(() => tab = i)),
      const ProfilePage()
    ];
    return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        extendBody: true,
        body: IndexedStack(index: tab, children: pages),
        bottomNavigationBar: CurvedBottomNav(
            index: tab,
            onChanged: (i) => setState(() => tab = i),
            items: const [
              CurvedNavItem(
                  icon: Icons.home_outlined,
                  activeIcon: Icons.home_rounded,
                  label: 'Home'),
              CurvedNavItem(
                  icon: Icons.calendar_month_outlined,
                  activeIcon: Icons.calendar_month,
                  label: 'Bookings'),
              CurvedNavItem(
                  icon: Icons.repeat_outlined,
                  activeIcon: Icons.repeat,
                  label: 'Plans'),
              CurvedNavItem(
                  icon: Icons.person_outline,
                  activeIcon: Icons.person,
                  label: 'Profile'),
            ]));
  }
}

// ---------- HOME ----------
class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.go});
  final void Function(int) go;
  @override
  State<HomePage> createState() => _HomeState();
}

class _HomeState extends State<HomePage> {
  bool loading = true;
  String error = '';
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = '';
    });
    await WashProRepository.loadCatalog();
    if (fbUid != null) await WashProRepository.refreshMine();
    if (!mounted) return;
    setState(() {
      loading = false;
      error = AppState.loadError;
    });
  }

  String get _greeting {
    final h = DateTime.now().hour;
    return h < 12
        ? 'GOOD MORNING'
        : h < 17
            ? 'GOOD AFTERNOON'
            : 'GOOD EVENING';
  }

  @override
  Widget build(BuildContext context) {
    final upcoming = AppState.bookings
        .where((b) => !['completed', 'cancelled'].contains(b.status))
        .toList()
      ..sort((a, b) => a.when.compareTo(b.when));
    final b = upcoming.isEmpty ? null : upcoming.first;
    final v = AppState.primaryVehicle;
    final addr = AppState.selectedAddress;
    final banner = AppState.banner;
    final inkC = context.wpInk;
    final mutedC = context.wpMuted;
    return SafeArea(
        child: RefreshIndicator(
            onRefresh: _load,
            color: green,
            child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 110),
                children: [
                  Row(children: [
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          sectionLabel(_greeting),
                          const SizedBox(height: 3),
                          Text('Hi, ${AppState.firstName}',
                              style: TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -.5,
                                  color: inkC))
                        ])),
                    Stack(children: [
                      bellBtn(context),
                      if (AppState.unreadCount > 0)
                        Positioned(
                            right: 6,
                            top: 6,
                            child: Container(
                                width: 9,
                                height: 9,
                                decoration: const BoxDecoration(
                                    color: Color(0xFFE5484D),
                                    shape: BoxShape.circle)))
                    ]),
                    const SizedBox(width: 10),
                    GestureDetector(
                        onTap: () => widget.go(3),
                        child: CircleAvatar(
                            radius: 22,
                            backgroundColor: dark,
                            child: Text(AppState.initials,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13))))
                  ]),
                  const SizedBox(height: 16),
                  wpCard(
                      context: context,
                      p: const EdgeInsets.symmetric(
                          horizontal: 15, vertical: 13),
                      onTap: () async {
                        await Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const AddressesPage()));
                        if (mounted) setState(() {});
                      },
                      child: Row(children: [
                        Icon(Icons.location_on_outlined,
                            color: context.wpPrimary, size: 22),
                        const SizedBox(width: 9),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text('Service at',
                                  style:
                                      TextStyle(color: mutedC, fontSize: 11)),
                              Text(
                                  addr == null
                                      ? 'Add your service address'
                                      : addr.titleLine,
                                  style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14,
                                      color: inkC),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              Text(
                                  addr == null
                                      ? 'Tap to choose where we wash'
                                      : (addr.line.trim().isNotEmpty
                                          ? addr.line
                                          : addr.shortArea),
                                  style: TextStyle(
                                      color: mutedC, fontSize: 12),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis)
                            ])),
                        Icon(Icons.chevron_right, color: mutedC)
                      ])),
                  const SizedBox(height: 14),
                  if (banner.active)
                    ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: SizedBox(
                            height: 238,
                            child: Stack(fit: StackFit.expand, children: [
                              if (banner.imageUrl != null &&
                                  banner.imageUrl!.isNotEmpty)
                                Image.network(banner.imageUrl!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Image.asset(
                                        'assets/images/hero-car.jpg',
                                        fit: BoxFit.cover))
                              else
                                Image.asset('assets/images/hero-car.jpg',
                                    fit: BoxFit.cover,
                                    alignment: const Alignment(0, 0.45)),
                              Container(
                                  decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: [
                                    dark2.withOpacity(.78),
                                    dark2.withOpacity(.28),
                                    dark2.withOpacity(.72)
                                  ],
                                          stops: const [
                                    0,
                                    .48,
                                    1
                                  ]))),
                              Container(
                                  decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                          begin: Alignment.centerLeft,
                                          end: Alignment.centerRight,
                                          colors: [
                                    dark2.withOpacity(.55),
                                    Colors.transparent
                                  ],
                                          stops: const [
                                    0,
                                    .75
                                  ]))),
                              Padding(
                                  padding: const EdgeInsets.all(21),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        pill(banner.pill.toUpperCase()),
                                        const SizedBox(height: 13),
                                        Text(
                                            banner.heading.trim().isEmpty
                                                ? 'Your car deserves a fresh start.'
                                                : banner.heading,
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 25,
                                                fontWeight: FontWeight.w800,
                                                height: 1.18,
                                                letterSpacing: -.4,
                                                shadows: [
                                                  Shadow(
                                                      color: Colors.black54,
                                                      blurRadius: 10,
                                                      offset: Offset(0, 2))
                                                ])),
                                        const SizedBox(height: 6),
                                        Text(
                                            banner.sub.trim().isEmpty
                                                ? 'Expert care, right where you park.'
                                                : banner.sub,
                                            style: const TextStyle(
                                                color: Colors.white70,
                                                fontSize: 13.5)),
                                        const Spacer(),
                                        SizedBox(
                                            height: 48,
                                            child: FilledButton(
                                                onPressed: () => Navigator.push(
                                                    context,
                                                    MaterialPageRoute(
                                                        builder: (_) =>
                                                            const BookingFlow())),
                                                style: FilledButton.styleFrom(
                                                    backgroundColor: bright,
                                                    shape:
                                                        RoundedRectangleBorder(
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        13)),
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 20)),
                                                child: const Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Text('Book a wash',
                                                          style: TextStyle(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w800,
                                                              color: dark2,
                                                              fontSize: 15)),
                                                      SizedBox(width: 7),
                                                      Icon(
                                                          Icons.arrow_forward,
                                                          size: 18,
                                                          color: dark2)
                                                    ]))),
                                      ])),
                            ]))),
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(
                        child: wpCard(
                            p: const EdgeInsets.all(15),
                            onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) =>
                                        const BookingFlow(instant: true))),
                            child: Row(children: [
                              mintIcon(Icons.auto_awesome),
                              const SizedBox(width: 10),
                              Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                    const Text('Book a Wash',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 14.5),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis),
                                    Text('Doorstep · ${nextSlotLabel()}',
                                        style: const TextStyle(
                                            color: muted, fontSize: 11),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis)
                                  ])),
                              const Icon(Icons.chevron_right,
                                  color: muted, size: 19)
                            ]))),
                    const SizedBox(width: 11),
                    Expanded(
                        child: wpCard(
                            p: const EdgeInsets.all(15),
                            onTap: () => widget.go(2),
                            child: Row(children: [
                              mintIcon(Icons.repeat),
                              const SizedBox(width: 10),
                              Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                    const Text('Subscriptions',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 14),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis),
                                    Text(
                                        AppState.maxPlanSave > 0
                                            ? 'Save up to ${AppState.maxPlanSave}%'
                                            : 'Monthly plans',
                                        style: const TextStyle(
                                            color: muted, fontSize: 11),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis)
                                  ])),
                              const Icon(Icons.chevron_right,
                                  color: muted, size: 19)
                            ]))),
                  ]),
                  const SizedBox(height: 22),
                  Row(children: [
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          sectionLabel('NEXT UP'),
                          const SizedBox(height: 3),
                          const Text('Upcoming wash',
                              style: TextStyle(
                                  fontSize: 17, fontWeight: FontWeight.w800))
                        ])),
                    if (b != null)
                      TextButton(
                          onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => BookingDetail(b: b))),
                          child: const Text('View details',
                              style: TextStyle(
                                  color: green, fontWeight: FontWeight.w700)))
                  ]),
                  const SizedBox(height: 8),
                  if (loading && AppState.bookings.isEmpty)
                    wpCard(
                        p: const EdgeInsets.all(22),
                        child: const Row(children: [
                          CircularProgressIndicator(
                              color: green, strokeWidth: 2.4),
                          SizedBox(width: 14),
                          Text('Loading your bookings…',
                              style: TextStyle(
                                  color: muted, fontWeight: FontWeight.w600))
                        ]))
                  else if (error.isNotEmpty && AppState.bookings.isEmpty)
                    wpCard(
                        p: const EdgeInsets.all(20),
                        child: Column(children: [
                          const Text('⚠️ Could not load your bookings',
                              style: TextStyle(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 6),
                          Text(error,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: muted, fontSize: 12.5)),
                          const SizedBox(height: 10),
                          OutlinedButton(
                              onPressed: _load, child: const Text('Retry'))
                        ]))
                  else if (b == null)
                    wpCard(
                        p: const EdgeInsets.all(20),
                        child: Column(children: [
                          const Text('✨ No upcoming washes',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 15)),
                          const SizedBox(height: 5),
                          const Text('Book a wash and it will show up here.',
                              style: TextStyle(color: muted, fontSize: 12.5)),
                          const SizedBox(height: 12),
                          FilledButton(
                              onPressed: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => const BookingFlow())),
                              style: FilledButton.styleFrom(
                                  backgroundColor: dark,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12))),
                              child: const Text('Book a wash'))
                        ]))
                  else
                    UpcomingBookingCard(
                      booking: b,
                      formatDate: fmtDate,
                      formatMoney: inrFull,
                      statusPill: statusPill,
                      months: months,
                      onOpen: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => BookingDetail(b: b))),
                    ),
                  const SizedBox(height: 22),
                  Row(children: [
                    const Expanded(
                        child: Text('Your garage',
                            style: TextStyle(
                                fontSize: 17, fontWeight: FontWeight.w800))),
                    TextButton(
                        onPressed: () async {
                          await Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const VehiclesPage()));
                          if (mounted) setState(() {});
                        },
                        child: const Text('Manage',
                            style: TextStyle(
                                color: green, fontWeight: FontWeight.w700)))
                  ]),
                  if (v == null)
                    wpCard(
                        p: const EdgeInsets.all(20),
                        onTap: () =>
                            showVehicleDialog(context, () => setState(() {})),
                        child: const Row(children: [
                          Text('🚙', style: TextStyle(fontSize: 30)),
                          SizedBox(width: 13),
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text('Add your first car',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 15)),
                                Text(
                                    'Vehicle-specific pricing, saved for every booking.',
                                    style:
                                        TextStyle(color: muted, fontSize: 12.5))
                              ])),
                          Icon(Icons.add_circle_outline, color: green)
                        ]))
                  else
                    GestureDetector(
                        onTap: () async {
                          await Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const VehiclesPage()));
                          if (mounted) setState(() {});
                        },
                        child: Container(
                            padding: const EdgeInsets.all(17),
                            decoration: BoxDecoration(
                                color: context.wpCard,
                                borderRadius: BorderRadius.circular(22),
                                border: Border.all(color: context.wpLine)),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                      height: 104,
                                      width: double.infinity,
                                      decoration: BoxDecoration(
                                          gradient: const LinearGradient(
                                              colors: [
                                                dark2,
                                                Color(0xFF17573E)
                                              ]),
                                          borderRadius:
                                              BorderRadius.circular(16)),
                                      child: Stack(children: [
                                        if (v.isDefault)
                                          Positioned(
                                              top: 10,
                                              left: 12,
                                              child: pill('PRIMARY', bg: mint)),
                                        const Center(
                                            child: Icon(
                                                Icons.directions_car_filled,
                                                size: 54,
                                                color: Colors.white70))
                                      ])),
                                  const SizedBox(height: 12),
                                  Text(v.displayName,
                                      style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 16,
                                          color: inkC)),
                                  Text(
                                      [
                                        if (v.reg.trim().isNotEmpty) v.reg,
                                        v.seatingLabel,
                                      ].join(' · '),
                                      style: TextStyle(
                                          color: mutedC, fontSize: 12.5)),
                                ]))),
                  const SizedBox(height: 18),
                  Text('Our services',
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: inkC)),
                  const SizedBox(height: 9),
                  ...services.map((s) {
                    final cat = v?.pricingCategory ?? 'sedan';
                    return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: wpCard(
                            context: context,
                            onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) =>
                                        BookingFlow(serviceId: s.id))),
                            child: Row(children: [
                              mintIcon(s.icon),
                              const SizedBox(width: 12),
                              Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                    Row(children: [
                                      Text(s.name,
                                          style: TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 15,
                                              color: inkC)),
                                      if (s.popular) ...[
                                        const SizedBox(width: 7),
                                        pill('POPULAR', bg: mint)
                                      ]
                                    ]),
                                    Text(s.tag,
                                        style: TextStyle(
                                            color: mutedC, fontSize: 12)),
                                    Text(
                                        '${inr(s.price(cat))} onwards · ${s.duration(cat)}',
                                        style: TextStyle(
                                            color: context.wpPrimary,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700))
                                  ])),
                              Icon(Icons.chevron_right, color: mutedC)
                            ])));
                  }),
                  const SizedBox(height: 18),
                  Text('Offers & coupons',
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: inkC)),
                  const SizedBox(height: 9),
                  wpCard(
                      context: context,
                      child: Row(children: [
                        mintIcon(Icons.local_offer_outlined),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text('WELCOME75',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: inkC)),
                              Text('Save ₹75 on your first doorstep wash',
                                  style: TextStyle(
                                      color: mutedC, fontSize: 12.5)),
                            ])),
                      ])),
                  const SizedBox(height: 18),
                  Text('Why choose ZYLO',
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: inkC)),
                  const SizedBox(height: 9),
                  wpCard(
                      context: context,
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _whyRow(Icons.home_work_outlined,
                                'Doorstep convenience',
                                'We wash where your car is parked.'),
                            const SizedBox(height: 12),
                            _whyRow(Icons.verified_outlined,
                                'Trained experts',
                                'Clear packages and careful finishing.'),
                            const SizedBox(height: 12),
                            _whyRow(Icons.lock_outline,
                                'Secure payments',
                                'Razorpay checkout with server verification.'),
                          ])),
                ])));
  }
}

// ---------- BOOKING FLOW (Steps 1-4 like mockups) ----------
class BookingFlow extends StatefulWidget {
  const BookingFlow({super.key, this.instant = false, this.serviceId});
  final bool instant;
  final String? serviceId;
  @override
  State<BookingFlow> createState() => _FlowState();
}

class _FlowState extends State<BookingFlow> {
  int step = 0;
  Vehicle? vehicle;
  Service service = services[0];
  Addr? addr;
  bool washNow = false;
  DateTime date = DateTime.now().add(const Duration(days: 1));
  String slot = '10:30 AM';
  String pay = 'ONLINE'; // ONLINE → Razorpay, CASH → cash after wash
  final selAddons = <String>{};
  bool showAddons = false;
  bool creating = false;
  bool couponApplied = true;
  String svcQuery = '';
  String svcSort = 'rec'; // rec | low | high
  @override
  void initState() {
    super.initState();
    washNow = widget.instant;
    vehicle = AppState.primaryVehicle;
    addr = AppState.selectedAddress;
    if (widget.serviceId != null)
      service = services.firstWhere((s) => s.id == widget.serviceId,
          orElse: () => services[0]);
    for (final d
        in List.generate(5, (i) => DateTime.now().add(Duration(days: i)))) {
      final ok = slotTimes.where((x) => slotAvailable(d, x)).toList();
      if (ok.isNotEmpty) {
        date = d;
        slot = ok.first;
        break;
      }
    }
  }

  int get servicePaise =>
      service.price(vehicle?.pricingCategory ?? 'sedan') +
      addons.where((a) => selAddons.contains(a.$1)).fold(0, (n, a) => n + a.$3);
  BookingPrice get price => BookingPrice.compute(
        servicePaise: servicePaise,
        washNow: washNow,
        couponApplied: couponApplied,
      );
  int get discount => price.discountPaise;
  int get fee => price.serviceFeePaise;
  int get express => price.expressFeePaiseApplied;
  int get total => price.totalPaise;
  /// Exactly 3 booking steps: vehicle+service → schedule+location → review & pay.
  static const titles = [
    ('Vehicle & service', 'Step 1 of 3'),
    ('Schedule & location', 'Step 2 of 3'),
    ('Review & pay', 'Step 3 of 3')
  ];
  @override
  Widget build(BuildContext context) {
    final cashOk = service.cashEligible &&
        addr != null &&
        addr!.areaId != 'banjara' &&
        addr!.areaId != 'jubilee';
    final cat = vehicle?.pricingCategory ?? 'sedan';
    final visibleServices = services
        .where((s) =>
            svcQuery.trim().isEmpty ||
            '${s.name} ${s.tag}'.toLowerCase().contains(svcQuery.toLowerCase()))
        .toList()
      ..sort((a, b) => svcSort == 'low'
          ? a.price(cat).compareTo(b.price(cat))
          : svcSort == 'high'
              ? b.price(cat).compareTo(a.price(cat))
              : (b.popular ? 1 : 0).compareTo(a.popular ? 1 : 0));
    final days = List.generate(5, (i) => DateTime.now().add(Duration(days: i)));
    return Scaffold(
        body: SafeArea(
            child: Column(children: [
      Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Row(children: [
            backBtn(context),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(titles[step].$1,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w800)),
                  Text(titles[step].$2,
                      style: const TextStyle(color: muted, fontSize: 12))
                ])),
            bellBtn(context)
          ])),
      Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                  value: (step + 1) / 3,
                  minHeight: 4,
                  backgroundColor: line,
                  color: green))),
      Expanded(
          child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              children: [
            if (step == 0) ...[
              const Text('Which car are we washing?',
                  style: TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.4)),
              const Text('Transparent, vehicle-specific pricing.',
                  style: TextStyle(color: muted)),
              const SizedBox(height: 16),
              if (AppState.vehicles.isEmpty)
                wpCard(
                    p: const EdgeInsets.all(20),
                    child: const Column(children: [
                      Text('🚙', style: TextStyle(fontSize: 30)),
                      SizedBox(height: 8),
                      Text('No vehicles yet',
                          style: TextStyle(fontWeight: FontWeight.w800)),
                      Text('Add your car below to continue.',
                          style: TextStyle(color: muted, fontSize: 12.5))
                    ])),
              ...AppState.vehicles.map((v) => Padding(
                  padding: const EdgeInsets.only(bottom: 11),
                  child: wpCard(
                      selected: vehicle == v,
                      onTap: () => setState(() => vehicle = v),
                      child: Row(children: [
                        Container(
                            width: 56,
                            height: 48,
                            decoration: BoxDecoration(
                                color: mint,
                                borderRadius: BorderRadius.circular(13)),
                            child: const Center(
                                child: Text('🚙',
                                    style: TextStyle(fontSize: 27)))),
                        const SizedBox(width: 13),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Row(children: [
                                Flexible(
                                    child: Text(v.displayName,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 15.5),
                                        overflow: TextOverflow.ellipsis)),
                                if (v.isDefault) ...[
                                  const SizedBox(width: 7),
                                  pill('PRIMARY')
                                ]
                              ]),
                              Text(
                                  [
                                    if (v.reg.trim().isNotEmpty) v.reg,
                                    v.seatingLabel,
                                  ].join(' · '),
                                  style: const TextStyle(
                                      color: muted, fontSize: 12.5))
                            ])),
                        checkCircle(vehicle == v)
                      ])))),
              GestureDetector(
                  onTap: () => showVehicleDialog(
                      context,
                      () => setState(() => vehicle ??=
                          AppState.primaryVehicle ??
                              (AppState.vehicles.isEmpty
                                  ? null
                                  : AppState.vehicles.first))),
                  child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: const Color(0xFFB9D8C4),
                              style: BorderStyle.solid)),
                      child: const Row(children: [
                        Icon(Icons.add_circle_outline, color: green),
                        SizedBox(width: 10),
                        Text('Add another car',
                            style: TextStyle(
                                fontWeight: FontWeight.w700, color: dark))
                      ]))),
              const SizedBox(height: 22),
              const Text('What does your car need?',
                  style: TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.4)),
              const Text('Transparent, vehicle-specific pricing.',
                  style: TextStyle(color: muted)),
              const SizedBox(height: 14),
              TextField(
                  onChanged: (v) => setState(() => svcQuery = v),
                  decoration: InputDecoration(
                      hintText: 'Search services — wash, interior, detail…',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(vertical: 4),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: line)))),
              const SizedBox(height: 10),
              SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    const Text('Sort:',
                        style: TextStyle(color: muted, fontSize: 12.5)),
                    const SizedBox(width: 8),
                    ...[
                      ('rec', 'Recommended'),
                      ('low', 'Price: low → high'),
                      ('high', 'Price: high → low')
                    ].map((o) => Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                            label: Text(o.$2,
                                style: const TextStyle(fontSize: 11.5)),
                            selected: svcSort == o.$1,
                            onSelected: (_) =>
                                setState(() => svcSort = o.$1)))),
                  ])),
              const SizedBox(height: 12),
              if (visibleServices.isEmpty)
                wpCard(
                    p: const EdgeInsets.all(20),
                    child: const Center(
                        child: Text('No services match your search.',
                            style: TextStyle(color: muted)))),
              ...visibleServices.map((s) => Padding(
                  padding: const EdgeInsets.only(bottom: 11),
                  child: Stack(clipBehavior: Clip.none, children: [
                    wpCard(
                        selected: service == s,
                        onTap: () => setState(() => service = s),
                        child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              mintIcon(s.icon),
                              const SizedBox(width: 13),
                              Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                    Text(s.name,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 16)),
                                    Text(s.tag,
                                        style: const TextStyle(
                                            color: muted, fontSize: 12.5)),
                                    const SizedBox(height: 9),
                                    Row(children: [
                                      const Icon(Icons.schedule,
                                          size: 15, color: muted),
                                      const SizedBox(width: 4),
                                      Text(
                                          s.duration(
                                              vehicle?.pricingCategory ?? 'sedan'),
                                          style: const TextStyle(
                                              color: muted, fontSize: 12.5)),
                                      const Spacer(),
                                      Text(
                                          inr(s.price(vehicle?.pricingCategory ?? 'sedan')),
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 16)),
                                      const Text(' onwards',
                                          style: TextStyle(
                                              color: muted, fontSize: 11))
                                    ])
                                  ])),
                              const SizedBox(width: 8),
                              checkCircle(service == s)
                            ])),
                    if (s.popular)
                      Positioned(
                          top: -9,
                          right: 18,
                          child: pill('MOST POPULAR', bg: mint))
                  ]))),
              wpCard(
                  onTap: () => setState(() => showAddons = !showAddons),
                  child: Row(children: [
                    Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                            color: mintBg,
                            borderRadius: BorderRadius.circular(10)),
                        child: const Icon(Icons.add, color: green)),
                    const SizedBox(width: 11),
                    const Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text('Add-ons available',
                              style: TextStyle(fontWeight: FontWeight.w700)),
                          Text('Tyre polish, fragrance & more',
                              style: TextStyle(color: muted, fontSize: 12))
                        ])),
                    Text(showAddons ? 'Hide' : 'View ${addons.length}',
                        style: const TextStyle(
                            color: green,
                            fontWeight: FontWeight.w700,
                            fontSize: 13))
                  ])),
              if (showAddons)
                ...addons.map((a) => CheckboxListTile(
                    value: selAddons.contains(a.$1),
                    activeColor: green,
                    onChanged: (v) => setState(() =>
                        v! ? selAddons.add(a.$1) : selAddons.remove(a.$1)),
                    title: Text(a.$2),
                    secondary: Text('+${inr(a.$3)}'))),
            ],
            if (step == 1) ...[
              sectionLabel('PICK A TIME'),
              const SizedBox(height: 6),
              const Text('When should we arrive?',
                  style: TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.4)),
              const Text(
                  'Only slots at least 45 minutes from now are bookable.',
                  style: TextStyle(color: muted)),
              const SizedBox(height: 16),
              Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                      color: const Color(0xFFEAF2EC),
                      borderRadius: BorderRadius.circular(15)),
                  child: Row(children: [
                    Expanded(
                        child: GestureDetector(
                            onTap: () => setState(() => washNow = false),
                            child: Container(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 11),
                                decoration: BoxDecoration(
                                    color: !washNow
                                        ? Colors.white
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(11),
                                    boxShadow: !washNow
                                        ? [
                                            BoxShadow(
                                                color: dark.withOpacity(.07),
                                                blurRadius: 8)
                                          ]
                                        : []),
                                child: const Text('Schedule',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        fontWeight: FontWeight.w700))))),
                    Expanded(
                        child: GestureDetector(
                            onTap: () => setState(() => washNow = true),
                            child: Container(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 11),
                                decoration: BoxDecoration(
                                    color: washNow
                                        ? Colors.white
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(11),
                                    boxShadow: washNow
                                        ? [
                                            BoxShadow(
                                                color: dark.withOpacity(.07),
                                                blurRadius: 8)
                                          ]
                                        : []),
                                child: const Text('Wash now  +₹99',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        fontWeight: FontWeight.w700)))))
                  ])),
              const SizedBox(height: 16),
              if (!washNow) ...[
                SizedBox(
                    height: 76,
                    child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: days.map((d) {
                          final sel =
                              d.day == date.day && d.month == date.month;
                          final isToday = d.day == DateTime.now().day;
                          return GestureDetector(
                              onTap: () => setState(() => date = d),
                              child: Container(
                                  width: 64,
                                  margin: const EdgeInsets.only(right: 9),
                                  decoration: BoxDecoration(
                                      color: sel ? dark : Colors.white,
                                      borderRadius: BorderRadius.circular(16),
                                      border:
                                          Border.all(color: sel ? dark : line)),
                                  child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                            isToday
                                                ? 'TODAY'
                                                : weekdays[d.weekday - 1],
                                            style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: .8,
                                                color: sel ? bright : muted)),
                                        Text('${d.day}',
                                            style: TextStyle(
                                                fontSize: 19,
                                                fontWeight: FontWeight.w800,
                                                color:
                                                    sel ? Colors.white : ink)),
                                        if (sel)
                                          const Icon(Icons.circle,
                                              size: 5, color: bright)
                                      ])));
                        }).toList())),
                const SizedBox(height: 18),
                Row(children: [
                  const Text('Available times',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  const Spacer(),
                  Row(children: [
                    Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                            color: green, shape: BoxShape.circle)),
                    const SizedBox(width: 5),
                    const Text('Best availability',
                        style: TextStyle(color: muted, fontSize: 11.5))
                  ])
                ]),
                const SizedBox(height: 10),
                GridView.count(
                    crossAxisCount: 3,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 9,
                    crossAxisSpacing: 9,
                    childAspectRatio: 2.15,
                    children: slotTimes.map((t) {
                      final sel = slot == t;
                      final full = !slotAvailable(date, t);
                      return GestureDetector(
                          onTap: full ? null : () => setState(() => slot = t),
                          child: Container(
                              decoration: BoxDecoration(
                                  color: sel ? mint : Colors.white,
                                  borderRadius: BorderRadius.circular(13),
                                  border: Border.all(
                                      color: sel ? green : line,
                                      width: sel ? 1.5 : 1)),
                              child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(full ? '$t · Full' : t,
                                        style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 12.5,
                                            color: full
                                                ? const Color(0xFFC3CFC7)
                                                : ink)),
                                    if (t == '10:30 AM' && !full)
                                      const Text('Popular',
                                          style: TextStyle(
                                              color: green,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700))
                                  ])));
                    }).toList())
              ] else
                wpCard(
                    child: const Row(children: [
                  Text('⚡', style: TextStyle(fontSize: 22)),
                  SizedBox(width: 11),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text('Arriving in ~45–90 min',
                            style: TextStyle(fontWeight: FontWeight.w800)),
                        Text(
                            'Express fee ₹99 applies · server confirms availability',
                            style: TextStyle(color: muted, fontSize: 12))
                      ]))
                ])),
              const SizedBox(height: 14),
              wpCard(
                  child: Row(children: [
                mintIcon(Icons.location_on_outlined),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      sectionLabel('SERVICE ADDRESS'),
                      Text(addr?.line ?? 'No address selected',
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 13.5)),
                      Text(addr?.slot ?? 'Add an address to continue',
                          style: const TextStyle(color: muted, fontSize: 12))
                    ])),
                IconButton(
                    icon:
                        const Icon(Icons.edit_outlined, color: green, size: 20),
                    onPressed: () => showModalBottomSheet(
                        context: context,
                        builder: (c) => Padding(
                            padding: const EdgeInsets.all(18),
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ...AppState.addresses.map((a) => ListTile(
                                      title: Text('${a.label} — ${a.line}'),
                                      subtitle: Text(a.slot),
                                      trailing: addr == a
                                          ? const Icon(Icons.check_circle,
                                              color: green)
                                          : null,
                                      onTap: () {
                                        setState(() => addr = a);
                                        Navigator.pop(c);
                                      })),
                                  ListTile(
                                      leading: const Icon(
                                          Icons.add_location_alt,
                                          color: green),
                                      title: const Text('Add new address'),
                                      onTap: () {
                                        Navigator.pop(c);
                                        showAddressDialog(
                                            context,
                                            () => setState(() => addr ??=
                                                AppState.selectedAddress));
                                      })
                                ]))))
              ])),
              const SizedBox(height: 11),
              Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                      color: mint, borderRadius: BorderRadius.circular(16)),
                  child: const Row(children: [
                    Icon(Icons.schedule, color: dark, size: 20),
                    SizedBox(width: 10),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text('45-minute arrival window',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: dark,
                                  fontSize: 13.5)),
                          Text(
                              "We'll notify you when your Zylo expert is on the way.",
                              style: TextStyle(color: dark, fontSize: 12))
                        ]))
                  ])),
            ],
            if (step == 2) ...[
              wpCard(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Row(children: [
                      mintIcon(service.icon),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            pill('CONFIRMED SLOT'),
                            const SizedBox(height: 5),
                            Text(service.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800, fontSize: 18)),
                            Text(
                                '${vehicle?.label ?? ''} · ${vehicle?.reg ?? ''}',
                                style: const TextStyle(
                                    color: muted, fontSize: 12.5))
                          ]))
                    ]),
                    const Divider(height: 26, color: line),
                    _reviewRow(
                        Icons.calendar_month_outlined,
                        'DATE & TIME',
                        washNow
                            ? 'Today · ASAP (+₹99)'
                            : '${fmtDate(date)} · $slot',
                        () => setState(() => step = 1)),
                    const SizedBox(height: 13),
                    _reviewRow(
                        Icons.location_on_outlined,
                        'SERVICE AT',
                        '${addr?.label ?? ''} · ${addr?.slot ?? ''}\n${addr?.line ?? ''}',
                        () => setState(() => step = 1)),
                  ])),
              const SizedBox(height: 12),
              wpCard(
                  context: context,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text('Offers & coupons',
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15.5,
                            color: context.wpInk)),
                    const SizedBox(height: 10),
                    if (couponApplied)
                      Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                              color: context.wpMint,
                              borderRadius: BorderRadius.circular(16)),
                          child: Row(children: [
                            Icon(Icons.local_offer_outlined,
                                color: context.wpPrimary),
                            const SizedBox(width: 10),
                            Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  Text(
                                      '${BookingPrice.welcomeCouponCode} applied',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          color: context.wpInk)),
                                  Text(
                                      'You save ${inrFull(discount)} on this booking',
                                      style: TextStyle(
                                          color: context.wpMuted,
                                          fontSize: 12.5))
                                ])),
                            TextButton(
                                onPressed: () =>
                                    setState(() => couponApplied = false),
                                child: Text('Remove',
                                    style: TextStyle(
                                        color: context.wpPrimary,
                                        fontWeight: FontWeight.w800)))
                          ]))
                    else
                      OutlinedButton.icon(
                          onPressed: () =>
                              setState(() => couponApplied = true),
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: Text(
                              'Apply ${BookingPrice.welcomeCouponCode}')),
                  ])),
              const SizedBox(height: 12),
              wpCard(
                  context: context,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text('Price breakdown',
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15.5,
                            color: context.wpInk)),
                    const SizedBox(height: 10),
                    _kv(service.name, inrFull(servicePaise)),
                    _kv('Service fee', inrFull(fee)),
                    if (express > 0)
                      _kv('Express service', inrFull(express)),
                    if (discount > 0)
                      _kv('Discount', '-${inrFull(discount)}', color: green),
                    _kv('Taxes', '₹0'),
                    Divider(height: 22, color: context.wpLine),
                    Row(children: [
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text('Total payable',
                                style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                    color: context.wpInk)),
                            Text(
                                'Charged exactly as ${inrFull(total)} on Razorpay',
                                style: TextStyle(
                                    color: context.wpMuted, fontSize: 11))
                          ])),
                      Text(inrFull(total),
                          style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                              color: context.wpInk))
                    ])
                  ])),
              const SizedBox(height: 14),
              Text('Payment',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15.5,
                      color: context.wpInk)),
              const SizedBox(height: 8),
              Text(
                  'Continue to payment opens Razorpay Checkout (UPI + Cards). No extra payment screen.',
                  style: TextStyle(color: context.wpMuted, fontSize: 12.5)),
              const SizedBox(height: 12),
              wpCard(
                  context: context,
                  selected: pay != 'CASH',
                  onTap: () => setState(() => pay = 'ONLINE'),
                  p: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
                  child: Row(children: [
                    mintIcon(Icons.lock_outline),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text('Online payment · Razorpay',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13.5,
                                  color: context.wpInk)),
                          Text(
                              'UPI + Cards via Razorpay · Intent/QR need Live Mode',
                              style: TextStyle(
                                  color: context.wpMuted, fontSize: 11.5))
                        ])),
                    checkCircle(pay != 'CASH')
                  ])),
              if (cashOk) ...[
                const SizedBox(height: 12),
                wpCard(
                    selected: pay == 'CASH',
                    onTap: () => setState(() => pay = 'CASH'),
                    p: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
                    child: Row(children: [
                      mintIcon(Icons.payments_outlined),
                      const SizedBox(width: 12),
                      const Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text('Cash after wash',
                                style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13.5)),
                            Text('Pay the expert when the service is done',
                                style: TextStyle(color: muted, fontSize: 11.5))
                          ])),
                      checkCircle(pay == 'CASH')
                    ])),
                if (pay == 'CASH')
                  Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: TextButton(
                          onPressed: () => setState(() => pay = 'UPI'),
                          child: const Text('Use UPI / Cards instead',
                              style: TextStyle(
                                  color: green, fontWeight: FontWeight.w700)))),
              ],
            ],
          ])),
      Container(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              border: Border(
                  top: BorderSide(color: Theme.of(context).dividerColor))),
          child: Row(children: [
            if (step == 0)
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Starts at',
                    style: TextStyle(color: muted, fontSize: 11.5)),
                Text(inr(service.price(vehicle?.pricingCategory ?? 'sedan')),
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 19))
              ]),
            if (step == 2)
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(pay == 'CASH' ? 'Pay after wash' : 'Total payable',
                    style: const TextStyle(color: muted, fontSize: 11.5)),
                Text(inrFull(total),
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 19))
              ]),
            const Spacer(),
            if (step > 0) ...[
              OutlinedButton(
                  onPressed: creating ? null : () => setState(() => step--),
                  style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 15),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14))),
                  child: const Text('Back')),
              const SizedBox(width: 10)
            ],
            SizedBox(
                height: 52,
                child: FilledButton(
                    onPressed: creating ? null : _next,
                    style: FilledButton.styleFrom(
                        backgroundColor: dark,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        padding: const EdgeInsets.symmetric(horizontal: 22)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(
                          creating
                              ? 'Please wait…'
                              : step == 1
                                  ? 'Review booking'
                                  : step == 2
                                      ? (pay == 'CASH'
                                          ? 'Confirm booking'
                                          : 'Continue to payment')
                                      : 'Continue',
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 15)),
                      const SizedBox(width: 7),
                      Icon(
                          step == 2 && pay != 'CASH'
                              ? Icons.lock_outline
                              : Icons.arrow_forward,
                          size: 18)
                    ]))),
          ])),
    ])));
  }

  Widget _kv(String k, String v, {Color? color}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(
            child:
                Text(k, style: const TextStyle(color: muted, fontSize: 13.5))),
        Text(v,
            style: TextStyle(
                fontWeight: FontWeight.w600, fontSize: 13.5, color: color))
      ]));
  Widget _reviewRow(
          IconData i, String label, String value, VoidCallback edit) =>
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(i, color: green, size: 20),
        const SizedBox(width: 11),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: const TextStyle(
                  color: muted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .8)),
          Text(value,
              style: const TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 13.5, height: 1.35))
        ])),
        TextButton(
            onPressed: edit,
            child: const Text('Edit',
                style: TextStyle(color: green, fontWeight: FontWeight.w700)))
      ]);
  Future<void> _next() async {
    if (creating) return; // double-tap / retry guard
    if (step == 0 && vehicle == null) {
      if (!isSignedIn) {
        final ok = await requireLogin(context,
            message: 'Sign in to add your car and book');
        if (!ok || !mounted) return;
        setState(() => vehicle = AppState.primaryVehicle);
      }
      if (vehicle == null) {
        toast(context, 'Add and select your car first');
        return;
      }
    }
    if (step == 1 && addr == null) {
      if (!isSignedIn) {
        final ok = await requireLogin(context,
            message: 'Sign in to add a service address');
        if (!ok || !mounted) return;
        setState(() => addr = AppState.selectedAddress);
      }
      if (addr == null) {
        toast(context, 'Add and select a service address first');
        return;
      }
    }
    if (step < 2) {
      setState(() => step++);
      return;
    }
    // Confirm booking always requires a signed-in account.
    if (!isSignedIn) {
      final ok = await requireLogin(context,
          message: 'Sign in to confirm your booking');
      if (!ok || !mounted) return;
    }

    // Direct Razorpay — no intermediate Payment Options page.
    setState(() => creating = true);
    final when =
        washNow ? DateTime.now() : DateTime(date.year, date.month, date.day);
    final payMethod = pay == 'CASH' ? 'CASH' : 'ONLINE';
    final b = Booking(
        AppState.nextId(),
        service,
        vehicle!,
        addr!,
        payMethod == 'CASH' ? 'confirmed' : 'awaiting_payment',
        when,
        washNow ? 'ASAP' : slot,
        total,
        servicePaise,
        payMethod,
        'pending',
        washNow ? 'instant' : 'scheduled');
    AppState.bookings.insert(0, b);
    await WashProRepository.saveBooking(b);
    if (!mounted) return;
    setState(() => creating = false);
    if (payMethod == 'CASH') {
      _success(b);
      return;
    }
    await _payOnline(b, total);
  }

  /// Razorpay checkout for an online booking. The booking is only confirmed
  /// after the SERVER verifies the Razorpay signature (verifyPayment Cloud
  /// Function) — the app never marks anything paid on its own say-so. If the
  /// gateway is not live yet (Functions/keys pending), the user can switch
  /// to cash or keep the booking and pay later from Booking details.
  Future<void> _payOnline(Booking b, int total,
      {String? preferredMethod}) async {
    try {
      toast(context, 'Opening secure Razorpay checkout…');
      final r = await RazorpayService.payBooking(
          bookingId: b.id,
          name: AppState.userName,
          email: AppState.userEmail,
          phone: AppState.userPhone,
          expectedAmountPaise: b.totalPaise,
          preferredMethod: preferredMethod);
      b.payStatus = 'paid';
      b.status = 'confirmed';
      b.providerRef = r.paymentId;
      if (mounted) _success(b);
    } on PaymentUnavailable catch (e) {
      if (!mounted) return;
      showModalBottomSheet(
          context: context,
          builder: (c) => Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('🔒 Online payment',
                    style:
                        TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(
                    '${e.message}\n\nYour booking ${b.id} is saved as Awaiting payment (${inrFull(total)} via ${b.payMethod}).',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: muted)),
                const SizedBox(height: 16),
                PrimaryBtn(
                    label: 'Retry payment',
                    onTap: () {
                      Navigator.pop(c);
                      _payOnline(b, total);
                    }),
                const SizedBox(height: 10),
                if (service.cashEligible)
                  PrimaryBtn(
                      label: 'Pay cash after wash instead',
                      onTap: () async {
                        b.payMethod = 'CASH';
                        b.status = 'confirmed';
                        await WashProRepository.patchBooking(b.id,
                            {'paymentMethod': 'cash', 'status': 'confirmed'});
                        if (c.mounted) Navigator.pop(c);
                        _success(b);
                      }),
                const SizedBox(height: 10),
                OutlinedButton(
                    onPressed: () {
                      Navigator.pop(c);
                      _success(b);
                    },
                    style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 22, vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14))),
                    child: const Text('Keep booking · pay later')),
              ])));
    }
  }

  void _success(Booking b) => Navigator.pushReplacement(
      context, MaterialPageRoute(builder: (_) => SuccessPage(b: b)));
}

// ---------- SUCCESS ----------
class SuccessPage extends StatelessWidget {
  const SuccessPage({super.key, required this.b});
  final Booking b;
  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: dark2,
      body: SafeArea(
          child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(children: [
                const SizedBox(height: 12),
                logoRow(light: true),
                const SizedBox(height: 28),
                Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: bright.withOpacity(.18),
                        border: Border.all(
                            color: bright.withOpacity(.35), width: 8)),
                    child: const Icon(Icons.check, color: bright, size: 42)),
                const SizedBox(height: 20),
                pill(b.status == 'awaiting_payment'
                    ? 'PAYMENT PENDING'
                    : 'BOOKING CONFIRMED'),
                const SizedBox(height: 14),
                Text(
                    b.status == 'awaiting_payment'
                        ? 'Booking received.'
                        : "You're all set.",
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 29,
                        fontWeight: FontWeight.w800)),
                const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    child: Text(
                        "Your car's fresh start is scheduled. We'll notify you when your expert is on the way.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white60, height: 1.45))),
                const SizedBox(height: 16),
                Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(19),
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20)),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            const Text('BOOKING ID',
                                style: TextStyle(
                                    color: muted,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: .8)),
                            const SizedBox(width: 12),
                            Expanded(
                                child: Text(b.id,
                                    textAlign: TextAlign.right,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: green,
                                        fontWeight: FontWeight.w800)))
                          ]),
                          const Divider(height: 24, color: line),
                          _sr(Icons.calendar_month_outlined,
                              '${fmtDate(b.when)}\n${b.time} – 45 min window'),
                          const SizedBox(height: 11),
                          _sr(Icons.directions_car_outlined,
                              '${b.vehicle.label}\n${b.service.name} · ${b.vehicle.reg}'),
                          const SizedBox(height: 11),
                          _sr(Icons.location_on_outlined, b.addr.line),
                          const SizedBox(height: 14),
                          Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 11),
                              decoration: BoxDecoration(
                                  color: mint,
                                  borderRadius: BorderRadius.circular(12)),
                              child: Row(children: [
                                Flexible(
                                    child: Text(
                                        b.payStatus == 'paid'
                                            ? 'PAID'
                                            : b.payMethod == 'CASH'
                                                ? 'PAY AFTER WASH'
                                                : 'PAYMENT PENDING',
                                        style: const TextStyle(
                                            color: dark,
                                            fontWeight: FontWeight.w800,
                                            fontSize: 12))),
                                const SizedBox(width: 8),
                                Text(
                                    '${b.payMethod} · ${inrFull(b.totalPaise)}',
                                    style: const TextStyle(
                                        color: dark,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12.5))
                              ])),
                        ])),
                const SizedBox(height: 20),
                SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: FilledButton(
                        onPressed: () => Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                                builder: (_) => BookingDetail(b: b))),
                        style: FilledButton.styleFrom(
                            backgroundColor: green,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15))),
                        child: const Text('Track booking',
                            style: TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 15.5)))),
                const SizedBox(height: 11),
                SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: OutlinedButton(
                        onPressed: () =>
                            Navigator.popUntil(context, (r) => r.isFirst),
                        style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.white24),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15))),
                        child: const Text('Back to home',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700)))),
                const SizedBox(height: 14),
                TextButton.icon(
                    onPressed: () => toast(context, 'Support chat opening…'),
                    icon: const Icon(Icons.headset_mic_outlined,
                        color: Colors.white54, size: 18),
                    label: const Text('Need help? Chat with Zylo support',
                        style:
                            TextStyle(color: Colors.white54, fontSize: 12.5))),
              ]))));
  Widget _sr(IconData i, String t) =>
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(i, color: green, size: 20),
        const SizedBox(width: 11),
        Expanded(
            child: Text(t,
                style: const TextStyle(
                    fontSize: 13, height: 1.4, fontWeight: FontWeight.w500)))
      ]);
}

// ---------- BOOKINGS ----------
class BookingsPage extends StatefulWidget {
  const BookingsPage({super.key});
  @override
  State<BookingsPage> createState() => _BookingsState();
}

class _BookingsState extends State<BookingsPage> {
  int seg = 0;
  int shown = 8; // lazy-load window; grows with "Load more"
  @override
  void initState() {
    super.initState();
    WashProRepository.refreshMine().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final list = AppState.bookings
        .where((b) => seg == 0
            ? ![
                'completed',
                'cancelled',
                'in_progress',
                'en_route',
                'arrived',
                'pending_verification'
              ].contains(b.status)
            : seg == 1
                ? [
                    'assigned',
                    'en_route',
                    'arrived',
                    'in_progress',
                    'pending_verification'
                  ].contains(b.status)
                : b.status == 'completed')
        .toList();
    return SafeArea(
        child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
            children: [
          Row(children: [logoRow(), const Spacer(), bellBtn(context)]),
          const SizedBox(height: 16),
          const Text('Your bookings',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
          const Text('Upcoming & past services',
              style: TextStyle(color: muted, fontSize: 13)),
          const SizedBox(height: 16),
          if (AppState.loadError.isNotEmpty)
            loadErrorBanner(context, () async {
              await WashProRepository.refreshMine();
              if (mounted) setState(() {});
            }),
          Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                  color: const Color(0xFFEAF2EC),
                  borderRadius: BorderRadius.circular(15)),
              child: Row(
                  children: ['Upcoming', 'In progress', 'Completed']
                      .indexed
                      .map((e) => Expanded(
                          child: GestureDetector(
                              onTap: () => setState(() {
                                    seg = e.$1;
                                    shown = 8;
                                  }),
                              child: Container(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 10),
                                  decoration: BoxDecoration(
                                      color: seg == e.$1
                                          ? Colors.white
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(11),
                                      boxShadow: seg == e.$1
                                          ? [
                                              BoxShadow(
                                                  color: dark.withOpacity(.07),
                                                  blurRadius: 8)
                                            ]
                                          : []),
                                  child: Text(e.$2,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 12.5,
                                          color: seg == e.$1 ? ink : muted))))))
                      .toList())),
          const SizedBox(height: 16),
          if (list.isEmpty)
            wpCard(
                p: const EdgeInsets.all(24),
                child: Column(children: [
                  const Text('✨', style: TextStyle(fontSize: 30)),
                  const Text('Nothing here yet',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                  const Text('Your bookings will appear here.',
                      style: TextStyle(color: muted, fontSize: 12.5)),
                  const SizedBox(height: 12),
                  FilledButton(
                      onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const BookingFlow())),
                      style: FilledButton.styleFrom(
                          backgroundColor: dark,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12))),
                      child: const Text('Book a wash'))
                ]))
          else
            ...list.take(shown).map((b) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: wpCard(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Row(children: [
                        statusPill(b.status),
                        const Spacer(),
                        Text(b.id,
                            style: const TextStyle(color: muted, fontSize: 11))
                      ]),
                      const SizedBox(height: 9),
                      Text(b.service.name,
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w800)),
                      Text('${b.vehicle.label} · ${b.vehicle.reg}',
                          style: const TextStyle(color: muted, fontSize: 12.5)),
                      const Divider(height: 22, color: line),
                      Row(children: [
                        const Icon(Icons.calendar_month_outlined,
                            size: 17, color: muted),
                        const SizedBox(width: 6),
                        Text('${fmtShort(b.when)} · ${b.time}',
                            style: const TextStyle(
                                fontSize: 12.5, fontWeight: FontWeight.w600)),
                        const Spacer(),
                        Text(inrFull(b.totalPaise),
                            style: const TextStyle(fontWeight: FontWeight.w800))
                      ]),
                      const SizedBox(height: 13),
                      Row(children: [
                        Expanded(
                            child: OutlinedButton(
                                onPressed: () async {
                                  final nw =
                                      b.when.add(const Duration(days: 1));
                                  await WashProRepository.patchBooking(b.id,
                                      {'scheduledAt': Timestamp.fromDate(nw)});
                                  setState(() => b.when = nw);
                                  toast(context,
                                      'Rescheduled to ${fmtShort(b.when)} ✓');
                                },
                                style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12))),
                                child: const Text('Reschedule'))),
                        const SizedBox(width: 10),
                        Expanded(
                            child: FilledButton(
                                onPressed: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (_) => BookingDetail(b: b)))
                                    .then((_) => setState(() {})),
                                style: FilledButton.styleFrom(
                                    backgroundColor: dark,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12))),
                                child: const Text('View details')))
                      ]),
                    ])))),
          if (list.length > shown)
            Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: OutlinedButton(
                    onPressed: () => setState(() => shown += 8),
                    style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12))),
                    child: Text(
                        'Load more (${list.length - shown} older bookings)'))),
          Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                  color: mint, borderRadius: BorderRadius.circular(20)),
              child: Column(children: [
                const Text('✨', style: TextStyle(fontSize: 24)),
                const Text('Your car will thank you',
                    style: TextStyle(fontWeight: FontWeight.w800, color: dark)),
                const Text('Book another service in under a minute.',
                    style: TextStyle(color: dark, fontSize: 12.5)),
                const SizedBox(height: 12),
                FilledButton(
                    onPressed: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const BookingFlow())),
                    style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12))),
                    child: const Text('Book a wash',
                        style: TextStyle(
                            color: dark, fontWeight: FontWeight.w700)))
              ])),
        ]));
  }
}

// ---------- BOOKING DETAIL / TRACKING / VERIFY ----------
class BookingDetail extends StatefulWidget {
  const BookingDetail({super.key, required this.b});
  final Booking b;
  @override
  State<BookingDetail> createState() => _DetailState();
}

class _DetailState extends State<BookingDetail> {
  Booking get b => widget.b;
  int myRating = 0;
  static const flow = [
    'confirmed',
    'assigned',
    'en_route',
    'arrived',
    'in_progress',
    'pending_verification',
    'completed'
  ];
  @override
  Widget build(BuildContext context) {
    final idx = flow.indexOf(b.status);
    return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: SafeArea(
            child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 22),
                children: [
              Row(children: [
                backBtn(context),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      const Text('Booking details',
                          style: TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w800)),
                      Text(b.id,
                          style: const TextStyle(color: muted, fontSize: 12))
                    ])),
                statusPill(b.status)
              ]),
              const SizedBox(height: 16),
              if (b.status == 'en_route')
                Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: [dark2, Color(0xFF17573E)]),
                        borderRadius: BorderRadius.circular(20)),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(children: [
                            Icon(Icons.navigation, color: bright, size: 20),
                            SizedBox(width: 8),
                            Text('Expert on the way',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800))
                          ]),
                          const SizedBox(height: 8),
                          Text(
                              '📍 Live location · updated just now · near ${b.addr.label}\nETA ~12 min (indicative)',
                              style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12.5,
                                  height: 1.5)),
                          const SizedBox(height: 10),
                          ClipRRect(
                              borderRadius: BorderRadius.circular(99),
                              child: const LinearProgressIndicator(
                                  value: .55,
                                  minHeight: 6,
                                  color: bright,
                                  backgroundColor: Colors.white24))
                        ])),
              if (b.status == 'en_route') const SizedBox(height: 12),
              wpCard(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Row(children: [
                      mintIcon(b.service.icon),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text(b.service.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16.5)),
                            Text('${b.vehicle.fullLabel}',
                                style: const TextStyle(
                                    color: muted, fontSize: 12.5))
                          ]))
                    ]),
                    const Divider(height: 24, color: line),
                    Text(
                        '🗓  ${fmtDate(b.when)} · ${b.time}\n📍  ${b.addr.line} · ${b.addr.slot}\n💳  ${inrFull(b.totalPaise)} · ${b.payMethod} (${b.payStatus})',
                        style: const TextStyle(height: 1.6, fontSize: 13.5))
                  ])),
              const SizedBox(height: 12),
              if (b.worker != null)
                wpCard(
                    child: Row(children: [
                  const CircleAvatar(
                      radius: 23, backgroundColor: dark, child: Text('👷')),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(b.worker!,
                            style:
                                const TextStyle(fontWeight: FontWeight.w800)),
                        const Text('Verified Zylo expert',
                            style: TextStyle(color: muted, fontSize: 12))
                      ])),
                  IconButton(
                      icon: const Icon(Icons.call, color: green),
                      onPressed: () => toast(context, 'Calling expert…')),
                  IconButton(
                      icon: const Icon(Icons.chat_bubble_outline, color: green),
                      onPressed: () => toast(context, 'Chat opening…'))
                ])),
              if (b.worker != null) const SizedBox(height: 12),
              wpCard(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    const Text('Service progress',
                        style: TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 15.5)),
                    const SizedBox(height: 10),
                    ...flow.map((s) {
                      final i = flow.indexOf(s);
                      final done = idx >= 0 && i <= idx;
                      return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: Row(children: [
                            Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                    color:
                                        done ? green : const Color(0xFFE4EEE7),
                                    shape: BoxShape.circle),
                                child: Icon(done ? Icons.check : Icons.circle,
                                    size: 11, color: Colors.white)),
                            const SizedBox(width: 11),
                            Text(statusLabel[s]!,
                                style: TextStyle(
                                    fontWeight: i == idx
                                        ? FontWeight.w800
                                        : FontWeight.w500,
                                    color: done ? ink : muted))
                          ]));
                    })
                  ])),
              if (b.status == 'pending_verification') ...[
                const SizedBox(height: 12),
                wpCard(
                    child: Column(children: [
                  const Text('Rate your wash',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                  Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                          5,
                          (i) => IconButton(
                              icon: Icon(
                                  i < myRating ? Icons.star : Icons.star_border,
                                  color: Colors.amber,
                                  size: 31),
                              onPressed: () =>
                                  setState(() => myRating = i + 1)))),
                  PrimaryBtn(
                      label: 'Verify completion ✓',
                      onTap: myRating == 0
                          ? null
                          : () async {
                              try {
                                await WashProRepository.verifyCompletion(b.id,
                                    rating: myRating);
                                if (!mounted) return;
                                setState(() {
                                  b.status = 'completed';
                                  b.rating = myRating;
                                });
                                toast(context, 'Thanks! Service verified ✓');
                              } on FirebaseFunctionsException catch (e) {
                                if (!mounted) return;
                                toast(
                                    context,
                                    e.message ??
                                        'Could not verify completion. Try again.');
                              } catch (_) {
                                if (!mounted) return;
                                toast(context,
                                    'Could not verify completion. Try again.');
                              }
                            })
                ]))
              ],
              if (b.status == 'completed') ...[
                const SizedBox(height: 12),
                Container(
                    padding: const EdgeInsets.all(17),
                    decoration: BoxDecoration(
                        color: mint, borderRadius: BorderRadius.circular(18)),
                    child: Text(
                        '✅ Completed ${b.rating != null ? '· You rated ${'★' * b.rating!}' : ''}\nPayment: ${b.payMethod} · ${b.payStatus}${b.payMethod == 'CASH' ? ' (collected by expert)' : ''}',
                        style: const TextStyle(
                            height: 1.55,
                            color: dark,
                            fontWeight: FontWeight.w600)))
              ],
              if (b.status == 'awaiting_payment') ...[
                const SizedBox(height: 12),
                PrimaryBtn(
                    label: 'Pay now · ${inrFull(b.totalPaise)} (Razorpay)',
                    icon: Icons.lock_outline,
                    onTap: () async {
                      try {
                        // After app kill mid-checkout, reconcile with server first.
                        try {
                          final st = await RazorpayService.getStatus(b.id);
                          if (st['paymentStatus'] == 'paid' ||
                              st['bookingStatus'] == 'confirmed') {
                            if (!mounted) return;
                            setState(() {
                              b.payStatus = 'paid';
                              b.status = 'confirmed';
                            });
                            toast(context, 'Payment already confirmed ✓');
                            return;
                          }
                        } catch (_) {}
                        final r = await RazorpayService.payBooking(
                            bookingId: b.id,
                            name: AppState.userName,
                            email: AppState.userEmail,
                            phone: AppState.userPhone,
                            expectedAmountPaise: b.totalPaise);
                        if (!mounted) return;
                        setState(() {
                          b.payStatus = 'paid';
                          b.status = 'confirmed';
                          b.payMethod = 'ONLINE';
                          b.providerRef = r.paymentId;
                        });
                        toast(context, 'Payment successful ✓');
                      } on PaymentUnavailable catch (e) {
                        if (mounted) toast(context, e.message);
                      }
                    }),
              ],
              const SizedBox(height: 16),
              if (!['completed', 'cancelled'].contains(b.status))
                OutlinedButton(
                    onPressed: () => showDialog(
                        context: context,
                        builder: (c) => AlertDialog(
                                title: const Text('Cancel booking?'),
                                content: const Text(
                                    'Free cancellation up to 2 hours before the slot. Paid refunds take 3–5 days.'),
                                actions: [
                                  TextButton(
                                      onPressed: () => Navigator.pop(c),
                                      child: const Text('Keep')),
                                  FilledButton(
                                      style: FilledButton.styleFrom(
                                          backgroundColor:
                                              const Color(0xFFB42318)),
                                      onPressed: () async {
                                        await WashProRepository.patchBooking(
                                            b.id, {
                                          'status': 'cancelled',
                                          'cancelReason':
                                              'Cancelled by customer'
                                        });
                                        setState(() => b.status = 'cancelled');
                                        if (c.mounted) Navigator.pop(c);
                                        toast(context, 'Booking cancelled');
                                      },
                                      child: const Text('Cancel booking'))
                                ])),
                    style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(13))),
                    child: const Text('Cancel booking',
                        style: TextStyle(color: Color(0xFFB42318)))),
            ])));
  }

}

// ---------- PLANS ----------
class PlansPage extends StatefulWidget {
  const PlansPage({super.key, required this.go});
  final void Function(int) go;
  @override
  State<PlansPage> createState() => _PlansState();
}

class _PlansState extends State<PlansPage> {
  String tab = 'explore';
  String planSort = 'save'; // save | low | visits
  Plan selected = plans.length > 1 ? plans[1] : plans[0];
  List<Plan> get sortedPlans => [...plans]..sort((a, b) => planSort == 'low'
      ? a.total.compareTo(b.total)
      : planSort == 'visits'
          ? b.visits.compareTo(a.visits)
          : b.save.compareTo(a.save));
  @override
  void initState() {
    super.initState();
    WashProRepository.loadCatalog().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) => SafeArea(
          child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 22),
              children: [
            Row(children: [
              iconBtn(Icons.arrow_back, () => widget.go(0)),
              const SizedBox(width: 12),
              const Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text('Wash plans',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w800)),
                    Text('Clean car, on your schedule',
                        style: TextStyle(color: muted, fontSize: 12))
                  ])),
              bellBtn(context)
            ]),
            const SizedBox(height: 16),
            if (AppState.loadError.isNotEmpty)
              loadErrorBanner(context, () async {
                await WashProRepository.loadCatalog();
                if (mounted) setState(() {});
              }),
            Container(
                padding: const EdgeInsets.all(21),
                decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [dark2, dark, Color(0xFF14573F)]),
                    borderRadius: BorderRadius.circular(22)),
                child: Row(children: [
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        pill('SAVE UP TO ${AppState.maxPlanSave}%'),
                        const SizedBox(height: 11),
                        const Text('Clean car.\nZero reminders.',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                height: 1.15)),
                        const SizedBox(height: 6),
                        const Text(
                            'Flexible recurring washes you can pause anytime.',
                            style: TextStyle(
                                color: Colors.white70, fontSize: 12.5))
                      ])),
                  const Icon(Icons.repeat, color: bright, size: 52)
                ])),
            const SizedBox(height: 14),
            Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                    color: const Color(0xFFEAF2EC),
                    borderRadius: BorderRadius.circular(15)),
                child: Row(
                    children: [
                  ('explore', 'Explore plans'),
                  ('mine', 'My subscription')
                ]
                        .map((t) => Expanded(
                            child: GestureDetector(
                                onTap: () => setState(() => tab = t.$1),
                                child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 11),
                                    decoration: BoxDecoration(
                                        color: tab == t.$1
                                            ? Colors.white
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(11),
                                        boxShadow: tab == t.$1
                                            ? [
                                                BoxShadow(
                                                    color:
                                                        dark.withOpacity(.07),
                                                    blurRadius: 8)
                                              ]
                                            : []),
                                    child: Text(t.$2, textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w700, color: tab == t.$1 ? ink : muted))))))
                        .toList())),
            const SizedBox(height: 16),
            if (tab == 'explore') ...[
              SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    const Text('Sort:',
                        style: TextStyle(color: muted, fontSize: 12.5)),
                    const SizedBox(width: 8),
                    ...[
                      ('save', 'Best saving'),
                      ('low', 'Price: low → high'),
                      ('visits', 'Most visits')
                    ].map((o) => Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                            label: Text(o.$2,
                                style: const TextStyle(fontSize: 11.5)),
                            selected: planSort == o.$1,
                            onSelected: (_) =>
                                setState(() => planSort = o.$1)))),
                  ])),
              const SizedBox(height: 12),
              ...sortedPlans.map((p) {
                final sel = selected == p;
                return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: wpCard(
                        selected: sel,
                        onTap: () => setState(() => selected = p),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Expanded(
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                      Text(p.kicker,
                                          style: const TextStyle(
                                              color: muted, fontSize: 11.5)),
                                      Text(p.name,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 17.5))
                                    ])),
                                checkCircle(sel)
                              ]),
                              const SizedBox(height: 12),
                              Container(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 11, horizontal: 13),
                                  decoration: BoxDecoration(
                                      color: mintBg,
                                      borderRadius: BorderRadius.circular(12)),
                                  child: Row(children: [
                                    Expanded(
                                        child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                          const Text('VISITS',
                                              style: TextStyle(
                                                  color: muted,
                                                  fontSize: 9.5,
                                                  fontWeight: FontWeight.w800,
                                                  letterSpacing: .8)),
                                          Text('${p.visits} washes / month',
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 12.5))
                                        ])),
                                    Container(
                                        width: 1, height: 26, color: line),
                                    const SizedBox(width: 13),
                                    Expanded(
                                        child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                          const Text('PER WASH',
                                              style: TextStyle(
                                                  color: muted,
                                                  fontSize: 9.5,
                                                  fontWeight: FontWeight.w800,
                                                  letterSpacing: .8)),
                                          Text('${inr(p.perWash)} / wash',
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 12.5))
                                        ]))
                                  ])),
                              const SizedBox(height: 12),
                              Row(children: [
                                Text(inr(p.total),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 21)),
                                const Text(' / month',
                                    style: TextStyle(
                                        color: muted, fontSize: 12.5)),
                                const Spacer(),
                                pill('SAVE ${p.save}%')
                              ]),
                              if (p.mode == 'recurring')
                                const Padding(
                                    padding: EdgeInsets.only(top: 6),
                                    child: Text(
                                        'Auto-billed monthly via mandate · cancel anytime',
                                        style: TextStyle(
                                            color: muted, fontSize: 11))),
                            ])));
              }),
              GestureDetector(
                  onTap: () => toast(context,
                      'Custom schedule builder — pick days, intervals & service in app chat'),
                  child: Container(
                      padding: const EdgeInsets.all(17),
                      decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFB9D8C4))),
                      child: Row(children: [
                        mintIcon(Icons.calendar_month_outlined),
                        const SizedBox(width: 12),
                        const Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text('Build a custom schedule',
                                  style:
                                      TextStyle(fontWeight: FontWeight.w800)),
                              Text('Choose days, intervals and service type',
                                  style: TextStyle(color: muted, fontSize: 12))
                            ])),
                        const Icon(Icons.chevron_right, color: green)
                      ]))),
              const SizedBox(height: 16),
              const Text('Every plan includes',
                  style:
                      TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
              const SizedBox(height: 9),
              GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 3.4,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 14,
                  children: [
                    'Easy skips',
                    'Pause anytime',
                    'Trusted experts',
                    'Priority support'
                  ]
                      .map((t) => Row(children: [
                            const Icon(Icons.check, color: green, size: 18),
                            const SizedBox(width: 7),
                            Text(t,
                                style: const TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w600))
                          ]))
                      .toList()),
              const SizedBox(height: 16),
              PrimaryBtn(
                  label:
                      'Subscribe · ${selected.name} ${inr(selected.total)}/mo',
                  icon: Icons.arrow_forward,
                  onTap: () async {
                    final veh = AppState.primaryVehicle;
                    if (veh == null) {
                      toast(context, 'Add your car first (Home → Your garage)');
                      return;
                    }
                    if (AppState.subs.any((x) =>
                        x.plan.id == selected.id && x.status != 'cancelled')) {
                      toast(context, 'You already have this plan');
                      setState(() => tab = 'mine');
                      return;
                    }
                    final s = Sub(selected, veh)
                      ..visitsLeft = selected.visits
                      ..status = 'pending_payment';
                    await WashProRepository.saveSub(s);
                    setState(() {
                      AppState.subs.add(s);
                      tab = 'mine';
                    });
                    toast(context,
                        'Plan reserved — it activates once payment is verified');
                  }),
            ] else ...[
              if (AppState.subs.isEmpty)
                wpCard(
                    p: const EdgeInsets.all(24),
                    child: const Center(
                        child: Text(
                            'No active subscription yet.\nExplore plans to get started.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: muted))))
              else
                ...AppState.subs.map((s) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: wpCard(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Row(children: [
                            Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  Text(s.plan.name,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 17)),
                                  Text(
                                      '${s.vehicle.label} · ${s.plan.mode} · ${inr(s.plan.total)}/mo',
                                      style: const TextStyle(
                                          color: muted, fontSize: 12))
                                ])),
                            pill(s.status.toUpperCase(),
                                bg: s.status == 'active'
                                    ? mint
                                    : const Color(0xFFFFF1D6),
                                fg: s.status == 'active'
                                    ? dark
                                    : const Color(0xFF9A6B12))
                          ]),
                          const SizedBox(height: 13),
                          ClipRRect(
                              borderRadius: BorderRadius.circular(99),
                              child: LinearProgressIndicator(
                                  value: s.plan.visits == 0
                                      ? 0
                                      : s.visitsLeft / s.plan.visits,
                                  minHeight: 8,
                                  color: green,
                                  backgroundColor: line)),
                          const SizedBox(height: 7),
                          Text(
                              '${s.visitsLeft}/${s.plan.visits} visits left · Credits used only on completed visits${s.status == 'pending_payment' ? ' · Awaiting payment verification' : ''}',
                              style:
                                  const TextStyle(color: muted, fontSize: 12)),
                          const SizedBox(height: 12),
                          Wrap(spacing: 8, children: [
                            OutlinedButton(
                                onPressed: () async {
                                  final ns = s.status == 'active'
                                      ? 'paused'
                                      : 'active';
                                  await WashProRepository.patchSub(
                                      s.id, {'status': ns});
                                  setState(() => s.status = ns);
                                },
                                child: Text(
                                    s.status == 'active' ? 'Pause' : 'Resume')),
                            OutlinedButton(
                                onPressed: () async {
                                  await WashProRepository.patchSub(s.id, {
                                    'nextVisitAt': Timestamp.fromDate(
                                        DateTime.now()
                                            .add(const Duration(days: 2)))
                                  });
                                  toast(context,
                                      'Next visit skipped · credit preserved');
                                },
                                child: const Text('Skip next')),
                            OutlinedButton(
                                onPressed: () => showDialog(
                                    context: context,
                                    builder: (c) => SimpleDialog(
                                        title:
                                            const Text('Preferred time window'),
                                        children: [
                                          '06:00-08:00',
                                          '07:00-09:00',
                                          '17:00-19:00'
                                        ]
                                            .map((w) => SimpleDialogOption(
                                                onPressed: () async {
                                                  await WashProRepository
                                                      .patchSub(s.id,
                                                          {'timeWindow': w});
                                                  if (c.mounted)
                                                    Navigator.pop(c);
                                                  toast(context,
                                                      'Time window set to $w');
                                                },
                                                child: Text(w)))
                                            .toList())),
                                child: const Text('Change time')),
                            TextButton(
                                onPressed: () async {
                                  await WashProRepository.patchSub(
                                      s.id, {'status': 'cancelled'});
                                  setState(() => AppState.subs.remove(s));
                                },
                                child: const Text('Cancel plan',
                                    style: TextStyle(color: Color(0xFFB42318))))
                          ]),
                        ])))),
            ],
          ]));
}

// ---------- SETTINGS ----------
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsState();
}

class _SettingsState extends State<SettingsPage> {
  bool pushOn = true;
  @override
  void initState() {
    super.initState();
    PushService.enabled().then((v) {
      if (mounted) setState(() => pushOn = v);
    });
  }

  void _changePassword() {
    if (!AuthService.hasPasswordProvider) {
      toast(context,
          'You signed in with Google — manage your password in your Google account.');
      return;
    }
    final cur = TextEditingController(), nxt = TextEditingController();
    showDialog(
        context: context,
        builder: (c) => AlertDialog(
              title: const Text('Change password'),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                    controller: cur,
                    obscureText: true,
                    decoration:
                        const InputDecoration(labelText: 'Current password')),
                const SizedBox(height: 8),
                TextField(
                    controller: nxt,
                    obscureText: true,
                    decoration: const InputDecoration(
                        labelText: 'New password (min 6 characters)')),
              ]),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(c),
                    child: const Text('Cancel')),
                FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: dark),
                    onPressed: () async {
                      if (nxt.text.length < 6) {
                        toast(c, 'New password must be at least 6 characters');
                        return;
                      }
                      try {
                        await AuthService.changePassword(cur.text, nxt.text);
                        if (c.mounted) Navigator.pop(c);
                        toast(context, 'Password changed ✓');
                      } on FirebaseAuthException catch (e) {
                        toast(
                            c,
                            e.code == 'wrong-password' ||
                                    e.code == 'invalid-credential'
                                ? 'Current password is incorrect'
                                : 'Could not change password (${e.code})');
                      } catch (_) {
                        toast(c, 'Could not change password. Try again.');
                      }
                    },
                    child: const Text('Change')),
              ],
            ));
  }

  Future<void> _open(String url) async {
    final ok = await launchUrl(Uri.parse(url),
        mode: LaunchMode.externalApplication);
    if (!ok && mounted) toast(context, 'Could not open $url');
  }

  @override
  Widget build(BuildContext context) => SubPage(
      title: 'Settings',
      child: Column(children: [
        wpCard(
            p: EdgeInsets.zero,
            child: Column(children: [
              ListTile(
                  leading: mintIcon(Icons.person_outline),
                  title: const Text('Name',
                      style: TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14.5)),
                  subtitle: Text(
                      AppState.userName.isEmpty
                          ? 'Add your name'
                          : AppState.userName,
                      style: const TextStyle(color: muted, fontSize: 12)),
                  trailing:
                      const Icon(Icons.chevron_right, color: muted, size: 20),
                  onTap: () {
                    final name =
                        TextEditingController(text: AppState.userName);
                    showDialog(
                        context: context,
                        builder: (c) => AlertDialog(
                              title: const Text('Edit name'),
                              content: TextField(
                                  controller: name,
                                  decoration: const InputDecoration(
                                      labelText: 'Full name')),
                              actions: [
                                TextButton(
                                    onPressed: () => Navigator.pop(c),
                                    child: const Text('Cancel')),
                                FilledButton(
                                    style: FilledButton.styleFrom(
                                        backgroundColor: dark),
                                    onPressed: () async {
                                      if (name.text.trim().isEmpty) return;
                                      await WashProRepository.saveProfile(
                                          name: name.text);
                                      if (c.mounted) Navigator.pop(c);
                                      setState(() {});
                                      toast(context, 'Name updated ✓');
                                    },
                                    child: const Text('Save')),
                              ],
                            ));
                  }),
              const Divider(height: 1, indent: 70, color: line),
              ListTile(
                  leading: mintIcon(Icons.mail_outline),
                  title: const Text('Email',
                      style: TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14.5)),
                  subtitle: Text(
                      AppState.userEmail.isEmpty
                          ? '—'
                          : AppState.userEmail,
                      style: const TextStyle(color: muted, fontSize: 12))),
              const Divider(height: 1, indent: 70, color: line),
              ListTile(
                  leading: mintIcon(Icons.lock_outline),
                  title: const Text('Change password',
                      style: TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14.5)),
                  trailing:
                      const Icon(Icons.chevron_right, color: muted, size: 20),
                  onTap: _changePassword),
            ])),
        const SizedBox(height: 14),
        wpCard(
            p: EdgeInsets.zero,
            child: Column(children: [
              SwitchListTile(
                  secondary: mintIcon(Icons.notifications_none),
                  title: const Text('Push notifications',
                      style: TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14.5)),
                  subtitle: const Text(
                      'Worker assigned, arrival and completion alerts',
                      style: TextStyle(color: muted, fontSize: 12)),
                  value: pushOn,
                  activeThumbColor: green,
                  onChanged: (v) async {
                    setState(() => pushOn = v);
                    await PushService.setEnabled(fbUid, v);
                    toast(context,
                        v ? 'Push notifications on' : 'Push notifications off');
                  }),
              const Divider(height: 1, indent: 70, color: line),
              ValueListenableBuilder<ThemeMode>(
                  valueListenable: AppTheme.mode,
                  builder: (_, mode, __) => ListTile(
                      leading: mintIcon(Icons.dark_mode_outlined),
                      title: const Text('Appearance',
                          style: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14.5)),
                      subtitle: Text(
                          mode == ThemeMode.dark
                              ? 'Dark'
                              : mode == ThemeMode.light
                                  ? 'Light'
                                  : 'System default',
                          style:
                              const TextStyle(color: muted, fontSize: 12)),
                      trailing: const Icon(Icons.chevron_right,
                          color: muted, size: 20),
                      onTap: () => showDialog(
                          context: context,
                          builder: (c) => AlertDialog(
                                title: const Text('Appearance'),
                                content: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      ('System default', ThemeMode.system),
                                      ('Light', ThemeMode.light),
                                      ('Dark', ThemeMode.dark)
                                    ]
                                        .map((o) => RadioListTile<ThemeMode>(
                                            title: Text(o.$1),
                                            value: o.$2,
                                            groupValue: AppTheme.mode.value,
                                            onChanged: (v) {
                                              if (v != null) AppTheme.set(v);
                                              Navigator.pop(c);
                                            }))
                                        .toList()),
                              )))),
            ])),
        const SizedBox(height: 14),
        wpCard(
            p: EdgeInsets.zero,
            child: Column(children: [
              ListTile(
                  leading: mintIcon(Icons.privacy_tip_outlined),
                  title: const Text('Privacy policy',
                      style: TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14.5)),
                  trailing:
                      const Icon(Icons.open_in_new, color: muted, size: 18),
                  onTap: () =>
                      _open('https://wash-pro-customer.web.app/privacy.html')),
              const Divider(height: 1, indent: 70, color: line),
              ListTile(
                  leading: mintIcon(Icons.description_outlined),
                  title: const Text('Terms of service',
                      style: TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14.5)),
                  trailing:
                      const Icon(Icons.open_in_new, color: muted, size: 18),
                  onTap: () =>
                      _open('https://wash-pro-customer.web.app/terms.html')),
              const Divider(height: 1, indent: 70, color: line),
              const ListTile(
                  leading: Icon(Icons.info_outline, color: muted),
                  title: Text('Zylo for Android',
                      style: TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14.5)),
                  subtitle: Text('Version 1.2.0 · Hyderabad pilot',
                      style: TextStyle(color: muted, fontSize: 12))),
            ])),
        const SizedBox(height: 14),
        GestureDetector(
            onTap: () async {
              await AuthService.signOut();
              if (context.mounted)
                Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const AuthPage()),
                    (_) => false);
            },
            child: Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: line)),
                child: const Text('Log out',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: green,
                        fontWeight: FontWeight.w700,
                        fontSize: 15)))),
        TextButton(
            onPressed: () => showDialog(
                context: context,
                builder: (c) => AlertDialog(
                        title: const Text('Delete account permanently?'),
                        content: const Text(
                            'This erases your profile, vehicles, addresses, subscriptions and notifications, and removes your sign-in. Past invoices are anonymised and kept only as required by law. This cannot be undone.'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(c),
                              child: const Text('Keep my account')),
                          TextButton(
                              onPressed: () async {
                                Navigator.pop(c);
                                try {
                                  await AuthService
                                      .deleteAccountPermanently();
                                  await AuthService.signOut();
                                  if (context.mounted)
                                    Navigator.pushAndRemoveUntil(
                                        context,
                                        MaterialPageRoute(
                                            builder: (_) => const AuthPage()),
                                        (_) => false);
                                  toast(context,
                                      'Account deleted. Sorry to see you go.');
                                } on PaymentUnavailable catch (e) {
                                  // Functions not live yet: record the
                                  // request so support completes it (≤30 days).
                                  await WashProRepository
                                      .requestAccountDeletion();
                                  toast(context,
                                      '${e.message} Request recorded — our team will confirm by email.');
                                }
                              },
                              child: const Text('Delete forever',
                                  style: TextStyle(
                                      color: Color(0xFFB42318),
                                      fontWeight: FontWeight.w700)))
                        ])),
            child: const Text('Delete account',
                style: TextStyle(color: muted, fontSize: 12))),
      ]));
}

// ---------- PROFILE + SUBPAGES ----------
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});
  @override
  State<ProfilePage> createState() => _ProfileState();
}

class _ProfileState extends State<ProfilePage> {
  void _editProfile() {
    final name = TextEditingController(text: AppState.userName);
    showDialog(
        context: context,
        builder: (c) => AlertDialog(
                title: const Text('Edit profile'),
                content: Column(mainAxisSize: MainAxisSize.min, children: [
                  TextField(
                      controller: name,
                      decoration:
                          const InputDecoration(labelText: 'Full name')),
                  const SizedBox(height: 8),
                  TextField(
                      enabled: false,
                      decoration: InputDecoration(
                          labelText: AppState.userPhone.isEmpty
                              ? (AppState.userEmail.isEmpty
                                  ? 'Signed in'
                                  : AppState.userEmail)
                              : AppState.userPhone))
                ]),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: const Text('Cancel')),
                  FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: dark),
                      onPressed: () async {
                        if (name.text.trim().isEmpty) return;
                        await WashProRepository.saveProfile(name: name.text);
                        if (c.mounted) Navigator.pop(c);
                        setState(() {});
                        toast(context, 'Profile updated ✓');
                      },
                      child: const Text('Save'))
                ]));
  }

  @override
  Widget build(BuildContext context) => SafeArea(
          child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
              children: [
            Row(children: [
              logoRow(),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    const Text('Profile',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w800)),
                    Text(
                        isSignedIn
                            ? 'Your Zylo account'
                            : 'Guest · explore services freely',
                        style: const TextStyle(color: muted, fontSize: 12))
                  ])),
              bellBtn(context)
            ]),
            const SizedBox(height: 18),
            Container(
                padding: const EdgeInsets.all(19),
                decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [dark2, Color(0xFF14573F)]),
                    borderRadius: BorderRadius.circular(22)),
                child: Row(children: [
                  Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                          color: bright,
                          borderRadius: BorderRadius.circular(15)),
                      child: Center(
                          child: Text(
                              isSignedIn
                                  ? (AppState.initials.isEmpty
                                      ? 'Z'
                                      : AppState.initials)
                                  : '?',
                              style: const TextStyle(
                                  color: dark2,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 17)))),
                  const SizedBox(width: 14),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(
                            !isSignedIn
                                ? 'Browsing as guest'
                                : (AppState.userName.isEmpty
                                    ? 'Zylo customer'
                                    : AppState.userName),
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 17)),
                        Text(
                            !isSignedIn
                                ? 'Sign in to book and save details'
                                : (AppState.userPhone.isNotEmpty
                                    ? AppState.userPhone
                                    : AppState.userEmail),
                            style: const TextStyle(
                                color: Colors.white60, fontSize: 12.5)),
                        const SizedBox(height: 7),
                        pill(!isSignedIn
                            ? 'GUEST'
                            : (AppState.memberSince == null
                                ? 'MEMBER'
                                : 'MEMBER SINCE ${AppState.memberSince!.year}'))
                      ])),
                  if (isSignedIn)
                    Container(
                        decoration: BoxDecoration(
                            color: Colors.white12,
                            borderRadius: BorderRadius.circular(11)),
                        child: IconButton(
                            icon: const Icon(Icons.edit_outlined,
                                color: Colors.white, size: 19),
                            onPressed: _editProfile)),
                ])),
            const SizedBox(height: 16),
            wpCard(
                p: EdgeInsets.zero,
                child: Column(children: [
                  _tile(context, Icons.directions_car_outlined, 'My vehicles',
                      const VehiclesPage()),
                  _tile(context, Icons.location_on_outlined, 'Saved addresses',
                      const AddressesPage()),
                  _tile(context, Icons.account_balance_wallet_outlined,
                      'Payments & refunds', const PaymentsPage()),
                  _tile(context, Icons.notifications_none, 'Notifications',
                      const NotificationsPage()),
                  _tile(context, Icons.settings_outlined, 'Settings',
                      const SettingsPage()),
                  _tile(context, Icons.headset_mic_outlined, 'Help & support',
                      const SupportPage(),
                      last: true),
                ])),
            const SizedBox(height: 14),
            GestureDetector(
                onTap: () async {
                  if (!isSignedIn) {
                    final ok = await requireLogin(context,
                        message: 'Sign in to save your profile');
                    if (ok && context.mounted) setState(() {});
                    return;
                  }
                  await AuthService.signOut();
                  if (context.mounted)
                    Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(builder: (_) => const AuthPage()),
                        (_) => false);
                },
                child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: line)),
                    child: Text(isSignedIn ? 'Log out' : 'Sign in',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: green,
                            fontWeight: FontWeight.w700,
                            fontSize: 15)))),
            if (isSignedIn)
            TextButton(
                onPressed: () => showDialog(
                    context: context,
                    builder: (c) => AlertDialog(
                            title: const Text('Delete account?'),
                            content: const Text(
                                'This records a deletion request with our support team. Your bookings, vehicles and addresses are erased within 30 days, except records we must keep by law (invoices).'),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(c),
                                  child: const Text('Cancel')),
                              TextButton(
                                  onPressed: () async {
                                    await WashProRepository
                                        .requestAccountDeletion();
                                    if (c.mounted) Navigator.pop(c);
                                    toast(context,
                                        'Deletion requested — our team will confirm by SMS/email');
                                  },
                                  child: const Text('Request deletion',
                                      style:
                                          TextStyle(color: Color(0xFFB42318))))
                            ])),
                child: const Text('Delete account',
                    style: TextStyle(color: muted, fontSize: 12))),
          ]));
  Widget _tile(BuildContext c, IconData i, String t, Widget page,
          {bool last = false}) =>
      Column(children: [
        ListTile(
            leading: mintIcon(i),
            title: Text(t,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 14.5)),
            trailing: const Icon(Icons.chevron_right, color: muted, size: 20),
            onTap: () =>
                Navigator.push(c, MaterialPageRoute(builder: (_) => page))),
        if (!last) const Divider(height: 1, indent: 70, color: line)
      ]);
}

class SubPage extends StatelessWidget {
  const SubPage({super.key, required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
          child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
              children: [
            Row(children: [
              backBtn(context),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(title,
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: context.wpInk))),
              bellBtn(context)
            ]),
            const SizedBox(height: 16),
            child
          ])));
}

class VehiclesPage extends StatefulWidget {
  const VehiclesPage({super.key});
  @override
  State<VehiclesPage> createState() => _VehiclesState();
}

class _VehiclesState extends State<VehiclesPage> {
  @override
  Widget build(BuildContext context) => SubPage(
      title: 'My vehicles',
      child: Column(children: [
        if (AppState.loadError.isNotEmpty)
          loadErrorBanner(context, () async {
            await WashProRepository.refreshMine();
            if (mounted) setState(() {});
          }),
        if (AppState.vehicles.isEmpty)
          wpCard(
              context: context,
              p: const EdgeInsets.all(22),
              child: Column(children: [
                Icon(Icons.directions_car_outlined,
                    size: 34, color: context.wpPrimary),
                const SizedBox(height: 8),
                Text('No vehicles yet',
                    style: TextStyle(
                        fontWeight: FontWeight.w800, color: context.wpInk)),
                Text('Add your car for seating-based pricing.',
                    style: TextStyle(color: context.wpMuted, fontSize: 12.5))
              ])),
        ...AppState.vehicles.map((v) => Padding(
            padding: const EdgeInsets.only(bottom: 11),
            child: wpCard(
                context: context,
                selected: v.isDefault,
                onTap: () async {
                  await WashProRepository.setPrimaryVehicle(v.id);
                  setState(() {});
                },
                child: Row(children: [
                  Container(
                      width: 54,
                      height: 46,
                      decoration: BoxDecoration(
                          color: context.wpMint,
                          borderRadius: BorderRadius.circular(12)),
                      child: Icon(Icons.directions_car_filled,
                          color: context.wpPrimary)),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Row(children: [
                          Flexible(
                              child: Text(v.displayName,
                                  style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: context.wpInk),
                                  overflow: TextOverflow.ellipsis)),
                          if (v.isDefault) ...[
                            const SizedBox(width: 7),
                            pill('PRIMARY')
                          ]
                        ]),
                        Text(
                            [
                              if (v.reg.trim().isNotEmpty) v.reg,
                              v.seatingLabel,
                            ].join(' · '),
                            style: TextStyle(
                                color: context.wpMuted, fontSize: 12))
                      ])),
                  IconButton(
                      icon: Icon(Icons.edit_outlined, color: context.wpMuted),
                      onPressed: () => showVehicleSheet(
                          context, () => setState(() {}),
                          existing: v)),
                  IconButton(
                      icon: const Icon(Icons.delete_outline,
                          color: WpColors.error),
                      onPressed: () => showDialog(
                          context: context,
                          builder: (c) => AlertDialog(
                                  title: const Text('Delete vehicle?'),
                                  content: Text(
                                      'Remove ${v.displayName} (${v.reg}) from your garage?'),
                                  actions: [
                                    TextButton(
                                        onPressed: () => Navigator.pop(c),
                                        child: const Text('Keep')),
                                    TextButton(
                                        onPressed: () async {
                                          await WashProRepository.deleteVehicle(
                                              v.id);
                                          setState(() =>
                                              AppState.vehicles.remove(v));
                                          if (c.mounted) Navigator.pop(c);
                                        },
                                        child: const Text('Delete',
                                            style: TextStyle(
                                                color: WpColors.error)))
                                  ])))
                ])))),
        SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
                onPressed: () =>
                    showVehicleSheet(context, () => setState(() {})),
                icon: Icon(Icons.add, color: context.wpPrimary),
                label: Text('Add vehicle',
                    style: TextStyle(
                        color: context.wpPrimary, fontWeight: FontWeight.w700)),
                style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    side: BorderSide(color: context.wpPrimary),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)))))
      ]));
}

class AddressesPage extends StatefulWidget {
  const AddressesPage({super.key});
  @override
  State<AddressesPage> createState() => _AddressesState();
}

class _AddressesState extends State<AddressesPage> {
  bool _saving = false;
  bool _loading = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _refreshList();
  }

  Future<void> _refreshList() async {
    if (!WashProRepository.live) return;
    setState(() => _loading = true);
    await WashProRepository.reloadAddresses();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _addOrEdit({Addr? existing}) async {
    if (_saving || WashProRepository.addressWriteInFlight) return;
    final result = await Navigator.push<LocationPickResult>(
        context,
        MaterialPageRoute(
            builder: (_) => LocationPickerPage(initial: existing)));
    if (result == null || !mounted) return;

    setState(() {
      _saving = true;
      _saveError = null;
    });

    AddressWriteResult write;
    if (existing != null) {
      // Keep a rollback copy so a failed write does not leave half-edited UI
      // without a matching Firestore document.
      final prior = (
        label: existing.label,
        line: existing.line,
        area: existing.area,
        slot: existing.slot,
        lat: existing.latitude,
        lng: existing.longitude,
        city: existing.city,
        postal: existing.postalCode,
        building: existing.building,
        state: existing.state,
        country: existing.country,
        formatted: existing.formattedAddress,
      );
      existing
        ..label = result.displayName
        ..line = result.line
        ..area = result.area
        ..slot = result.building.isNotEmpty ? result.building : existing.slot
        ..latitude = result.latitude
        ..longitude = result.longitude
        ..city = result.city
        ..postalCode = result.postalCode
        ..building = result.building
        ..state = result.state
        ..country = result.country
        ..formattedAddress = result.formattedAddress;
      write = await WashProRepository.updateAddress(existing);
      if (!write.ok) {
        existing
          ..label = prior.label
          ..line = prior.line
          ..area = prior.area
          ..slot = prior.slot
          ..latitude = prior.lat
          ..longitude = prior.lng
          ..city = prior.city
          ..postalCode = prior.postal
          ..building = prior.building
          ..state = prior.state
          ..country = prior.country
          ..formattedAddress = prior.formatted;
      }
    } else {
      final na = Addr(
          '',
          result.displayName,
          result.line,
          result.area,
          'kondapur',
          result.building.isNotEmpty ? result.building : '—',
          latitude: result.latitude,
          longitude: result.longitude,
          city: result.city,
          postalCode: result.postalCode,
          building: result.building,
          state: result.state,
          country: result.country,
          formattedAddress: result.formattedAddress);
      na.isDefault = AppState.addresses.isEmpty;
      write = await WashProRepository.saveAddress(na);
      if (write.ok) {
        // Add only after Firestore confirms — prevents empty-list flash and
        // "update" failures against local-only ids.
        if (!AppState.addresses.any((x) => x.id == na.id)) {
          AppState.addresses.add(na);
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _saving = false;
      _saveError = write.ok ? null : write.message;
    });
    if (write.ok) {
      toast(context, existing != null ? 'Address updated' : 'Address saved');
    }
  }

  Future<void> _delete(Addr a) async {
    if (_saving) return;
    final isOnly = AppState.addresses.length == 1;
    final isSelected = a.isDefault;
    final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
              title: const Text('Delete address?'),
              content: Text(isSelected && !isOnly
                  ? 'This is your selected service address. Delete it anyway? Another address will become selected.'
                  : isOnly
                      ? 'This is your only saved address. Delete it?'
                      : 'Remove ${a.titleLine}?'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(c, false),
                    child: const Text('Keep')),
                TextButton(
                    onPressed: () => Navigator.pop(c, true),
                    child: const Text('Delete',
                        style: TextStyle(color: WpColors.error))),
              ],
            ));
    if (ok != true) return;
    setState(() => _saving = true);
    final res = await WashProRepository.deleteAddress(a.id);
    if (res.ok) {
      AppState.addresses.removeWhere((x) => x.id == a.id);
      if (AppState.addresses.isNotEmpty &&
          !AppState.addresses.any((x) => x.isDefault)) {
        await WashProRepository.setDefaultAddress(AppState.addresses.first.id);
      }
    } else {
      _saveError = res.message;
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) => SubPage(
      title: 'Saved Addresses',
      child: Column(children: [
        if (_saving)
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: LinearProgressIndicator(minHeight: 3),
          ),
        if (_saveError != null)
          wpCard(
              context: context,
              p: const EdgeInsets.all(14),
              child: Row(children: [
                const Icon(Icons.error_outline, color: WpColors.error),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(_saveError!,
                        style: const TextStyle(
                            color: WpColors.error, fontSize: 13))),
                TextButton(
                    onPressed: _saving
                        ? null
                        : () async {
                            setState(() => _saveError = null);
                            await _refreshList();
                          },
                    child: const Text('Retry')),
              ])),
        if (AppState.loadError.isNotEmpty)
          loadErrorBanner(context, () async {
            await _refreshList();
          }),
        if (_loading && AppState.addresses.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (AppState.addresses.isEmpty)
          wpCard(
              context: context,
              p: const EdgeInsets.all(22),
              child: Column(children: [
                Icon(Icons.location_on_outlined,
                    size: 34, color: context.wpPrimary),
                const SizedBox(height: 8),
                Text('No addresses yet',
                    style: TextStyle(
                        fontWeight: FontWeight.w800, color: context.wpInk)),
                Text('Add where your car is parked so experts can find it.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: context.wpMuted, fontSize: 12.5))
              ])),
        ...AppState.addresses.map((a) => Padding(
            padding: const EdgeInsets.only(bottom: 11),
            child: wpCard(
                context: context,
                selected: a.isDefault,
                onTap: _saving
                    ? null
                    : () async {
                        setState(() => _saving = true);
                        await WashProRepository.setDefaultAddress(a.id);
                        if (mounted) setState(() => _saving = false);
                      },
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                          color: context.wpMint,
                          borderRadius: BorderRadius.circular(12)),
                      child: Icon(Icons.location_on,
                          color: context.wpPrimary, size: 22)),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Row(children: [
                          Flexible(
                              child: Text(a.titleLine,
                                  style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: context.wpInk),
                                  overflow: TextOverflow.ellipsis)),
                          if (a.isDefault) ...[
                            const SizedBox(width: 7),
                            pill('SELECTED')
                          ]
                        ]),
                        const SizedBox(height: 3),
                        Text(a.subtitleLine,
                            style: TextStyle(
                                color: context.wpMuted,
                                fontSize: 12.5,
                                height: 1.35)),
                        const SizedBox(height: 6),
                        if (a.hasCoordinates)
                          Text(
                              'GPS ${a.latitude!.toStringAsFixed(5)}, ${a.longitude!.toStringAsFixed(5)}',
                              style: TextStyle(
                                  color: context.wpPrimary,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600))
                        else
                          Row(children: [
                            const Icon(Icons.warning_amber_rounded,
                                size: 14, color: WpColors.error),
                            const SizedBox(width: 4),
                            Expanded(
                                child: Text(
                                    'Location not verified — pin exact spot',
                                    style: TextStyle(
                                        color: WpColors.error,
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600))),
                          ]),
                      ])),
                  IconButton(
                      icon: Icon(Icons.edit_outlined, color: context.wpMuted),
                      onPressed: _saving ? null : () => _addOrEdit(existing: a)),
                  IconButton(
                      icon: const Icon(Icons.delete_outline,
                          color: WpColors.error),
                      onPressed: _saving ? null : () => _delete(a)),
                ])))),
        SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
                onPressed: _saving ? null : () => _addOrEdit(),
                icon: Icon(Icons.add_location_alt_outlined,
                    color: context.wpPrimary),
                label: Text(_saving ? 'Saving…' : 'Add address',
                    style: TextStyle(
                        color: context.wpPrimary, fontWeight: FontWeight.w800)),
                style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    side: BorderSide(color: context.wpPrimary, width: 1.2),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)))))
      ]));
}

class PaymentsPage extends StatelessWidget {
  const PaymentsPage({super.key});
  @override
  Widget build(BuildContext context) => SubPage(
      title: 'Payments & refunds',
      child: Column(children: [
        if (AppState.bookings.isEmpty)
          wpCard(
              p: const EdgeInsets.all(22),
              child: const Center(
                  child: Text(
                      'No payments yet.\nYour booking payments will appear here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: muted)))),
        ...AppState.bookings.map((b) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: wpCard(
                child: Row(children: [
              mintIcon(Icons.receipt_long_outlined),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text('${b.service.name} · ${inrFull(b.totalPaise)}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text('${b.id} · ${b.payMethod}',
                        style: const TextStyle(color: muted, fontSize: 12))
                  ])),
              pill(b.payStatus.toUpperCase())
            ]))))
      ]));
}

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});
  @override
  State<NotificationsPage> createState() => _NotifState();
}

class _NotifState extends State<NotificationsPage> {
  int shown = 15; // lazy-load window
  @override
  void initState() {
    super.initState();
    WashProRepository.refreshMine().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) => SubPage(
      title: 'Notifications',
      child: Column(children: [
        if (AppState.loadError.isNotEmpty)
          loadErrorBanner(context, () async {
            await WashProRepository.refreshMine();
            if (mounted) setState(() {});
          }),
        if (AppState.notifications.any((n) => !n.read))
          Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                  onPressed: () async {
                    await WashProRepository.markAllNotificationsRead();
                    setState(() {});
                  },
                  child: const Text('Mark all as read',
                      style: TextStyle(
                          color: green, fontWeight: FontWeight.w700)))),
        if (AppState.notifications.isEmpty)
          wpCard(
              p: const EdgeInsets.all(22),
              child: const Center(
                  child: Text(
                      '🔔 No notifications yet.\nBooking updates will appear here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: muted))))
        else
          ...AppState.notifications.take(shown).map((n) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: wpCard(
                  onTap: () async {
                    await WashProRepository.markNotificationRead(n.id);
                    setState(() {});
                    final bk =
                        AppState.bookings.where((x) => x.id == n.bookingId);
                    if (bk.isNotEmpty && context.mounted)
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => BookingDetail(b: bk.first)));
                  },
                  child: Row(children: [
                    mintIcon(n.read
                        ? Icons.mail_outline
                        : Icons.notifications_active_outlined),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(n.title,
                              style: TextStyle(
                                  fontWeight: n.read
                                      ? FontWeight.w600
                                      : FontWeight.w800)),
                          Text(n.body,
                              style:
                                  const TextStyle(color: muted, fontSize: 12.5))
                        ])),
                    if (!n.read)
                      Container(
                          width: 9,
                          height: 9,
                          decoration: const BoxDecoration(
                              color: green, shape: BoxShape.circle))
                  ])))),
        if (AppState.notifications.length > shown)
          OutlinedButton(
              onPressed: () => setState(() => shown += 15),
              child: Text(
                  'Load more (${AppState.notifications.length - shown} more)')),
      ]));
}

class SupportPage extends StatefulWidget {
  const SupportPage({super.key});
  @override
  State<SupportPage> createState() => _SupportState();
}

class _SupportState extends State<SupportPage> {
  final subject = TextEditingController();
  @override
  Widget build(BuildContext context) => SubPage(
      title: 'Help & support',
      child: wpCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('How can we help?',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 6),
        const Text('We usually reply within 2 hours, 7 AM – 9 PM.',
            style: TextStyle(color: muted, fontSize: 12.5)),
        const SizedBox(height: 13),
        TextField(
            controller: subject,
            maxLines: 3,
            decoration: InputDecoration(
                labelText: 'Describe your issue',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(13)))),
        const SizedBox(height: 12),
        PrimaryBtn(
            label: 'Raise support ticket',
            onTap: subject.text.trim().isEmpty
                ? null
                : () async {
                    await WashProRepository.saveTicket(subject.text.trim());
                    toast(context, 'Ticket created ✓');
                    subject.clear();
                    setState(() {});
                  })
      ])));
}

/// Opens the simplified Add Vehicle bottom sheet (name / reg / 5–7 seater).
void showVehicleDialog(BuildContext context, VoidCallback refresh,
    {Vehicle? existing}) {
  showVehicleSheet(context, refresh, existing: existing);
}

/// Opens the OSM location picker for create/edit, then persists via repository.
Future<void> showAddressDialog(BuildContext context, VoidCallback refresh,
    {Addr? existing}) async {
  if (WashProRepository.addressWriteInFlight) return;
  final result = await Navigator.push<LocationPickResult>(
      context,
      MaterialPageRoute(
          builder: (_) => LocationPickerPage(initial: existing)));
  if (result == null) return;
  if (existing != null) {
    existing
      ..label = result.displayName
      ..line = result.line
      ..area = result.area
      ..slot = result.building.isNotEmpty ? result.building : existing.slot
      ..latitude = result.latitude
      ..longitude = result.longitude
      ..city = result.city
      ..postalCode = result.postalCode
      ..building = result.building
      ..state = result.state
      ..country = result.country
      ..formattedAddress = result.formattedAddress;
    final write = await WashProRepository.updateAddress(existing);
    if (write.ok && context.mounted) toast(context, 'Address updated');
  } else {
    final na = Addr(
        '',
        result.displayName,
        result.line,
        result.area,
        'kondapur',
        result.building.isNotEmpty ? result.building : '—',
        latitude: result.latitude,
        longitude: result.longitude,
        city: result.city,
        postalCode: result.postalCode,
        building: result.building,
        state: result.state,
        country: result.country,
        formattedAddress: result.formattedAddress);
    na.isDefault = AppState.addresses.isEmpty;
    final write = await WashProRepository.saveAddress(na);
    if (write.ok) {
      if (!AppState.addresses.any((x) => x.id == na.id)) {
        AppState.addresses.add(na);
      }
      if (context.mounted) toast(context, 'Address saved');
    }
  }
  refresh();
}
