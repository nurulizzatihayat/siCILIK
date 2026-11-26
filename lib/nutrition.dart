import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'recipe.dart';

const Color mealOrange = Color(0xFFF39C12);
const Color mealAmber = Color(0xFFFFB41F);
const Color mealPanel = Color(0xFFF4F6FB);
const Color mealChip = Color(0xFFEEF1F8);
const Color mealPurple = Color(0xFF6D4FC2);
const Color mealText = Color(0xFF1F2430);
const Color mealMuted = Color(0xFF667085);

const _listPadding = EdgeInsets.fromLTRB(16, 14, 16, 24);
const _phoneListPadding = EdgeInsets.fromLTRB(12, 12, 12, 20);

String _dateKey(DateTime d) => d.toIso8601String().split('T').first;
String _number(double value) =>
    value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

Map<String, dynamic> _map(Object? value) =>
    value is Map<String, dynamic> ? value : const {};
List<dynamic> _list(Object? value) => value is List ? value : const [];
String _text(Object? value) => value is String ? value.trim() : '';
double? _quantity(Object? value) =>
    value is num && value.isFinite && value >= 0 ? value.toDouble() : null;

int? _ageInMonths(Object? birth, DateTime day) {
  final parsed = birth is Timestamp
      ? birth.toDate()
      : DateTime.tryParse(_text(birth));
  if (parsed == null) return null;
  final date = DateUtils.dateOnly(parsed);
  if (day.isBefore(date)) return -1;
  final months = (day.year - date.year) * 12 + day.month - date.month;
  final anniversary = date.day.clamp(
    1,
    DateUtils.getDaysInMonth(day.year, day.month),
  );
  return day.day < anniversary ? months - 1 : months;
}

enum _Nutrient {
  energy('Tenaga', 'kcal', Icons.local_fire_department_rounded),
  protein('Protein', 'g', Icons.egg_alt_rounded),
  calcium('Kalsium', 'mg', Icons.water_drop_rounded),
  iron('Zat besi', 'mg', Icons.bloodtype_rounded);

  const _Nutrient(this.label, this.unit, this.icon);
  final String label;
  final String unit;
  final IconData icon;
}

final _recipeAgeRange = RegExp(
  r'^(\d+)\s*(bulan|tahun)?\s*(?:[-–—]|hingga|sampai)\s*(\d+)\s*(bulan|tahun)$',
);
final _recipeAgeMinimum = RegExp(
  r'^(\d+)\s*(bulan|tahun)\s*(\+|(?:dan\s+)?ke\s+atas)?$',
);
final _recipeAgePrefix = RegExp(
  r'^(?:sesuai\s+untuk\s+)?(?:(?:bayi|kanak-kanak)\s+)?(?:berumur\s+|umur\s+)?',
);
final _recipeAmount = RegExp(
  r'^(?:[±~≈]\s*)?(\d+(?:[.,]\d+)?)\s*(kcal|mg|g)$',
  caseSensitive: false,
);
final _recipeEnergyLabel = RegExp(
  r'^(?:[±~≈]\s*)?\d+(?:[.,]\d+)?(?:\s*[-–]\s*\d+(?:[.,]\d+)?)?\s*kcal$',
  caseSensitive: false,
);

bool _recipeFitsAge(Recipe recipe, int age) {
  final minimum = recipe.minAgeMonths;
  final maximum = recipe.maxAgeMonths;
  if (minimum != null || maximum != null) {
    return minimum != null &&
        maximum != null &&
        minimum >= 0 &&
        age >= minimum &&
        age <= maximum;
  }

  final label = _text(recipe.ageSuitability)
      .toLowerCase()
      .replaceFirst(_recipeAgePrefix, '');
  final range = _recipeAgeRange.firstMatch(label);
  if (range != null) {
    final finalUnit = range[4]!;
    final first =
        int.parse(range[1]!) * ((range[2] ?? finalUnit) == 'tahun' ? 12 : 1);
    final last =
        int.parse(range[3]!) * (finalUnit == 'tahun' ? 12 : 1) +
        (finalUnit == 'tahun' ? 11 : 0);
    return age >= first && age <= last;
  }
  final single = _recipeAgeMinimum.firstMatch(label);
  if (single == null) return false;
  final unitMonths = single[2] == 'tahun' ? 12 : 1;
  final first = int.parse(single[1]!) * unitMonths;
  return age >= first && (single[3] != null || age < first + unitMonths);
}

double? _recipeNutrient(Recipe recipe, _Nutrient nutrient) {
  final value = recipe.nutrition?[nutrient.name];
  if (value is num) return _quantity(value);
  final match = _recipeAmount.firstMatch(_text(value));
  if (match == null) return null;
  final amount = _quantity(double.tryParse(match[1]!.replaceAll(',', '.')));
  if (amount == null) return null;
  final unit = match[2]!.toLowerCase();
  if (unit == nutrient.unit) return amount;
  if (unit == 'g' && nutrient.unit == 'mg') return amount * 1000;
  if (unit == 'mg' && nutrient.unit == 'g') return amount / 1000;
  return null;
}

// Age groups and textures in Keperluan Makanan Harian Bayi & Kanak-Kanak.
// Individual meals and nutrient targets come from Firestore.
({String label, List<String> pages})? _referenceMenu(int age) => switch (age) {
  >= 6 && <= 8 => (
    label: '6–8 bulan · Makanan dilecek atau dipuri',
    pages: const ['A', 'B'],
  ),
  >= 9 && <= 11 => (
    label: '9–11 bulan · Makanan lembut, dicincang atau dipotong kecil',
    pages: const ['C', 'D'],
  ),
  >= 12 && <= 47 => (
    label: '1–3 tahun · Makanan keluarga',
    pages: const ['E', 'F', 'G'],
  ),
  >= 48 && <= 83 => (
    label: '4–6 tahun · Makanan keluarga',
    pages: const ['H', 'I', 'J', 'K'],
  ),
  _ => null,
};

