// WashPro Customer App — Flutter (PRD §5) · UI matched to approved design mockups.
// Demo mode mirrors Firestore/Functions; production: replace DemoStore calls
// with cloud_functions callables (createBooking / createPaymentOrder / verifyPayment).
import 'dart:async';
import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
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
    FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED);
    // Crash reporting: Flutter + async errors land in Crashlytics.
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
    FirebaseMessaging.onBackgroundMessage(fcmBackgroundHandler);
  } catch (_) {
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

// ---------- Design tokens (from mockups) ----------
const dark = Color(0xFF0A3828); // deep forest green
const dark2 = Color(0xFF06231A);
const green = Color(0xFF0E9F6E);
const bright = Color(0xFF39C98B);
const mint = Color(0xFFDFF3E7);
const mintBg = Color(0xFFF2F7F3);
const ink = Color(0xFF122019);
const muted = Color(0xFF71857A);
const line = Color(0xFFE4EEE7);
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
        Text('Loading WashPro…',
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
              title: 'WashPro',
              debugShowCheckedModeBanner: false,
              navigatorKey: appNavKey,
              themeMode: mode,
              theme: ThemeData(
                  useMaterial3: true,
                  scaffoldBackgroundColor: mintBg,
                  colorScheme:
                      ColorScheme.fromSeed(seedColor: green, primary: dark),
                  appBarTheme: const AppBarTheme(
                      backgroundColor: mintBg,
                      elevation: 0,
                      foregroundColor: ink)),
              darkTheme: ThemeData(
                  useMaterial3: true,
                  brightness: Brightness.dark,
                  scaffoldBackgroundColor: const Color(0xFF0C1A13),
                  colorScheme: ColorScheme.fromSeed(
                      seedColor: green,
                      primary: bright,
                      brightness: Brightness.dark),
                  appBarTheme: const AppBarTheme(
                      backgroundColor: Color(0xFF0C1A13),
                      elevation: 0,
                      foregroundColor: Colors.white)),
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
        bool selected = false}) =>
    GestureDetector(
        onTap: onTap,
        child: Container(
            padding: p,
            decoration: BoxDecoration(
                color: color ?? Colors.white,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                    color: selected ? green : line, width: selected ? 1.6 : 1),
                boxShadow: [
                  BoxShadow(
                      color: dark.withOpacity(.04),
                      blurRadius: 14,
                      offset: const Offset(0, 4))
                ]),
            child: child));
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
      Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
              color: green, borderRadius: BorderRadius.circular(10)),
          child: const Icon(Icons.auto_awesome, color: Colors.white, size: 20)),
      const SizedBox(width: 9),
      Text('WashPro',
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
            '${m.notification?.title ?? 'WashPro'} — ${m.notification?.body ?? ''}'),
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
  /// Google-signed-in accounts have no password — handled by the caller.
  static bool get hasPasswordProvider =>
      FirebaseAuth.instance.currentUser?.providerData
          .any((p) => p.providerId == 'password') ??
      false;

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
  /// Throws PaymentUnavailable-style message if Functions aren't live yet.
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

// ---------- AUTH ----------
class AuthPage extends StatefulWidget {
  const AuthPage({super.key});
  @override
  State<AuthPage> createState() => _AuthState();
}

class _AuthState extends State<AuthPage> {
  final email = TextEditingController(), pass = TextEditingController();
  bool signup = false, busy = false;
  String err = '';

