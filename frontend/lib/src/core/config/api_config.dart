class ApiConfig {
  static const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8085',
  );

  // Set to true to use backend APIs; false keeps UI fully local.
  static const useBackend = bool.fromEnvironment(
    'USE_BACKEND',
    defaultValue: true,
  );

  // Keep resolve-for-route disabled on the hot path unless explicitly enabled.
  static const resolveAmbiguousDestination = bool.fromEnvironment(
    'RESOLVE_AMBIGUOUS_DESTINATION',
    defaultValue: false,
  );
}
