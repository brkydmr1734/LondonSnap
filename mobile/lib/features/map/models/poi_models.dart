import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

// ──────────────────────────────────────────────────────────────────
// POI CATEGORY — GTA5-inspired venue classification
// ──────────────────────────────────────────────────────────────────

enum PoiCategory {
  restaurant(
    'Restaurants',
    Color(0xFFF97316), // Warm orange
    Icons.restaurant,
    '🍽️',
  ),
  cafe(
    'Cafés',
    Color(0xFF8B5CF6), // Purple
    Icons.local_cafe,
    '☕',
  ),
  nightclub(
    'Nightclubs',
    Color(0xFFEC4899), // Hot pink
    Icons.nightlife,
    '🥂',
  ),
  hospital(
    'Hospitals',
    Color(0xFF10B981), // Emerald
    Icons.local_hospital,
    '🏥',
  ),
  casino(
    'Casinos',
    Color(0xFFEAB308), // Gold
    Icons.casino,
    '🎰',
  );

  final String label;
  final Color color;
  final IconData icon;
  final String emoji;

  const PoiCategory(this.label, this.color, this.icon, this.emoji);
}

// ──────────────────────────────────────────────────────────────────
// POI PIN MODEL
// ──────────────────────────────────────────────────────────────────

class PoiPin {
  final String id;
  final String name;
  final PoiCategory category;
  final LatLng position;
  final double rating;
  final String? priceLevel; // £, ££, £££, ££££
  final String address;
  final String? imageUrl;
  final String? description;
  final bool isOpen;
  final String? openHours;

  const PoiPin({
    required this.id,
    required this.name,
    required this.category,
    required this.position,
    required this.rating,
    this.priceLevel,
    required this.address,
    this.imageUrl,
    this.description,
    this.isOpen = true,
    this.openHours,
  });
}

// ──────────────────────────────────────────────────────────────────
// CURATED LONDON VENUES — Prestigious & Popular
// ──────────────────────────────────────────────────────────────────

