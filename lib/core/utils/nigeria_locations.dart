/// Nigeria's states and the towns people actually write on an address.
///
/// Typed into free-text boxes, a state is spelled six ways ("FCT", "Abuja",
/// "F.C.T", "Federal Capital Territory") and a city ten, and the marketplace
/// then matches none of them against each other: a tenant filtering for
/// "Lagos" misses every listing whose landlord typed "lagos state". Offering
/// the list instead is what makes the two sides of that search agree.
///
/// The city lists are **not** the full 774 LGAs. They are the places a
/// property is plausibly advertised in: LGA headquarters plus the well-known
/// districts and towns inside the big metros, which is what somebody writes
/// on a Nigerian address. The picker lets a landlord type anything not in the
/// list, so an omission is an inconvenience rather than a wall.
class NigeriaLocations {
  NigeriaLocations._();

  /// Every state, alphabetical, with the FCT under the name people use for
  /// it. "Abuja" rather than "Federal Capital Territory": it is what the
  /// address says, and it is what a tenant types into the search box.
  static const Map<String, List<String>> statesWithCities = {
    'Abia': [
      'Aba',
      'Arochukwu',
      'Bende',
      'Isiala Ngwa',
      'Ohafia',
      'Umuahia',
    ],
    'Abuja (FCT)': [
      'Asokoro',
      'Bwari',
      'Central Business District',
      'Dawaki',
      'Garki',
      'Gwagwalada',
      'Gwarinpa',
      'Jabi',
      'Jahi',
      'Karu',
      'Katampe',
      'Kubwa',
      'Kuje',
      'Lokogoma',
      'Lugbe',
      'Maitama',
      'Mpape',
      'Nyanya',
      'Utako',
      'Wuse',
      'Wuse 2',
    ],
    'Adamawa': ['Ganye', 'Gombi', 'Jimeta', 'Mubi', 'Numan', 'Yola'],
    'Akwa Ibom': [
      'Eket',
      'Ikot Abasi',
      'Ikot Ekpene',
      'Oron',
      'Uyo',
    ],
    'Anambra': [
      'Awka',
      'Ekwulobia',
      'Nnewi',
      'Obosi',
      'Ogidi',
      'Onitsha',
    ],
    'Bauchi': ['Azare', 'Bauchi', 'Jama\'are', 'Misau', 'Ningi'],
    'Bayelsa': ['Brass', 'Ogbia', 'Sagbama', 'Yenagoa'],
    'Benue': ['Gboko', 'Katsina-Ala', 'Makurdi', 'Otukpo', 'Vandeikya'],
    'Borno': ['Bama', 'Biu', 'Dikwa', 'Maiduguri', 'Monguno'],
    'Cross River': ['Calabar', 'Ikom', 'Obudu', 'Ogoja', 'Ugep'],
    'Delta': [
      'Agbor',
      'Asaba',
      'Effurun',
      'Oghara',
      'Sapele',
      'Ughelli',
      'Warri',
    ],
    'Ebonyi': ['Abakaliki', 'Afikpo', 'Onueke'],
    'Edo': ['Auchi', 'Benin City', 'Ekpoma', 'Igarra', 'Uromi'],
    'Ekiti': ['Ado-Ekiti', 'Efon-Alaaye', 'Ikere-Ekiti', 'Ikole-Ekiti'],
    'Enugu': ['Awgu', 'Enugu', 'Nsukka', 'Oji River', 'Udi'],
    'Gombe': ['Bajoga', 'Billiri', 'Deba', 'Gombe', 'Kaltungo'],
    'Imo': ['Mbaise', 'Okigwe', 'Orlu', 'Owerri'],
    'Jigawa': ['Birnin Kudu', 'Dutse', 'Gumel', 'Hadejia', 'Kazaure'],
    'Kaduna': [
      'Kaduna',
      'Kafanchan',
      'Sabon Gari',
      'Zaria',
      'Zonkwa',
    ],
    'Kano': ['Bichi', 'Dala', 'Gwale', 'Kano', 'Nassarawa', 'Wudil'],
    'Katsina': ['Daura', 'Funtua', 'Katsina', 'Malumfashi'],
    'Kebbi': ['Argungu', 'Birnin Kebbi', 'Yauri', 'Zuru'],
    'Kogi': ['Idah', 'Kabba', 'Lokoja', 'Okene'],
    'Kwara': ['Ilorin', 'Jebba', 'Offa', 'Omu-Aran', 'Patigi'],
    'Lagos': [
      'Agege',
      'Ajah',
      'Alimosho',
      'Amuwo-Odofin',
      'Apapa',
      'Badagry',
      'Epe',
      'Festac',
      'Gbagada',
      'Ifako-Ijaiye',
      'Ikeja',
      'Ikorodu',
      'Ikoyi',
      'Ilupeju',
      'Isolo',
      'Ketu',
      'Lagos Island',
      'Lekki',
      'Magodo',
      'Maryland',
      'Mushin',
      'Ogba',
      'Ogudu',
      'Ojo',
      'Ojota',
      'Oshodi',
      'Sangotedo',
      'Shomolu',
      'Surulere',
      'Victoria Island',
      'Yaba',
    ],
    'Nasarawa': ['Akwanga', 'Karu', 'Keffi', 'Lafia', 'Nasarawa'],
    'Niger': ['Bida', 'Kontagora', 'Minna', 'Suleja'],
    'Ogun': [
      'Abeokuta',
      'Ado-Odo/Ota',
      'Ijebu-Ode',
      'Ilaro',
      'Mowe',
      'Sagamu',
      'Sango Ota',
    ],
    'Ondo': ['Akure', 'Ikare', 'Okitipupa', 'Ondo', 'Owo'],
    'Osun': ['Ede', 'Ife', 'Ikirun', 'Ilesa', 'Osogbo'],
    'Oyo': ['Bodija', 'Ibadan', 'Iseyin', 'Ogbomosho', 'Oyo', 'Saki'],
    'Plateau': ['Barkin Ladi', 'Bukuru', 'Jos', 'Pankshin', 'Shendam'],
    'Rivers': [
      'Bonny',
      'Eleme',
      'Obio-Akpor',
      'Okrika',
      'Port Harcourt',
      'Rumuokoro',
    ],
    'Sokoto': ['Gwadabawa', 'Sokoto', 'Tambuwal', 'Wurno'],
    'Taraba': ['Bali', 'Gembu', 'Jalingo', 'Wukari'],
    'Yobe': ['Damaturu', 'Gashua', 'Nguru', 'Potiskum'],
    'Zamfara': ['Gusau', 'Kaura Namoda', 'Talata Mafara'],
  };