// Dish labels, ingredients, selected portions and photos from the supplied menus.
const _referenceDishes = {
  'A': [
    (
      name: 'Bubur nasi ayam dan bayam',
      photo: 'meal-1-1.jpg',
      ingredients: ['Beras', 'Isi ayam', 'Bayam', 'Minyak masak'],
      portion: '½ cawan atau 1 senduk bubur nasi pekat',
    ),
    (
      name: 'Pisang lecek',
      photo: 'meal-1-2.jpg',
      ingredients: ['Pisang'],
      portion: '¾ sudu makan pisang',
    ),
    (
      name: 'Bubur nasi ikan, bayam dan lobak merah',
      photo: 'meal-1-3.jpg',
      ingredients: [
        'Beras',
        'Isi ikan',
        'Bayam',
        'Lobak merah',
        'Minyak masak',
      ],
      portion: '½ cawan atau 1 senduk bubur nasi pekat',
    ),
    (
      name: 'Puri betik',
      photo: 'meal-1-4.jpg',
      ingredients: ['Betik'],
      portion: '¾ sudu makan betik',
    ),
    (
      name: 'Bubur nasi ayam, bayam dan tauhu lembut',
      photo: 'meal-1-5.jpg',
      ingredients: [
        'Beras',
        'Isi ayam',
        'Bayam',
        'Tauhu lembut',
        'Minyak masak',
      ],
      portion: '½ cawan atau 1 senduk bubur nasi pekat',
    ),
  ],
  'C': [
    (
      name: 'Bubur nasi ayam, tauhu lembut dan daun bawang',
      photo: 'meal-2-1.jpg',
      ingredients: [
        'Beras',
        'Isi ayam',
        'Tauhu lembut',
        'Daun bawang',
        'Minyak masak',
      ],
      portion: '½ cawan atau 1 senduk bubur nasi pekat',
    ),
    (
      name: 'Betik potong kecil',
      photo: 'meal-2-2.jpg',
      ingredients: ['Betik'],
      portion: '2½ sudu makan betik',
    ),
    (
      name: 'Bubur nasi ayam, kentang, brokoli dan lobak merah',
      photo: 'meal-2-3.jpg',
      ingredients: [
        'Beras',
        'Isi ayam',
        'Kentang',
        'Brokoli',
        'Lobak merah',
        'Minyak masak',
      ],
      portion: '¾ cawan atau 1½ senduk bubur nasi pekat',
    ),
    (
      name: 'Mangga potong kecil',
      photo: 'meal-2-4.jpg',
      ingredients: ['Mangga'],
      portion: '2 sudu makan mangga',
    ),
    (
      name: 'Bubur nasi ikan, bayam merah dan lobak merah',
      photo: 'meal-2-5.jpg',
      ingredients: [
        'Beras',
        'Isi ikan',
        'Bayam merah',
        'Lobak merah',
        'Minyak masak',
      ],
      portion: '1 cawan atau 2 senduk bubur nasi pekat',
    ),
  ],
  'E': [
    (
      name: 'Roti dengan telur hancur, timun dan keju',
      photo: 'meal-3-1.jpg',
      ingredients: ['Roti', 'Telur', 'Timun', 'Keju'],
      portion: '1 keping roti, ¼ biji telur, 2 hiris timun dan 1 keping keju',
    ),
    (
      name: 'Epal dan susu penuh krim',
      photo: 'meal-3-2.jpg',
      ingredients: ['Epal', 'Susu penuh krim'],
      portion: '½ biji epal dan 1 gelas susu penuh krim',
    ),
    (
      name: 'Nasi dan sup ayam dengan kentang dan lobak merah',
      photo: 'meal-3-3.jpg',
      ingredients: ['Beras', 'Isi ayam', 'Kentang', 'Lobak merah'],
      portion: '¾ cawan nasi dengan sup ayam',
    ),
    (
      name: 'Puding mangga dan tauhu bergedil',
      photo: 'meal-3-4.jpg',
      ingredients: ['Mangga', 'Tauhu bergedil'],
      portion: 'Puding daripada ¼ biji mangga dan 1 biji tauhu bergedil',
    ),
    (
      name: 'Pasta daging dengan sayur campur',
      photo: 'meal-3-5.jpg',
      ingredients: ['Pasta', 'Daging', 'Sayur campur'],
      portion: '1 cawan pasta dengan daging dan sayur campur',
    ),
    (
      name: 'Susu penuh krim',
      photo: 'meal-3-6.jpg',
      ingredients: ['Susu penuh krim'],
      portion: '1 gelas susu penuh krim',
    ),
  ],
  'H': [
    (
      name: 'Roti mentega, telur hancur, salad dan susu penuh krim',
      photo: 'meal-4-1.jpg',
      ingredients: ['Roti', 'Mentega', 'Telur', 'Salad', 'Susu penuh krim'],
      portion: '1 keping roti, ½ biji telur dan 250 ml susu penuh krim',
    ),
    (
      name: 'Cucur ikan bilis dan sayur',
      photo: 'meal-4-2.jpg',
      ingredients: ['Cucur ikan bilis dan sayur'],
      portion: '3 biji cucur ikan bilis dan sayur',
    ),
    (
      name: 'Nasi, ayam masam manis dengan tauhu, sup sayur dan pisang',
      photo: 'meal-4-3.jpg',
      ingredients: ['Beras', 'Isi ayam', 'Tauhu', 'Sup sayur', 'Pisang emas'],
      portion: '1½ senduk nasi putih dengan lauk dan sup sayur',
    ),
    (
      name: 'Bebola keledek berinti kacang merah dan minuman coklat bermalta',
      photo: 'meal-4-4.jpg',
      ingredients: ['Keledek', 'Kacang merah', 'Minuman coklat bermalta'],
      portion: '2 biji bebola keledek dan 1 gelas minuman coklat bermalta',
    ),
    (
      name: 'Mi goreng daging, sayur dan betik',
      photo: 'meal-4-5.jpg',
      ingredients: ['Mi', 'Daging', 'Sayur', 'Betik'],
      portion: '1½ senduk mi goreng dengan daging, sayur dan betik',
    ),
    (
      name: 'Bun kismis dan susu penuh krim',
      photo: 'meal-4-6.jpg',
      ingredients: ['Bun kismis', 'Susu penuh krim'],
      portion: '1 biji bun kismis dan 250 ml susu penuh krim',
    ),
  ],
};

enum _MealSlot {
  breakfast('Sarapan', Icons.wb_sunny_rounded, mealOrange),
  morningSnack('Minum pagi', Icons.local_florist_rounded, mealPurple),
  lunch('Makan tengah hari', Icons.wb_sunny_rounded, mealOrange),
  afternoonSnack('Minum petang', Icons.local_florist_rounded, mealPurple),
  dinner('Makan malam', Icons.nightlight_round, mealPurple),
  supper('Minum malam', Icons.nightlight_round, mealPurple);

  const _MealSlot(this.label, this.icon, this.color);
  final String label;
  final IconData icon;
  final Color color;
}

class _Meal {
  _Meal(this.data, this.slot, {this.photoAsset});

  final Map<String, dynamic> data;
  final _MealSlot slot;
  final String? photoAsset;