class LondonPois {
  static const List<PoiPin> all = [
    // ─── RESTAURANTS ─────────────────────────────────────────────
    PoiPin(
      id: 'r1', name: 'Dishoom King\'s Cross',
      category: PoiCategory.restaurant,
      position: LatLng(51.5332, -0.1240),
      rating: 4.7, priceLevel: '££',
      address: 'Granary Square, N1C 4AA',
      description: 'Award-winning Bombay-style café — student favourite for bacon naan rolls.',
    ),
    PoiPin(
      id: 'r2', name: 'Sketch',
      category: PoiCategory.restaurant,
      position: LatLng(51.5128, -0.1420),
      rating: 4.5, priceLevel: '££££',
      address: '9 Conduit St, Mayfair, W1S 2XG',
      description: 'Iconic pink gallery restaurant with Michelin-starred afternoon tea.',
    ),
    PoiPin(
      id: 'r3', name: 'Flat Iron Soho',
      category: PoiCategory.restaurant,
      position: LatLng(51.5138, -0.1340),
      rating: 4.6, priceLevel: '£',
      address: '17 Beak St, Soho, W1F 9RW',
      description: 'Cult-favourite steak spot — incredible value at £12 for a flat iron.',
    ),
    PoiPin(
      id: 'r4', name: 'The Ivy Chelsea Garden',
      category: PoiCategory.restaurant,
      position: LatLng(51.4876, -0.1685),
      rating: 4.4, priceLevel: '£££',
      address: '195-197 King\'s Rd, Chelsea, SW3 5EQ',
      description: 'Glamorous all-day dining with a stunning garden terrace.',
    ),
    PoiPin(
      id: 'r5', name: 'Padella',
      category: PoiCategory.restaurant,
      position: LatLng(51.5055, -0.0914),
      rating: 4.7, priceLevel: '£',
      address: '6 Southwark St, SE1 1TQ',
      description: 'London\'s most-queued pasta bar — hand-rolled perfection from £6.',
    ),
    PoiPin(
      id: 'r6', name: 'Nobu London',
      category: PoiCategory.restaurant,
      position: LatLng(51.5033, -0.1523),
      rating: 4.5, priceLevel: '££££',
      address: '19 Old Park Lane, W1K 1LB',
      description: 'World-renowned Japanese-Peruvian fusion in the heart of Mayfair.',
    ),
    PoiPin(
      id: 'r7', name: 'Burger & Lobster Soho',
      category: PoiCategory.restaurant,
      position: LatLng(51.5130, -0.1368),
      rating: 4.3, priceLevel: '££',
      address: '36 Dean St, Soho, W1D 4PS',
      description: 'Simple menu — choose burger, lobster, or lobster roll. All £20.',
    ),
    PoiPin(
      id: 'r8', name: 'Duck & Waffle',
      category: PoiCategory.restaurant,
      position: LatLng(51.5165, -0.0827),
      rating: 4.4, priceLevel: '£££',
      address: '110 Bishopsgate, EC2N 4AY',
      description: '24/7 rooftop dining on the 40th floor with skyline views.',
    ),
    PoiPin(
      id: 'r9', name: 'Bao Soho',
      category: PoiCategory.restaurant,
      position: LatLng(51.5133, -0.1310),
      rating: 4.6, priceLevel: '£',
      address: '53 Lexington St, Soho, W1F 9AS',
      description: 'Cult Taiwanese steamed buns — tiny space, massive flavour.',
    ),
    PoiPin(
      id: 'r10', name: 'Gymkhana',
      category: PoiCategory.restaurant,
      position: LatLng(51.5088, -0.1398),
      rating: 4.6, priceLevel: '£££',
      address: '42 Albemarle St, Mayfair, W1S 4JH',
      description: 'Michelin-starred modern Indian inspired by colonial gymkhana clubs.',
    ),
    PoiPin(
      id: 'r11', name: 'Hawksmoor Seven Dials',
      category: PoiCategory.restaurant,
      position: LatLng(51.5138, -0.1268),
      rating: 4.7, priceLevel: '£££',
      address: '11 Langley St, Covent Garden, WC2H 9JG',
      description: 'London\'s best steak restaurant — dry-aged British beef perfection.',
    ),
    PoiPin(
      id: 'r12', name: 'Koya Bar',
      category: PoiCategory.restaurant,
      position: LatLng(51.5115, -0.1365),
      rating: 4.5, priceLevel: '£',
      address: '50 Frith St, Soho, W1D 4SQ',
      description: 'Authentic Japanese udon bar — handmade noodles in rich dashi.',
    ),
    PoiPin(
      id: 'r13', name: 'Franco Manca Brixton',
      category: PoiCategory.restaurant,
      position: LatLng(51.4613, -0.1156),
      rating: 4.5, priceLevel: '£',
      address: '4 Market Row, Brixton, SW9 8LD',
      description: 'The original sourdough pizza spot — slow-risen bases from £7.',
    ),
    PoiPin(
      id: 'r14', name: 'The River Café',
      category: PoiCategory.restaurant,
      position: LatLng(51.4833, -0.2316),
      rating: 4.6, priceLevel: '££££',
      address: 'Thames Wharf, Rainville Rd, W6 9HA',
      description: 'Legendary Italian on the Thames — trained Jamie Oliver & many more.',
    ),
    PoiPin(
      id: 'r15', name: 'Mangal 2',
      category: PoiCategory.restaurant,
      position: LatLng(51.5498, -0.0746),
      rating: 4.5, priceLevel: '£',
      address: '4 Stoke Newington Rd, Dalston, N16 8BH',
      description: 'East London\'s legendary Turkish grill — art on walls, fire on charcoal.',
    ),
    PoiPin(
      id: 'r16', name: 'Poppies Fish & Chips',
      category: PoiCategory.restaurant,
      position: LatLng(51.5202, -0.0726),
      rating: 4.4, priceLevel: '£',
      address: '6-8 Hanbury St, Spitalfields, E1 6QR',
      description: '1950s-themed chippy — award-winning cod & chips since 1945.',
    ),
    PoiPin(
      id: 'r17', name: 'The Ledbury',
      category: PoiCategory.restaurant,
      position: LatLng(51.5150, -0.2035),
      rating: 4.7, priceLevel: '££££',
      address: '127 Ledbury Rd, Notting Hill, W11 2AQ',
      description: 'Two Michelin stars — modern European tasting menus of exceptional craft.',
    ),
    PoiPin(
      id: 'r18', name: 'Dishoom Shoreditch',
      category: PoiCategory.restaurant,
      position: LatLng(51.5237, -0.0775),
      rating: 4.6, priceLevel: '££',
      address: '7 Boundary St, Shoreditch, E2 7JE',
      description: 'Bombay café vibes in a warehouse — black daal is life-changing.',
    ),
    PoiPin(
      id: 'r19', name: 'Nando\'s Greenwich',
      category: PoiCategory.restaurant,
      position: LatLng(51.4784, -0.0140),
      rating: 4.2, priceLevel: '£',
      address: '43 Greenwich Church St, SE10 9BL',
      description: 'Student favourite peri-peri chicken with Cutty Sark views nearby.',
    ),
    PoiPin(
      id: 'r20', name: 'Tayyabs',
      category: PoiCategory.restaurant,
      position: LatLng(51.5162, -0.0644),
      rating: 4.5, priceLevel: '£',
      address: '83-89 Fieldgate St, Whitechapel, E1 1JU',
      description: 'BYO Punjabi legend — lamb chops that are worth every queue minute.',
    ),

    // ─── CAFÉS ───────────────────────────────────────────────────
    PoiPin(
      id: 'c1', name: 'Monmouth Coffee Borough',
      category: PoiCategory.cafe,
      position: LatLng(51.5047, -0.0903),
      rating: 4.7, priceLevel: '£',
      address: '2 Park St, Borough Market, SE1 9AB',
      description: 'London\'s cult coffee roaster — single-origin brews since 1978.',
    ),
    PoiPin(
      id: 'c2', name: 'Peggy Porschen',
      category: PoiCategory.cafe,
      position: LatLng(51.4933, -0.1500),
      rating: 4.5, priceLevel: '££',
      address: '116 Ebury St, Belgravia, SW1W 9QQ',
      description: 'Instagram-famous pink floral façade with artisan cupcakes.',
    ),
    PoiPin(
      id: 'c3', name: 'Attendant Fitzrovia',
      category: PoiCategory.cafe,
      position: LatLng(51.5198, -0.1379),
      rating: 4.6, priceLevel: '£',
      address: '27A Foley St, Fitzrovia, W1W 6DY',
      description: 'Speakeasy-style café hidden in a converted Victorian lavatory.',
    ),
    PoiPin(
      id: 'c4', name: 'KOKO Coffee & Design',
      category: PoiCategory.cafe,
      position: LatLng(51.5175, -0.0765),
      rating: 4.4, priceLevel: '£',
      address: 'Shoreditch High St, E1 6JJ',
      description: 'Minimalist Scandi-inspired café with specialty pourover & pastries.',
    ),
    PoiPin(
      id: 'c5', name: 'Farm Girl Notting Hill',
      category: PoiCategory.cafe,
      position: LatLng(51.5148, -0.2020),
      rating: 4.5, priceLevel: '££',
      address: '59A Portobello Rd, W11 3DB',
      description: 'Aussie-inspired wellness café with rose lattes & acai bowls.',
    ),
    PoiPin(
      id: 'c6', name: 'The Wren Coffee',
      category: PoiCategory.cafe,
      position: LatLng(51.5136, -0.0879),
      rating: 4.6, priceLevel: '£',
      address: '24 Bride Ln, EC4Y 8DT',
      description: 'Hidden gem near St Paul\'s — artisan coffee in a medieval church alley.',
    ),
    PoiPin(
      id: 'c7', name: 'Ozone Coffee Shoreditch',
      category: PoiCategory.cafe,
      position: LatLng(51.5278, -0.0769),
      rating: 4.6, priceLevel: '££',
      address: '11 Leonard St, Shoreditch, EC2A 4AQ',
      description: 'New Zealand-born roastery with brunch that rivals any restaurant.',
    ),
    PoiPin(
      id: 'c8', name: 'Rosslyn Coffee',
      category: PoiCategory.cafe,
      position: LatLng(51.5132, -0.0871),
      rating: 4.7, priceLevel: '£',
      address: '78 Queen Victoria St, EC4N 4SJ',
      description: 'Speciality coffee by the river — consistently one of London\'s best.',
    ),
    PoiPin(
      id: 'c9', name: 'Pavilion Café Victoria Park',
      category: PoiCategory.cafe,
      position: LatLng(51.5362, -0.0380),
      rating: 4.5, priceLevel: '£',
      address: 'Victoria Park, Crown Gate West, E9 7DE',
      description: 'Lakeside café in East London\'s best park — sourdough toasties & flat whites.',
    ),
    PoiPin(
      id: 'c10', name: 'Gail\'s Hampstead',
      category: PoiCategory.cafe,
      position: LatLng(51.5560, -0.1780),
      rating: 4.5, priceLevel: '££',
      address: '64 Hampstead High St, NW3 1QH',
      description: 'Beloved bakery with sourdough, pastries & strong flat whites.',
    ),
    PoiPin(
      id: 'c11', name: 'E Pellicci',
      category: PoiCategory.cafe,
      position: LatLng(51.5277, -0.0596),
      rating: 4.7, priceLevel: '£',
      address: '332 Bethnal Green Rd, E2 0AG',
      description: 'Grade II listed Italian caff since 1900 — full English with charm.',
    ),
    PoiPin(
      id: 'c12', name: 'Buns From Home Covent Garden',
      category: PoiCategory.cafe,
      position: LatLng(51.5130, -0.1239),
      rating: 4.4, priceLevel: '£',
      address: '35 The Market, Covent Garden, WC2E 8RF',
      description: 'Viral cinnamon buns — fluffy, decadent, and ridiculously Instagrammable.',
    ),
    PoiPin(
      id: 'c13', name: 'Watch House Bermondsey',
      category: PoiCategory.cafe,
      position: LatLng(51.5006, -0.0798),
      rating: 4.6, priceLevel: '£',
      address: '199 Bermondsey St, SE1 3UW',
      description: 'Specialty coffee in a converted 1830s watch house — beautiful courtyard.',
    ),
    PoiPin(
      id: 'c14', name: 'The Fields Beneath',
      category: PoiCategory.cafe,
      position: LatLng(51.5460, -0.1430),
      rating: 4.5, priceLevel: '£',
      address: '52a Prince of Wales Rd, Kentish Town, NW5 3LN',
      description: 'Tiny railway arch café — some of the best espresso in North London.',
    ),

    // ─── NIGHTCLUBS ──────────────────────────────────────────────
    PoiPin(
      id: 'n1', name: 'Fabric',
      category: PoiCategory.nightclub,
      position: LatLng(51.5200, -0.1026),
      rating: 4.6, priceLevel: '££',
      address: '77A Charterhouse St, EC1M 6HJ',
      description: 'Legendary 2,500-capacity superclub — world-class DJs & bodysonic dancefloor.',
    ),
    PoiPin(
      id: 'n2', name: 'Ministry of Sound',
      category: PoiCategory.nightclub,
      position: LatLng(51.4955, -0.1010),
      rating: 4.5, priceLevel: '££',
      address: '103 Gaunt St, Elephant & Castle, SE1 6DP',
      description: 'Iconic dance music institution with a £4M custom sound system.',
    ),
    PoiPin(
      id: 'n3', name: 'XOYO Shoreditch',
      category: PoiCategory.nightclub,
      position: LatLng(51.5245, -0.0790),
      rating: 4.4, priceLevel: '£',
      address: '32-37 Cowper St, EC2A 4AP',
      description: 'Shoreditch favourite — rotating residencies from underground to house.',
    ),
    PoiPin(
      id: 'n4', name: 'Tape London',
      category: PoiCategory.nightclub,
      position: LatLng(51.5098, -0.1418),
      rating: 4.3, priceLevel: '££££',
      address: '17 Hanover Square, Mayfair, W1S 1HU',
      description: 'Ultra-exclusive Mayfair members club for celebrities & VIPs.',
    ),
    PoiPin(
      id: 'n5', name: 'Printworks',
      category: PoiCategory.nightclub,
      position: LatLng(51.4987, -0.0215),
      rating: 4.7, priceLevel: '££',
      address: 'Surrey Quays Rd, SE16 7PJ',
      description: 'Colossal ex-printing press turned immersive venue — 5,000 capacity.',
    ),
    PoiPin(
      id: 'n6', name: 'Cirque le Soir',
      category: PoiCategory.nightclub,
      position: LatLng(51.5145, -0.1330),
      rating: 4.2, priceLevel: '££££',
      address: '15-21 Ganton St, Soho, W1F 9BN',
      description: 'Carnival-themed circus club — fire breathers, acrobats, and cocktails.',
    ),
    PoiPin(
      id: 'n7', name: 'Cargo Shoreditch',
      category: PoiCategory.nightclub,
      position: LatLng(51.5265, -0.0790),
      rating: 4.3, priceLevel: '£',
      address: '83 Rivington St, Shoreditch, EC2A 3AY',
      description: 'Railway arch venue with outdoor terrace — hip-hop, R&B & student nights.',
    ),
    PoiPin(
      id: 'n8', name: 'Egg London',
      category: PoiCategory.nightclub,
      position: LatLng(51.5392, -0.1254),
      rating: 4.3, priceLevel: '££',
      address: '200 York Way, King\'s Cross, N7 9AX',
      description: 'Multi-room warehouse club with garden — techno till sunrise.',
    ),
    PoiPin(
      id: 'n9', name: 'Village Underground',
      category: PoiCategory.nightclub,
      position: LatLng(51.5253, -0.0782),
      rating: 4.5, priceLevel: '££',
      address: '54 Holywell Ln, Shoreditch, EC2A 3PQ',
      description: 'Creative warehouse with tube carriages on the roof — gigs & club nights.',
    ),
    PoiPin(
      id: 'n10', name: 'Corsica Studios',
      category: PoiCategory.nightclub,
      position: LatLng(51.4943, -0.1005),
      rating: 4.5, priceLevel: '£',
      address: '4-5 Elephant Rd, SE17 1LB',
      description: 'Underground favourite — two dark rooms, serious sound system, no pretence.',
    ),
    PoiPin(
      id: 'n11', name: 'Heaven',
      category: PoiCategory.nightclub,
      position: LatLng(51.5073, -0.1228),
      rating: 4.4, priceLevel: '£',
      address: 'The Arches, Villiers St, WC2N 6NG',
      description: 'Iconic LGBTQ+ club under Charing Cross — pop anthems since 1979.',
    ),
    PoiPin(
      id: 'n12', name: 'Phonox Brixton',
      category: PoiCategory.nightclub,
      position: LatLng(51.4615, -0.1147),
      rating: 4.4, priceLevel: '£',
      address: '418 Brixton Rd, SW9 7AY',
      description: 'Brixton\'s best late-night spot — intimate room, big-name DJs, free entry.',
    ),

    // ─── HOSPITALS ───────────────────────────────────────────────
    PoiPin(
      id: 'h1', name: 'University College Hospital',
      category: PoiCategory.hospital,
      position: LatLng(51.5248, -0.1358),
      rating: 4.3, priceLevel: null,
      address: '235 Euston Rd, NW1 2BU',
      description: 'Major NHS teaching hospital & Level 1 trauma centre.',
    ),
    PoiPin(
      id: 'h2', name: 'St Thomas\' Hospital',
      category: PoiCategory.hospital,
      position: LatLng(51.4985, -0.1186),
      rating: 4.4, priceLevel: null,
      address: 'Westminster Bridge Rd, SE1 7EH',
      description: 'Iconic Thames-side hospital opposite the Houses of Parliament.',
    ),
    PoiPin(
      id: 'h3', name: 'Royal London Hospital',
      category: PoiCategory.hospital,
      position: LatLng(51.5183, -0.0595),
      rating: 4.2, priceLevel: null,
      address: 'Whitechapel Rd, E1 1FR',
      description: 'East London\'s largest hospital with a helipad & major A&E.',
    ),
    PoiPin(
      id: 'h4', name: 'King\'s College Hospital',
      category: PoiCategory.hospital,
      position: LatLng(51.4684, -0.0945),
      rating: 4.1, priceLevel: null,
      address: 'Denmark Hill, SE5 9RS',
      description: 'World-renowned liver transplant centre & major trauma unit.',
    ),
    PoiPin(
      id: 'h5', name: 'Guy\'s Hospital',
      category: PoiCategory.hospital,
      position: LatLng(51.5038, -0.0879),
      rating: 4.3, priceLevel: null,
      address: 'Great Maze Pond, SE1 9RT',
      description: 'Historic hospital near London Bridge with specialist dental care.',
    ),
    PoiPin(
      id: 'h6', name: 'Chelsea & Westminster Hospital',
      category: PoiCategory.hospital,
      position: LatLng(51.4845, -0.1810),
      rating: 4.3, priceLevel: null,
      address: '369 Fulham Rd, Chelsea, SW10 9NH',
      description: 'Award-winning NHS hospital with public art gallery inside.',
    ),
    PoiPin(
      id: 'h7', name: 'Whittington Hospital',
      category: PoiCategory.hospital,
      position: LatLng(51.5652, -0.1385),
      rating: 4.0, priceLevel: null,
      address: 'Magdala Ave, Archway, N19 5NF',
      description: 'North London A&E and maternity unit near Archway station.',
    ),
    PoiPin(
      id: 'h8', name: 'Homerton University Hospital',
      category: PoiCategory.hospital,
      position: LatLng(51.5477, -0.0440),
      rating: 4.1, priceLevel: null,
      address: 'Homerton Row, Hackney, E9 6SR',
      description: 'Hackney\'s main hospital — A&E, maternity & specialist care.',
    ),

    // ─── CASINOS ─────────────────────────────────────────────────
    PoiPin(
      id: 'k1', name: 'The Hippodrome Casino',
      category: PoiCategory.casino,
      position: LatLng(51.5110, -0.1280),
      rating: 4.5, priceLevel: '£££',
      address: 'Cranbourn St, Leicester Square, WC2H 7JH',
      description: 'London\'s biggest casino — 5 floors of gaming, dining & live shows.',
    ),
    PoiPin(
      id: 'k2', name: 'The Ritz Club',
      category: PoiCategory.casino,
      position: LatLng(51.5070, -0.1415),
      rating: 4.7, priceLevel: '££££',
      address: '150 Piccadilly, W1J 9BR',
      description: 'Ultra-prestigious private gaming salon inside The Ritz London.',
    ),
    PoiPin(
      id: 'k3', name: 'Aspers Casino Westfield',
      category: PoiCategory.casino,
      position: LatLng(51.5434, -0.0092),
      rating: 4.2, priceLevel: '££',
      address: 'Westfield Stratford, E20 1ET',
      description: 'Modern casino inside Stratford\'s mega-mall — poker, slots & sports.',
    ),
    PoiPin(
      id: 'k4', name: 'Les Ambassadeurs Club',
      category: PoiCategory.casino,
      position: LatLng(51.5069, -0.1540),
      rating: 4.6, priceLevel: '££££',
      address: '5 Hamilton Place, Mayfair, W1J 7ED',
      description: 'The most exclusive private gaming club in the world — since 1827.',
    ),
    PoiPin(
      id: 'k5', name: 'Grosvenor Casino The Victoria',
      category: PoiCategory.casino,
      position: LatLng(51.4934, -0.1467),
      rating: 4.3, priceLevel: '££',
      address: '150-162 Edgware Rd, W2 2DT',
      description: 'London\'s favourite poker room — cash games, tournaments & sports bar.',
    ),
    PoiPin(
      id: 'k6', name: 'Empire Casino Leicester Square',
      category: PoiCategory.casino,
      position: LatLng(51.5106, -0.1303),
      rating: 4.2, priceLevel: '££',
      address: '5-6 Leicester Square, WC2H 7NA',
      description: 'Open 24/7 in the heart of the West End — slots, roulette & poker.',
    ),
  ];

  /// Get venues filtered by category
  static List<PoiPin> byCategory(PoiCategory category) =>
      all.where((p) => p.category == category).toList();
}
