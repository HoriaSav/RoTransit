import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:uuid/uuid.dart';

import '../domain/app_user.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final hasFirebase = Firebase.apps.isNotEmpty;
  return AuthRepository(
    firebaseAuth: hasFirebase ? FirebaseAuth.instance : null,
    googleSignIn: hasFirebase ? GoogleSignIn() : null,
  );
});

class AuthRepository {
  AuthRepository({
    required FirebaseAuth? firebaseAuth,
    required GoogleSignIn? googleSignIn,
  })  : _firebaseAuth = firebaseAuth,
        _googleSignIn = googleSignIn;

  final FirebaseAuth? _firebaseAuth;
  final GoogleSignIn? _googleSignIn;
  static const _guestIdKey = 'guest_device_user_id';

  Future<AppUser> signInAsGuest() async {
    final prefs = await SharedPreferences.getInstance();
    var guestId = prefs.getString(_guestIdKey);
    guestId ??= const Uuid().v4();
    await prefs.setString(_guestIdKey, guestId);
    return AppUser(id: guestId, provider: AuthProviderType.guest);
  }

  Future<AppUser> signInWithGoogle() async {
    if (_firebaseAuth == null || _googleSignIn == null) {
      return signInAsGuest();
    }
    final account = await _googleSignIn.signIn();
    if (account == null) {
      return signInAsGuest();
    }
    final auth = await account.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: auth.accessToken,
      idToken: auth.idToken,
    );
    final result = await _firebaseAuth.signInWithCredential(credential);
    final user = result.user;
    if (user == null) return signInAsGuest();
    return AppUser(
      id: user.uid,
      provider: AuthProviderType.google,
      email: user.email,
    );
  }

  Future<AppUser> signInWithApple() async {
    if (_firebaseAuth == null) {
      return signInAsGuest();
    }
    final appleIdCredential = await SignInWithApple.getAppleIDCredential(
      scopes: [AppleIDAuthorizationScopes.email],
    );
    final oauthCredential = OAuthProvider('apple.com').credential(
      idToken: appleIdCredential.identityToken,
      accessToken: appleIdCredential.authorizationCode,
    );
    final result = await _firebaseAuth.signInWithCredential(oauthCredential);
    final user = result.user;
    if (user == null) return signInAsGuest();
    return AppUser(
      id: user.uid,
      provider: AuthProviderType.apple,
      email: user.email,
    );
  }
}