  /// The state names, in the order the picker shows them.
  static List<String> get states => statesWithCities.keys.toList();

  /// Towns for [state], or an empty list when the state is not one we know.
  static List<String> citiesIn(String? state) =>
      statesWithCities[canonicalState(state) ?? ''] ?? const [];

  /// Maps whatever a user or the geocoder produced onto the exact spelling in
  /// [statesWithCities], or null when it is nothing we recognise.
  ///
  /// This is the one place that knows "FCT", "Federal Capital Territory" and
  /// "Abuja" name the same place. Nominatim answers with the formal name,
  /// people type the short one, and the marketplace matches on the string.
  static String? canonicalState(String? value) {
    final needle = _normalise(value);
    if (needle.isEmpty) return null;

    for (final alias in _stateAliases.entries) {
      if (alias.key == needle) return alias.value;
    }
    for (final state in statesWithCities.keys) {
      final normalised = _normalise(state);
      if (normalised == needle) return state;
      // "Abuja (FCT)" against "abuja", and "Nasarawa State" against
      // "Nasarawa": a containment check either way covers both without
      // enumerating every decoration a source might add.
      if (normalised.startsWith(needle) || needle.startsWith(normalised)) {
        return state;
      }
    }
    return null;
  }

  /// Maps a geocoded town onto the spelling in this state's list, or null.
  ///
  /// Only ever a *lookup*: a town that is not in the list is returned to the
  /// caller unchanged rather than being replaced by a near-miss, because
  /// guessing at somebody's address is worse than leaving what they wrote.
  static String? canonicalCity({required String? state, String? city}) {
    final needle = _normalise(city);
    if (needle.isEmpty) return null;
    for (final known in citiesIn(state)) {
      final normalised = _normalise(known);
      if (normalised == needle) return known;
      // "Ikeja LGA" or "Port Harcourt City" against the plain name.
      if (needle.startsWith(normalised) || normalised.startsWith(needle)) {
        return known;
      }
    }
    return null;
  }

  /// Lower-cased, punctuation-free, single-spaced, so "Akwa-Ibom",
  /// "akwa ibom" and "AKWA  IBOM" compare equal.
  static String _normalise(String? value) => (value ?? '')
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Spellings that are not a prefix of the canonical name, so the
  /// containment rule above cannot reach them.
  static const Map<String, String> _stateAliases = {
    'fct': 'Abuja (FCT)',
    'f c t': 'Abuja (FCT)',
    'federal capital territory': 'Abuja (FCT)',
    'fct abuja': 'Abuja (FCT)',
    'abuja federal capital territory': 'Abuja (FCT)',
    'nassarawa': 'Nasarawa',
    'cross rivers': 'Cross River',
    'akwa ibom state': 'Akwa Ibom',
  };
}