  String get id => _text(data['id']);
  String get recipeId => _text(data['recipeId']);
  String get name => _text(data['name']);
  String get portion => _text(data['portion']);
  String get time => _text(data['time']);
  String get imageUrl => _text(data['imageUrl']);
  Map<String, dynamic> get nutrition => _map(data['nutrition']);

  bool matchesRecipeServing(Recipe recipe) {
    final serving = _text(recipe.nutrition?['serving']);
    return serving.isNotEmpty &&
        (portion.isEmpty || portion.toLowerCase() == serving.toLowerCase());
  }

  double? amountFor(_Nutrient nutrient, Recipe? recipe) {
    return _quantity(nutrition[nutrient.name]) ??
        (recipe != null && matchesRecipeServing(recipe)
            ? _recipeNutrient(recipe, nutrient)
            : null);
  }

  List<String> get ingredients =>
      _list(data['ingredients'])
          .map(_text)
          .where((item) => item.isNotEmpty)
          .toList();
}

class _Recommendation {
  _Recommendation(this.data);

  final Map<String, dynamic> data;

  static _Recommendation? forDay(Object? source, int age, String day) {
    Map<String, dynamic>? ongoing;
    // Publish at most one matching recommendation per date and age band.
    for (final item in _list(source).map(_map)) {
      final min = item['minAgeMonths'];
      final max = item['maxAgeMonths'];
      if (min is! int || max is! int || age < min || age > max) continue;
      final date = item['date'];
      if (date == day) return _Recommendation(item);
      if (date == null) ongoing ??= item;
    }
    return ongoing == null ? null : _Recommendation(ongoing);
  }

  Map<String, dynamic> get targets => _map(data['targets']);
  String get advice => _text(data['advice']);

  List<_Meal> get meals {
    final ids = <String>{};
    final meals = <_Meal>[];
    for (final data in _list(this.data['meals']).map(_map)) {
      final slot = _MealSlot.values.asNameMap()[data['slot']];
      if (slot == null) continue;
      final meal = _Meal(data, slot);
      if (meal.id.isEmpty || (meal.name.isEmpty && meal.recipeId.isEmpty)) {
        continue;
      }
      if (ids.add(meal.id)) meals.add(meal);
    }
    return meals;
  }
}

/// Nutrition uses the existing users/{uid}/growth_children/{childId} document.
/// A clinician-supplied nutritionPlans array holds recommendations with inclusive
/// minAgeMonths/maxAgeMonths, optional YYYY-MM-DD date, optional Malay advice,
/// targets, and meals. Each meal has an id (stable for that serving on that
/// day), a _MealSlot name, Malay name/portion/ingredients and/or recipeId, and
/// nutrition per planned portion. Optional time and imageUrl fields provide
/// the displayed meal time and HTTPS photo URL. Nutrient maps use _Nutrient
/// names and units.
/// Daily logs are stored under the same child in nutrition_days/{YYYY-MM-DD}.
class NutritionRepository {
  Stream<Map<String, dynamic>> dayDetails(
    String owner,
    String child,
    String day,
  ) => _day(
    owner,
    child,
    day,
  ).snapshots().map((snapshot) => snapshot.data() ?? {});

  Future<void> generate(
    String child,
    String day,
    String mode, {
    String? slot,
  }) async {
    final auth = FirebaseAuth.instance;
    final token = await auth.currentUser?.getIdToken();
    if (token == null) throw const FormatException('Sila log masuk semula.');
    final project = auth.app.options.projectId;
    final response = await http
        .post(
          Uri.https(
            'asia-southeast1-$project.cloudfunctions.net',
            '/generateNutritionPlan',
          ),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'data': {'childId': child, 'day': day, 'mode': mode, 'slot': ?slot},
          }),
        )
        .timeout(const Duration(seconds: 65));
    final Map<String, dynamic> body;
    try {
      body = _map(jsonDecode(response.body));
    } on FormatException {
      throw const FormatException('Pelayan cadangan AI belum tersedia.');
    }
    if (response.statusCode != 200 || _map(body['result'])['saved'] != true) {
      throw FormatException(_text(_map(body['error'])['message']));
    }
  }

  Future<void> saveDrinks(
    String owner,
    String child,
    String day,
    int water,
    int milk,
  ) => _day(owner, child, day).set({
    'drinks': {'waterMl': water, 'milkMl': milk},
  }, SetOptions(merge: true));

  CollectionReference<Map<String, dynamic>> _children(String owner) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(owner)
          .collection('growth_children');

  DocumentReference<Map<String, dynamic>> _day(
    String owner,
    String child,
    String day,
  ) => _children(owner).doc(child).collection('nutrition_days').doc(day);

  Stream<Map<String, Map<String, dynamic>>> children(String owner) =>
      _children(owner).snapshots().map(
        (snapshot) => {for (final doc in snapshot.docs) doc.id: doc.data()},
      );

  Stream<Map<String, Recipe>> recipes() => FirebaseFirestore.instance
      .collection('recipes')
      .snapshots()
      .map(
        (snapshot) => {
          for (final doc in snapshot.docs)
            if (_text(doc.data()['name']).isNotEmpty)
              doc.id: Recipe.fromFirestore(doc),
        },
      );

  Stream<Map<String, dynamic>> intake(String owner, String child, String day) =>
      _day(
        owner,
        child,
        day,
      ).snapshots().map((snapshot) => _map(snapshot.data()?['intake']));

  Future<void> saveIntake(
    String owner,
    String child,
    String day,
    String meal,
    double fraction,
    Map<String, double?> nutrients,
  ) {
    final entry = {'fraction': fraction, 'nutrition': nutrients};
    return _day(owner, child, day).set(
      {
        'intake': {meal: entry},
        'intakeUpdatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(
        mergeFields: [
          FieldPath(['intake', meal]),
          FieldPath(['intakeUpdatedAt']),
        ],
      ),
    );
  }
}

class MealPlanPage extends StatefulWidget {
  final String ownerId;
  final String? selectedChildId;
  final NutritionRepository? repository;

  const MealPlanPage({
    super.key,
    required this.ownerId,
    this.selectedChildId,
    this.repository,
  });

  @override
  State<MealPlanPage> createState() => _MealPlanPageState();
}

class _MealPlanPageState extends State<MealPlanPage> {
  final _completedMeals = <(String, String, String, int), Set<String>>{};
  static const _tabs = ['Pelan Harian', 'Senarai Belian'];
  late final _repo = widget.repository ?? NutritionRepository();
  late Stream<Map<String, Map<String, dynamic>>> _children;
  late DateTime _today;
  Timer? _midnight;
  int _tab = 0;
  int _previewAge = 0;

  @override
  void initState() {
    super.initState();
    _today = DateUtils.dateOnly(DateTime.now());
    _children = _repo.children(widget.ownerId);
    _scheduleMidnight();
  }

