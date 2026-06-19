import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../config/theme.dart';
import '../../config/app_images.dart';
import '../../providers/daily_progress_provider.dart';
import '../../services/daily_content_manager.dart';
import '../../services/upsc_content_service.dart';
import '../../widgets/glass_widgets.dart';

/// ──────────────────────────────────────────────────────────────────────────────
/// UpscMustKnowScreen — Comprehensive UPSC knowledge base with 10 categories,
/// 250+ facts, search, category filters, and internet content fetching.
/// ──────────────────────────────────────────────────────────────────────────────
class UpscMustKnowScreen extends StatefulWidget {
  const UpscMustKnowScreen({super.key});

  @override
  State<UpscMustKnowScreen> createState() => _UpscMustKnowScreenState();
}

class _UpscMustKnowScreenState extends State<UpscMustKnowScreen> {
  final ScrollController _scrollController = ScrollController();
  static const _ib = 'assets/flaticon_pngs/';

  // ── Massive local data: 10 categories, 25+ facts each ──
  static const _localSections = [
    _Section('${_ib}polity.png', 'Polity & Governance', 'polity', [
      'Preamble: Sovereign, Socialist, Secular, Democratic, Republic — "We the People" (42nd Amendment added Socialist, Secular)',
      'Fundamental Rights: Articles 14-32 — Right to Equality (14-18), Freedom (19-22), Against Exploitation (23-24), Religion (25-28), Cultural & Educational (29-30), Constitutional Remedies (32)',
      'DPSPs: Articles 36-51 — Non-justiciable but fundamental in governance. Based on Irish Constitution. Classified as Socialistic, Gandhian, Liberal-Intellectual',
      'Fundamental Duties: Article 51A — 11 duties (42nd Amendment). 11th duty (education of children 6-14) added by 86th Amendment',
      'Supreme Court: 34 judges (CJI + 33). Original, appellate, advisory jurisdiction. Guardian of Constitution. Collegium system for appointments',
      'CAG: Articles 148-151 — Guardian of public purse. Audits all central & state expenditure. Reports to Parliament via President',
      'Emergency: Art 352 (National — war/aggression/armed rebellion), Art 356 (State — President\'s Rule, max 3 years), Art 360 (Financial, never used)',
      '73rd/74th Amendment (1992): Panchayati Raj & Municipalities constitutionalized. Part IX and Part IXA. 11th & 12th Schedule',
      'Constitutional Bodies: Election Commission (Art 324), UPSC (Art 315), Finance Commission (Art 280), Attorney General (Art 76)',
      'Amendment Process: Art 368. Simple majority, Special majority (2/3 present + absolute), Special + half state ratification',
      'Writ Jurisdiction: Habeas Corpus (produce body), Mandamus (command), Certiorari (quash), Prohibition (prevent), Quo Warranto (by what authority)',
      'Anti-Defection Law: 10th Schedule (52nd Amendment 1985). Modified by 91st Amendment 2003. Speaker decides disqualification',
      'Inter-State Council: Art 263 — PM as chairman. Recommends on inter-state disputes. Constituted in 1990',
      'Lok Sabha: 543 elected members. Term: 5 years. Speaker presides. Money Bills only here. No-Confidence Motion only in LS',
      'Rajya Sabha: 250 members (238 elected + 12 nominated). Permanent body — 1/3 retire every 2 years. VP is Chairman',
      'Governor: Art 153-162. Appointed by President. Discretionary powers: Reserve bill, Report for President\'s Rule, Appoint CM when no majority',
      'Right to Education: Article 21A (86th Amendment 2002). RTE Act 2009 — Free & compulsory education for 6-14 years',
      'Citizenship: Art 5-11. Citizenship Act 1955 — by birth, descent, registration, naturalization. CAA 2019 amended acquisition rules',
      'Schedules: 12 Schedules — 1st: States & UTs, 7th: Union/State/Concurrent, 8th: 22 languages, 9th: Laws immune from review, 10th: Anti-defection',
      'Money Bill vs Finance Bill: Money Bill (Art 110) — only in LS, RS has 14 days. Speaker certifies. Finance Bill has two types',
      'Judicial Review: Art 13, 32, 226. Basic Structure doctrine (Kesavananda Bharati 1973). Courts can strike down unconstitutional laws',
      'President: Art 52-62. Indirectly elected (Electoral College). Art 72: Pardoning power (Pardon, Commute, Remit, Respite, Reprieve)',
      'PM and Council of Ministers: Art 74-75. Collective responsibility to Lok Sabha. Individual responsibility to PM. Cabinet, MoS, Deputy Ministers',
      'RTI Act 2005: Every citizen has right to request info from public authorities. 30-day response. Central & State Information Commissions',
      'Lokpal & Lokayuktas Act 2013: Anti-corruption ombudsman. Lokpal for Centre (PM excluded for some acts), Lokayuktas for states',
    ]),
    _Section('${_ib}economy.png', 'Economy & Finance', 'economy', [
      'GDP 2024-25: ~\$3.7 trillion (5th largest). Services ~55%, Industry ~25%, Agriculture ~18%. Target: \$5 trillion economy',
      'RBI: Monetary Policy Committee (MPC) — 6 members. Inflation targeting: 4% ± 2%. Key tools: Repo, Reverse Repo, CRR, SLR',
      'GST: 101st Amendment, July 1, 2017. 5 slabs: 0%, 5%, 12%, 18%, 28%. GST Council (Art 279A) chaired by FM. One Nation One Tax',
      'FRBM Act 2003: Fiscal deficit target <3% GDP. Revenue deficit elimination. NK Singh Committee reviewed fiscal targets',
      'NITI Aayog: Replaced Planning Commission (Jan 1, 2015). PM is Chairman. Think tank with no fund allocation power. CEO appointed by PM',
      'PLI Scheme: Production Linked Incentive for 14 sectors. Total outlay: ₹1.97 lakh crore. Electronics, auto, pharma, textiles, solar',
      'Digital India: UPI processed 12B+ txn/month. Aadhaar: 1.4B enrolled. DigiLocker, CoWIN, ONDC as digital public infrastructure',
      'Finance Commission: 16th FC (Arvind Panagariya). Art 280. Recommends tax devolution Centre-States. 5-year term',
      'Monetary Policy Tools: Repo Rate (RBI lending rate), Reverse Repo, CRR (cash reserves, no interest), SLR (liquid assets %)',
      'Balance of Payments: Current Account + Capital Account. CAD target: <2.5% GDP. Forex reserves: ~\$650 billion (10+ months import cover)',
      'FDI Routes: Automatic (no approval) vs Government Route. 100% FDI in most sectors. FDI inflow: \$80B+ annually',
      'MSP: Minimum Support Price for 23 crops. Set by CACP based on A2+FL cost. Procurement by FCI, NAFED',
      'Banking Reforms: IBC 2016 for insolvency. NARCL (bad bank) for stressed assets. NBFCs tightened post-IL&FS crisis',
      'Fiscal Deficit 2024-25: ~5.1% GDP (BE). Target: <4.5% by 2025-26. Revenue deficit declining. CapEx driving growth',
      'MUDRA Loans: 3 categories — Shishu (up to ₹50K), Kishore (₹50K-5L), Tarun (₹5L-10L). Financial inclusion for micro enterprises',
      'Inflation Types: CPI (consumer, RBI target), WPI (wholesale), GDP deflator. Core inflation excludes food & fuel',
      'Financial Inclusion: Jan Dhan Yojana (50cr+ accounts), APY, PMJJBY, PMSBY, Stand-Up India. JAM Trinity: Jan Dhan + Aadhaar + Mobile',
      'Capital vs Revenue Expenditure: Capital creates assets (roads, bridges); Revenue is recurring (salaries, interest). CapEx drives GDP growth',
      'Make in India: 25 sectors. Manufacturing share of GDP target: 25%. Linked to PLI, Startup India, Atmanirbhar Bharat',
      'Cryptocurrency: 30% tax on gains (Budget 2022). 1% TDS. RBI CBDC (e-Rupee) as regulated digital currency alternative',
      'Budget 2025-26: CapEx ~₹11 lakh crore. New tax regime default. Green bonds. Infrastructure focus. Social sector spending maintained',
      'India\'s External Debt: ~\$630 billion. Short-term ~19%. Manageable debt-to-GDP ratio (~19%). Forex reserves provide comfort',
      'PM Surya Ghar: Free electricity up to 300 units via rooftop solar. ₹75,000 crore scheme. 1 crore households target',
      'Green Bonds: India issued sovereign green bonds worth ₹16,000 crore. For renewable energy, clean transport, water management',
      'GIFT IFSC: International financial services hub in Gujarat. Tax benefits, regulatory ease. Smart regulation for global finance',
    ]),
    _Section('${_ib}environment.png', 'Environment & Ecology', 'environment', [
      'Paris Agreement: Limit warming to 1.5°C/2°C. India\'s NDC: 45% emission intensity cut by 2030, Net Zero by 2070',
      'India\'s NDCs: 50% electric power from non-fossil sources by 2030. Additional carbon sink of 2.5-3 billion tonnes CO₂',
      'Ramsar Sites: 85+ in India. Largest: Sundarbans (WB). Convention signed 1971 in Ramsar, Iran. Wetlands of international importance',
      'Biodiversity Hotspots: 4 in India — Western Ghats, Eastern Himalayas, Indo-Burma, Sundaland. 36 globally',
      'National Parks: 106 | Wildlife Sanctuaries: 567. NPs have stricter protection — no human activity allowed',
      'Project Tiger: April 1, 1973 at Jim Corbett NP. 53+ tiger reserves. NTCA administers. Census every 4 years. 3,167+ tigers',
      'CAMPA: Compensatory Afforestation Fund Act 2016. From forest land diversion. 80% to states, 10% Centre',
      'Wetlands: Cover ~4.6% of India. Flood control, water purification, carbon storage, biodiversity. Wetlands Rules 2017',
      'Green Hydrogen Mission: ₹19,744 crore. 5 MMT/year by 2030. SIGHT program for electrolyzers. Zero-carbon from water + renewables',
      'Forest Cover: 21.71% (ISFR 2021). Target: 33% under National Forest Policy 1988. MP has largest forest area',
      'Climate Finance: Green Climate Fund, Adaptation Fund, GEF. India demands \$1T/year from developed nations. Loss & Damage Fund at COP-28',
      'Ozone Layer: Montreal Protocol 1987 (CFCs). Kigali Amendment 2016 (HFCs phase-down). India signed both protocols',
      'Coral Reefs: 4 areas — Gulf of Kutch, Gulf of Mannar, Andaman & Nicobar, Lakshadweep. Threatened by bleaching from warming',
      'Mangroves: India ranks 3rd globally. Sundarbans = largest mangrove forest. Gujarat mangroves growing fastest. Key carbon sinks',
      'Biosphere Reserves: 18 in India (12 in UNESCO MAB network). First: Nilgiri (1986). Covers buffer + core + transition zones',
      'CCTS: Carbon Credit Trading Scheme. BEE administers. Carbon Credit Certificates traded on Indian Carbon Market (ICM)',
      'NAPCC: 8 missions — Solar, Energy Efficiency, Sustainable Habitat, Water, Himalayan Ecosystem, Green India, Agriculture, Knowledge',
      'Plastic Waste: Single-use plastics banned July 2022. Extended Producer Responsibility (EPR). Swachh Bharat linked',
      'Air Quality: NCAP targets 20-30% PM2.5 reduction in 131 cities by 2026. CPCB monitors via CAAQMS stations',
      'ISA: International Solar Alliance — co-founded by India & France at COP-21 (2015). HQ: Gurugram. 116 members',
      'Wildlife Protection Act 1972: Schedules I-VI. CITES compliance. 2022 amendments strengthened provisions',
      'REDD+: Reducing Emissions from Deforestation & Degradation. UN framework. India has national REDD+ strategy',
      'Electric Vehicles: FAME-II (₹10,000 cr). National EV Policy: 30% EV sales by 2030. Battery swapping infrastructure',
      'Desertification: 30% land degraded. UNCCD target: Land Degradation Neutrality by 2030. Bonn Challenge: 26 Mha restoration',
      'Endangered Species: IUCN Red List — Great Indian Bustard (CR), Snow Leopard (VU), Gangetic Dolphin (EN), Asiatic Lion (EN)',
    ]),
    _Section('${_ib}science.png', 'Science & Technology', 'science', [
      'ISRO: Chandrayaan-3 (Moon south pole, 2023), Aditya-L1 (Sun), Gaganyaan (human space, 2025), SPADEX (docking). 4th to land on Moon',
      'NavIC: Indian Regional Navigation — 7 satellites (3 GEO + 4 GSO). Covers India + 1,500 km. Alternative to GPS. Accuracy: 5-10 m',
      'Digital Public Infrastructure: Aadhaar (1.4B), UPI (12B+ txn/month), DigiLocker, ONDC, Account Aggregators. India Stack model',
      'AI Mission: IndiaAI — ₹10,000 crore. AI compute centers, datasets, application development, responsible AI frameworks, startups',
      'Quantum Mission: ₹6,003 crore (2023-31). 4 areas: computing, communication, sensing, materials. QKD demonstrated over 300 km',
      'DRDO: Agni-5 MIRV (Mission Divyastra), SMART torpedo, BrahMos (joint with Russia), Tejas LCA, Kaveri engine. Defence R&D',
      'Biotechnology: Genome India Project (10,000 genomes). BioE3 Policy. mRNA vaccine platform. CAR-T cell therapy (NexCAR19)',
      'Semiconductor Mission: Micron (Gujarat), Tata-PSMC (Dholera). ₹76,000 crore incentives. Reduce chip import dependency',
      '5G: Launched Oct 2022. 4 lakh+ towers. Jio & Airtel coverage expanding. Use cases: smart agriculture, telemedicine, Industry 4.0',
      'Supercomputers: PARAM series by C-DAC. National Supercomputing Mission — 24 petaflop. Weather prediction, genomics, AI',
      'Nuclear Program: 23 reactors (7,480 MW). Fast Breeder Reactor (PFBR) at Kalpakkam. Thorium utilization program for India\'s vast reserves',
      'Space Economy: IN-SPACe for private sector. Skyroot\'s Vikram-S (first private rocket). Agnikul 3D-printed engine. Target: \$50B by 2030',
      'Cybersecurity: CERT-In — nodal agency. IT Act 2000 (amended 2008). DPDP Act 2023. National Cyber Security Policy',
      'Deep Ocean Mission: ₹4,077 crore. Samudrayaan MATSYA 6000 — manned submersible to 6,000m. Mining, biodiversity, desalination',
      'Gaganyaan: India\'s first human spaceflight. 3 crew to LEO (400 km). TV-D1 success (2023). Astronaut training in Russia & India',
      'Gene Editing: CRISPR-Cas9. GM crop debate — Bt Cotton approved, Bt Brinjal moratorium. GEAC regulates GM organisms in India',
      'Renewable Energy: India 4th globally. Solar: 80+ GW. Wind: 45+ GW. Target: 500 GW non-fossil by 2030',
      'Defence Exports: Crossed \$2.5 billion. BrahMos to Philippines. Tejas interest from Malaysia, Argentina. Self-reliance in defence',
      'BharOS: Indian mobile OS by IIT Madras. Secure, no pre-installed apps. Alternative to Android for strategic use',
      'AI in Governance: AI for crop prediction, tax compliance, healthcare (AI-powered diagnostics), judiciary (SUPACE system)',
      '6G Research: Bharat 6G Alliance launched. THz communication research at IITs. Standard development for 2030 deployment',
      'ISRO SPADEX: Space Docking Experiment — India became 4th to achieve space docking. Critical for Gaganyaan & space station',
      'Aditya-L1 Results: Detected solar wind patterns & CMEs from L1 point. Data for predicting space weather affecting Earth',
      'Digital Health (ABDM): Health ID for every citizen. Digitized health records. DigiDoctor, Health Facility Registry. Interoperable',
      'Lithium Discovery: 5.9 million tonnes in Reasi, J&K. Critical for EV batteries. Reduces import dependence on China & Australia',
    ]),
    _Section('${_ib}international.png', 'International Relations', 'international', [
      'QUAD: India, US, Japan, Australia — Free & Open Indo-Pacific. Not a military alliance. Vaccine initiative, cyber, climate, maritime',
      'BRICS: Now BRICS+ with 6 new members (Egypt, Ethiopia, Iran, Saudi, UAE). NDB — HQ: Shanghai. Counterweight to Western institutions',
      'G20: India presidency 2023 — "One Earth, One Family, One Future". New Delhi Declaration. AU as permanent member. DPI as global model',
      'SCO: 9 members (India, Pakistan joined 2017). Security, counter-terrorism, economic cooperation. Shanghai spirit',
      'IORA: Indian Ocean Rim Association — 23 members. Blue economy, maritime safety, trade. India is founding member',
      'I2U2: India, Israel, UAE, US — Water, energy, transport, space, health, food security. Joint infrastructure investments',
      'ASEAN: 10 members. India\'s Act East Policy (2014, upgraded from Look East). RCEP — India opted out. FTA review ongoing',
      'SAARC: 8 South Asian nations. Dormant since 2014. BIMSTEC emerged as alternative for Bay of Bengal regional cooperation',
      'India-US: Comprehensive Global Strategic Partnership. iCET (tech). Defence: GE engines, MQ-9B drones. 2+2 dialogue mechanism',
      'India-China: Galwan standoff (2020). LAC disengagement ongoing. Trade deficit ~\$85B. India banned Chinese apps. S-400 vs CAATSA',
      'India-Russia: Special & Privileged Strategic Partnership. S-400, BrahMos. Energy: Rosneft, Sakhalin. Rupee-Ruble trade mechanism',
      'India at UN: Demands UNSC permanent seat (G4: India, Japan, Germany, Brazil). Largest troop contributor to peacekeeping historically',
      'Indo-Pacific: SAGAR policy. Indo-Pacific Oceans Initiative. Maritime domain awareness. Andaman & Nicobar as strategic hub',
      'India-Middle East: Think West Policy. IMEC corridor. Abraham Accords impact. Energy security & 9M+ diaspora',
      'India-Africa: 10 Guiding Principles. LoC, development partnership. ISA, CDRI collaboration. Forum Summits every 3 years',
      'Neighbourhood First: Bangladesh (Teesta), Nepal (Constitution, border), Sri Lanka (debt crisis), Maldives (India Out), Bhutan (hydropower)',
      'WTO: Agriculture subsidies dispute (public stockholding). Fisheries subsidies (MC12). E-commerce moratorium. TRIPS waiver',
      'Climate Diplomacy: CBDR principle. Loss & Damage at COP-28. India co-leads ISA & CDRI. Just transition advocacy',
      'Nuclear Diplomacy: India-US 123 Agreement (2008). NSG membership bid. CTBT not signed. Credible minimum deterrence',
      'IMEC: India-Middle East-Europe Corridor (G20 2023). Rail + shipping connectivity. Counterweight to China\'s BRI. Feasibility studies ongoing',
      'AUKUS: Australia-UK-US — nuclear subs for Australia. India supports rules-based order but not part of military alliances',
      'India-Japan: Special Strategic Partnership. Bullet train (Mumbai-Ahmedabad). 2+2 dialogue. Defence, digital, infrastructure cooperation',
      'Multilateralism: Reformed multilateralism stance. Voice of Global South Summit. Non-aligned DNA with strategic autonomy',
      'India-EU: Strategic Partnership since 2004. FTA negotiations resumed. Trade & Tech Council. Connectivity Partnership (2021)',
      'India\'s Defence Exports: \$2.5B+. BrahMos to Philippines, Tejas interest from 6 countries. Atmanirbhar Bharat in defence',
    ]),
    _Section('${_ib}history.png', 'History & Culture', 'history', [
      'IVC (2600-1900 BCE): Harappa, Mohenjo-daro. Urban planning, Great Bath, granaries, standardized weights. Saraswati river drying caused decline',
      'Vedic Period: Rig Veda (earliest text). Sabha & Samiti assemblies. Later Vedic — pastoral to agriculture shift. Varna system emerges',
      'Maurya Empire: Chandragupta (322 BCE), Ashoka\'s Dhamma. Arthashastra by Kautilya. Centralized bureaucracy. Rock & pillar edicts',
      'Gupta Period: Golden Age (320-550 CE). Aryabhata (math), Kalidasa (Shakuntala), Fa-Hien. Decimal system, iron pillar metallurgy',
      'Mughal Empire: Babur (1526 Panipat), Akbar (Mansabdari, Sulh-i-Kul, Din-i-Ilahi), Shah Jahan (Taj Mahal), Aurangzeb (Jizya reimposed)',
      'Bhakti Movement: 7th-17th century. Ramanuja, Kabir, Guru Nanak, Mirabai, Tulsidas, Chaitanya. Devotion over rituals. Social equality',
      'British Consolidation: 1757 Plassey, 1764 Buxar. Subsidiary Alliance (Wellesley). Doctrine of Lapse (Dalhousie). Economic drain theory',
      'Revolt of 1857: First War of Independence. Mangal Pandey, Rani Laxmibai, Tantia Tope. Ended Company rule → Crown took over (Govt of India Act 1858)',
      'INC Founded 1885 (A.O. Hume). Moderates: Gokhale, Naoroji (Drain Theory). Extremists: Tilak ("Swaraj is my birthright"), Lala Lajpat Rai',
      'Gandhian Era: Non-Cooperation (1920-22, Chauri Chaura), Civil Disobedience (1930 — Salt March/Dandi), Quit India (1942 — "Do or Die")',
      'Constitution: Adopted Nov 26, 1949. Effective Jan 26, 1950. 395 Articles, 8 Schedules originally. Longest written constitution',
      'Constituent Assembly: 389 members (299 after Partition). B.R. Ambedkar: Drafting Committee Chair. Objective Resolution by Nehru (Dec 13, 1946)',
      'Partition 1947: Mountbatten Plan. Radcliffe Line. Massive displacement & communal violence. Two-nation theory. Princely states integration',
      'Revolutionaries: Bhagat Singh (Lahore Conspiracy), Chandrashekhar Azad, Surya Sen (Chittagong). HSRA. INA (Subhas Chandra Bose)',
      'Social Reform: Ram Mohan Roy (Sati abolition, Brahmo Samaj), Vidyasagar (widow remarriage), Jyotirao Phule (caste reform), Ambedkar (Dalit rights)',
      'Art & Architecture: Ajanta-Ellora caves, Khajuraho, Konark Sun Temple, Hampi (Vijayanagara). 42 UNESCO World Heritage Sites in India',
      'Delhi Sultanate (1206-1526): Slave, Khilji, Tughlaq, Sayyid, Lodi dynasties. Alauddin\'s market reforms. Ibn Battuta under Tughlaq',
      'Chola Dynasty: Rajaraja I, Rajendra I. Naval power, Brihadeeswara temple. Trade with SE Asia. Village self-governance model',
      'Vijayanagara: Founded 1336. Krishnadeva Raya — greatest. Battle of Talikota 1565 (decline). Hampi = UNESCO site',
      'Freedom Movement Timeline: 1885 INC → 1905 Swadeshi → 1919 Jallianwala → 1920 NCM → 1930 CDM → 1942 QIM → 1947 Independence',
      'Post-Independence: Sardar Patel — integration of 565 princely states. Linguistic states (1956). Green Revolution 1960s (Swaminathan)',
      'Cultural Heritage: 42 UNESCO Sites (34 cultural, 7 natural, 1 mixed). Intangible: Yoga, Kumbh Mela, Nowruz',
      'Ancient Trade: Silk Route (130 BC-1453 AD). Indian Ocean spice trade. Roman trade with Peninsular India. "Black gold" = pepper',
      'Indian Diaspora: 32 million strong. Largest in UAE, US, Saudi Arabia. Remittances: \$100B+ annually. OCI cards',
      'Regulating Act 1773: First British attempt to control EIC. Supreme Court in Calcutta. Governor of Bengal → Governor-General. Pitt\'s India Act 1784',
    ]),
    _Section('${_ib}environment.png', 'Geography', 'geography', [
      'India: 7th largest (3.28M km²). 28 states, 8 UTs. Coastline: 7,516 km. Land borders with 7 countries. Lat: 8°N-37°N, Long: 68°E-97°E',
      'Divisions: Northern Mountains, Indo-Gangetic Plains, Peninsular Plateau, Coastal Plains, Islands (Andaman & Lakshadweep)',
      'Rivers: Ganga (2,525 km), Brahmaputra, Godavari (longest Peninsular, 1,465 km), Krishna, Kaveri. Narmada & Tapi (west-flowing rift valley)',
      'Climate: Monsoon type — 4 seasons. SW Monsoon (June-Sept): 75% rainfall. NE Monsoon: Tamil Nadu (Oct-Dec). Retreating monsoon: cyclones',
      'Soils: Alluvial (most widespread, Indo-Gangetic), Black/Regur (Deccan, cotton), Red (granite/gneiss), Laterite (heavy rainfall, acidic)',
      'Tropic of Cancer: 8 states — Gujarat, Rajasthan, MP, Chhattisgarh, Jharkhand, West Bengal, Tripura, Mizoram',
      'Himalayas: Shiwalik (youngest), Lesser/Middle, Greater Himalayas. K2 (2nd tallest, PoK). Kanchenjunga (3rd, Sikkim, highest in India)',
      'Western Ghats: UNESCO WH. 1,600 km Gujarat-Kerala. Highest: Anamudi (2,695 m). Biodiversity hotspot. Source of major rivers',
      'Thar Desert: Largest hot desert in South Asia. Indira Gandhi Canal. Luni = only river. Desert National Park: GIB habitat',
      'Deccan Plateau: Bounded by Western & Eastern Ghats. Black soil. Godavari, Krishna basins. 600-900 m elevation',
      'Islands: Andaman & Nicobar (572, Barren Island = only active volcano). Lakshadweep (36 islands, coral origin, Arabian Sea)',
      'Minerals: Coal (Jharkhand, Odisha), Iron (Karnataka, Jharkhand), Mica (Jharkhand), Bauxite (Odisha), Petroleum (Mumbai High, Assam)',
      'Agriculture: Kharif (rice, sugarcane — monsoon), Rabi (wheat, mustard — winter), Zaid (summer). India: 2nd in agri production globally',
      'Population: 1.44 billion (2024, most populous). 65% under 35 (demographic dividend). Density: ~464/km². 17.5% of world population',
      'Drainage: Himalayan (perennial, snow-fed) vs Peninsular (seasonal, rain-fed). 4 drainage patterns: Dendritic, Trellis, Radial, Rectangular',
      'Mountain Passes: Khyber (Af-Pak), Nathu La & Jelep La (Sikkim-Tibet), Rohtang (Himachal), Banihal (Kashmir), Bomdi La (Arunachal)',
      'Disasters: Earthquakes (Zone V: NE, J&K, Gujarat), Cyclones (Bay of Bengal > Arabian Sea), Floods (Assam, Bihar), Droughts (Rajasthan)',
      'Peninsular Rivers: East-flowing — Godavari, Krishna, Kaveri. West-flowing — Narmada & Tapi (rift valley). Peninsular rivers non-perennial',
      'Urban India: 35% urban (2024). Mega cities: Mumbai, Delhi, Bangalore, Hyderabad, Chennai. Smart Cities Mission: 100 cities',
      'Forest Types: Tropical Evergreen (NE, WG), Deciduous (largest), Thorn (Rajasthan), Mangrove (Sundarbans), Alpine/Montane (Himalayas)',
      'Glaciers: Siachen (largest, Karakoram), Gangotri (Ganga source), Zemu (Sikkim). Rapidly retreating due to global warming',
      'Coastline: West — Konkan, Malabar (submerged/emergent). East — Coromandel, Uttar. 13 major ports, 200+ minor ports',
      'Indian Ocean: Strategic location. Strait of Malacca, Strait of Hormuz. 90% oil imports via sea. Navy dominance critical',
      'Cyclone Naming: IMD + WMO system. Named alphabetically by member countries. BOB cyclones more frequent (Oct-Dec, Apr-May)',
      'Soil Conservation: Contour plowing, terrace farming, strip cropping, shelterbelts. National Mission on Sustainable Agriculture',
    ]),
    _Section('${_ib}polity.png', 'Ethics & Integrity', 'ethics', [
      'GS-IV Paper: Ethics, Integrity & Aptitude — 250 marks. Attitude, emotional intelligence, public service values, case studies',
      'Key Thinkers: Gandhi (Satyagraha), Kant (Categorical Imperative), Rawls (Veil of Ignorance), Amartya Sen (Capability approach)',
      'Values: Integrity, objectivity, impartiality, non-partisanship, dedication to public service, empathy, tolerance, compassion',
      'Emotional Intelligence: Goleman — Self-awareness, Self-regulation, Motivation, Empathy, Social Skills. Essential for civil servants',
      'Ethical Dilemmas: Duty vs conscience, organizational vs personal ethics, consequentialism (ends) vs deontology (means)',
      'Civil Service Conduct: Political neutrality, no misuse of position, financial integrity, loyalty to Constitution, non-partisanship',
      'Probity: RTI 2005, Lokpal & Lokayuktas 2013, Whistleblowers Act 2014, Citizen Charters, Social Audit, e-Governance transparency',
      'Case Study Framework: Identify stakeholders → Ethical issues → Apply theories → Evaluate options → Justify with values & empathy',
      'Attitude Components: Cognitive (belief), Affective (feeling), Behavioral (action). Formed through persuasion, experience, social influence',
      'Corporate Governance: Board independence, CSR (Section 135). ESG investing. Ethical business practices. SEBI guidelines',
      'Information Ethics: Data privacy, surveillance, digital divide, AI ethics (bias, fairness). Deepfake concerns. Right to be forgotten',
      'Moral Thinkers — Indian: Kautilya (statecraft), Vivekananda (service), Ambedkar (social justice), Tagore (universalism), Aurobindo (spiritual)',
      'Corruption Index: India ranked ~93/180 (TI CPI). Technology, RTI, Lokpal, judicial reform as solutions. CVC for Central Government',
      'Whistleblower Protection: WPA 2014. RTI activists\' safety concerns. Institutional mechanisms for exposing corruption without fear',
      'ARC 2nd Report: Ethics in governance recommendations. Code of Ethics vs Code of Conduct distinction. Values for bureaucracy',
    ]),
    _Section('${_ib}polity.png', 'Internal Security', 'security', [
      'GS-III Topic: Terrorism, insurgency, LWE, border management, cyber security, money laundering, maritime security',
      'LWE (Naxalism): 90+ districts, 11 states. Operation SAMADHAN strategy. Surrender & rehabilitation. Developmental approach',
      'Border Management: 15,106 km land borders. BSF (Pak/BD), ITBP (China), SSB (Nepal/Bhutan), Assam Rifles (Myanmar)',
      'Terrorism: UAPA Act. NIA (National Investigation Agency). Multi-Agency Centre (MAC). NATGRID for intelligence sharing',
      'Northeast: AFSPA (controversial). Insurgent groups: NDFB, ULFA, NSCN. Framework Agreement with NSCN(IM). Ethnic clashes in Manipur',
      'Cyber Security: CERT-In. National Cyber Security Policy 2013. Cyber Swachhta Kendra. Critical information infrastructure protection',
      'Money Laundering: PMLA 2002. ED (Enforcement Directorate). FATF membership. Hawala, shell companies, crypto-based laundering',
      'Maritime Security: Navy, Coast Guard. IFC-IOR (Information Fusion Centre). Anti-piracy. Island territory defence',
      'Intelligence: RAW (external), IB (internal), NTRO (technical), DIA (defence). NSA coordinates. MAC for info sharing',
      'Social Media Threats: Fake news, deepfakes, radicalization. IT Act Section 69A (blocking). Intermediary Guidelines 2021',
      'Drug Trafficking: Golden Triangle & Golden Crescent routes. NCB. NDPS Act 1985. Dark web. Synthetic drugs increasing',
      'Disaster Management: NDMA (National), SDMA (State), DDMA (District). NDRF — 16 battalions. DM Act 2005',
      'Defence Reforms: CDS created 2019. Theatre commands proposed. Atmanirbhar in defence. Integrated defence planning',
      'Communalism: District admin role in riot prevention. National Integration Council. NCM, NHRC provisions',
      'Organized Crime: MCOCA. Human trafficking (ITPA). Cross-border syndicates. NIA expanded mandate',
    ]),
    _Section('${_ib}polity.png', 'Governance & Schemes', 'governance', [
      'PM-KISAN: ₹6,000/year in 3 installments to farmers. DBT — 11 crore+ beneficiaries. No middlemen. Aadhaar-linked',
      'Ayushman Bharat (PM-JAY): Health insurance ₹5 lakh/family/year. 55 crore+ beneficiaries. Cashless at empaneled hospitals',
      'Swachh Bharat: Phase I (2014-19) — ODF India. Phase II — ODF+, solid/liquid waste management. Rural + Urban components',
      'Jal Jeevan Mission: Tap water to every rural household. Har Ghar Jal. ₹3.60 lakh crore. Functional Household Tap Connections',
      'NEP 2020: 5+3+3+4 structure. Mother tongue till Class 5. Multiple entry/exit. Academic Bank of Credits. Liberal education',
      'PM Awas Yojana: Housing for All. Urban + Rural (Gramin). Subsidy linked. 2.95 crore+ houses constructed. Extended timelines',
      'Aspirational Districts: 112 districts — low socio-economic indicators. Real-time monitoring & ranking. NITI Aayog coordinates',
      'Mission Karmayogi: Civil services capacity building. iGOT platform. Competency-based training. National Programme for CS capacity',
      'Start-up India: Launched 2016. Tax benefits, IPR support, easy compliance. Fund of Funds. 1.15 lakh+ recognized startups',
      'PM GatiShakti: National Master Plan — multi-modal connectivity. 16 ministries integrated. GIS-based planning. Infrastructure coordination',
      'Skill India: PMKVY (Kaushal Vikas Yojana). Sector Skill Councils. Apprenticeship. Target: skilled workforce for demographic dividend',
      'DBT: Direct Benefit Transfer via JAM Trinity. Eliminates middlemen. ₹28+ lakh crore transferred. 300+ schemes digitized',
      'Smart Cities: 100 cities. Area-based development. Technology solutions. SPVs. Urban mobility, water, sanitation, energy',
      'Ujjwala Yojana: Free LPG for BPL women. 10 crore+ beneficiaries. Clean cooking fuel. Reduced indoor pollution deaths',
      'MGNREGA: 100 days guaranteed wage employment. Demand-driven. Social audit mandatory. Rural employment backbone since 2005',
      'NFSA 2013: 67% population covered. 5 kg/person/month at ₹1-3/kg. PMGKAY extended free rations during COVID',
      'Digital India: BharatNet rural broadband. CSCs. e-Governance. DigiLocker, UMANG, Aarogya Setu. Internet penetration 52%+',
      'Lakhpati Didi: Target 2 crore rural women earning ₹1 lakh+/year through SHGs. Micro-enterprise & skill development',
      'Vibrant Villages: Border village development. Infrastructure, livelihood, tourism. Counter depopulation near China border',
      'PM Vishwakarma: Traditional artisans & craftspeople. Skill training, toolkit support, credit. 18 trades covered. ₹13,000 crore',
    ]),
  ];

