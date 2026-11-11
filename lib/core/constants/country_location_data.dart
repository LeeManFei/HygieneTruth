/// Centralized Country & State / City location dataset
/// Provides synchronized, hierarchical Country-to-State mapping across the app.
class CountryLocationData {
  static const Map<String, List<String>> countryStatesMap = {
    'Malaysia': [
      'Kuala Lumpur',
      'Selangor',
      'Penang',
      'Johor',
      'Perak',
      'Melaka',
      'Kedah',
      'Pahang',
      'Negeri Sembilan',
      'Sabah',
      'Sarawak',
      'Kelantan',
      'Terengganu',
      'Perlis',
      'Putrajaya',
      'Labuan',
      'Other',
    ],
    'Singapore': [
      'Central Region',
      'East Region',
      'North Region',
      'North-East Region',
      'West Region',
      'Downtown / Marina Bay',
      'Singapore (City)',
      'Other',
    ],
    'Indonesia': [
      'Jakarta',
      'West Java (Bandung)',
      'Central Java (Semarang)',
      'East Java (Surabaya)',
      'Bali (Denpasar)',
      'North Sumatra (Medan)',
      'Banten',
      'Yogyakarta',
      'Other',
    ],
    'Thailand': [
      'Bangkok',
      'Chiang Mai',
      'Phuket',
      'Chonburi (Pattaya)',
      'Nonthaburi',
      'Surat Thani (Koh Samui)',
      'Krabi',
      'Other',
    ],
    'Brunei': [
      'Brunei-Muara (Bandar Seri Begawan)',
      'Belait',
      'Tutong',
      'Temburong',
      'Other',
    ],
    'United States': [
      'California',
      'New York',
      'Texas',
      'Florida',
      'Washington',
      'Illinois',
      'Massachusetts',
      'Other',
    ],
    'United Kingdom': [
      'London',
      'Manchester',
      'Birmingham',
      'Edinburgh',
      'Glasgow',
      'Other',
    ],
    'Australia': [
      'New South Wales (Sydney)',
      'Victoria (Melbourne)',
      'Queensland (Brisbane)',
      'Western Australia (Perth)',
      'Other',
    ],
    'China': [
      'Beijing',
      'Shanghai',
      'Guangdong (Guangzhou / Shenzhen)',
      'Zhejiang (Hangzhou)',
      'Sichuan (Chengdu)',
      'Other',
    ],
    'Other': [
      'Other / International',
    ],
  };

  static List<String> get countryList => countryStatesMap.keys.toList();

  /// Resolves the corresponding states/cities for a given country name
  static List<String> getStatesForCountry(String? country) {
    if (country == null || country.isEmpty) {
      return countryStatesMap['Malaysia']!;
    }

    final cleanCountry = country
        .replaceAll(RegExp(r'[\u{1F1E6}-\u{1F1FF}]', unicode: true), '')
        .trim();

    for (final entry in countryStatesMap.entries) {
      if (entry.key.toLowerCase() == cleanCountry.toLowerCase() ||
          cleanCountry.toLowerCase().contains(entry.key.toLowerCase()) ||
          entry.key.toLowerCase().contains(cleanCountry.toLowerCase())) {
        return entry.value;
      }
    }

    return countryStatesMap['Other']!;
  }
}
