import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sicilik/nutrition.dart';
import 'package:sicilik/recipe.dart';

String dateKey(DateTime date) => date.toIso8601String().split('T').first;

class TestNutritionRepository extends NutritionRepository {
  final updates = StreamController<Map<String, Map<String, dynamic>>>();
  final recipeUpdates = StreamController<Map<String, Recipe>>.broadcast();
  final records = <(String, String), Map<String, dynamic>>{};
  final intakeUpdates = StreamController<(String, String)>.broadcast();
  final visits = <(String, String)>[];
  final details = <String, Map<String, dynamic>>{};
  final detailsUpdates = StreamController<String>.broadcast();
  Future<void> Function(String child, String day, String mode, String? slot)?
  onGenerate;

  @override
  Stream<Map<String, dynamic>> dayDetails(
    String owner,
    String child,
    String day,
  ) async* {
    yield details[day] ?? {};
    yield* detailsUpdates.stream
        .where((updated) => updated == day)
        .map((_) => details[day] ?? {});
  }

  @override
  Future<void> generate(
    String child,
    String day,
    String mode, {
    String? slot,
  }) async {
    await onGenerate?.call(child, day, mode, slot);
  }

  @override
  Future<void> saveDrinks(
    String owner,
    String child,
    String day,
    int water,
    int milk,
  ) async {
    (details[day] ??= {})['drinks'] = {'waterMl': water, 'milkMl': milk};
    detailsUpdates.add(day);
  }

  @override
  Stream<Map<String, Map<String, dynamic>>> children(String owner) =>
      updates.stream;

  @override
  Stream<Map<String, Recipe>> recipes() => recipeUpdates.stream;

  @override
  Stream<Map<String, dynamic>> intake(
    String owner,
    String child,
    String day,
  ) async* {
    final key = (child, day);
    visits.add(key);
    yield records[key] ?? {};
    yield* intakeUpdates.stream
        .where((updated) => updated == key)
        .map((_) => records[key] ?? {});
  }

  @override
  Future<void> saveIntake(
    String owner,
    String child,
    String day,
    String meal,
    double fraction,
    Map<String, double?> nutrients,
  ) async {
    final key = (child, day);
    (records[key] ??= {})[meal] = {
      'fraction': fraction,
      'nutrition': nutrients,
    };
    intakeUpdates.add(key);
  }

  void close() {
    unawaited(updates.close());
    unawaited(recipeUpdates.close());
    unawaited(intakeUpdates.close());
    unawaited(detailsUpdates.close());
  }
}

Map<String, dynamic> recommendation(
  int min,
  int max,
  String name,
  String ingredient,
  int target, {
  String? date,
  String? recipeId,
  int? energy = 200,
}) => {
  'minAgeMonths': min,
  'maxAgeMonths': max,
  'date': ?date,
  'targets': {'energy': target},
  'meals': [
    {
      'id': 'meal-1',
      'slot': 'breakfast',
      'name': name,
      'portion': '1 mangkuk',
      'ingredients': [if (ingredient.isNotEmpty) ingredient],
      'recipeId': ?recipeId,
      'nutrition': {'energy': ?energy, 'protein': 10},
    },
  ],
};