  Future<void> _forgot() async {
    final ctrl = TextEditingController(text: email.text.trim());
    final send = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
              title: const Text('Reset your password'),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text(
                    'We will email you a secure link to set a new password.'),
                const SizedBox(height: 12),
                TextField(
                    controller: ctrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                        labelText: 'Email address',
                        prefixIcon: Icon(Icons.mail_outline))),
              ]),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(c, false),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(c, true),
                    child: const Text('Send reset link')),
              ],
            ));
    if (send != true) return;
    final em = ctrl.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(em)) {
      setState(() => err = 'Enter a valid email to reset your password');
      return;
    }
    try {
      await AuthService.sendPasswordReset(em);
      if (mounted)
        setState(() =>
            err = 'Reset link sent to $em — check your inbox (and spam).');
    } on FirebaseAuthException catch (e) {
      if (mounted)
        setState(() => err = e.code == 'user-not-found'
            ? 'No account with this email — create one first.'
            : 'Could not send reset email (${e.code}). Try again.');
    }
  }

  Future<void> _enter(User? u) async {
    if (u != null) {
      fbUid = u.uid;
      await WashProRepository.loadFor(u.uid, authUser: u);
      initPushForCustomer(u.uid);
    } else {
      // Offline/demo fallback only (Firebase unreachable): identity comes
      // from the entered email; basic-details still runs next.
      AppState.userEmail = email.text.trim();
      AppState.profileLoaded = true;
    }
    if (mounted)
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => afterLoginDestination()));
  }

  Future<void> _google() async {
    setState(() {
      busy = true;
      err = '';
    });
    try {
      final u = await AuthService.signInWithGoogle();
      if (u != null) {
        await _enter(u);
        return;
      }
      _enter(null);
    } on FirebaseAuthException catch (e) {
      setState(() => err =
          'Google sign-in failed (${e.code}). Check that Google is enabled in Firebase Auth and try again.');
    } catch (_) {
      if (mounted) _enter(null);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _emailAuth() async {
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email.text.trim())) {
      setState(() => err = 'Enter a valid email address');
      return;
    }
    if (pass.text.length < 6) {
      setState(() => err = 'Password must be at least 6 characters');
      return;
    }
    setState(() {
      busy = true;
      err = '';
    });
    try {
      final u = signup
          ? await AuthService.signUpWithEmail(email.text, pass.text)
          : await AuthService.signInWithEmail(email.text, pass.text);
      await _enter(u);
    } on FirebaseAuthException catch (e) {
      final friendly = {
        'invalid-credential':
            'Wrong email or password. Try again, or create an account.',
        'user-not-found': 'No account with this email — create one first.',
        'wrong-password': 'Wrong password. Please try again.',
        'email-already-in-use':
            'This email already has an account — sign in instead.',
        'weak-password': 'Password must be at least 6 characters.',
        'invalid-email': 'Enter a valid email address.',
        'configuration-not-found':
            'Email/Password is not enabled yet in Firebase Auth.',
        'too-many-requests': 'Too many attempts — wait a minute and retry.',
      }[e.code];
      setState(() =>
          err = friendly ?? 'Sign-in failed (${e.code}). Please try again.');
    } catch (_) {
      _enter(null);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      body: SafeArea(
          child: SingleChildScrollView(
              padding: const EdgeInsets.all(22),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 26),
                    logoRow(),
                    const SizedBox(height: 34),
                    Container(
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                            gradient: const LinearGradient(
                                colors: [dark, Color(0xFF11543C)]),
                            borderRadius: BorderRadius.circular(24)),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              pill('DOORSTEP DETAILING',
                                  bg: mint.withOpacity(.9)),
                              const SizedBox(height: 12),
                              const Text('Your car deserves a\nfresh start.',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 26,
                                      fontWeight: FontWeight.w800,
                                      height: 1.15)),
                              const SizedBox(height: 6),
                              const Text('Expert care, right where you park.',
                                  style: TextStyle(color: Colors.white70))
                            ])),
                    const SizedBox(height: 26),
                    Text(signup ? 'Create your account' : 'Welcome back',
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w800)),
                    const Text('Sign in with your email or Google account',
                        style: TextStyle(color: muted)),
                    const SizedBox(height: 14),
                    TextField(
                        controller: email,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        decoration: InputDecoration(
                            labelText: 'Email address',
                            prefixIcon: const Icon(Icons.mail_outline),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(15),
                                borderSide: const BorderSide(color: line)))),
                    const SizedBox(height: 10),
                    TextField(
                        controller: pass,
                        obscureText: true,
                        autofillHints: const [AutofillHints.password],
                        decoration: InputDecoration(
                            labelText: 'Password (min 6 characters)',
                            prefixIcon: const Icon(Icons.lock_outline),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(15),
                                borderSide: const BorderSide(color: line)))),
                    if (!signup)
                      Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                              onPressed: busy ? null : _forgot,
                              child: const Text('Forgot password?',
                                  style: TextStyle(
                                      color: green,
                                      fontWeight: FontWeight.w700)))),
                    if (err.isNotEmpty)
                      Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(err,
                              style:
                                  const TextStyle(color: Color(0xFFB42318)))),
                    const SizedBox(height: 16),
                    PrimaryBtn(
                        label: busy
                            ? 'Please wait…'
                            : signup
                                ? 'Create account'
                                : 'Sign in',
                        icon: Icons.arrow_forward,
                        onTap: busy ? null : _emailAuth),
                    const SizedBox(height: 10),
                    Row(children: [
                      const Expanded(child: Divider(color: line)),
                      const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 10),
                          child: Text('or', style: TextStyle(color: muted))),
                      const Expanded(child: Divider(color: line))
                    ]),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                        onPressed: busy ? null : _google,
                        icon: const Text('G',
                            style: TextStyle(
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF4285F4),
                                fontSize: 17)),
                        label: const Text('Continue with Google',
                            style: TextStyle(
                                fontWeight: FontWeight.w700, color: ink)),
                        style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            side: const BorderSide(color: line),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)))),
                    TextButton(
                        onPressed: () => setState(() {
                              signup = !signup;
                              err = '';
                            }),
                        child: Text(signup
                            ? 'Already have an account? Sign in'
                            : 'New to WashPro? Create an account')),
                    const SizedBox(height: 26),
                    const Text(
                        'By continuing you agree to Terms & Privacy Policy.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: muted, fontSize: 12)),
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
      text: AppState.userPhone.replaceAll('+91', '').replaceAll(' ', ''));
  final email = TextEditingController(text: AppState.userEmail);
  String err = '';
  bool saving = false;

  bool get _phoneLogin => AppState.userPhone.isNotEmpty;

  Future<void> _save() async {
    final n = name.text.trim();
    if (n.length < 3) {
      setState(() => err = 'Please enter your full name');
      return;
    }
    final ph = phoneC.text.replaceAll(RegExp(r'[\s+]'), '');
    if (ph.isNotEmpty && !RegExp(r'^(\+?91)?\d{10}$').hasMatch(ph)) {
      setState(() => err = 'Enter a valid 10-digit mobile number');
      return;
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
      phone: ph.isEmpty ? '' : (ph.startsWith('+') ? ph : '+91 $ph'),
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
                        keyboardType: TextInputType.phone,
                        maxLength: 10,
                        decoration: InputDecoration(
                            labelText: _phoneLogin
                                ? 'Mobile number (from your login)'
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
        body: pages[tab],
        bottomNavigationBar: Container(
            decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: line))),
            child: NavigationBar(
                backgroundColor: Colors.white,
                indicatorColor: mint,
                selectedIndex: tab,
                onDestinationSelected: (i) => setState(() => tab = i),
                destinations: const [
                  NavigationDestination(
                      icon: Icon(Icons.home_outlined),
                      selectedIcon: Icon(Icons.home, color: dark),
                      label: 'Home'),
                  NavigationDestination(
                      icon: Icon(Icons.calendar_month_outlined),
                      selectedIcon: Icon(Icons.calendar_month, color: dark),
                      label: 'Bookings'),
                  NavigationDestination(
                      icon: Icon(Icons.repeat_outlined),
                      selectedIcon: Icon(Icons.repeat, color: dark),
                      label: 'Plans'),
                  NavigationDestination(
                      icon: Icon(Icons.person_outline),
                      selectedIcon: Icon(Icons.person, color: dark),
                      label: 'Profile')
                ])));
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
    return SafeArea(
        child: RefreshIndicator(
            onRefresh: _load,
            color: green,
            child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
                children: [
                  Row(children: [
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          sectionLabel(_greeting),
                          const SizedBox(height: 3),
                          Text('Hi, ${AppState.firstName}',
                              style: const TextStyle(
                                  fontSize: 27,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -.5))
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
                    CircleAvatar(
                        radius: 22,
                        backgroundColor: dark,
                        child: Text(AppState.initials,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 13)))
                  ]),
                  const SizedBox(height: 16),
                  wpCard(
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
                        const Icon(Icons.location_on_outlined,
                            color: green, size: 20),
                        const SizedBox(width: 9),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              const Text('Service at',
                                  style: TextStyle(color: muted, fontSize: 11)),
                              Text(
                                  addr == null
                                      ? 'Add your service address'
                                      : '${addr.label} · ${addr.line}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13.5),
                                  overflow: TextOverflow.ellipsis),
                              if (addr != null)
                                Text(addr.slot,
                                    style: const TextStyle(
                                        color: muted, fontSize: 11.5),
                                    overflow: TextOverflow.ellipsis)
                            ])),
                        const Icon(Icons.chevron_right, color: muted)
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
                                        Text(banner.heading,
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
                                        Text(banner.sub,
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
                                                child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Text(banner.cta,
                                                          style:
                                                              const TextStyle(
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w800,
                                                                  color: dark2,
                                                                  fontSize:
                                                                      15)),
                                                      const SizedBox(width: 7),
                                                      const Icon(
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
                                    const Text('Wash now',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 14.5)),
                                    Text('Next slot · ${nextSlotLabel()}',
                                        style: const TextStyle(
                                            color: muted, fontSize: 11))
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
                                    const Text('Subscribe',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 14.5)),
                                    Text(
                                        AppState.maxPlanSave > 0
                                            ? 'Save up to ${AppState.maxPlanSave}%'
                                            : 'Monthly plans',
                                        style: const TextStyle(
                                            color: muted, fontSize: 11))
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
                    wpCard(
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => BookingDetail(b: b))),
                        child: Row(children: [
                          Container(
                              width: 56,
                              padding: const EdgeInsets.symmetric(vertical: 9),
                              decoration: BoxDecoration(
                                  color: mint,
                                  borderRadius: BorderRadius.circular(14)),
                              child: Column(children: [
                                Text('${b.when.day}',
                                    style: const TextStyle(
                                        fontSize: 21,
                                        fontWeight: FontWeight.w800,
                                        color: dark)),
                                Text(months[b.when.month - 1].toUpperCase(),
                                    style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        color: dark))
                              ])),
                          const SizedBox(width: 14),
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Row(children: [
                                  statusPill(b.status),
                                  const SizedBox(width: 8),
                                  Text(b.time,
                                      style: const TextStyle(
                                          color: muted,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600))
                                ]),
                                const SizedBox(height: 6),
                                Text('${b.service.name} · ${b.vehicle.label}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15)),
                                Text('📍 ${b.addr.label} · ${b.addr.slot}',
                                    style: const TextStyle(
                                        color: muted, fontSize: 12.5),
                                    overflow: TextOverflow.ellipsis)
                              ])),
                          const Icon(Icons.chevron_right, color: muted),
                        ])),
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
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(22),
                                border: Border.all(color: line)),
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
                                            child: Text('🚙',
                                                style: TextStyle(fontSize: 58)))
                                      ])),
                                  const SizedBox(height: 12),
                                  Text('${v.make} ${v.model}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 16)),
                                  Text(
                                      '${v.reg} · ${v.color} · ${v.category.toUpperCase()}',
                                      style: const TextStyle(
                                          color: muted, fontSize: 12.5)),
                                ]))),
                  const SizedBox(height: 18),
                  const Text('Our services',
                      style:
                          TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 9),
                  ...services.map((s) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: wpCard(
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
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 15)),
                                    if (s.popular) ...[
                                      const SizedBox(width: 7),
                                      pill('POPULAR', bg: mint)
                                    ]
                                  ]),
                                  Text(s.tag,
                                      style: const TextStyle(
                                          color: muted, fontSize: 12)),
                                  Text(
                                      '${inr(s.price(v?.category ?? 'hatchback'))} onwards · ${s.duration(v?.category ?? 'hatchback')}',
                                      style: const TextStyle(
                                          color: dark,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700))
                                ])),
                            const Icon(Icons.chevron_right, color: muted)
                          ])))),
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
  String pay = 'UPI';
  final selAddons = <String>{};
  bool showAddons = false;
  bool creating = false;
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
      service.price(vehicle?.category ?? 'hatchback') +
      addons.where((a) => selAddons.contains(a.$1)).fold(0, (n, a) => n + a.$3);
  int get discount => 7500;
  int get fee => 2900;
  int get total => servicePaise + fee + (washNow ? 9900 : 0) - discount;
  static const titles = [
    ('Select your car', 'Step 1 of 4'),
    ('Select a service', 'Step 2 of 4'),
    ('Schedule your wash', 'Step 3 of 4'),
    ('Review & pay', 'Step 4 of 4')
  ];
  @override
  Widget build(BuildContext context) {
    final cashOk = service.cashEligible &&
        addr != null &&
        addr!.areaId != 'banjara' &&
        addr!.areaId != 'jubilee';
    final cat = vehicle?.category ?? 'hatchback';
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
                  value: (step + 1) / 4,
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
                                Text('${v.make} ${v.model}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 15.5)),
                                if (v.isDefault) ...[
                                  const SizedBox(width: 7),
                                  pill('PRIMARY')
                                ]
                              ]),
                              Text('${v.reg} · ${v.color} · ${v.category}',
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
            ],
            if (step == 1) ...[
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
              Row(children: [
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
                        label: Text(o.$2, style: const TextStyle(fontSize: 11.5)),
                        selected: svcSort == o.$1,
                        onSelected: (_) => setState(() => svcSort = o.$1)))),
              ]),
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
                                              vehicle?.category ?? 'hatchback'),
                                          style: const TextStyle(
                                              color: muted, fontSize: 12.5)),
                                      const Spacer(),
                                      Text(
                                          inr(s.price(vehicle?.category ??
                                              'hatchback')),
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
            if (step == 2) ...[
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
                              "We'll notify you when your WashPro expert is on the way.",
                              style: TextStyle(color: dark, fontSize: 12))
                        ]))
                  ])),
            ],
            if (step == 3) ...[
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
                        () => setState(() => step = 2)),
                    const SizedBox(height: 13),
                    _reviewRow(
                        Icons.location_on_outlined,
                        'SERVICE AT',
                        '${addr?.label ?? ''} · ${addr?.slot ?? ''}\n${addr?.line ?? ''}',
                        () => setState(() => step = 2)),
                  ])),
              const SizedBox(height: 12),
              Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                      color: mint, borderRadius: BorderRadius.circular(18)),
                  child: Row(children: [
                    mintIcon(Icons.auto_awesome),
                    const SizedBox(width: 12),
                    const Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text('WELCOME75 applied',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800, color: dark)),
                          Text('You saved ₹75 on this booking',
                              style: TextStyle(color: dark, fontSize: 12.5))
                        ])),
                    const Icon(Icons.check, color: dark)
                  ])),
              const SizedBox(height: 12),
              wpCard(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    const Text('Price details',
                        style: TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 15.5)),
                    const SizedBox(height: 10),
                    _kv(service.name, inrFull(servicePaise)),
                    _kv('Service fee', inrFull(fee)),
                    if (washNow) _kv('Wash now express', '₹99'),
                    _kv('Introductory discount', '-₹75', color: green),
                    const Divider(height: 22, color: line),
                    Row(children: [
                      const Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text('Amount to pay',
                                style: TextStyle(
                                    fontWeight: FontWeight.w800, fontSize: 15)),
                            Text('Inclusive of applicable taxes',
                                style: TextStyle(color: muted, fontSize: 11))
                          ])),
                      Text(inrFull(total),
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 17))
                    ])
                  ])),
              const SizedBox(height: 14),
              Row(children: [
                const Text('Pay securely with',
                    style:
                        TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                const Spacer(),
                const Icon(Icons.verified_user, color: green, size: 19)
              ]),
              const SizedBox(height: 10),
              _payTile('UPI', 'Google Pay, PhonePe or any UPI app', 'UPI',
                  Icons.account_balance_wallet_outlined),
              _payTile('CARD', 'Credit / Debit Card · Visa, Mastercard, RuPay',
                  'CARD', Icons.credit_card),
              _payTile(
                  'CASH',
                  cashOk
                      ? 'Pay cash to the expert after the wash'
                      : 'Not available for this service/area',
                  'CASH',
                  Icons.payments_outlined,
                  enabled: cashOk),
            ],
          ])),
      Container(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: line))),
          child: Row(children: [
            if (step == 1)
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Starts at',
                    style: TextStyle(color: muted, fontSize: 11.5)),
                Text(inr(service.price(vehicle?.category ?? 'hatchback')),
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 19))
              ]),
            if (step == 3)
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Total',
                    style: TextStyle(color: muted, fontSize: 11.5)),
                Text(inrFull(total),
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 19))
              ]),
            const Spacer(),
            if (step > 0) ...[
              OutlinedButton(
                  onPressed: () => setState(() => step--),
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
                    onPressed: _next,
                    style: FilledButton.styleFrom(
                        backgroundColor: dark,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        padding: const EdgeInsets.symmetric(horizontal: 22)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(
                          creating
                              ? 'Please wait…'
                              : step == 2
                                  ? 'Review booking'
                                  : step == 3
                                      ? (pay == 'CASH'
                                          ? 'Confirm booking'
                                          : 'Continue')
                                      : 'Continue',
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 15)),
                      const SizedBox(width: 7),
                      Icon(
                          step == 3 && pay != 'CASH'
                              ? Icons.verified_user
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
  Widget _payTile(String title, String sub, String value, IconData icon,
          {bool enabled = true}) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: wpCard(
              selected: pay == value,
              p: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
              onTap: enabled ? () => setState(() => pay = value) : null,
              child: Row(children: [
                Container(
                    width: 42,
                    height: 32,
                    decoration: BoxDecoration(
                        color: mintBg, borderRadius: BorderRadius.circular(8)),
                    child: Icon(icon, size: 18, color: dark)),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(title,
                          style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13.5,
                              color: enabled ? ink : const Color(0xFFB7C6BC))),
                      Text(sub,
                          style: const TextStyle(color: muted, fontSize: 11.5))
                    ])),
                checkCircle(pay == value && enabled)
              ])));
  Future<void> _next() async {
    if (creating) return; // double-tap / retry guard
    if (step == 0 && vehicle == null) {
      toast(context, 'Add and select your car first');
      return;
    }
    if (step == 2 && addr == null) {
      toast(context, 'Add and select a service address first');
      return;
    }
    if (step < 3) {
      setState(() => step++);
      return;
    }
    setState(() => creating = true);
    final when =
        washNow ? DateTime.now() : DateTime(date.year, date.month, date.day);
    final b = Booking(
        AppState.nextId(),
        service,
        vehicle!,
        addr!,
        pay == 'CASH' ? 'confirmed' : 'awaiting_payment',
        when,
        washNow ? 'ASAP' : slot,
        total,
        servicePaise,
        pay,
        'pending',
        washNow ? 'instant' : 'scheduled');
    AppState.bookings.insert(0, b);
    await WashProRepository.saveBooking(b);
    if (!mounted) return;
    setState(() => creating = false);
    if (pay == 'CASH') {
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
  Future<void> _payOnline(Booking b, int total) async {
    try {
      toast(context, 'Opening secure Razorpay checkout…');
      final r = await RazorpayService.payBooking(
          bookingId: b.id,
          name: AppState.userName,
          email: AppState.userEmail,
          phone: AppState.userPhone);
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
          child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(children: [
                const SizedBox(height: 18),
                logoRow(light: true),
                const SizedBox(height: 38),
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
                            const Spacer(),
                            Text(b.id,
                                style: const TextStyle(
                                    color: green, fontWeight: FontWeight.w800))
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
                                Text(
                                    b.payStatus == 'paid'
                                        ? 'PAID'
                                        : b.payMethod == 'CASH'
                                            ? 'PAY AFTER WASH'
                                            : 'PAYMENT PENDING',
                                    style: const TextStyle(
                                        color: dark,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 12)),
                                const Spacer(),
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
                    label: const Text('Need help? Chat with WashPro support',
                        style:
                            TextStyle(color: Colors.white54, fontSize: 12.5))),
              ]))));
  Widget _sr(IconData i, String t) =>
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(i, color: green, size: 20),
        const SizedBox(width: 11),
        Text(t,
            style: const TextStyle(
                fontSize: 13, height: 1.4, fontWeight: FontWeight.w500))
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
        backgroundColor: mintBg,
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
                        const Text('Verified WashPro expert',
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
                              await WashProRepository.patchBooking(b.id,
                                  {'status': 'completed', 'rating': myRating});
                              setState(() {
                                b.status = 'completed';
                                b.rating = myRating;
                                toast(context, 'Thanks! Service verified ✓');
                              });
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
                        final r = await RazorpayService.payBooking(
                            bookingId: b.id,
                            name: AppState.userName,
                            email: AppState.userEmail,
                            phone: AppState.userPhone);
                        setState(() {
                          b.payStatus = 'paid';
                          b.status = 'confirmed';
                          b.providerRef = r.paymentId;
                        });
                        toast(context, 'Payment successful ✓');
                      } on PaymentUnavailable catch (e) {
                        toast(context, e.message);
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
              Row(children: [
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
                        label:
                            Text(o.$2, style: const TextStyle(fontSize: 11.5)),
                        selected: planSort == o.$1,
                        onSelected: (_) => setState(() => planSort = o.$1)))),
              ]),
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
                  title: Text('WashPro for Android',
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
              const Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text('Profile',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w800)),
                    Text('Your WashPro account',
                        style: TextStyle(color: muted, fontSize: 12))
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
                          child: Text(AppState.initials,
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
                            AppState.userName.isEmpty
                                ? 'WashPro customer'
                                : AppState.userName,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 17)),
                        Text(
                            AppState.userPhone.isNotEmpty
                                ? AppState.userPhone
                                : AppState.userEmail,
                            style: const TextStyle(
                                color: Colors.white60, fontSize: 12.5)),
                        const SizedBox(height: 7),
                        pill(AppState.memberSince == null
                            ? 'MEMBER'
                            : 'MEMBER SINCE ${AppState.memberSince!.year}')
                      ])),
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
      backgroundColor: mintBg,
      body: SafeArea(
          child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 22),
              children: [
            Row(children: [
              backBtn(context),
              const SizedBox(width: 12),
              Text(title,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w800)),
              const Spacer(),
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
              p: const EdgeInsets.all(22),
              child: const Column(children: [
                Text('🚙', style: TextStyle(fontSize: 30)),
                SizedBox(height: 8),
                Text('No vehicles yet',
                    style: TextStyle(fontWeight: FontWeight.w800)),
                Text('Add your car to see vehicle-specific pricing.',
                    style: TextStyle(color: muted, fontSize: 12.5))
              ])),
        ...AppState.vehicles.map((v) => Padding(
            padding: const EdgeInsets.only(bottom: 11),
            child: wpCard(
                child: Row(children: [
              Container(
                  width: 54,
                  height: 46,
                  decoration: BoxDecoration(
                      color: mint, borderRadius: BorderRadius.circular(12)),
                  child: const Center(
                      child: Text('🚙', style: TextStyle(fontSize: 26)))),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Row(children: [
                      Text('${v.make} ${v.model}',
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      if (v.isDefault) ...[
                        const SizedBox(width: 7),
                        pill('PRIMARY')
                      ]
                    ]),
                    Text('${v.reg} · ${v.color} · ${v.category}',
                        style: const TextStyle(color: muted, fontSize: 12))
                  ])),
              if (!v.isDefault)
                IconButton(
                    icon: const Icon(Icons.star_border, color: green),
                    tooltip: 'Set primary',
                    onPressed: () async {
                      await WashProRepository.setPrimaryVehicle(v.id);
                      setState(() {});
                    }),
              IconButton(
                  icon: const Icon(Icons.edit_outlined, color: muted),
                  onPressed: () => showVehicleDialog(
                      context, () => setState(() {}),
                      existing: v)),
              IconButton(
                  icon: const Icon(Icons.delete_outline,
                      color: Color(0xFFB42318)),
                  onPressed: () => showDialog(
                      context: context,
                      builder: (c) => AlertDialog(
                              title: const Text('Delete vehicle?'),
                              content: Text(
                                  'Remove ${v.make} ${v.model} (${v.reg}) from your garage?'),
                              actions: [
                                TextButton(
                                    onPressed: () => Navigator.pop(c),
                                    child: const Text('Keep')),
                                TextButton(
                                    onPressed: () async {
                                      await WashProRepository.deleteVehicle(
                                          v.id);
                                      setState(
                                          () => AppState.vehicles.remove(v));
                                      if (c.mounted) Navigator.pop(c);
                                    },
                                    child: const Text('Delete',
                                        style: TextStyle(
                                            color: Color(0xFFB42318))))
                              ])))
            ])))),
        SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
                onPressed: () =>
                    showVehicleDialog(context, () => setState(() {})),
                icon: const Icon(Icons.add, color: green),
                label: const Text('Add vehicle',
                    style: TextStyle(color: dark, fontWeight: FontWeight.w700)),
                style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 15),
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
  @override
  Widget build(BuildContext context) => SubPage(
      title: 'Saved addresses',
      child: Column(children: [
        if (AppState.loadError.isNotEmpty)
          loadErrorBanner(context, () async {
            await WashProRepository.refreshMine();
            if (mounted) setState(() {});
          }),
        if (AppState.addresses.isEmpty)
          wpCard(
              p: const EdgeInsets.all(22),
              child: const Column(children: [
                Text('📍', style: TextStyle(fontSize: 30)),
                SizedBox(height: 8),
                Text('No addresses yet',
                    style: TextStyle(fontWeight: FontWeight.w800)),
                Text('Add where your car is parked so experts can find it.',
                    style: TextStyle(color: muted, fontSize: 12.5))
              ])),
        ...AppState.addresses.map((a) => Padding(
            padding: const EdgeInsets.only(bottom: 11),
            child: wpCard(
                child: Row(children: [
              mintIcon(Icons.location_on_outlined),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Row(children: [
                      Text(a.label,
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      if (a.isDefault) ...[
                        const SizedBox(width: 7),
                        pill('SELECTED')
                      ]
                    ]),
                    Text('${a.line}\n${a.slot} · ${a.area}',
                        style: const TextStyle(
                            color: muted, fontSize: 12, height: 1.4))
                  ])),
              if (!a.isDefault)
                IconButton(
                    icon: const Icon(Icons.check_circle_outline, color: green),
                    tooltip: 'Use this address',
                    onPressed: () async {
                      await WashProRepository.setDefaultAddress(a.id);
                      setState(() {});
                    }),
              IconButton(
                  icon: const Icon(Icons.edit_outlined, color: muted),
                  onPressed: () => showAddressDialog(
                      context, () => setState(() {}),
                      existing: a)),
              IconButton(
                  icon: const Icon(Icons.delete_outline,
                      color: Color(0xFFB42318)),
                  onPressed: () => showDialog(
                      context: context,
                      builder: (c) => AlertDialog(
                              title: const Text('Delete address?'),
                              content: Text('Remove ${a.label} (${a.line})?'),
                              actions: [
                                TextButton(
                                    onPressed: () => Navigator.pop(c),
                                    child: const Text('Keep')),
                                TextButton(
                                    onPressed: () async {
                                      await WashProRepository.deleteAddress(
                                          a.id);
                                      setState(
                                          () => AppState.addresses.remove(a));
                                      if (c.mounted) Navigator.pop(c);
                                    },
                                    child: const Text('Delete',
                                        style: TextStyle(
                                            color: Color(0xFFB42318))))
                              ])))
            ])))),
        SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
                onPressed: () =>
                    showAddressDialog(context, () => setState(() {})),
                icon: const Icon(Icons.add_location_alt, color: green),
                label: const Text('Add address',
                    style: TextStyle(color: dark, fontWeight: FontWeight.w700)),
                style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 15),
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

