import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_repository.dart';
import '../domain/app_user.dart';

final sessionProvider = StateNotifierProvider<SessionController, AppUser?>(
  (ref) => SessionController(ref.read(authRepositoryProvider)),
);

class SessionController extends StateNotifier<AppUser?> {
  SessionController(this._authRepository) : super(null);

  final AuthRepository _authRepository;

  Future<void> continueAsGuest() async {
    state = await _authRepository.signInAsGuest();
  }

  Future<void> signInGoogle() async {
    state = await _authRepository.signInWithGoogle();
  }

  Future<void> signInApple() async {
    state = await _authRepository.signInWithApple();
  }
}