void main() {
  testWidgets('child aged 49 months can replace meals, log and shop', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = TestNutritionRepository();
    addTearDown(repo.close);
    final now = DateTime.now();
    final day = dateKey(now);
    const slots = [
      'breakfast',
      'morningSnack',
      'lunch',
      'afternoonSnack',
      'dinner',
      'supper',
    ];
    Map<String, Object?> meal(String slot, {bool replacement = false}) => {
      'id': replacement ? 'changed' : slot,
      'slot': slot,
      'name': replacement ? 'Hidangan ganti' : 'Hidangan $slot',
      'portion': '1 hidangan',
      'ingredients': [replacement ? 'Oat' : 'Beras'],
      'shopping': [
        {
          'name': replacement ? 'Oat' : 'Beras',
          'group': 'Karbohidrat',
          'quantity': 50,
          'unit': 'g',
        },
      ],
      'nutrition': {'energy': 100, 'protein': 8, 'calcium': 40, 'iron': 2},
      'steps': ['Langkah ujian'],
    };
    repo.onGenerate = (child, date, mode, slot) async {
      expect(child, 'child');
      expect(date, day);
      repo.details[date] = {
        'generatedPlan': {
          'allergySnapshot': <String>[],
          'meals': [
            for (final period in slots)
              meal(period, replacement: mode == 'replace' && period == slot),
          ],
        },
      };
      repo.detailsUpdates.add(date);
    };
    await repo.generate('child', day, 'generate');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MealPlanPage(ownerId: 'owner', repository: repo),
        ),
      ),
    );
    repo.updates.add({
      'child': {
        'name': 'Anak ujian',
        'birth': dateKey(DateTime(now.year - 4, now.month - 1, 1)),
        'foodAllergies': <String>[],
      },
    });
    await tester.pumpAndSettle();
    expect(find.text('Anak ujian · 4 tahun 1 bulan'), findsOneWidget);
    expect(find.text('Jana Pelan Makanan AI'), findsNothing);
    await tester.tap(find.text('Senarai Belian'));
    await tester.pumpAndSettle();
    expect(find.text('Cadangan Makanan AI'), findsNothing);
    expect(find.text('Beras · 300 g'), findsOneWidget);
    await tester.tap(find.text('Pelan Harian'));
    await tester.pumpAndSettle();
    expect(find.text('Jana Semula'), findsNothing);
    expect(find.text('Hidangan breakfast'), findsOneWidget);
    await tester.tap(find.text('Tukar Menu').first);
    await tester.pumpAndSettle();
    expect(find.text('Hidangan ganti'), findsOneWidget);
    expect(find.text('Hidangan morningSnack'), findsOneWidget);
    final breakfast = find.byTooltip('Sarapan selesai');
    await tester.ensureVisible(breakfast);
    await tester.pumpAndSettle();
    await tester.tap(breakfast);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Pengambilan Nutrien'), 180);
    await tester.pumpAndSettle();
    for (final amount in ['100 kcal', '8 g', '40 mg', '2 mg']) {
      expect(find.text(amount), findsOneWidget);
    }
    expect(repo.records, isEmpty);
    await tester.scrollUntilVisible(breakfast, -180);
    await tester.pumpAndSettle();
    await tester.tap(breakfast);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Pengambilan Nutrien'), 180);
    await tester.pumpAndSettle();
    expect(find.text('100 kcal'), findsNothing);
    await tester.scrollUntilVisible(breakfast, -180);
    await tester.pumpAndSettle();
    final dropdown = find.byType(DropdownButton<double>).first;
    await tester.ensureVisible(dropdown);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('½ hidangan').last);
    await tester.pumpAndSettle();
    expect(repo.records[('child', day)]?['changed']['nutrition']['iron'], 1);
    await tester.scrollUntilVisible(find.text('Pengambilan Nutrien'), 160);
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    expect(find.text('50 kcal'), findsOneWidget);
    for (final label in [
      'Padanan Resipi',
      'Anggaran Pelan Harian',
      'Ringkasan Kumpulan Makanan',
      'Rekod Pengambilan Air dan Susu',
    ]) {
      expect(find.text(label), findsNothing);
    }
    await tester.tap(find.text('Senarai Belian'));
    await tester.pumpAndSettle();
    expect(find.text('Karbohidrat'), findsOneWidget);
    expect(find.text('Oat · 50 g'), findsOneWidget);
    expect(find.text('Beras · 250 g'), findsOneWidget);
    expect(find.byIcon(Icons.calendar_today_outlined), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'reference menu changes when the selected child reaches six months',
    (tester) async {
      final repo = TestNutritionRepository();
      addTearDown(repo.close);
      final today = DateTime.now();

      Future<void> select(String id) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MealPlanPage(
                ownerId: 'owner',
                selectedChildId: id,
                repository: repo,
              ),
            ),
          ),
        );
      }

      await select('younger');
      repo.updates.add({
        'younger': {'birth': dateKey(DateTime(today.year, today.month - 5, 1))},
        'older': {'birth': dateKey(DateTime(today.year, today.month - 6, 1))},
      });
      await tester.pumpAndSettle();
      expect(find.text('Bayi bawah 6 bulan'), findsOneWidget);
      expect(find.text('Bubur nasi ayam dan bayam'), findsNothing);

      await select('older');
      await tester.pumpAndSettle();
      expect(find.text('Bubur nasi ayam dan bayam'), findsOneWidget);
      expect(find.text('½ cawan atau 1 senduk bubur nasi pekat'), findsWidgets);
      expect(find.text('Bayi bawah 6 bulan'), findsNothing);
      final breakfast = find.byTooltip('Sarapan selesai');
      Finder checkbox() =>
          find.descendant(of: breakfast, matching: find.byType(Checkbox));
      expect(tester.widget<Checkbox>(checkbox()).value, isFalse);
      await tester.tap(find.text('Bubur nasi ayam dan bayam'));
      await tester.pumpAndSettle();
      expect(tester.widget<Checkbox>(checkbox()).value, isTrue);
      expect(
        find.ancestor(
          of: breakfast,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Material && widget.color == const Color(0xFFE9DECD),
          ),
        ),
        findsOneWidget,
      );
      expect(repo.records, isEmpty);
      await tester.tap(breakfast);
      await tester.pumpAndSettle();
      expect(tester.widget<Checkbox>(checkbox()).value, isFalse);
      await tester.tap(find.byType(DropdownButton<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('4–6 tahun').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('Pratonton menu rujukan KKM'), findsOneWidget);
      expect(
        find.text('Roti mentega, telur hancur, salad dan susu penuh krim'),
        findsOneWidget,
      );
      expect(tester.widget<Checkbox>(checkbox()).value, isFalse);
      await tester.tap(breakfast);
      await tester.pumpAndSettle();
      expect(tester.widget<Checkbox>(checkbox()).value, isTrue);
      await tester.scrollUntilVisible(find.text('Pengambilan Nutrien'), 200);
      await tester.pumpAndSettle();
      expect(find.text('Berdasarkan 1 catatan pengambilan.'), findsOneWidget);
      expect(find.text('Data tidak lengkap'), findsNWidgets(4));
      expect(repo.records, isEmpty);
      await tester.tap(find.text('Senarai Belian'));
      await tester.pumpAndSettle();
      expect(find.text('Bahan menu rujukan KKM · 4–6 tahun'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'all tabs follow the child, date, plan updates and recorded intake',
    (tester) async {
      final repo = TestNutritionRepository();
      addTearDown(repo.close);
      final today = DateTime.now();
      final tomorrow = DateTime(today.year, today.month, today.day + 1);
      final children = <String, Map<String, dynamic>>{
        'baby': {
          'name': 'Aisyah',
          'birth': dateKey(DateTime(today.year, today.month - 7, 1)),
          'nutritionPlans': [
            recommendation(6, 8, 'Bubur ayam', 'Isi ayam', 600),
            recommendation(9, 11, 'Pelan umur lain', 'Ikan', 700),
          ],
        },
        'older': {
          'name': 'Zara',
          'birth': dateKey(DateTime(today.year - 4, today.month, 1)),
          'nutritionPlans': [
            recommendation(48, 83, 'Roti telur', 'Telur', 1200),
            recommendation(
              48,
              83,
              'Sup sayur',
              'Lobak merah',
              1300,
              date: dateKey(tomorrow),
            ),
          ],
        },
      };

      Future<void> showChild(String id) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MealPlanPage(
                ownerId: 'owner',
                selectedChildId: id,
                repository: repo,
              ),
            ),
          ),
        );
      }

      Future<void> tap(Finder finder) async {
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }

      await showChild('baby');
      repo.updates.add(children);
      await tester.pumpAndSettle();
      expect(find.text('Bubur ayam'), findsOneWidget);
      expect(find.text('Pelan umur lain'), findsNothing);

      final portion = find.byType(DropdownButton<double>);
      await tester.scrollUntilVisible(portion, 160);
      await tester.ensureVisible(portion);
      await tester.pumpAndSettle();
      await tap(portion);
      await tap(find.text('½ hidangan').last);
      expect(
        repo.records[('baby', dateKey(today))]?['meal-1']['fraction'],
        0.5,
      );
      await tester.pumpAndSettle();
      expect(find.text('Kalori harian'), findsNothing);
      expect(find.text('200 kcal bagi hidangan ini'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Pengambilan Nutrien'), 160);
      await tester.pumpAndSettle();
      Recipe candidate(
        String id,
        String name,
        String? age,
        String amount, {
        Map<String, dynamic> nutrients = const {},
      }) => Recipe(
        id: id,
        name: name,
        description: '',
        emoji: '',
        color: Colors.white,
        ingredients: const [],
        steps: const [],
        ageSuitability: age,
        nutrition: {'energy': amount, 'serving': '1 hidangan', ...nutrients},
      );
      final candidates = {
        'baby': candidate(
          'baby',
          'Resipi bayi',
          '6–8 bulan',
          '± 110 kcal',
          nutrients: {'protein': '± 14 g', 'calcium': '0.1 g', 'iron': '2 mg'},
        ),
        'older': candidate(
          'older',
          'Resipi empat tahun',
          '4–6 tahun',
          '± 160 kcal',
        ),
        'unknown': candidate(
          'unknown',
          'Resipi tiada umur',
          null,
          '± 200 kcal',
        ),
        'unit': candidate(
          'unit',
          'Resipi unit salah',
          '6 bulan ke atas',
          '± 60 g',
        ),
      };
      repo.recipeUpdates.add(candidates);
      await tester.pumpAndSettle();
      expect(find.text('100 kcal'), findsOneWidget);
      expect(find.text('5 g'), findsOneWidget);
      expect(find.text('Sasaran 600 kcal'), findsOneWidget);
      expect(find.text('16.67%'), findsOneWidget);
      expect(find.text('Data tidak lengkap'), findsNWidgets(2));
      final recipePicker = find.byType(DropdownButton<String>);
      await tester.ensureVisible(recipePicker);
      await tester.pumpAndSettle();
      await tap(recipePicker);
      expect(find.text('Anggaran: Resipi empat tahun'), findsNothing);
      expect(find.text('Anggaran: Resipi tiada umur'), findsNothing);
      expect(find.text('Anggaran: Resipi unit salah'), findsNothing);
      await tap(find.text('Anggaran: Resipi bayi').last);
      expect(find.text('Anggaran: Resipi bayi'), findsOneWidget);
      expect(find.text('110 kcal'), findsOneWidget);
      await tap(find.byType(DropdownButton<double>).last);
      await tap(find.text('½ hidangan').last);
      expect(find.text('55 kcal'), findsOneWidget);
      expect(find.text('7 g'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('50 mg'), 140);
      expect(find.text('50 mg'), findsOneWidget);
      expect(find.text('1 mg'), findsOneWidget);
      expect(
        repo.records[(
          'baby',
          dateKey(today),
        )]?['meal-1']['nutrition']['energy'],
        100.0,
      );
      repo.intakeUpdates.addError(StateError('permission-denied'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Rekod pengambilan tidak dapat dimuatkan.'),
        -180,
      );
      await tester.pumpAndSettle();
      expect(find.text('Anggaran: Resipi bayi'), findsOneWidget);
      expect(
        find.text('Rekod pengambilan tidak dapat dimuatkan.'),
        findsOneWidget,
      );
      expect(find.text('100 kcal'), findsNothing);
      expect(find.text('55 kcal'), findsOneWidget);

      await tap(find.text('Senarai Belian'));
      expect(find.text('Isi ayam'), findsOneWidget);
      await tap(find.byType(CheckboxListTile));
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        true,
      );

      await showChild('older');
      await tester.pumpAndSettle();
      expect(find.text('Isi ayam'), findsNothing);
      expect(find.text('Telur'), findsOneWidget);
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        false,
      );
      await tap(find.text('Pelan Harian'));
      await tester.scrollUntilVisible(find.text('Pengambilan Nutrien'), 160);
      await tester.pumpAndSettle();
      expect(find.text('Sasaran 1200 kcal'), findsOneWidget);
      expect(find.text('Belum ada rekod pengambilan.'), findsOneWidget);
      expect(find.text('100 kcal'), findsNothing);
      repo.recipeUpdates.add(candidates);
      await tester.pumpAndSettle();
      expect(find.text('Anggaran: Resipi empat tahun'), findsOneWidget);
      expect(find.text('160 kcal'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Roti telur'), -180);
      expect(find.text('Roti telur'), findsOneWidget);

      expect(find.text('Sup sayur'), findsNothing);
      await tap(find.text('Senarai Belian'));
      expect(find.text('Telur'), findsOneWidget);

      children['older']!['nutritionPlans'] = [
        recommendation(
          48,
          83,
          'Sup kentang',
          'Kentang',
          1250,
          date: dateKey(today),
        ),
      ];
      repo.updates.add(children);
      await tester.pumpAndSettle();
      expect(find.text('Kentang'), findsOneWidget);
      expect(find.text('Lobak merah'), findsNothing);
      await tap(find.text('Pelan Harian'));
      await tester.scrollUntilVisible(find.text('Pengambilan Nutrien'), 160);
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
      expect(find.text('Sasaran 1250 kcal'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Sup kentang'), -180);
      expect(find.text('Sup kentang'), findsOneWidget);
      expect(repo.visits, contains(('older', dateKey(today))));
      children['older']!.remove('nutritionPlans');
      repo.updates.add(children);
      await tester.pumpAndSettle();
      expect(find.text('Contoh Menu Mengikut Umur'), findsNothing);
      expect(
        find.text('Roti mentega, telur hancur, salad dan susu penuh krim'),
        findsOneWidget,
      );
      final photo =
          tester.widget<Image>(find.byType(Image).first).image as AssetImage;
      expect(photo.assetName, 'assets/nutrition_meals/meal-4-1.jpg');
      await tester.drag(find.byType(ListView), const Offset(0, -2000));
      await tester.pumpAndSettle();
      expect(find.text('Butiran pemakanan'), findsNothing);
      expect(
        find.textContaining('Tiada pelan makanan daripada doktor'),
        findsNothing,
      );
      expect(find.text('Lihat ilustrasi dan sukatan asal'), findsNothing);
      await tap(find.text('Senarai Belian'));
      expect(find.text('Bahan menu rujukan KKM · 4–6 tahun'), findsOneWidget);
      expect(find.text('Susu penuh krim'), findsOneWidget);
      expect(find.text('Beras'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('linked recipe ingredients update on web and phone', (
    tester,
  ) async {
    final repo = TestNutritionRepository();
    addTearDown(repo.close);
    await tester.binding.setSurfaceSize(const Size(360, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final today = DateTime.now();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MealPlanPage(ownerId: 'owner', repository: repo),
        ),
      ),
    );
    repo.updates.add({
      'child': {
        'birth': dateKey(DateTime(today.year - 2, today.month, 1)),
        'nutritionPlans': [
          recommendation(12, 47, '', '', 900, recipeId: 'recipe', energy: null),
        ],
      },
    });
    await tester.pump();
    repo.recipeUpdates.add({
      'recipe': const Recipe(
        id: 'recipe',
        name: 'Sup ikan',
        description: '',
        emoji: '🐟',
        color: Colors.orange,
        ingredients: ['Ikan', 'ikan', 'Bawang'],
        steps: [],
        nutrition: {
          'energy': '110–120 kcal',
          'serving': '1 mangkuk',
          'calcium': '± 40 mg',
          'iron': '2 mg',
        },
      ),
    });
    await tester.pumpAndSettle();
    expect(find.text('Sup ikan'), findsOneWidget);
    expect(
      find.text('Anggaran resipi: 110–120 kcal bagi 1 mangkuk'),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Sarapan selesai'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Pengambilan Nutrien'), 160);
    await tester.pumpAndSettle();
    expect(find.text('40 mg'), findsOneWidget);
    expect(find.text('2 mg'), findsOneWidget);
    expect(repo.records, isEmpty);

    await tester.tap(find.text('Senarai Belian'));
    await tester.pumpAndSettle();
    expect(find.text('Ikan'), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsNWidgets(2));

    repo.recipeUpdates.add({
      'recipe': const Recipe(
        id: 'recipe',
        name: 'Sup ikan',
        description: '',
        emoji: '🐟',
        color: Colors.orange,
        ingredients: ['Ikan', 'Kentang'],
        steps: [],
      ),
    });
    await tester.pumpAndSettle();
    expect(find.text('Kentang'), findsOneWidget);
    expect(find.text('Bawang'), findsNothing);

    expect(find.byIcon(Icons.calendar_today_outlined), findsNothing);

    await tester.binding.setSurfaceSize(const Size(320, 568));
    tester.platformDispatcher.textScaleFactorTestValue = 1.4;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    expect(find.text('Kentang'), findsOneWidget);

    await tester.tap(find.text('Pelan Harian'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Sup ikan'), -120);
    expect(find.text('Sup ikan'), findsOneWidget);
    await tester.scrollUntilVisible(find.byType(DropdownButton<double>), 120);
    expect(
      tester
          .widget<DropdownButton<double>>(find.byType(DropdownButton<double>))
          .isExpanded,
      isTrue,
    );

    await tester.scrollUntilVisible(find.text('Pengambilan Nutrien'), 160);
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    final energy = find.text('Tenaga');
    final protein = find.text('Protein');
    await tester.scrollUntilVisible(energy, 180);
    expect(tester.getTopLeft(energy).dy, tester.getTopLeft(protein).dy);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
