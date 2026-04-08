enum AuthProviderType { guest, google, apple }

class AppUser {
  const AppUser({required this.id, required this.provider, this.email});

  final String id;
  final AuthProviderType provider;
  final String? email;
}