  List<_Section> _sections = [];
  List<_Section> _allSections = [];
  bool _isLoading = true;
  bool _isLoadingWeb = false;
  String _searchQuery = '';
  String _selectedCategory = 'All';
  final _searchController = TextEditingController();

  static const _iconMap = {
    'Polity': '${_ib}polity.png',
    'Economy': '${_ib}economy.png',
    'Environment': '${_ib}environment.png',
    'Science & Technology': '${_ib}science.png',
    'International Relations': '${_ib}international.png',
    'History': '${_ib}history.png',
    'Geography': '${_ib}environment.png',
    'Governance': '${_ib}polity.png',
    'Ethics': '${_ib}polity.png',
    'Security': '${_ib}polity.png',
    'Current Affairs': '${_ib}science.png',
  };

  static const _categoryMap = {
    'Polity': 'polity',
    'Economy': 'economy',
    'Environment': 'environment',
    'Science & Technology': 'science',
    'International Relations': 'international',
    'History': 'history',
    'Geography': 'geography',
    'Governance': 'governance',
    'Ethics': 'ethics',
    'Security': 'security',
    'Current Affairs': 'current',
  };

  static const _categoryTabs = [
    'All', 'Polity', 'Economy', 'Environment', 'Science',
    'IR', 'History', 'Geography', 'Ethics', 'Security', 'Governance',
  ];

