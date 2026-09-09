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
  /// Where each state's map view should open, as (latitude, longitude).
  ///
  /// The capital, or the city the state is actually known by — Edo points at
  /// Benin City, Oyo at Ibadan, Rivers at Port Harcourt.
  ///
  /// Bundled rather than looked up, for three reasons. A state's centre never
  /// changes, so asking a third party for it every time is a request that can
  /// only fail. Nominatim rate-limits hard — this machine collected a `429`
  /// probing four of these in a row — and the geocoder treats any non-200 as
  /// "not found", so a throttled landlord got no answer and a map still
  /// showing Lagos. And it is instant and works offline, which matters on the
  /// connections this app is used over.
  ///
  /// The network is still asked for the *street*, which is the part that
  /// genuinely varies. This only answers "roughly where is this state".
  ///
  /// Kept as a record rather than a `LatLng` so this file stays free of the
  /// mapping package: it is a data table, not a map widget.
  static const Map<String, (double, double)> stateCentres = {
    'Abia': (5.5320, 7.4860),
    'Abuja (FCT)': (9.0765, 7.3986),
    'Adamawa': (9.2035, 12.4954),
    'Akwa Ibom': (5.0377, 7.9128),
    'Anambra': (6.2109, 7.0741),
    'Bauchi': (10.3158, 9.8442),
    'Bayelsa': (4.9267, 6.2676),
    'Benue': (7.7322, 8.5391),
    'Borno': (11.8311, 13.1510),
    'Cross River': (4.9757, 8.3417),
    'Delta': (6.1980, 6.7370),
    'Ebonyi': (6.3249, 8.1137),
    'Edo': (6.3350, 5.6037),
    'Ekiti': (7.6211, 5.2214),
    'Enugu': (6.4584, 7.5464),
    'Gombe': (10.2897, 11.1673),
    'Imo': (5.4836, 7.0333),
    'Jigawa': (11.7568, 9.3389),
    'Kaduna': (10.5222, 7.4383),
    'Kano': (12.0022, 8.5920),
    'Katsina': (12.9908, 7.6018),
    'Kebbi': (12.4539, 4.1975),
    'Kogi': (7.8023, 6.7333),
    'Kwara': (8.4966, 4.5421),
    'Lagos': (6.5244, 3.3792),
    'Nasarawa': (8.4939, 8.5157),
    'Niger': (9.6139, 6.5569),
    'Ogun': (7.1475, 3.3619),
    'Ondo': (7.2571, 5.2058),
    'Osun': (7.7827, 4.5418),
    'Oyo': (7.3775, 3.9470),
    'Plateau': (9.8965, 8.8583),
    'Rivers': (4.8156, 7.0498),
    'Sokoto': (13.0059, 5.2476),
    'Taraba': (8.8900, 11.3660),
    'Yobe': (11.7480, 11.9608),
    'Zamfara': (12.1628, 6.6641),
  };

  /// The map centre for a state name in any spelling the picker accepts.
  ///
  /// Goes through [canonicalState] first, so "lagos state", "FCT" and
  /// "Federal Capital Territory" all resolve.
  static (double, double)? centreOf(String? state) {
    final canonical = canonicalState(state);
    return canonical == null ? null : stateCentres[canonical];
  }

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