  @override
  void didUpdateWidget(covariant MealPlanPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ownerId != widget.ownerId) {
      _children = _repo.children(widget.ownerId);
    }
    if (oldWidget.selectedChildId != widget.selectedChildId ||
        oldWidget.ownerId != widget.ownerId) {
      _previewAge = 0;
    }
  }

  void _scheduleMidnight() {
    final now = DateTime.now();
    final next = DateTime(now.year, now.month, now.day + 1);
    _midnight = Timer(next.difference(now), () {
      setState(() {
        _today = DateUtils.dateOnly(DateTime.now());
      });
      _scheduleMidnight();
    });
  }

  @override
  void dispose() {
    _midnight?.cancel();
    super.dispose();
  }

  Widget _childContent(bool compact) {
    return StreamBuilder(
      key: ValueKey(widget.ownerId),
      stream: _children,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _message('Maklumat anak tidak dapat dimuatkan.');
        }
        if (!snapshot.hasData) return _loading();
        final children = snapshot.data!;
        if (children.isEmpty) {
          return _message(
            'Tambah profil anak di tab Utama untuk melihat pelan makanan.',
          );
        }
        final ids = children.keys.toList()
          ..sort((a, b) {
            final order = _text(children[a]?['name'])
                .toLowerCase()
                .compareTo(_text(children[b]?['name']).toLowerCase());
            return order == 0 ? a.compareTo(b) : order;
          });
        final childId = children.containsKey(widget.selectedChildId)
            ? widget.selectedChildId!
            : ids.first;
        final child = children[childId]!;
        final age = _ageInMonths(child['birth'], _today);
        if (age == null) return _message('Tarikh lahir anak belum direkodkan.');
        if (age < 0) return _message('Tarikh ini sebelum kelahiran anak.');

        final day = _dateKey(_today);
        final key = (widget.ownerId, childId, day);
        final marksKey = (widget.ownerId, childId, day, _previewAge);
        return _NutritionDay(
          key: ValueKey(key),
          repo: _repo,
          owner: widget.ownerId,
          child: childId,
          completedMeals: _completedMeals[marksKey] ?? const <String>{},
          onMealCompleted: (meal, completed) => setState(() {
            final marks = _completedMeals.putIfAbsent(
              marksKey,
              () => <String>{},
            );
            if (completed) {
              marks.add(meal);
            } else {
              marks.remove(meal);
              if (marks.isEmpty) _completedMeals.remove(marksKey);
            }
          }),
          day: day,
          name: _text(child['name']),
          foodProfile: child,
          age: age,
          previewAge: _previewAge == 0 ? null : _previewAge,
          tab: _tab,
          compact: compact,
          recommendation: _Recommendation.forDay(
            child['nutritionPlans'],
            age,
            day,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => _buildPage(constraints.maxWidth <= 480),
  );

  Widget _buildPage(bool compact) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Container(
        color: mealOrange,
        child: Column(
          children: [
            _buildHeader(compact),
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
                child: Container(
                  color: mealPanel,
                  child: Column(
                    children: [
                      _buildControls(compact),
                      Expanded(child: _childContent(compact)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool compact) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(compact ? 12 : 16, 12, 8, 16),
        child: Row(
          children: [
            const CircleAvatar(
              radius: 24,
              backgroundColor: Colors.white,
              child: Icon(
                Icons.dinner_dining_rounded,
                color: Color(0xFF8B5100),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pelan Makanan Anak',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: compact ? 22 : 26,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Text(
                    'Lihat menu harian dan pengambilan nutrien anak anda.',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControls(bool compact) {
    return Container(
      color: Colors.white,
      padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 16, vertical: 8),
      child: Column(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 250),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: mealChip,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      value: _previewAge,
                      isExpanded: true,
                      onChanged: (value) {
                        if (value != null) setState(() => _previewAge = value);
                      },
                      items: const [
                        DropdownMenuItem(
                          value: 0,
                          child: Text('Pilih umur anak'),
                        ),
                        DropdownMenuItem(value: 6, child: Text('6–8 bulan')),
                        DropdownMenuItem(value: 9, child: Text('9–11 bulan')),
                        DropdownMenuItem(value: 12, child: Text('1–3 tahun')),
                        DropdownMenuItem(value: 48, child: Text('4–6 tahun')),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (var i = 0; i < _tabs.length; i++) ...[
                if (i > 0) SizedBox(width: compact ? 4 : 8),
                Expanded(child: _buildTab(i, compact)),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTab(int index, bool compact) {
    final selected = _tab == index;
    final label = Text(
      _tabs[index],
      textAlign: TextAlign.center,
      maxLines: compact ? 2 : 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: selected ? Colors.white : mealText,
        fontSize: 14,
        fontWeight: selected ? FontWeight.bold : FontWeight.w600,
      ),
    );
    return Material(
      color: selected ? mealAmber : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() => _tab = index),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: 44,
            maxHeight: compact ? double.infinity : 44,
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: compact
                  ? label
                  : FittedBox(fit: BoxFit.scaleDown, child: label),
            ),
          ),
        ),
      ),
    );
  }
}

Widget _loading() => const Center(
  child: CircularProgressIndicator(
    color: mealOrange,
    semanticsLabel: 'Sedang memuatkan maklumat',
  ),
);

Widget _message(String message) => Center(
  child: Padding(
    padding: const EdgeInsets.all(16),
    child: Text(
      message,
      textAlign: TextAlign.center,
      style: const TextStyle(color: mealMuted),
    ),
  ),
);

BoxDecoration _cardDecoration() => BoxDecoration(
  color: Colors.white,
  borderRadius: BorderRadius.circular(18),
  boxShadow: [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.05),
      blurRadius: 10,
      offset: const Offset(0, 3),
    ),
  ],
);

class _NutritionDay extends StatefulWidget {
  const _NutritionDay({
    super.key,
    required this.repo,
    required this.owner,
    required this.child,
    required this.completedMeals,
    required this.onMealCompleted,
    required this.day,
    required this.name,
    required this.foodProfile,
    required this.age,
    required this.previewAge,
    required this.tab,
    required this.compact,
    required this.recommendation,
  });

  final NutritionRepository repo;
  final String owner;
  final String child;
  final Set<String> completedMeals;
  final void Function(String, bool) onMealCompleted;
  final String day;
  final String name;
  final Map<String, dynamic> foodProfile;
  final int age;
  final int? previewAge;
  final int tab;
  final bool compact;
  final _Recommendation? recommendation;

  @override
  State<_NutritionDay> createState() => _NutritionDayState();
}

class _NutritionDayState extends State<_NutritionDay> {
  EdgeInsets get _contentPadding =>
      widget.compact ? _phoneListPadding : _listPadding;
  static final _portions = Map<double, String>.unmodifiable({
    0.0: 'Tidak dimakan',
    0.25: '¼ hidangan',
    0.5: '½ hidangan',
    0.75: '¾ hidangan',
    1.0: '1 hidangan',
  });

  late final _intake = widget.repo.intake(
    widget.owner,
    widget.child,
    widget.day,
  );
  late final _recipes = widget.repo.recipes();
  late final _details = widget.repo.dayDetails(
    widget.owner,
    widget.child,
    widget.day,
  );
  bool _requestingAi = false;

  void _notice(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _requestAi(String mode, {String? slot}) async {
    if (_requestingAi) return;
    setState(() => _requestingAi = true);
    try {
      await widget.repo.generate(widget.child, widget.day, mode, slot: slot);
    } on FormatException catch (error) {
      _notice(
        error.message.isEmpty
            ? 'Permintaan AI tidak dapat diselesaikan.'
            : error.message,
      );
    } catch (_) {
      _notice('AI tidak dapat dihubungi. Cuba lagi.');
    } finally {
      if (mounted) setState(() => _requestingAi = false);
    }
  }

  final _bought = <String>{};
  final _saving = <String>{};
  String? _nutrientRecipeId;
  double _previewPortion = 1;

  void _selectNutrientRecipe(String id) {
    setState(() {
      _nutrientRecipeId = id;
      _previewPortion = 1;
    });
  }

  Future<void> _record(_Meal meal, Recipe? recipe, double fraction) async {
    setState(() => _saving.add(meal.id));
    try {
      await widget.repo.saveIntake(
        widget.owner,
        widget.child,
        widget.day,
        meal.id,
        fraction,
        {
          for (final nutrient in _Nutrient.values)
            nutrient.name: fraction == 0
                ? 0
                : _scale(meal.amountFor(nutrient, recipe), fraction),
        },
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pengambilan tidak dapat disimpan. Cuba lagi.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving.remove(meal.id));
    }
  }

  double? _scale(double? amount, double fraction) =>
      amount == null ? null : amount * fraction;

  @override
  Widget build(BuildContext context) => StreamBuilder(
    stream: _details,
    builder: (context, details) => _buildDay(details.data ?? const {}),
  );

  Widget _buildDay(Map<String, dynamic> details) {
    final generated = _map(details['generatedPlan']);
    final usingAi =
        widget.recommendation == null &&
        generated.isNotEmpty &&
        widget.foodProfile['foodAllergies'] is List &&
        listEquals(_list(generated['allergySnapshot']), _allergySnapshot);
    final meals =
        (widget.recommendation ?? (usingAi ? _Recommendation(generated) : null))
            ?.meals ??
        const <_Meal>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(
            '${widget.name.isEmpty ? 'Anak' : widget.name} · ${_ageLabel(widget.age)}',
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: mealMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder(
            stream: _intake,
            builder: (context, intake) {
              if ((widget.tab == 1 || widget.previewAge != null) &&
                  meals.every((meal) => meal.recipeId.isEmpty)) {
                return _buildTab(meals, intake, const {}, usingAi);
              }
              return StreamBuilder(
                stream: _recipes,
                builder: (context, recipes) {
                  if (!usingAi &&
                      widget.previewAge == null &&
                      meals.any((meal) => meal.recipeId.isNotEmpty) &&
                      !recipes.hasData &&
                      !recipes.hasError) {
                    return _loading();
                  }
                  return _buildTab(
                    meals,
                    intake,
                    recipes.data ?? const {},
                    usingAi,
                    recipeStatus: recipes.hasError
                        ? 'Resipi tidak dapat dimuatkan.'
                        : !recipes.hasData
                        ? 'Sedang memuatkan resipi.'
                        : null,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  List<String> get _allergySnapshot =>
      _list(widget.foodProfile['foodAllergies'])
          .map((tag) => _text(tag).toLowerCase())
          .toList()
        ..sort();

  String _ageLabel(int age) {
    if (age < 12) return '$age bulan';
    return '${age ~/ 12} tahun ${age % 12} bulan';
  }

  Widget _buildTab(
    List<_Meal> meals,
    AsyncSnapshot<Map<String, dynamic>> intake,
    Map<String, Recipe> recipes,
    bool usingAi, {
    String? recipeStatus,
  }) {
    final preview = widget.previewAge == null
        ? null
        : _referenceMenu(widget.previewAge!);
    if (preview != null && widget.tab == 0) {
      return _referencePlan(
        preview.label,
        preview.pages,
        previewOnly: true,
        nutrients: _nutrientIntake(
          const AsyncSnapshot.withData(ConnectionState.active, {}),
          const {},
          null,
          _referenceMeals(preview.pages.first),
        ),
      );
    }
    if (widget.tab == 1) {
      final reference =
          preview ?? (meals.isEmpty ? _referenceMenu(widget.age) : null);
      return _shopping(
        reference == null ? meals : _referenceMeals(reference.pages.first),
        recipes,
        referenceLabel: reference?.label,
      );
    }

    if (meals.isEmpty) {
      final advice = widget.recommendation?.advice ?? '';
      final message = advice.isEmpty
          ? 'Tiada pelan makanan daripada doktor untuk umur dan tarikh ini.'
          : advice;
      final reference = _referenceMenu(widget.age);
      if (widget.tab == 0 && reference != null) {
        return _referencePlan(
          reference.label,
          reference.pages,
          nutrients: _nutrientIntake(
            intake,
            recipes,
            recipeStatus,
            _referenceMeals(reference.pages.first),
          ),
        );
      }
      if (widget.tab == 0 && widget.age < 6 && advice.isEmpty) {
        return ListView(
          padding: _contentPadding,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: _cardDecoration(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Bayi bawah 6 bulan',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Panduan KKM menggalakkan penyusuan susu ibu secara eksklusif sehingga umur 6 bulan. Contoh menu makanan pelengkap dalam rujukan bermula pada umur 6 bulan.',
                  ),
                ],
              ),
            ),
          ],
        );
      }
      return _message(message);
    }
    return _dailyPlan(
      meals,
      recipes,
      intake,
      usingAi,
      _nutrientIntake(intake, recipes, recipeStatus, meals),
    );
  }

  List<_Meal> _referenceMeals(String page) => [
    for (final (index, dish) in _referenceDishes[page]!.indexed)
      _Meal(
        {
          'id': 'kkm-$page-${_MealSlot.values[index].name}',
          'name': dish.name,
          'portion': dish.portion,
          'ingredients': dish.ingredients,
        },
        _MealSlot.values[index],
        photoAsset: dish.photo,
      ),
  ];

  Widget _referencePlan(
    String label,
    List<String> pages, {
    bool previewOnly = false,
    Widget? nutrients,
  }) {
    final message = 'Pratonton menu rujukan KKM · $label';
    final meals = _referenceMeals(pages.first);
    return ListView(
      padding: _contentPadding,
      children: [
        if (previewOnly)
          Text(message, style: const TextStyle(color: mealMuted)),
        for (final meal in meals) _mealCard(meal, null, null),
        ?nutrients,
        if (previewOnly)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (context) => Dialog.fullscreen(
                  child: Scaffold(
                    appBar: AppBar(
                      automaticallyImplyLeading: false,
                      leading: IconButton(
                        tooltip: 'Tutup rujukan',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                      ),
                      title: const Text('Ilustrasi Rujukan'),
                    ),
                    body: _referencePages(message, label, pages),
                  ),
                ),
              ),
              icon: const Icon(Icons.menu_book_outlined),
              label: const Text('Lihat ilustrasi dan sukatan asal'),
            ),
          ),
      ],
    );
  }

  Widget _referencePages(String message, String label, List<String> pages) {
    return ListView.builder(
      padding: _contentPadding,
      itemCount: pages.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message, style: const TextStyle(color: mealMuted)),
              const SizedBox(height: 12),
              Text(
                'Contoh Menu Mengikut Umur',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(label),
              const Text('Ketik ilustrasi untuk zum.'),
              const SizedBox(height: 12),
            ],
          );
        }
        final path = 'assets/nutrition_reference/${pages[index - 1]}.png';
        final pageLabel =
            'Ilustrasi menu, halaman $index daripada ${pages.length}';
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => showDialog<void>(
                context: context,
                builder: (context) => Dialog.fullscreen(
                  child: Scaffold(
                    appBar: AppBar(
                      automaticallyImplyLeading: false,
                      leading: IconButton(
                        tooltip: 'Tutup',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                      ),
                      title: Text('Ilustrasi menu $index'),
                    ),
                    body: Center(
                      child: InteractiveViewer(
                        maxScale: 5,
                        child: Image.asset(path, semanticLabel: pageLabel),
                      ),
                    ),
                  ),
                ),
              ),
              child: AspectRatio(
                aspectRatio: 1414 / 2000,
                child: Image.asset(path, semanticLabel: pageLabel),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _dailyPlan(
    List<_Meal> meals,
    Map<String, Recipe> recipes,
    AsyncSnapshot<Map<String, dynamic>> intake,
    bool usingAi,
    Widget nutrients,
  ) {
    final advice = widget.recommendation?.advice ?? '';
    return ListView(
      key: const PageStorageKey('pelan-harian'),
      padding: _contentPadding,
      children: [
        if (advice.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(advice, style: const TextStyle(color: mealText)),
          ),
        for (final meal in meals)
          _mealCard(
            meal,
            recipes[meal.recipeId],
            intake.hasError ? null : intake.data,
            usingAi: usingAi,
          ),
        nutrients,
      ],
    );
  }

  Widget _mealCard(
    _Meal meal,
    Recipe? recipe,
    Map<String, dynamic>? intake, {
    bool usingAi = false,
  }) {
    final calories = _quantity(meal.nutrition[_Nutrient.energy.name]);
    final recipeServing = _text(recipe?.nutrition?['serving']);
    final recipeEnergy = recipe?.nutrition?[_Nutrient.energy.name];
    final recipeLabel = recipeEnergy is num && _quantity(recipeEnergy) != null
        ? '${_number(recipeEnergy.toDouble())} kcal'
        : _text(recipeEnergy);
    final hasRecipeEstimate =
        recipe != null &&
        meal.matchesRecipeServing(recipe) &&
        _recipeEnergyLabel.hasMatch(recipeLabel);
    final recorded = _quantity(_map(intake?[meal.id])['fraction']);
    final compact = widget.compact;
    final completed = widget.completedMeals.contains(meal.id);
    void markCompleted(bool value) {
      _selectNutrientRecipe('');
      widget.onMealCompleted(meal.id, value);
    }

    final DropdownButton<double> portionPicker = DropdownButton<double>(
      isExpanded: compact,
      value: _portions.containsKey(recorded) ? recorded : null,
      hint: const Text('Catat'),
      items: [
        for (final portion in _portions.entries)
          DropdownMenuItem(
            value: portion.key,
            child: Text(portion.value, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: _saving.contains(meal.id)
          ? null
          : (value) {
              if (value != null) _record(meal, recipe, value);
            },
    );
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFDDE2EB))),
      ),
      child: Material(
        color: completed ? const Color(0xFFE9DECD) : Colors.transparent,
        child: InkWell(
          onTap: () => markCompleted(!completed),
          hoverColor: mealOrange.withValues(alpha: 0.10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(meal.slot.icon, color: meal.slot.color, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        meal.time.isEmpty
                            ? meal.slot.label
                            : '${meal.slot.label} (${meal.time})',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Tooltip(
                      message: '${meal.slot.label} selesai',
                      child: Checkbox(
                        value: completed,
                        activeColor: mealOrange,
                        onChanged: (value) => markCompleted(value == true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Flexible(
                      flex: 4,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 158),
                        child: _mealPhoto(meal, recipe),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 5,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            meal.name.isEmpty
                                ? recipe?.name ?? 'Resipi tidak tersedia'
                                : meal.name,
                            style: const TextStyle(
                              color: mealText,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (meal.portion.isNotEmpty) Text(meal.portion),
                          Text(
                            calories != null
                                ? '${_number(calories)} kcal bagi hidangan ini'
                                : hasRecipeEstimate
                                ? 'Anggaran resipi: $recipeLabel bagi $recipeServing'
                                : 'Kalori belum tersedia',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          for (final nutrient in _Nutrient.values)
                            if (nutrient != _Nutrient.energy)
                              if (meal.amountFor(nutrient, recipe)
                                  case final amount?)
                                Text(
                                  '• ${nutrient.label} ${_number(amount)} ${nutrient.unit}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (usingAi) ...[
                  if (_text(meal.data['benefits']).isNotEmpty)
                    Text(_text(meal.data['benefits'])),
                  Text(
                    _text(meal.data['reason']),
                    style: const TextStyle(color: mealMuted),
                  ),
                  Wrap(
                    children: [
                      TextButton(
                        onPressed: () => showDialog<void>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: Text(meal.name),
                            content: SingleChildScrollView(
                              child: Text(
                                _list(meal.data['steps'])
                                    .map(_text)
                                    .join('\n\n'),
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Tutup'),
                              ),
                            ],
                          ),
                        ),
                        child: const Text('Lihat Resipi'),
                      ),
                      TextButton(
                        onPressed: _requestingAi
                            ? null
                            : () => _requestAi('replace', slot: meal.slot.name),
                        child: const Text('Tukar Menu'),
                      ),
                    ],
                  ),
                ],
                if (intake != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          usingAi ? 'Rekod Pengambilan' : 'Jumlah dimakan',
                        ),
                      ),
                      if (compact)
                        Expanded(child: portionPicker)
                      else
                        portionPicker,
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _mealPhoto(_Meal meal, Recipe? recipe) {
    final asset = meal.photoAsset;
    final url = Uri.tryParse(meal.imageUrl);
    final fallback = ColoredBox(
      color: recipe?.color ?? const Color(0xFFFFF1D6),
      child: Center(
        child: Icon(Icons.restaurant_rounded, color: meal.slot.color, size: 32),
      ),
    );
    final Widget photo;
    if (asset != null) {
      photo = Image.asset('assets/nutrition_meals/$asset', fit: BoxFit.cover);
    } else if (url != null && url.scheme == 'https' && url.host.isNotEmpty) {
      photo = Image.network(
        meal.imageUrl,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stack) => fallback,
      );
    } else {
      photo = fallback;
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: AspectRatio(aspectRatio: 1.42, child: photo),
    );
  }

  Widget _nutrientIntake(
    AsyncSnapshot<Map<String, dynamic>> intake,
    Map<String, Recipe> recipes,
    String? recipeStatus,
    List<_Meal> meals,
  ) {
    final targets = widget.previewAge == null
        ? widget.recommendation?.targets ?? const {}
        : const <String, dynamic>{};
    final error = intake.error;
    final denied =
        error is FirebaseException && error.code == 'permission-denied';
    final records =
        (intake.hasError
                ? const <String, dynamic>{}
                : intake.data ?? const <String, dynamic>{})
            .map((id, entry) => MapEntry(id, _map(entry)));
    final mealsById = {for (final meal in meals) meal.id: meal};
    double? recordedAmount(
      String id,
      Map<String, dynamic> record,
      _Nutrient nutrient,
      double fraction,
    ) {
      final saved = _quantity(_map(record['nutrition'])[nutrient.name]);
      if (saved != null) return saved;
      if (fraction == 0) return 0;
      final meal = mealsById[id];
      final recipe = meal == null ? null : recipes[meal.recipeId];
      return meal != null && recipe != null && meal.matchesRecipeServing(recipe)
          ? _scale(_recipeNutrient(recipe, nutrient), fraction)
          : null;
    }

    final entries = <String, Map<String, dynamic>>{
      for (final meal in meals)
        if (widget.completedMeals.contains(meal.id))
          meal.id: {
            for (final nutrient in _Nutrient.values)
              nutrient.name: meal.amountFor(nutrient, recipes[meal.recipeId]),
          },
      for (final record in records.entries)
        if (_quantity(record.value['fraction']) case final fraction?)
          record.key: {
            for (final nutrient in _Nutrient.values)
              nutrient.name: recordedAmount(
                record.key,
                record.value,
                nutrient,
                fraction,
              ),
          },
    };
    final needs = <_Nutrient, double>{};
    var hasTargets = false;
    ({double? target, double? consumed, bool incomplete, double? progress})
    totals(_Nutrient nutrient) {
      final target = _quantity(targets[nutrient.name]);
      final amounts = entries.values
          .map((entry) => _quantity(entry[nutrient.name]))
          .toList();
      final known = amounts.whereType<double>();
      final consumed = known.isEmpty
          ? null
          : known.fold(0.0, (total, value) => total + value);
      final incomplete = known.length != amounts.length;
      final progress =
          target != null && target > 0 && consumed != null && !incomplete
          ? consumed / target
          : null;
      if (target != null && target > 0) {
        hasTargets = true;
        final remaining = progress == null ? target : target - consumed!;
        if (remaining > 0) needs[nutrient] = remaining;
      }
      return (
        target: target,
        consumed: consumed,
        incomplete: incomplete,
        progress: progress,
      );
    }

    final stats = {
      for (final nutrient in _Nutrient.values) nutrient: totals(nutrient),
    };
    final matches = recipeStatus == null
        ? _findRecipeMatches(recipes, needs, hasTargets)
        : const <({Recipe recipe, double score})>[];
    final previewRecipes = {
      for (final match in matches) match.recipe.id: match.recipe,
    };
    final firstWithServing = previewRecipes.values
        .where((recipe) => _text(recipe.nutrition?['serving']).isNotEmpty)
        .firstOrNull;
    final previewRecipe = _nutrientRecipeId == null && entries.isEmpty
        ? firstWithServing
        : previewRecipes[_nutrientRecipeId];
    final serving = _text(previewRecipe?.nutrition?['serving']);

    Widget tile(_Nutrient nutrient) {
      final (:target, :consumed, :incomplete, :progress) = stats[nutrient]!;
      final estimate = previewRecipe == null || serving.isEmpty
          ? null
          : _recipeNutrient(previewRecipe, nutrient);
      final amount = previewRecipe == null
          ? consumed
          : _scale(estimate, _previewPortion);
      return Expanded(
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: _cardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(nutrient.icon, color: mealOrange, size: 24),
              const SizedBox(height: 10),
              Text(nutrient.label, style: const TextStyle(color: mealMuted)),
              Text(
                amount == null ? '—' : '${_number(amount)} ${nutrient.unit}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (previewRecipe != null)
                Text(
                  amount == null
                      ? serving.isEmpty
                            ? 'Sukatan asal belum tersedia'
                            : 'Tiada data dalam resipi'
                      : 'Anggaran bagi bahagian dipilih',
                )
              else
                Text(
                  target == null
                      ? 'Tiada sasaran'
                      : 'Sasaran ${_number(target)} ${nutrient.unit}',
                ),
              if (previewRecipe == null && incomplete)
                const Text('Data tidak lengkap'),
              if (previewRecipe == null && progress != null) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: progress.clamp(0.0, 1.0),
                  color: mealOrange,
                  semanticsLabel: 'Kemajuan ${nutrient.label}',
                ),
                Text('${_number(progress * 100)}%'),
              ],
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20),
        Text(
          'Pengambilan Nutrien',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (meals.any(
          (meal) =>
              widget.completedMeals.contains(meal.id) &&
              _quantity(records[meal.id]?['fraction']) == null,
        ))
          const Text('Hidangan bertanda dikira sebagai satu hidangan.'),
        if (!denied)
          Text(
            intake.hasError
                ? 'Rekod pengambilan tidak dapat dimuatkan.'
                : !intake.hasData
                ? 'Sedang memuatkan rekod pengambilan.'
                : entries.isEmpty
                ? 'Belum ada rekod pengambilan.'
                : 'Berdasarkan ${entries.length} catatan pengambilan.',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        const SizedBox(height: 12),
        if (previewRecipes.isNotEmpty) ...[
          const Text('Paparan Nutrien'),
          DropdownButton<String>(
            value: previewRecipe?.id ?? '',
            isExpanded: true,
            onChanged: (id) {
              if (id != null) _selectNutrientRecipe(id);
            },
            items: [
              const DropdownMenuItem(
                value: '',
                child: Text('Rekod makanan dimakan'),
              ),
              for (final recipe in previewRecipes.values)
                DropdownMenuItem(
                  value: recipe.id,
                  child: Text(
                    'Anggaran: ${recipe.name}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
          if (previewRecipe != null && serving.isNotEmpty) ...[
            Text('Sukatan asal: $serving'),
            DropdownButton<double>(
              isExpanded: widget.compact,
              value: _previewPortion,
              onChanged: (value) {
                if (value != null) setState(() => _previewPortion = value);
              },
              items: [
                for (final portion in _portions.entries)
                  if (portion.key > 0)
                    DropdownMenuItem(
                      value: portion.key,
                      child: Text(portion.value),
                    ),
              ],
            ),
          ],
          const SizedBox(height: 12),
        ] else if (widget.age >= 6 && recipeStatus != null) ...[
          Text(recipeStatus, style: const TextStyle(color: mealMuted)),
          const SizedBox(height: 12),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            tile(_Nutrient.energy),
            const SizedBox(width: 12),
            tile(_Nutrient.protein),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            tile(_Nutrient.calcium),
            const SizedBox(width: 12),
            tile(_Nutrient.iron),
          ],
        ),
      ],
    );
  }

  List<({Recipe recipe, double score})> _findRecipeMatches(
    Map<String, Recipe> recipes,
    Map<_Nutrient, double> needs,
    bool hasTargets,
  ) {
    if (widget.age < 6 ||
        _allergySnapshot.isNotEmpty ||
        (hasTargets && needs.isEmpty)) {
      return const [];
    }
    final nutrients = hasTargets ? needs.keys : _Nutrient.values;
    final matches = <({Recipe recipe, double score})>[];
    for (final recipe in recipes.values) {
      if (!_recipeFitsAge(recipe, widget.age)) continue;
      var score = 0.0;
      for (final nutrient in nutrients) {
        final amount = _recipeNutrient(recipe, nutrient);
        if (amount == null || amount <= 0) continue;
        final remaining = needs[nutrient];
        score += remaining == null ? 1 : (amount / remaining).clamp(0, 1);
      }
      if (score > 0) {
        matches.add((recipe: recipe, score: score));
      }
    }
    matches.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      return byScore == 0 ? a.recipe.name.compareTo(b.recipe.name) : byScore;
    });

    return matches.take(5).toList();
  }

  Widget _shopping(
    List<_Meal> meals,
    Map<String, Recipe> recipes, {
    String? referenceLabel,
  }) {
    final items = <String, String>{};
    final grouped =
        <String, Map<(String, String), ({String name, double? amount})>>{};
    var missing = false;
    for (final meal in meals) {
      final structured = _list(meal.data['shopping'])
          .map(_map)
          .where((item) => _text(item['name']).isNotEmpty)
          .toList();
      if (structured.isNotEmpty) {
        for (final item in structured) {
          final group = _text(item['group']);
          final name = _text(item['name']);
          final rawUnit = _text(item['unit']).toLowerCase();
          final rawAmount = _quantity(item['quantity']);
          final (unit, multiplier) = switch (rawUnit) {
            'kg' => ('g', 1000.0),
            'mg' => ('g', 0.001),
            'l' => ('ml', 1000.0),
            _ => (rawUnit, 1.0),
          };
          final amount = _scale(rawAmount, multiplier);
          final key = (name.toLowerCase(), amount == null ? '' : unit);
          final bucket = grouped.putIfAbsent(group, () => {});
          bucket[key] = (
            name: name,
            amount: amount == null ? null : (bucket[key]?.amount ?? 0) + amount,
          );
        }
        continue;
      }
      final ingredients = meal.ingredients.isNotEmpty
          ? meal.ingredients
          : recipes[meal.recipeId]?.ingredients ?? const <String>[];
      final names = ingredients
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty);
      missing = missing || names.isEmpty;
      for (final item in names) {
        items.putIfAbsent(item.toLowerCase(), () => item);
      }
    }

    final hasIngredients = items.isNotEmpty || grouped.isNotEmpty;
    return ListView(
      key: const PageStorageKey('senarai-belian'),
      padding: _contentPadding,
      children: [
        if (referenceLabel != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'Bahan menu rujukan KKM · ${referenceLabel.split(' · ').first}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        if (!hasIngredients)
          const Text(
            'Tiada bahan direkodkan untuk pelan ini.',
            style: TextStyle(color: mealMuted),
          ),
        if (hasIngredients)
          Container(
            decoration: _cardDecoration(),
            child: Material(
              type: MaterialType.transparency,
              borderRadius: BorderRadius.circular(18),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (final group in grouped.entries) ...[
                    ListTile(
                      title: Text(
                        group.key,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    for (final item in group.value.entries)
                      _shoppingCheckbox(
                        '${group.key}/${item.key}/${item.value.amount}',
                        item.value.amount == null
                            ? item.value.name
                            : '${item.value.name} · ${_number(item.value.amount!)} ${item.key.$2}',
                      ),
                  ],
                  for (final item in items.entries)
                    _shoppingCheckbox(
                      referenceLabel == null
                          ? item.key
                          : '$referenceLabel/${item.key}',
                      item.value,
                    ),
                ],
              ),
            ),
          ),
        if (hasIngredients && missing)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text('Senarai bahan belum lengkap untuk semua hidangan.'),
          ),
      ],
    );
  }

  Widget _shoppingCheckbox(String key, String name) => CheckboxListTile(
    activeColor: mealOrange,
    controlAffinity: ListTileControlAffinity.leading,
    value: _bought.contains(key),
    onChanged: (checked) => setState(() {
      if (checked == true) {
        _bought.add(key);
      } else {
        _bought.remove(key);
      }
    }),
    title: Text(
      name,
      style: TextStyle(
        color: mealText,
        fontWeight: FontWeight.w600,
        decoration: _bought.contains(key) ? TextDecoration.lineThrough : null,
      ),
    ),
  );
}