  @override
  void initState() {
    super.initState();
    _loadAllContent();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAllContent() async {
    setState(() => _isLoading = true);

    // Start with rich local data
    _allSections = List.from(_localSections);

    // Merge Firestore data
    final firestoreFacts = await DailyContentManager.fetchDailyFacts();
    if (firestoreFacts.isNotEmpty) {
      for (final fact in firestoreFacts) {
        final cat = fact['category'] as String;
        final title = fact['title'] as String;
        final facts = (fact['facts'] as List<dynamic>).map((e) => e.toString()).toList();
        final icon = _iconMap[cat] ?? '${_ib}polity.png';
        final category = _categoryMap[cat] ?? cat.toLowerCase();

        // Find existing section and merge facts, or add new section
        final existing = _allSections.indexWhere((s) => s.category == category);
        if (existing >= 0) {
          final existingFacts = Set<String>.from(_allSections[existing].facts);
          final newFacts = facts.where((f) => !existingFacts.contains(f)).toList();
          if (newFacts.isNotEmpty) {
            final merged = [..._allSections[existing].facts, ...newFacts];
            _allSections[existing] = _Section(
              _allSections[existing].iconPath, _allSections[existing].title,
              _allSections[existing].category, merged,
            );
          }
        } else {
          _allSections.add(_Section(icon, title, category, facts));
        }
      }
    }

    _applyFilters();
    if (mounted) setState(() => _isLoading = false);

    // Fetch web content in background
    _fetchWebContent();
  }

  Future<void> _fetchWebContent() async {
    if (!mounted) return;
    setState(() => _isLoadingWeb = true);

    try {
      final webContent = await UpscContentService.fetchCurrentAffairs();
      if (webContent.isNotEmpty && mounted) {
        for (final item in webContent) {
          final cat = item['category'] as String? ?? 'Current Affairs';
          final title = item['title'] as String? ?? cat;
          final facts = (item['facts'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
          if (facts.isEmpty) continue;

          final icon = _iconMap[cat] ?? '${_ib}science.png';
          final category = _categoryMap[cat] ?? cat.toLowerCase().replaceAll(' ', '');

          final existing = _allSections.indexWhere((s) => s.category == category);
          if (existing >= 0) {
            final existingFacts = Set<String>.from(_allSections[existing].facts);
            final newFacts = facts.where((f) => !existingFacts.contains(f)).toList();
            if (newFacts.isNotEmpty) {
              final merged = [..._allSections[existing].facts, ...newFacts];
              _allSections[existing] = _Section(
                _allSections[existing].iconPath, _allSections[existing].title,
                _allSections[existing].category, merged,
              );
            }
          } else {
            _allSections.add(_Section(icon, '$title (Live)', category, facts));
          }
        }
        _applyFilters();
      }
    } catch (e) {
      debugPrint('Web content fetch error: $e');
    }

    if (mounted) setState(() => _isLoadingWeb = false);
  }

  void _applyFilters() {
    var filtered = List<_Section>.from(_allSections);

    // Category filter
    if (_selectedCategory != 'All') {
      final catKey = _selectedCategory.toLowerCase();
      filtered = filtered.where((s) {
        final sc = s.category.toLowerCase();
        if (catKey == 'ir') return sc == 'international';
        if (catKey == 'science') return sc == 'science';
        return sc.contains(catKey);
      }).toList();
    }

    // Search filter
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = filtered.map((s) {
        final matchingFacts = s.facts.where((f) => f.toLowerCase().contains(query)).toList();
        if (matchingFacts.isNotEmpty) {
          return _Section(s.iconPath, s.title, s.category, matchingFacts);
        }
        if (s.title.toLowerCase().contains(query)) return s;
        return null;
      }).whereType<_Section>().toList();
    }

    _sections = filtered;
  }

  @override
  Widget build(BuildContext context) {
    final progress = context.watch<DailyProgressProvider>();
    final totalFacts = _allSections.fold<int>(0, (sum, s) => sum + s.facts.length);

    return GradientScaffold(
      showAppBar: false,
      child: SafeArea(
        child: Column(
          children: [
            _backBar(context, totalFacts),
            _buildSearchBar(context),
            _buildCategoryTabs(context),
            if (_isLoading)
              Expanded(child: Center(child: Lottie.asset('assets/animations/loading.json', width: 120, height: 120)))
            else
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async {
                    await UpscContentService.clearCache();
                    await _loadAllContent();
                  },
                  child: ListView.builder(
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                    itemCount: _sections.length + (_isLoadingWeb ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (_isLoadingWeb && i == _sections.length) {
                        return Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryColor)),
                              const SizedBox(width: 10),
                              Text('Fetching latest content...', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textS(context))),
                            ],
                          ),
                        );
                      }
                      return _buildSection(context, _sections[i], progress);
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _backBar(BuildContext context, int totalFacts) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
      child: Row(
        children: [
          IconButton(icon: const Icon(Icons.arrow_back_ios_rounded), onPressed: () {
            HapticFeedback.lightImpact();
            Navigator.pop(context);
          }),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('UPSC Must Know', style: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.w700, color: AppTheme.textP(context))),
                Text('$totalFacts facts across ${_allSections.length} topics', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textS(context))),
              ],
            ),
          ),
          if (_isLoadingWeb)
            SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryColor)),
        ],
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: GlassCard(
        padding: EdgeInsets.zero,
        child: TextField(
          controller: _searchController,
          style: GoogleFonts.inter(fontSize: 14, color: AppTheme.textP(context)),
          decoration: InputDecoration(
            hintText: 'Search facts... (e.g., "Article 21", "GDP", "ISRO")',
            hintStyle: GoogleFonts.inter(fontSize: 13, color: AppTheme.textS(context)),
            prefixIcon: Icon(Icons.search_rounded, color: AppTheme.textS(context), size: 20),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: Icon(Icons.clear_rounded, color: AppTheme.textS(context), size: 18),
                    onPressed: () {
                      _searchController.clear();
                      setState(() {
                        _searchQuery = '';
                        _applyFilters();
                      });
                    },
                  )
                : null,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            fillColor: Colors.transparent,
            filled: true,
          ),
          onChanged: (value) {
            setState(() {
              _searchQuery = value;
              _applyFilters();
            });
          },
        ),
      ),
    );
  }

  Widget _buildCategoryTabs(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        itemCount: _categoryTabs.length,
        itemBuilder: (context, i) {
          final tab = _categoryTabs[i];
          final isSelected = _selectedCategory == tab;
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() {
                  _selectedCategory = tab;
                  _applyFilters();
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: isSelected ? AppTheme.primaryColor : AppTheme.primaryColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  tab,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.white : AppTheme.textS(context),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSection(BuildContext context, _Section section, DailyProgressProvider progress) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: GlassCard(
          padding: EdgeInsets.zero,
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 44, height: 44,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: CachedNetworkImage(
                          imageUrl: AppImages.categoryImage(section.category),
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(color: AppTheme.primaryColor.withValues(alpha: 0.08)),
                          errorWidget: (_, __, ___) => Container(color: AppTheme.primaryColor.withValues(alpha: 0.08)),
                        ),
                      ),
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft, end: Alignment.bottomRight,
                              colors: [
                                AppTheme.primaryColor.withValues(alpha: 0.5),
                                AppTheme.accentViolet.withValues(alpha: 0.5),
                              ],
                            ),
                          ),
                          child: Center(child: Image.asset(section.iconPath, width: 22, height: 22, color: Colors.white)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              title: Text(section.title, style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.textP(context))),
              subtitle: Text('${section.facts.length} key facts', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textS(context))),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: section.facts.asMap().entries.map((entry) {
                final idx = entry.key;
                final fact = entry.value;
                final saved = progress.isFactSaved(fact);

                // Highlight search matches
                final hasMatch = _searchQuery.isNotEmpty && fact.toLowerCase().contains(_searchQuery.toLowerCase());

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Container(
                    padding: hasMatch ? const EdgeInsets.all(8) : EdgeInsets.zero,
                    decoration: hasMatch
                        ? BoxDecoration(
                            color: AppTheme.primaryColor.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.15)),
                          )
                        : null,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Container(
                            width: 20, height: 20,
                            decoration: BoxDecoration(
                              color: AppTheme.primaryColor.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                '${idx + 1}',
                                style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w700, color: AppTheme.primaryColor),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            fact,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: AppTheme.textP(context),
                              height: 1.55,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: () => progress.toggleSavedFact(fact),
                          child: Icon(
                            saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                            color: saved ? AppTheme.warningOrange : AppTheme.textS(context),
                            size: 18,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }
}

class _Section {
  final String iconPath;
  final String title;
  final String category;
  final List<String> facts;
  const _Section(this.iconPath, this.title, this.category, this.facts);
}
