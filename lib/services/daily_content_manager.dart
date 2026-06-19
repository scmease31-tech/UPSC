import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/dummy_data.dart';
import '../models/quiz_question.dart';

/// Manages daily rotation of quiz questions, flashcards, and daily challenge.
/// Fetches from Firestore when available; falls back to local data.
class DailyContentManager {
  static const _keyLastQuizDate = 'dcm_lastQuizDate';
  static const _keyLastFlashcardDate = 'dcm_lastFlashcardDate';
  static const _keyContentUpdateLog = 'dcm_contentUpdateLog';

  // Cached Firestore flashcards
  static List<Map<String, String>>? _cachedFirestoreFlashcards;
  // Cached Firestore daily facts
  static List<Map<String, dynamic>>? _cachedDailyFacts;

  /// Get today's date as string.
  static String _today() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  /// Get a daily seed based on date for deterministic shuffling.
  static int _dailySeed(DateTime date) {
    return date.year * 10000 + date.month * 100 + date.day;
  }

  /// Get today's quiz questions — rotated daily, 10 questions per day.
  static List<QuizQuestion> getTodaysQuizQuestions() {
    final seed = _dailySeed(DateTime.now());
    final allQuestions = List<QuizQuestion>.from(DummyData.quizQuestions);
    final rng = Random(seed);
    allQuestions.shuffle(rng);
    return allQuestions.take(10).toList();
  }

  /// Get today's daily challenge questions — 5 questions, different from quiz.
  static List<Map<String, dynamic>> getTodaysChallengeQuestions() {
    final seed = _dailySeed(DateTime.now()) + 999; // Different seed from quiz
    final rng = Random(seed);

    // Extended question bank for daily challenges
    final allChallengeQs = _extendedChallengeQuestions;
    final shuffled = List<Map<String, dynamic>>.from(allChallengeQs);
    shuffled.shuffle(rng);
    return shuffled.take(5).toList();
  }

  /// Get today's flashcard set — tries Firestore first, falls back to local.
  static List<Map<String, String>> getTodaysFlashcards() {
    final seed = _dailySeed(DateTime.now()) + 500;
    final rng = Random(seed);

    // Use Firestore cache if available
    if (_cachedFirestoreFlashcards != null && _cachedFirestoreFlashcards!.isNotEmpty) {
      final allCards = List<Map<String, String>>.from(_cachedFirestoreFlashcards!);
      allCards.shuffle(rng);
      return allCards.take(15).toList();
    }

    final allCards = List<Map<String, String>>.from(_extendedFlashcards);
    allCards.shuffle(rng);
    return allCards.take(15).toList();
  }