void showVehicleDialog(BuildContext context, VoidCallback refresh,
    {Vehicle? existing}) {
  final nick = TextEditingController(text: existing?.nickname),
      make = TextEditingController(text: existing?.make),
      model = TextEditingController(text: existing?.model),
      reg = TextEditingController(text: existing?.reg);
  String cat = existing?.category ?? 'suv';
  showDialog(
      context: context,
      builder: (c) => AlertDialog(
              title: const Text('Add vehicle'),
              content: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                    controller: nick,
                    decoration: const InputDecoration(
                        labelText: 'Nickname (e.g. Nexon EV)')),
                TextField(
                    controller: make,
                    decoration:
                        const InputDecoration(labelText: 'Make (Tata)')),
                TextField(
                    controller: model,
                    decoration:
                        const InputDecoration(labelText: 'Model (Nexon EV)')),
                TextField(
                    controller: reg,
                    decoration: const InputDecoration(
                        labelText: 'Registration (TS 09 MX 1234)')),
                DropdownButtonFormField(
                    value: cat,
                    items: ['hatchback', 'sedan', 'suv', 'luxury']
                        .map((x) => DropdownMenuItem(value: x, child: Text(x)))
                        .toList(),
                    onChanged: (v) => cat = v!,
                    decoration: const InputDecoration(labelText: 'Category'))
              ])),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(c),
                    child: const Text('Cancel')),
                FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: dark),
                    onPressed: () async {
                      if (make.text.trim().isEmpty ||
                          model.text.trim().isEmpty ||
                          reg.text.trim().isEmpty) {
                        return;
                      }
                      if (existing != null) {
                        existing.nickname =
                            nick.text.isEmpty ? model.text : nick.text;
                        existing.category = cat;
                        existing.make = make.text;
                        existing.model = model.text;
                        existing.reg = reg.text.toUpperCase();
                        await WashProRepository.updateVehicle(existing);
                      } else {
                        final nv = Vehicle(
                            'v${DateTime.now().millisecondsSinceEpoch}',
                            nick.text.isEmpty ? model.text : nick.text,
                            cat,
                            make.text,
                            model.text,
                            '—',
                            reg.text.toUpperCase());
                        if (AppState.vehicles.isEmpty) nv.isDefault = true;
                        AppState.vehicles.add(nv);
                        await WashProRepository.saveVehicle(nv);
                      }
                      if (c.mounted) Navigator.pop(c);
                      refresh();
                    },
                    child: const Text('Save'))
              ]));
}

