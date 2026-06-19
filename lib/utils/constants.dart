/// App-wide constants.
class AppConstants {
  AppConstants._();

  static const String appName = 'UPSC Daily Edge';
  static const String tagline = 'Your Daily UPSC Companion';

  // Quiz settings
  static const int quizTimerSeconds = 30;
  static const int questionsPerQuiz = 10;

  // Category icon mapping (Flaticon PNG assets)
  static const String _iconBase = 'assets/flaticon_pngs/';
  static const Map<String, String> categoryIcons = {
    'Polity': '${_iconBase}polity.png',
    'Economy': '${_iconBase}economy.png',
    'Environment': '${_iconBase}environment.png',
    'Science & Technology': '${_iconBase}science.png',
    'International Relations': '${_iconBase}international.png',
    'History': '${_iconBase}history.png',
    'Geography': '${_iconBase}geography.png',
    'Social Issues': '${_iconBase}people_community.png',
    'Governance': '${_iconBase}scales_justice.png',
    'Security': '${_iconBase}shield.png',
    'Ethics': '${_iconBase}compass.png',
    'Current Affairs': '${_iconBase}newspaper.png',
    'Defence': '${_iconBase}military_badge.png',
    'Art & Culture': '${_iconBase}theater_masks.png',
    'Agriculture': '${_iconBase}wheat_agriculture.png',
  };
}