  /// Fetch flashcards from Firestore and cache them.
  static Future<void> fetchFlashcardsFromFirestore() async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection('flashcards').get();
      if (snapshot.docs.isNotEmpty) {
        _cachedFirestoreFlashcards = snapshot.docs.map((doc) {
          final data = doc.data();
          return <String, String>{
            'front': (data['front'] ?? '') as String,
            'back': (data['back'] ?? '') as String,
            'category': (data['category'] ?? '') as String,
          };
        }).toList();
      }
    } catch (_) {
      // Silently fall back to local data
    }
  }

  /// Fetch daily facts from Firestore for the Must-Know screen.
  static Future<List<Map<String, dynamic>>> fetchDailyFacts() async {
    if (_cachedDailyFacts != null) return _cachedDailyFacts!;
    try {
      final snapshot = await FirebaseFirestore.instance.collection('dailyFacts').get();
      if (snapshot.docs.isNotEmpty) {
        _cachedDailyFacts = snapshot.docs.map((doc) {
          final data = doc.data();
          return <String, dynamic>{
            'category': data['category'] ?? '',
            'title': data['title'] ?? '',
            'facts': (data['facts'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
          };
        }).toList();
        return _cachedDailyFacts!;
      }
    } catch (_) {
      // Fall through to empty list
    }
    return [];
  }

  /// Log that content was refreshed today.
  static Future<void> logContentUpdate(String contentType) async {
    final prefs = await SharedPreferences.getInstance();
    final log = prefs.getStringList(_keyContentUpdateLog) ?? [];
    log.add('${_today()}|$contentType');
    // Keep last 30 entries
    if (log.length > 30) log.removeRange(0, log.length - 30);
    await prefs.setStringList(_keyContentUpdateLog, log);
  }

  /// Get content update history for tracker.
  static Future<List<String>> getContentUpdateLog() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_keyContentUpdateLog) ?? [];
  }

  /// Check if quiz was updated today.
  static Future<bool> isQuizUpdatedToday() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyLastQuizDate) == _today();
  }

  /// Mark quiz as updated today.
  static Future<void> markQuizUpdated() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastQuizDate, _today());
    await logContentUpdate('quiz');
  }

  /// Check if flashcards were updated today.
  static Future<bool> isFlashcardUpdatedToday() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyLastFlashcardDate) == _today();
  }

  /// Mark flashcards as updated today.
  static Future<void> markFlashcardUpdated() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastFlashcardDate, _today());
    await logContentUpdate('flashcards');
  }

  // ──────────────────────────────────────────────────────────────────────────
  // EXTENDED DAILY CHALLENGE QUESTIONS (40+ questions for variety)
  // ──────────────────────────────────────────────────────────────────────────
  static const _extendedChallengeQuestions = [
    {
      'q': 'Which article of the Indian Constitution deals with the Right to Equality?',
      'options': ['Article 12', 'Article 14', 'Article 19', 'Article 21'],
      'answer': 1,
      'explain': 'Article 14 guarantees equality before law and equal protection of laws within the territory of India.',
    },
    {
      'q': 'The Palk Strait separates India from which country?',
      'options': ['Bangladesh', 'Myanmar', 'Sri Lanka', 'Maldives'],
      'answer': 2,
      'explain': 'The Palk Strait is between Tamil Nadu (India) and Mannar district of Sri Lanka.',
    },
    {
      'q': 'Which Five Year Plan is known as the "Mahalanobis Plan"?',
      'options': ['First', 'Second', 'Third', 'Fourth'],
      'answer': 1,
      'explain': 'The Second Five Year Plan (1956-61) was based on P.C. Mahalanobis model focusing on rapid industrialization.',
    },
    {
      'q': 'ISRO\'s launch vehicle GSLV uses which type of upper stage engine?',
      'options': ['Solid fuel', 'Liquid fuel', 'Cryogenic', 'Ion propulsion'],
      'answer': 2,
      'explain': 'GSLV uses an indigenous cryogenic upper stage (CUS) engine using liquid hydrogen and liquid oxygen.',
    },
    {
      'q': 'The concept of "Basic Structure" doctrine was established in which case?',
      'options': ['Golaknath case', 'Kesavananda Bharati case', 'Minerva Mills case', 'Maneka Gandhi case'],
      'answer': 1,
      'explain': 'Kesavananda Bharati v. State of Kerala (1973) established that Parliament cannot alter the basic structure of the Constitution.',
    },
    {
      'q': 'Which body recommends the distribution of taxes between Centre and States?',
      'options': ['NITI Aayog', 'Planning Commission', 'Finance Commission', 'GST Council'],
      'answer': 2,
      'explain': 'The Finance Commission (Article 280) recommends the distribution of net proceeds of taxes between Centre and States.',
    },
    {
      'q': 'The National Green Tribunal (NGT) was established under which Act?',
      'options': ['Environment Protection Act, 1986', 'National Green Tribunal Act, 2010', 'Wildlife Protection Act, 1972', 'Forest Conservation Act, 1980'],
      'answer': 1,
      'explain': 'NGT was established under the National Green Tribunal Act, 2010 for effective disposal of environmental cases.',
    },
    {
      'q': 'Which river is called the "Sorrow of Bengal"?',
      'options': ['Hooghly', 'Kosi', 'Damodar', 'Teesta'],
      'answer': 2,
      'explain': 'River Damodar is called the "Sorrow of Bengal" due to its devastating floods. Kosi is the "Sorrow of Bihar".',
    },
    {
      'q': 'The Chipko Movement was started in which state?',
      'options': ['Himachal Pradesh', 'Uttarakhand', 'Jharkhand', 'Rajasthan'],
      'answer': 1,
      'explain': 'The Chipko Movement started in 1973 in Chamoli district of Uttarakhand led by Sunderlal Bahuguna and Gaura Devi.',
    },
    {
      'q': 'Which Article of the Constitution empowers the President to proclaim a National Emergency?',
      'options': ['Article 352', 'Article 356', 'Article 360', 'Article 365'],
      'answer': 0,
      'explain': 'Article 352 empowers the President to proclaim National Emergency on grounds of war, external aggression, or armed rebellion.',
    },
    {
      'q': 'The headquarters of the International Court of Justice is at:',
      'options': ['Geneva', 'New York', 'The Hague', 'Vienna'],
      'answer': 2,
      'explain': 'The ICJ is the principal judicial organ of the UN, located at the Peace Palace in The Hague, Netherlands.',
    },
    {
      'q': 'Which committee recommended the three-tier Panchayati Raj system?',
      'options': ['Ashok Mehta', 'Balwant Rai Mehta', 'L.M. Singhvi', 'G.V.K. Rao'],
      'answer': 1,
      'explain': 'The Balwant Rai Mehta Committee (1957) recommended the three-tier (village, block, district) Panchayati Raj system.',
    },
    {
      'q': 'Which gas is most abundant in Earth\'s atmosphere?',
      'options': ['Oxygen', 'Carbon Dioxide', 'Nitrogen', 'Argon'],
      'answer': 2,
      'explain': 'Nitrogen makes up approximately 78% of Earth\'s atmosphere, followed by Oxygen at about 21%.',
    },
    {
      'q': 'The Indian Ocean Rim Association (IORA) is headquartered in:',
      'options': ['New Delhi', 'Colombo', 'Mauritius', 'Jakarta'],
      'answer': 2,
      'explain': 'IORA is headquartered in Ebene, Mauritius. It has 23 member states and aims at sustainable growth and development.',
    },
    {
      'q': 'Which Schedule of the Constitution lists the languages recognized?',
      'options': ['Seventh Schedule', 'Eighth Schedule', 'Ninth Schedule', 'Tenth Schedule'],
      'answer': 1,
      'explain': 'The Eighth Schedule currently recognizes 22 languages. The 92nd Amendment (2003) added Bodo, Dogri, Maithili, and Santhali.',
    },
    {
      'q': 'The Indus Water Treaty was signed between India and Pakistan in:',
      'options': ['1947', '1960', '1971', '1972'],
      'answer': 1,
      'explain': 'The Indus Waters Treaty was signed in 1960 brokered by the World Bank. India got Ravi, Beas, Sutlej; Pakistan got Indus, Jhelum, Chenab.',
    },
    {
      'q': 'Biosphere Reserves in India are designated by:',
      'options': ['UNESCO', 'Government of India', 'IUCN', 'WWF'],
      'answer': 1,
      'explain': 'Biosphere Reserves are designated by the Government of India. UNESCO may then recognize them under its MAB (Man and Biosphere) programme.',
    },
    {
      'q': 'Which is the largest freshwater lake in India?',
      'options': ['Chilika Lake', 'Wular Lake', 'Dal Lake', 'Loktak Lake'],
      'answer': 1,
      'explain': 'Wular Lake in J&K is the largest freshwater lake in India. Chilika in Odisha is the largest brackish water lake.',
    },
    {
      'q': 'The concept of "Welfare State" in India is derived from:',
      'options': ['Fundamental Rights', 'Directive Principles', 'Preamble', 'Fundamental Duties'],
      'answer': 1,
      'explain': 'The Directive Principles of State Policy (Part IV, Articles 36-51) embody the concept of a Welfare State, borrowed from the Irish Constitution.',
    },
    {
      'q': 'Project Tiger was launched in India in which year?',
      'options': ['1970', '1972', '1973', '1975'],
      'answer': 2,
      'explain': 'Project Tiger was launched on April 1, 1973, at Jim Corbett National Park. It is now administered by the National Tiger Conservation Authority (NTCA).',
    },
    {
      'q': 'The first Indian satellite was:',
      'options': ['Bhaskara', 'Rohini', 'Aryabhata', 'INSAT-1A'],
      'answer': 2,
      'explain': 'Aryabhata, named after the mathematician, was India\'s first satellite launched on April 19, 1975, by the Soviet Union.',
    },
    {
      'q': 'Which constitutional amendment introduced the anti-defection law?',
      'options': ['44th Amendment', '52nd Amendment', '61st Amendment', '73rd Amendment'],
      'answer': 1,
      'explain': 'The 52nd Amendment Act, 1985 added the Tenth Schedule (anti-defection law). It was modified by the 91st Amendment, 2003.',
    },
    {
      'q': 'Which is India\'s first National Park?',
      'options': ['Kanha', 'Gir', 'Jim Corbett', 'Kaziranga'],
      'answer': 2,
      'explain': 'Jim Corbett National Park (Uttarakhand), established in 1936 as Hailey National Park, is India\'s first national park.',
    },
    {
      'q': 'The "look East Policy" of India was started by which PM?',
      'options': ['Rajiv Gandhi', 'P.V. Narasimha Rao', 'Atal Bihari Vajpayee', 'Manmohan Singh'],
      'answer': 1,
      'explain': 'P.V. Narasimha Rao initiated the Look East Policy in 1991 to strengthen ties with ASEAN. PM Modi upgraded it to Act East Policy in 2014.',
    },
    {
      'q': 'Fundamental Duties were added to the Indian Constitution by which Amendment?',
      'options': ['42nd Amendment', '44th Amendment', '46th Amendment', '52nd Amendment'],
      'answer': 0,
      'explain': 'The 42nd Amendment Act, 1976 added Fundamental Duties (Article 51A) on the recommendation of the Swaran Singh Committee. Initially 10, now 11.',
    },
    {
      'q': 'The Human Development Index (HDI) is published by:',
      'options': ['World Bank', 'IMF', 'UNDP', 'WTO'],
      'answer': 2,
      'explain': 'HDI is published by UNDP in its Human Development Report. It measures life expectancy, education, and per capita income.',
    },
    {
      'q': 'Which ocean current affects the Indian monsoon?',
      'options': ['Gulf Stream', 'Kuroshio Current', 'Indian Ocean Dipole', 'Labrador Current'],
      'answer': 2,
      'explain': 'The Indian Ocean Dipole (IOD) — temperature difference between western and eastern Indian Ocean — significantly affects Indian monsoon patterns.',
    },
    {
      'q': 'The Right to Education Act makes education free and compulsory for children aged:',
      'options': ['5-11 years', '6-14 years', '6-16 years', '5-14 years'],
      'answer': 1,
      'explain': 'RTE Act, 2009 (under Article 21A added by 86th Amendment) makes education free and compulsory for children aged 6-14 years.',
    },
    {
      'q': 'Which soil type is most suitable for cotton cultivation?',
      'options': ['Alluvial Soil', 'Red Soil', 'Black Soil (Regur)', 'Laterite Soil'],
      'answer': 2,
      'explain': 'Black soil (Regur soil) found in the Deccan Plateau is ideal for cotton due to its moisture-retaining capacity and high clay content.',
    },
    {
      'q': 'The Kyoto Protocol is related to:',
      'options': ['Nuclear disarmament', 'Ozone layer protection', 'Greenhouse gas reduction', 'Biodiversity conservation'],
      'answer': 2,
      'explain': 'The Kyoto Protocol (1997) was an international treaty to reduce greenhouse gas emissions. It was succeeded by the Paris Agreement (2015).',
    },
    // ── Additional 30 questions for richer variety ──
    {
      'q': 'Which amendment reduced the voting age from 21 to 18 years?',
      'options': ['42nd Amendment', '44th Amendment', '52nd Amendment', '61st Amendment'],
      'answer': 3,
      'explain': 'The 61st Amendment Act, 1988 reduced the voting age from 21 to 18 years by amending Article 326.',
    },
    {
      'q': 'The Exclusive Economic Zone (EEZ) extends up to:',
      'options': ['12 nautical miles', '24 nautical miles', '200 nautical miles', '350 nautical miles'],
      'answer': 2,
      'explain': 'Under UNCLOS, EEZ extends 200 nautical miles from the baseline. The state has rights over marine resources in this zone.',
    },
    {
      'q': 'Which plan was called Industrial and Transport Plan?',
      'options': ['First Plan', 'Second Plan', 'Third Plan', 'Fourth Plan'],
      'answer': 1,
      'explain': 'The Second Five Year Plan (1956-61) focused on rapid industrialization and transport. Based on the Mahalanobis model.',
    },
    {
      'q': 'The DPSP "Equal pay for equal work" is mentioned in:',
      'options': ['Article 38', 'Article 39', 'Article 41', 'Article 43'],
      'answer': 1,
      'explain': 'Article 39(d) directs the State to ensure equal pay for equal work for both men and women.',
    },
    {
      'q': 'Which river has the largest river basin in India?',
      'options': ['Ganga', 'Godavari', 'Krishna', 'Brahmaputra'],
      'answer': 0,
      'explain': 'The Ganga basin is the largest river basin in India covering about 26% of the country\'s total geographical area.',
    },
    {
      'q': 'The National Human Rights Commission (NHRC) was established in:',
      'options': ['1990', '1993', '1995', '1997'],
      'answer': 1,
      'explain': 'NHRC was established in 1993 under the Protection of Human Rights Act, 1993. It is a statutory body, not constitutional.',
    },
    {
      'q': 'Which planet is known as the "Morning Star"?',
      'options': ['Mars', 'Jupiter', 'Venus', 'Mercury'],
      'answer': 2,
      'explain': 'Venus is called the Morning Star (and Evening Star) because it is visible just before sunrise and after sunset due to its orbit.',
    },
    {
      'q': 'Sardar Vallabhbhai Patel is associated with the integration of:',
      'options': ['Union Territories', 'Princely States', 'French colonies', 'Portuguese territories'],
      'answer': 1,
      'explain': 'Sardar Patel, the "Iron Man of India", integrated 565 princely states into the Indian Union after independence.',
    },
    {
      'q': 'The concept of "Public Interest Litigation" was introduced by:',
      'options': ['Justice V.R. Krishna Iyer', 'Justice P.N. Bhagwati', 'Justice H.R. Khanna', 'Justice Y.V. Chandrachud'],
      'answer': 1,
      'explain': 'Justice P.N. Bhagwati and Justice V.R. Krishna Iyer are pioneers of PIL in India which allows any person to file cases on behalf of the public.',
    },
    {
      'q': 'Which country shares the longest border with India?',
      'options': ['Pakistan', 'China', 'Bangladesh', 'Nepal'],
      'answer': 2,
      'explain': 'Bangladesh shares the longest border with India at approximately 4,096 km, followed by China and Pakistan.',
    },
    {
      'q': 'The Constituent Assembly adopted the National Flag on:',
      'options': ['January 26, 1950', 'August 15, 1947', 'July 22, 1947', 'November 26, 1949'],
      'answer': 2,
      'explain': 'The Indian National Flag was adopted by the Constituent Assembly on July 22, 1947. It was designed by Pingali Venkayya.',
    },
    {
      'q': 'Which Act is known as the "Magna Carta of Indian Education"?',
      'options': ['Indian Education Commission', 'Wood\'s Despatch 1854', 'Hunter Commission', 'Hartog Committee'],
      'answer': 1,
      'explain': 'Wood\'s Despatch of 1854 (by Charles Wood) is called the Magna Carta of Indian Education. It recommended English medium education and universities.',
    },
    {
      'q': 'The Planning Commission of India was set up in:',
      'options': ['1947', '1948', '1950', '1951'],
      'answer': 2,
      'explain': 'The Planning Commission was set up in March 1950 by a Cabinet resolution. It was replaced by NITI Aayog on January 1, 2015.',
    },
    {
      'q': 'Which Indian state has the longest coastline?',
      'options': ['Tamil Nadu', 'Gujarat', 'Maharashtra', 'Andhra Pradesh'],
      'answer': 1,
      'explain': 'Gujarat has the longest coastline among Indian states at approximately 1,600 km, followed by Andhra Pradesh.',
    },
    {
      'q': 'The "Doctrine of Eclipse" is related to:',
      'options': ['Article 12', 'Article 13', 'Article 14', 'Article 19'],
      'answer': 1,
      'explain': 'Doctrine of Eclipse (Article 13) — pre-constitutional laws inconsistent with Fundamental Rights are not void but overshadowed until the inconsistency is removed.',
    },
    {
      'q': 'Which is the highest peak in India?',
      'options': ['Nanda Devi', 'Kanchenjunga', 'K2', 'Mount Everest'],
      'answer': 1,
      'explain': 'Kanchenjunga (8,586 m) in Sikkim is the highest peak entirely within India. K2 is in PoK. Nanda Devi is 2nd highest fully in India.',
    },
    {
      'q': 'The Food and Agriculture Organization (FAO) is headquartered in:',
      'options': ['New York', 'Geneva', 'Rome', 'Paris'],
      'answer': 2,
      'explain': 'FAO is headquartered in Rome, Italy. Founded in 1945, it leads international efforts to defeat hunger and improve nutrition.',
    },
    {
      'q': 'Under which article can Parliament form a new State?',
      'options': ['Article 1', 'Article 2', 'Article 3', 'Article 4'],
      'answer': 2,
      'explain': 'Article 3 empowers Parliament to form new states, alter boundaries/names of existing states. Only requires simple majority, not amendment.',
    },
    {
      'q': 'The Ashoka Chakra on our national flag has how many spokes?',
      'options': ['12', '20', '22', '24'],
      'answer': 3,
      'explain': 'The Ashoka Chakra has 24 spokes representing 24 hours of the day, symbolizing continuous progress. It is navy blue in color.',
    },
    {
      'q': 'Which dynasty built the Qutub Minar?',
      'options': ['Tughlaq dynasty', 'Slave dynasty', 'Khilji dynasty', 'Lodi dynasty'],
      'answer': 1,
      'explain': 'Qutub Minar was started by Qutbuddin Aibak (Slave dynasty) in 1193 and completed by Iltutmish. It is 72.5 meters tall.',
    },
    {
      'q': 'India\'s GDP growth rate for 2024-25 is approximately:',
      'options': ['5.5%', '6.5%', '7.5%', '8.5%'],
      'answer': 1,
      'explain': 'India\'s GDP growth for FY 2024-25 is estimated at around 6.5-7% by various agencies including RBI and IMF.',
    },
    {
      'q': 'The "Great Indian Bustard" is found mainly in:',
      'options': ['Assam', 'Rajasthan', 'Kerala', 'Uttarakhand'],
      'answer': 1,
      'explain': 'The Great Indian Bustard is critically endangered and found mainly in the Desert National Park, Rajasthan. Less than 150 remain.',
    },
    {
      'q': 'NATGRID is related to:',
      'options': ['National power grid', 'Intelligence database', 'Railway network', 'Internet infrastructure'],
      'answer': 1,
      'explain': 'National Intelligence Grid (NATGRID) is a counter-terrorism intelligence database linking 21 data sources from across agencies.',
    },
    {
      'q': 'The Preamble of the Indian Constitution was inspired by which country?',
      'options': ['UK', 'USA', 'France', 'Australia'],
      'answer': 1,
      'explain': 'The Preamble was inspired by the American Constitution, particularly its ideals of justice, liberty, equality, and fraternity.',
    },
    {
      'q': '"Satyameva Jayate" is taken from:',
      'options': ['Rig Veda', 'Mundaka Upanishad', 'Bhagavad Gita', 'Arthashastra'],
      'answer': 1,
      'explain': '"Satyameva Jayate" (Truth Alone Triumphs) is taken from the Mundaka Upanishad. It is inscribed below the State Emblem of India.',
    },
    {
      'q': 'The first General Elections in India were held in:',
      'options': ['1950', '1951-52', '1955', '1957'],
      'answer': 1,
      'explain': 'India\'s first General Elections were held from Oct 25, 1951 to Feb 21, 1952. INC won 364 out of 489 seats. Sukumar Sen was the first CEC.',
    },
    {
      'q': 'Which of these is NOT a Greenhouse Gas?',
      'options': ['Carbon Dioxide', 'Methane', 'Nitrogen', 'Nitrous Oxide'],
      'answer': 2,
      'explain': 'Nitrogen (N₂) is not a greenhouse gas. CO₂, CH₄, N₂O and water vapor are the main greenhouse gases trapping heat in the atmosphere.',
    },
    {
      'q': 'The Simon Commission visited India in which year?',
      'options': ['1925', '1927', '1928', '1930'],
      'answer': 2,
      'explain': 'The Simon Commission arrived in India in 1928. It was boycotted by Indians as it had no Indian member. "Simon Go Back" became the slogan.',
    },
    {
      'q': 'Which institution publishes the World Development Report?',
      'options': ['IMF', 'UNDP', 'World Bank', 'WTO'],
      'answer': 2,
      'explain': 'The World Bank publishes the World Development Report annually since 1978. UNDP publishes the Human Development Report.',
    },
    {
      'q': 'Laterite soil is found mainly in:',
      'options': ['Indo-Gangetic plains', 'Deccan Plateau', 'Western and Eastern Ghats', 'Thar Desert'],
      'answer': 2,
      'explain': 'Laterite soils form in areas of heavy rainfall and high temperature. Found in Western Ghats, Eastern Ghats, and hilly areas of NE India.',
    },
  ];

  // ──────────────────────────────────────────────────────────────────────────
  // EXTENDED FLASHCARDS (40+ flashcards for daily rotation)
  // ──────────────────────────────────────────────────────────────────────────
  static const _extendedFlashcards = [
    {'front': 'What is Article 21?', 'back': 'Right to Life and Personal Liberty — No person shall be deprived of his life or personal liberty except according to procedure established by law.', 'category': 'Polity'},
    {'front': 'What is the Tropic of Cancer latitude?', 'back': '23.5°N — passes through 8 Indian states: Gujarat, Rajasthan, MP, Chhattisgarh, Jharkhand, WB, Tripura, Mizoram.', 'category': 'Geography'},
    {'front': 'When was GST implemented?', 'back': 'July 1, 2017 — via 101st Constitutional Amendment Act, 2016. It replaced multiple indirect taxes with "One Nation, One Tax".', 'category': 'Economy'},
    {'front': 'What is the Chandrayaan-3 achievement?', 'back': 'India became the 4th country to land on Moon and 1st to land near the south pole. Vikram lander touched down on Aug 23, 2023.', 'category': 'Science'},
    {'front': 'What is the 73rd Amendment?', 'back': 'Constitutionalized Panchayati Raj Institutions (1992). Added Part IX and 11th Schedule. Provides for 3-tier system at village, intermediate, and district levels.', 'category': 'Polity'},
    {'front': 'What are the Fundamental Duties?', 'back': 'Article 51A — 11 duties added by 42nd Amendment (1976) on Swaran Singh Committee recommendation. 11th duty (education of children) added by 86th Amendment.', 'category': 'Polity'},
    {'front': 'What is El Niño?', 'back': 'Warming of Pacific Ocean surface waters off South America. Causes drought in India, weaker monsoon. La Niña is the opposite — cooling of Pacific, stronger monsoon.', 'category': 'Geography'},
    {'front': 'What is NITI Aayog?', 'back': 'National Institution for Transforming India — replaced Planning Commission on Jan 1, 2015. Acts as think tank. PM is chairman, CEO appointed by PM.', 'category': 'Economy'},
    {'front': 'Who appoints the CAG?', 'back': 'The President of India appoints the CAG (Article 148). CAG audits all govt expenditure and reports to Parliament. Removable like a Supreme Court judge.', 'category': 'Polity'},
    {'front': 'What is the Western Ghats biodiversity?', 'back': 'UNESCO World Heritage Site, one of 8 "hottest hotspots" of biodiversity. Home to 7,402 species of flowering plants. Runs 1,600 km from Maharashtra to Kerala.', 'category': 'Environment'},
    {'front': 'What is SDG?', 'back': 'Sustainable Development Goals — 17 goals adopted by UN in 2015, to be achieved by 2030. Covers poverty, hunger, health, education, climate, inequality.', 'category': 'International'},
    {'front': 'What is Money Bill (Article 110)?', 'back': 'Bill dealing with taxation, borrowing, Consolidated Fund. Can only be introduced in Lok Sabha. Rajya Sabha can only suggest amendments (14 days). Speaker certifies.', 'category': 'Polity'},
    {'front': 'What is Agni-5?', 'back': 'India\'s ICBM with 5,000+ km range. Surface-to-surface, nuclear capable. Part of India\'s credible minimum deterrence strategy.', 'category': 'Defence'},
    {'front': 'What is the Silk Route?', 'back': 'Ancient trade routes connecting China to Mediterranean (130 BC – 1453 AD). Named for Chinese silk trade. Extended across Central Asia through India.', 'category': 'History'},
    {'front': 'What is Judicial Review?', 'back': 'Power of courts to examine constitutionality of laws. Based on Articles 13, 32, 226. Ensures rule of law and constitutional supremacy.', 'category': 'Polity'},
    {'front': 'What is the Repo Rate?', 'back': 'Rate at which RBI lends to commercial banks against government securities. Key tool for controlling inflation. Decided by MPC every 2 months.', 'category': 'Economy'},
    {'front': 'What is Article 370?', 'back': 'Granted special autonomous status to J&K. Abrogated on Aug 5, 2019 via Presidential Order under Article 367. J&K reorganized into two UTs.', 'category': 'Polity'},
    {'front': 'What is the Green Revolution?', 'back': 'Agricultural transformation in 1960s-70s. Led by M.S. Swaminathan. HYV seeds, chemical fertilizers, irrigation. Made India self-sufficient in food grains.', 'category': 'Economy'},
    {'front': 'What is the Ninth Schedule?', 'back': 'Added by 1st Amendment (1951). Laws in this schedule are immune from judicial review. But Coelho case (2007) holds basic structure test still applies.', 'category': 'Polity'},
    {'front': 'What is Coral Bleaching?', 'back': 'Corals expel symbiotic algae (zooxanthellae) due to heat stress, losing color. Major threat from climate change. Affects Great Barrier Reef and Indian reefs.', 'category': 'Environment'},
    {'front': 'What is the FRBM Act?', 'back': 'Fiscal Responsibility and Budget Management Act, 2003. Targets fiscal deficit below 3% of GDP and eliminates revenue deficit for fiscal discipline.', 'category': 'Economy'},
    {'front': 'What is Mansabdari System?', 'back': 'Mughal administrative system introduced by Akbar. Mansabdars held ranks (zat & sawar). Combined civil and military duties. Non-hereditary.', 'category': 'History'},
    {'front': 'What is Schedule 7 of the Constitution?', 'back': 'Contains 3 lists: Union List (98 subjects), State List (59 subjects), Concurrent List (52 subjects). Defines legislative powers of Centre and States.', 'category': 'Polity'},
    {'front': 'What is the Ozone Layer?', 'back': 'Layer of O₃ in stratosphere (15-35 km). Absorbs UV-B radiation. Depleted by CFCs. Montreal Protocol (1987) phased out ozone-depleting substances.', 'category': 'Environment'},
    {'front': 'Who is known as the Father of Indian Constitution?', 'back': 'Dr. B.R. Ambedkar — Chairman of the Drafting Committee. Architect of the Indian Constitution. Also championed social justice and rights of Dalits.', 'category': 'Polity'},
    {'front': 'What is India\'s Fiscal Deficit target?', 'back': 'Under FRBM Act, target is below 3% of GDP. Budget 2024-25 targets 5.1% of GDP. Fiscal deficit = Total Expenditure - Total Receipts (excl. borrowings).', 'category': 'Economy'},
    {'front': 'What is the Ganga Action Plan?', 'back': 'Launched in 1985 to clean river Ganga. Succeeded by Namami Gange (2014) with Rs 20,000 crore budget. Covers pollution abatement, rejuvenation, and conservation.', 'category': 'Environment'},
    {'front': 'What is the Regulating Act, 1773?', 'back': 'First attempt by British Parliament to control East India Company. Established Supreme Court in Calcutta. Made Governor of Bengal the Governor-General.', 'category': 'History'},
    {'front': 'What is BRICS?', 'back': 'Brazil, Russia, India, China, South Africa — major emerging economies. Formed in 2009. NDB (New Development Bank) established in 2015. HQ: Shanghai.', 'category': 'International'},
    {'front': 'What is the Minimum Support Price (MSP)?', 'back': 'Government-guaranteed price for agricultural produce. Set by CACP (Commission for Agricultural Costs and Prices). Covers 23 crops. Based on A2+FL cost formula.', 'category': 'Economy'},
    {'front': 'What is NavIC?', 'back': 'Navigation with Indian Constellation — India\'s regional satellite navigation system. 7 satellites: 3 in GEO + 4 in GSO. Covers India + 1,500 km. Alternative to GPS.', 'category': 'Science'},
    {'front': 'What is the Right to Information Act?', 'back': 'RTI Act, 2005. Every citizen has right to request information from public authorities. 30-day response time. Central/State Information Commissions oversee.', 'category': 'Polity'},
    {'front': 'What is the Demographic Dividend?', 'back': 'Economic benefit from increased working-age population (15-64 years). India has ~68% working-age population. Window until 2055. Requires skill development.', 'category': 'Economy'},
    {'front': 'What is Wetland Conservation?', 'back': 'Ramsar Convention (1971) protects wetlands. India has 80+ Ramsar sites. Wetlands provide flood control, water purification, biodiversity habitat, carbon storage.', 'category': 'Environment'},
    {'front': 'What is the Non-Aligned Movement?', 'back': 'NAM formed during Cold War (1961). India co-founded with Yugoslavia, Egypt. Policy of not aligning with any major power bloc. Currently 120 member states.', 'category': 'International'},
    {'front': 'What is the Comptroller and Auditor General?', 'back': 'CAG (Article 148) is the guardian of the public purse. Audits all government accounts. Appointed by President. Reports to Parliament. Cannot be removed easily.', 'category': 'Polity'},
    {'front': 'What is Aditya-L1?', 'back': 'India\'s first space-based solar observatory. Placed at L1 Lagrange point (1.5M km from Earth). Carries 7 payloads. Studies solar corona, wind, and space weather.', 'category': 'Science'},
    {'front': 'What is the Caste Census debate?', 'back': 'Last caste census was 1931. SECC 2011 collected data but not fully released. Demanded for evidence-based reservation and welfare policy targeting.', 'category': 'Polity'},
    {'front': 'What is the Bhakti Movement?', 'back': 'Medieval devotional movement (7th-17th century). Started in South India. Key saints: Ramanuja, Kabir, Guru Nanak, Mirabai, Tulsidas. United faith across castes.', 'category': 'History'},
    {'front': 'What is a Carbon Sink?', 'back': 'Natural or artificial reservoir that absorbs CO₂. Forests, oceans, soil are natural sinks. India aims to create additional carbon sink of 2.5-3 billion tonnes by 2030.', 'category': 'Environment'},
    // ── Additional 30 flashcards ──
    {'front': 'What is UAPA?', 'back': 'Unlawful Activities (Prevention) Act — India\'s primary anti-terrorism law. Allows designation of organizations and individuals as terrorists. NIA investigates.', 'category': 'Polity'},
    {'front': 'What is the Creamy Layer?', 'back': 'Income threshold above which OBC members are excluded from reservation benefits. Currently ₹8 lakh/year. Concept from Indra Sawhney case (1992).', 'category': 'Polity'},
    {'front': 'What is PLI Scheme?', 'back': 'Production Linked Incentive — incentives to manufacturers based on incremental sales. 14 sectors. ₹1.97 lakh crore outlay. Boosts Make in India.', 'category': 'Economy'},
    {'front': 'What is the Continental Shelf?', 'back': 'Submerged extension of a continent up to 200 nautical miles (extendable to 350 nm). Coastal states have sovereign rights over resources. UNCLOS governs.', 'category': 'Geography'},
    {'front': 'What is the Rowlatt Act?', 'back': 'Passed in March 1919. Allowed detention without trial. Sparked nationwide protests. Gandhi\'s first nationwide satyagraha. Led to Jallianwala Bagh (April 13, 1919).', 'category': 'History'},
    {'front': 'What is ENSO?', 'back': 'El Niño-Southern Oscillation — coupled oceanic-atmospheric phenomenon. El Niño = warm phase (drought in India), La Niña = cool phase (excess rain in India).', 'category': 'Geography'},
    {'front': 'What is PM GatiShakti?', 'back': 'National Master Plan for multi-modal connectivity. GIS-based platform integrating 16 ministries. Reduces project delays. Infrastructure coordination and planning.', 'category': 'Governance'},
    {'front': 'What is the Nuclear Triad?', 'back': 'Three-pronged nuclear delivery capability: land-based missiles (Agni), sea-based (Arihant class SSBN), air-based (fighter jets). India achieved full triad.', 'category': 'Defence'},
    {'front': 'What is NEP 2020?', 'back': 'National Education Policy 2020. 5+3+3+4 structure. Mother tongue till Class 5. Multiple entry/exit in higher education. Academic Bank of Credits. Replaced NEP 1986.', 'category': 'Governance'},
    {'front': 'What is the Siachen Glacier?', 'back': 'Longest glacier in the Karakoram at ~76 km. World\'s highest battlefield. India has controlled it since Operation Meghdoot (1984). Located in Ladakh.', 'category': 'Geography'},
    {'front': 'What is the Inter-State Council?', 'back': 'Constitutional body under Article 263. PM is chairman. Recommends on inter-state disputes and coordination. Constituted in 1990 on Sarkaria Commission recommendation.', 'category': 'Polity'},
    {'front': 'What is Ayushman Bharat?', 'back': 'Two pillars: Health & Wellness Centres (HWCs) for primary care, and PM-JAY for insurance (₹5 lakh/family/year). Covers 55 crore+ beneficiaries. Cashless treatment.', 'category': 'Governance'},
    {'front': 'What is the Green Climate Fund?', 'back': 'UN fund to help developing countries combat climate change. Target: USD 100B/year (escalated to USD 300B/year at COP-29). Adaptation + mitigation projects.', 'category': 'Environment'},
    {'front': 'What is Article 356?', 'back': 'President\'s Rule — imposed when state constitutional machinery fails. Governor recommends. Max 3 years (with Parliament approval every 6 months). Bommai case set restrictions.', 'category': 'Polity'},
    {'front': 'What is the Eighth Schedule?', 'back': 'Lists 22 officially recognized languages. Started with 14 in 1950. Last additions (2003, 92nd Amendment): Bodo, Dogri, Maithili, Santhali.', 'category': 'Polity'},
    {'front': 'What is QUAD?', 'back': 'Quadrilateral Security Dialogue — India, US, Japan, Australia. Focus: Free & Open Indo-Pacific. Not a military alliance. Vaccine, tech, climate, maritime cooperation.', 'category': 'International'},
    {'front': 'What is the CAG?', 'back': 'Comptroller and Auditor General (Article 148). Audits all government expenditure. Guardian of public purse. Reports to Parliament. Appointed by President.', 'category': 'Polity'},
    {'front': 'What is the National Hydrogen Mission?', 'back': 'Green Hydrogen Mission — ₹19,744 crore. Target: 5 MMT/year by 2030. SIGHT program for electrolyzers. Zero-carbon fuel produced from water using renewable energy.', 'category': 'Science'},
    {'front': 'What is FATF?', 'back': 'Financial Action Task Force — global body combating money laundering and terror financing. Grey List = increased monitoring. Black List = sanctioned. India is a member.', 'category': 'Economy'},
    {'front': 'What is Gaganyaan?', 'back': 'India\'s first human spaceflight mission. 3 crew members to LEO (400 km). TV-D1 abort test succeeded (2023). Astronauts training in Russia and India. Target: 2025.', 'category': 'Science'},
    {'front': 'What is the Dandi March?', 'back': 'Salt March (March 12 – April 6, 1930) — Gandhi walked 388 km from Sabarmati to Dandi to make salt, defying British salt tax. Started Civil Disobedience Movement.', 'category': 'History'},
    {'front': 'What is MGNREGA?', 'back': 'Mahatma Gandhi National Rural Employment Guarantee Act, 2005. Guarantees 100 days of wage employment per household per year. Demand-driven. Social audit mandatory.', 'category': 'Governance'},
    {'front': 'What is Biodiversity Hotspot?', 'back': 'Region with at least 1,500 endemic vascular plant species and 70%+ habitat loss. 36 globally, 4 in India: Western Ghats, Eastern Himalayas, Indo-Burma, Sundaland.', 'category': 'Environment'},
    {'front': 'What is the Jallianwala Bagh Massacre?', 'back': 'April 13, 1919, Amritsar. General Dyer ordered firing on peaceful gathering. ~1,000+ killed. Hunter Commission investigated. Led to widespread anti-British sentiment.', 'category': 'History'},
    {'front': 'What is BharatNet?', 'back': 'National fiber optic network to connect 2.5+ lakh Gram Panchayats with broadband. Backbone of Digital India. Phase 1 and 2 implemented, Phase 3 ongoing.', 'category': 'Science'},
    {'front': 'What is Carbon Credit?', 'back': 'One carbon credit = one tonne of CO₂ reduced/removed. Traded in carbon markets. India launched Carbon Credit Trading Scheme (CCTS) with BEE as administrator.', 'category': 'Environment'},
    {'front': 'What is the Lokpal?', 'back': 'Anti-corruption ombudsman for the Centre. Lokpal and Lokayuktas Act, 2013. Chairperson + 8 members. Jurisdiction over PM (with conditions), ministers, MPs, officials.', 'category': 'Polity'},
    {'front': 'What is the IMF?', 'back': 'International Monetary Fund — 190 member countries. Provides financial stability, monetary cooperation, loans. India has 2.75% quota share. SDR is its reserve asset.', 'category': 'International'},
    {'front': 'What is UPI?', 'back': 'Unified Payments Interface — real-time mobile payment system by NPCI. 12B+ transactions/month. India\'s digital public infrastructure success. Being adopted by other countries.', 'category': 'Economy'},
    {'front': 'What is the Arthashastra?', 'back': 'Ancient treatise on statecraft, economics, and military strategy by Kautilya (Chanakya). Written ~300 BCE. Covers governance, law, taxation, foreign policy, espionage.', 'category': 'History'},
  ];
}