void showAddressDialog(BuildContext context, VoidCallback refresh,
    {Addr? existing}) {
  final label = TextEditingController(text: existing?.label),
      line = TextEditingController(text: existing?.line),
      slotC = TextEditingController(text: existing?.slot);
  showDialog(
      context: context,
      builder: (c) => AlertDialog(
              title: Text(existing == null ? 'Add address' : 'Edit address'),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                    controller: label,
                    decoration: const InputDecoration(
                        labelText: 'Label (Home / Office)')),
                TextField(
                    controller: line,
                    decoration: const InputDecoration(
                        labelText: 'Full address (society, tower, area)')),
                TextField(
                    controller: slotC,
                    decoration: const InputDecoration(
                        labelText: 'Parking slot / gate notes (e.g. B2-118)'))
              ]),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(c),
                    child: const Text('Cancel')),
                FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: dark),
                    onPressed: () async {
                      if (line.text.trim().isEmpty) return;
                      if (existing != null) {
                        existing.label =
                            label.text.isEmpty ? 'Address' : label.text;
                        existing.line = line.text;
                        existing.slot = slotC.text;
                        await WashProRepository.updateAddress(existing);
                      } else {
                        final na = Addr(
                            'a${DateTime.now().millisecondsSinceEpoch}',
                            label.text.isEmpty ? 'Address' : label.text,
                            line.text,
                            'Hyderabad',
                            'kondapur',
                            slotC.text.isEmpty ? '—' : slotC.text);
                        if (AppState.addresses.isEmpty) na.isDefault = true;
                        AppState.addresses.add(na);
                        await WashProRepository.saveAddress(na);
                      }
                      if (c.mounted) Navigator.pop(c);
                      refresh();
                    },
                    child: const Text('Save'))
              ]));
}
