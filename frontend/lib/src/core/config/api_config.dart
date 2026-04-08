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
}
