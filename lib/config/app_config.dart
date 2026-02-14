class AppConfig {
  final String baseUrl;
  final String version;

  AppConfig({required this.baseUrl, required this.version});

  static AppConfig fromCountry(String country) {
    switch (country) {
      case 'CA':
        return AppConfig(
          baseUrl: 'https://clickstocartca.com',
          version: '05c7c5a71e52',
        );
      case 'US':
      default:
        return AppConfig(
          baseUrl: 'https://clickstocartus.com',
          version: 'bf1c4c815a09',
        );
    }
  }
}
