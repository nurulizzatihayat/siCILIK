import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'database.dart';

const Color growthGreen = Color(0xFF32966A);
const Color growthGreenLight = Color(0xFFE5F5EB);
const Color growthGreenDark = Color(0xFF216747);

class GrowthPage extends StatefulWidget {
  final String ownerId;
  final String? initialChildId;
  final bool visible;
  final ValueChanged<String>? onChildSelected;
  final GrowthRepository? repository;
  final Future<String>? heightReference;
  final Future<bool> Function(String childId, String date)? scheduleReminder;

  const GrowthPage({
    super.key,
    required this.ownerId,
    this.initialChildId,
    this.visible = true,
    this.onChildSelected,
    this.repository,
    this.heightReference,
    this.scheduleReminder,
  });

  @override
  State<GrowthPage> createState() => _GrowthPageState();
}

class _GrowthPageState extends State<GrowthPage> {
  late final GrowthRepository repo = widget.repository ?? GrowthRepository();

  List<Map<String, Object?>> children = [];
  List<Map<String, Object?>> records = [];

  String? selectedId;
  String? selectedMeasurementId;

  int indicator = 0;

  final ScrollController scrollController = ScrollController();

  bool loading = true;
  String? error;
  int loadRequest = 0;
  String? reminderKey;

  @override
  void initState() {
    super.initState();
    selectedId = widget.initialChildId;
    load();
  }

  @override
  void dispose() {
    scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant GrowthPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.initialChildId != oldWidget.initialChildId ||
        (widget.visible && !oldWidget.visible)) {
      if (widget.initialChildId != null &&
          widget.initialChildId != selectedId) {
        selectedId = widget.initialChildId;
        selectedMeasurementId = null;
      }

      loading = true;
      load();
    }
  }

  Future<void> load() async {
    final request = ++loadRequest;

    try {
      final list = await repo.children(widget.ownerId);

      final id = list.any((c) => c['id'] == selectedId)
          ? selectedId
          : (list.isEmpty ? null : list.first['id'] as String);

      final entries = id == null
          ? <Map<String, Object?>>[]
          : await repo.measurements(widget.ownerId, id);

      if (!mounted || request != loadRequest) return;

      setState(() {
        if (selectedId != id ||
            !entries.any((entry) => entry['id'] == selectedMeasurementId)) {
          selectedMeasurementId = entries.isEmpty
              ? null
              : entries.first['id'] as String;
        }

        children = list;
        selectedId = id;
        records = entries;
        loading = false;
        error = null;
      });

      if (widget.visible && id != null && entries.isNotEmpty) {
        final date = entries.first['date'] as String;

        final name = list.firstWhere((c) => c['id'] == id)['name'] as String;

        final key = '$id:$date:$name';

        if (key != reminderKey) {
          reminderKey = key;
          _scheduleReminder(id, name, date);
        }
      }
    } catch (e, st) {
      debugPrint('Growth load failed: $e\n$st');

      if (mounted && request == loadRequest) {
        setState(() {
          loading = false;
          error = 'Data pertumbuhan tak dapat dimuatkan.';
        });
      }
    }
  }

  Future<void> _scheduleReminder(
    String childId,
    String childName,
    String date,
  ) async {
    if (widget.scheduleReminder == null && !GrowthReminders.supported) {
      return;
    }

    try {
      final allowed = widget.scheduleReminder != null
          ? await widget.scheduleReminder!(childId, date)
          : await GrowthReminders.schedule(
              childId: childId,
              childName: childName,
              latestDate: date,
            );

      if (!allowed && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Benarkan notifikasi dalam tetapan telefon untuk menerima peringatan pertumbuhan.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Ukuran telah disimpan, tetapi peringatan tak dapat dijadualkan.',
            ),
          ),
        );
      }
    }
  }

  Future<void> addMeasurement() async {
    final height = TextEditingController();
    final weight = TextEditingController();

    DateTime date = DateUtils.dateOnly(DateTime.now());

    final child = children.firstWhere((c) => c['id'] == selectedId);

    final birth = DateTime.parse(child['birth'] as String);

    final route = DialogRoute<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Tambah ukuran'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: context,
                      locale: const Locale('ms'),
                      firstDate: birth,
                      lastDate: DateTime.now(),
                      initialDate: date,
                    );

                    if (d != null) {
                      update(() => date = d);
                    }
                  },
                  icon: const Icon(Icons.calendar_today),
                  label: Text(dateText(date)),
                ),
                TextField(
                  controller: height,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Tinggi atau panjang (cm)',
                  ),
                ),
                TextField(
                  controller: weight,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Berat (kg)'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () {
                final h = double.tryParse(height.text);
                final w = double.tryParse(weight.text);

                if (h == null ||
                    w == null ||
                    !h.isFinite ||
                    !w.isFinite ||
                    h <= 0 ||
                    w <= 0 ||
                    date.isBefore(birth)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Masukkan ukuran positif yang sah dan tarikh selepas tarikh lahir.',
                      ),
                    ),
                  );
                  return;
                }

                Navigator.pop(context, true);
              },
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );

    final result = await Navigator.of(context).push(route);
    await route.completed;

    if (result == true) {
      try {
        selectedMeasurementId = await repo.addMeasurement(
          widget.ownerId,
          selectedId!,
          dateText(date),
          double.parse(height.text),
          double.parse(weight.text),
          'unknown',
        );

        await load();
      } catch (_) {
        showError();
      }
    }

    height.dispose();
    weight.dispose();
  }

  Future<void> editMeasurement(Map<String, Object?> record) async {
    final height = TextEditingController(
      text: (record['height'] as num).toString(),
    );
    final weight = TextEditingController(
      text: (record['weight'] as num).toString(),
    );
    final childId = selectedId;

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit ukuran'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: height,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Tinggi atau panjang (cm)',
              ),
            ),
            TextField(
              controller: weight,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Berat (kg)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              final h = double.tryParse(height.text);
              final w = double.tryParse(weight.text);
              if (h == null ||
                  w == null ||
                  !h.isFinite ||
                  !w.isFinite ||
                  h <= 0 ||
                  w <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Masukkan tinggi dan berat yang sah.'),
                  ),
                );
                return;
              }
              Navigator.pop(dialogContext, true);
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );

    if (result == true && childId != null) {
      try {
        await repo.updateMeasurement(
          ownerId: widget.ownerId,
          childId: childId,
          measurementId: record['id'] as String,
          date: record['date'] as String,
          height: double.parse(height.text),
          weight: double.parse(weight.text),
          method: record['method'] as String? ?? 'unknown',
        );
        await load();
      } catch (_) {
        showError();
      }
    }

    height.dispose();
    weight.dispose();
  }

  void showError() {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ukuran tak dapat disimpan. Cuba lagi.')),
      );
    }
  }

  String dateText(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static const green = Color(0xFF1DA270);

  static const labels = ['Risiko bantut', 'Risiko kurang berat', 'BMI anak'];

  @override
  Widget build(BuildContext context) {
    final child = selectedId == null || children.isEmpty
        ? null
        : children.where((c) => c['id'] == selectedId).firstOrNull;

    return Scaffold(
      backgroundColor: growthGreen,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const _GrowthHeader(),

            Expanded(
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: Color(0xFFF4F5F9),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: loading
                    ? const Center(child: CircularProgressIndicator())
                    : error != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(error!),
                            TextButton(
                              onPressed: load,
                              child: const Text('Cuba lagi'),
                            ),
                          ],
                        ),
                      )
                    : ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.all(14),
                        children: [
                          if (children.isEmpty) ...[
                            const Text(
                              'Tambah anak di halaman Utama untuk bermula.',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: null,
                                icon: const Icon(Icons.add),
                                label: const Text('Tambah ukuran'),
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size.fromHeight(48),
                                ),
                              ),
                            ),
                          ] else
                            Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: DropdownButtonFormField<String>(
                                    key: ValueKey(selectedId),
                                    initialValue:
                                        children.any(
                                          (c) => c['id'] == selectedId,
                                        )
                                        ? selectedId
                                        : null,
                                    isExpanded: true,
                                    iconSize: 18,
                                    decoration: const InputDecoration(
                                      labelText: 'Pilih Anak',
                                      labelStyle: TextStyle(fontSize: 14),
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 14,
                                      ),
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                    items: children
                                        .map(
                                          (c) => DropdownMenuItem<String>(
                                            value: c['id'] as String,
                                            child: Text(
                                              c['name'] as String,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (id) {
                                      setState(() {
                                        selectedId = id;
                                        selectedMeasurementId = null;
                                        records = [];
                                      });

                                      if (id != null) {
                                        widget.onChildSelected?.call(id);
                                      }

                                      load();
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 5,
                                  child: SizedBox(
                                    height: 48,
                                    child: FilledButton.icon(
                                      onPressed: child == null
                                          ? null
                                          : addMeasurement,
                                      icon: const Icon(Icons.add),
                                      label: const Text('Tambah ukuran'),
                                      style: FilledButton.styleFrom(
                                        backgroundColor: growthGreen,
                                        foregroundColor: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),

                          const SizedBox(height: 14),

                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: List.generate(
                                labels.length,
                                (i) => Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: ChoiceChip(
                                    label: Text(labels[i]),
                                    selected: indicator == i,
                                    selectedColor: green,
                                    backgroundColor: const Color(0xFFEDEFF4),
                                    labelStyle: TextStyle(
                                      color: indicator == i
                                          ? Colors.white
                                          : Colors.black87,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    onSelected: (_) =>
                                        setState(() => indicator = i),
                                  ),
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 12),

                          GrowthReferenceChart(
                            child: child,
                            reference: widget.heightReference,
                            indicator: ['height', 'weight', 'bmi'][indicator],
                            onEditMeasurement: editMeasurement,
                            isLatestMeasurement:
                                records.isNotEmpty &&
                                records.first['id'] == selectedMeasurementId,
                            record: records
                                .where((r) => r['id'] == selectedMeasurementId)
                                .firstOrNull,
                          ),

                          const SizedBox(height: 16),

                          Card(
                            margin: EdgeInsets.zero,
                            color: Colors.white,
                            elevation: 0,
                            clipBehavior: Clip.antiAlias,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: const BorderSide(color: Color(0xFFE5E8EF)),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      const Expanded(
                                        child: Text(
                                          'Sejarah ukuran',
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      FilledButton.icon(
                                        onPressed: child == null
                                            ? null
                                            : addMeasurement,
                                        icon: const Icon(Icons.add, size: 18),
                                        label: const Text('Tambah'),
                                        style: FilledButton.styleFrom(
                                          minimumSize: const Size(0, 36),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                          ),
                                          backgroundColor: const Color(
                                            0xFFEAE4FF,
                                          ),
                                          foregroundColor: const Color(
                                            0xFF603DB8,
                                          ),
                                          elevation: 0,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  if (child == null)
                                    const Padding(
                                      padding: EdgeInsets.symmetric(
                                        vertical: 16,
                                      ),
                                      child: Text(
                                        'Pilih atau tambah anak dahulu.',
                                      ),
                                    )
                                  else
                                    MeasurementHistory(
                                      child: child,
                                      records: records,
                                      indicator: [
                                        'height',
                                        'weight',
                                        'bmi',
                                      ][indicator],
                                      reference: widget.heightReference,
                                      selectedId: selectedMeasurementId,
                                      onSelected: (id) {
                                        setState(() {
                                          selectedMeasurementId = id;
                                        });
                                        scrollController.animateTo(
                                          0,
                                          duration: const Duration(
                                            milliseconds: 300,
                                          ),
                                          curve: Curves.easeOut,
                                        );
                                      },
                                    ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 18),

                          if (child != null)
                            MonthlyProgress(
                              child: child,
                              records: records,
                              reference: widget.heightReference,
                              isWeightForAge: indicator == 1,
                              isBmiForAge: indicator == 2,
                            ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

///siCILIK app header.
class _GrowthHeader extends StatelessWidget {
  const _GrowthHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 24,
            backgroundColor: Colors.white,
            child: Icon(Icons.trending_up_rounded, color: growthGreenDark),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Progres Pertumbuhan',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Lihat carta pertumbuhan anak anda dan rekod bulanan.',
                  style: TextStyle(color: Colors.white, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

int? completedAgeMonths(DateTime birth, DateTime date) {
  var months = (date.year - birth.year) * 12 + date.month - birth.month;

  if (date.day < birth.day) months--;

  return months < 0 ? null : months;
}

String ageInMonths(DateTime birth, DateTime date) {
  final months = completedAgeMonths(birth, date);

  if (months == null) return 'Umur tidak diketahui';

  return '$months bulan';
}

class MeasurementHistory extends StatelessWidget {
  final Map<String, Object?> child;
  final List<Map<String, Object?>> records;
  final String indicator;
  final Future<String>? reference;
  final String? selectedId;
  final ValueChanged<String> onSelected;

  const MeasurementHistory({
    super.key,
    required this.child,
    required this.records,
    required this.indicator,
    required this.reference,
    required this.selectedId,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final isWeight = indicator == 'weight';
    final isBmi = indicator == 'bmi';

    if (records.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Text('Belum ada ukuran.'),
      );
    }

    return FutureBuilder<String>(
      future:
          reference ?? rootBundle.loadString('assets/who/growth_curves.csv'),
      builder: (context, snapshot) {
        final birth = DateTime.parse(child['birth'] as String);
        final sexValue = (child['sex'] as String? ?? '').toLowerCase();
        final sex = sexValue == 'boy' || sexValue == 'male' ? 'boys' : 'girls';
        final rows = snapshot.data == null
            ? <List<String>>[]
            : snapshot.data!
                  .trim()
                  .split('\n')
                  .skip(1)
                  .map((line) => line.trim().split(','))
                  .where((row) => row.length >= 11)
                  .toList();

        final table = DataTable(
          showCheckboxColumn: false,
          headingRowColor: const WidgetStatePropertyAll(Color(0xFFF0F2F6)),
          border: const TableBorder(
            top: BorderSide(color: Color(0xFFD8DEE8)),
            bottom: BorderSide(color: Color(0xFFD8DEE8)),
            left: BorderSide(color: Color(0xFFD8DEE8)),
            right: BorderSide(color: Color(0xFFD8DEE8)),
            horizontalInside: BorderSide(color: Color(0xFFE1E5EC)),
            verticalInside: BorderSide(color: Color(0xFFE1E5EC)),
          ),
          dataRowMinHeight: 44,
          dataRowMaxHeight: 48,
          headingRowHeight: 46,
          columnSpacing: 12,
          horizontalMargin: 8,
          columns: [
            const DataColumn(label: Text('Tarikh')),
            DataColumn(
              label: const Text('Umur\n(bulan)', textAlign: TextAlign.center),
            ),
            DataColumn(
              label: Text(
                isBmi
                    ? 'BMI'
                    : isWeight
                    ? 'Berat\n(kg)'
                    : 'Tinggi\n(cm)',
                textAlign: TextAlign.center,
              ),
            ),
            DataColumn(
              label: Text(
                isBmi
                    ? 'Skor BMI\nikut umur'
                    : isWeight
                    ? 'WAZ'
                    : 'HAZ',
                textAlign: TextAlign.center,
              ),
            ),
            const DataColumn(label: Text('Status')),
          ],
          rows: records.map((record) {
            final age = completedAgeMonths(
              birth,
              DateTime.parse(record['date'] as String),
            );
            final year = age != null && age > 60 ? 2007 : 2006;
            final height = (record['height'] as num?)?.toDouble();
            final weight = (record['weight'] as num?)?.toDouble();
            final measurementValue = isBmi
                ? height != null && height > 0 && weight != null
                      ? weight / math.pow(height / 100, 2)
                      : double.nan
                : (record[isWeight ? 'weight' : 'height'] as num).toDouble();
            final referenceRows = rows
                .where(
                  (row) =>
                      row[0] ==
                          (isBmi
                              ? 'bmi'
                              : isWeight
                              ? 'weight'
                              : 'height') &&
                      row[1] == sex &&
                      row[2] == '$year',
                )
                .map((row) => row.skip(3).map(double.parse).toList())
                .toList();
            final maxAge = isWeight ? 120 : 228;
            final zScore =
                age != null &&
                    age <= maxAge &&
                    measurementValue.isFinite &&
                    referenceRows.isNotEmpty
                ? estimateGrowthZScore(referenceRows, age, measurementValue)
                : null;
            final bmiAtRisk =
                isBmi &&
                age != null &&
                age <= 60 &&
                zScore != null &&
                zScore > 1 &&
                zScore <= 2;
            final bmiOverweight =
                isBmi &&
                age != null &&
                zScore != null &&
                zScore > (age <= 60 ? 2 : 1);
            final bmiObesity =
                isBmi &&
                age != null &&
                zScore != null &&
                zScore > (age <= 60 ? 3 : 2);
            final bmiThinness = isBmi && zScore != null && zScore < -2;
            final bmiSevereThinness = isBmi && zScore != null && zScore < -3;
            final status = zScore == null
                ? '—'
                : isBmi
                ? bmiSevereThinness
                      ? 'Terlalu kurus'
                      : bmiThinness
                      ? 'Kurus'
                      : bmiObesity
                      ? 'Obesiti'
                      : bmiOverweight
                      ? 'Berat berlebihan'
                      : bmiAtRisk
                      ? 'Risiko berat berlebihan'
                      : 'Normal'
                : zScore < -3
                ? isWeight
                      ? 'Kurang berat teruk'
                      : 'Bantut teruk'
                : zScore < -2
                ? isWeight
                      ? 'Kurang berat'
                      : 'Bantut'
                : 'Normal';
            final statusColor = zScore == null
                ? const Color(0xFFEDEFF4)
                : isBmi && (bmiSevereThinness || bmiObesity)
                ? const Color(0xFFF8D7DC)
                : isBmi && (bmiThinness || bmiAtRisk || bmiOverweight)
                ? const Color(0xFFFFE59A)
                : zScore < -3
                ? const Color(0xFFF8D7DC)
                : zScore < -2
                ? const Color(0xFFFFE59A)
                : const Color(0xFFD5F2E4);

            return DataRow(
              selected: record['id'] == selectedId,
              onSelectChanged: (_) => onSelected(record['id'] as String),
              color: const WidgetStatePropertyAll(Colors.white),
              cells: [
                DataCell(
                  Text(_formatMeasurementDate(record['date'] as String)),
                ),
                DataCell(Center(child: Text(age?.toString() ?? '-'))),
                DataCell(
                  Center(
                    child: Text(
                      measurementValue.isFinite
                          ? measurementValue.toStringAsFixed(1)
                          : '-',
                    ),
                  ),
                ),
                DataCell(
                  Center(child: Text(zScore?.toStringAsFixed(1) ?? '-')),
                ),
                DataCell(
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      status,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            );
          }).toList(),
        );

        return LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: table,
            ),
          ),
        );
      },
    );
  }
}

class GrowthReferenceChart extends StatefulWidget {
  final Map<String, Object?>? child;
  final Map<String, Object?>? record;
  final String indicator;
  final bool isLatestMeasurement;
  final Future<void> Function(Map<String, Object?> record)? onEditMeasurement;
  final Future<String>? reference;
  final DateTime? today;

  const GrowthReferenceChart({
    super.key,
    this.child,
    this.record,
    required this.indicator,
    required this.isLatestMeasurement,
    this.onEditMeasurement,
    this.reference,
    this.today,
  });

  @override
  State<GrowthReferenceChart> createState() => _GrowthReferenceChartState();
}

class _GrowthReferenceChartState extends State<GrowthReferenceChart> {
  late final Future<String> data =
      widget.reference ?? rootBundle.loadString('assets/who/growth_curves.csv');
  ui.Image? childSprite;

  @override
  void initState() {
    super.initState();
    _loadChildSprite();
  }

  Future<void> _loadChildSprite() async {
    final bytes = await rootBundle.load('assets/characters/children.png');
    final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    codec.dispose();
    if (!mounted) {
      frame.image.dispose();
      return;
    }
    setState(() => childSprite = frame.image);
  }

  @override
  void dispose() {
    childSprite?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
    future: data,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const Text('Data rujukan pertumbuhan tak dapat dimuatkan.');
      }

      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }

      final child = widget.child;

      if (child == null) {
        return const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text('Pilih anak untuk melihat carta.'),
          ),
        );
      }

      final birth = DateTime.parse(child['birth'] as String);
      final record = widget.record;

      final measurementAge = record == null
          ? null
          : completedAgeMonths(birth, DateTime.parse(record['date'] as String));

      final storedSex = (child['sex'] as String? ?? '').toLowerCase();
      final isBoy = storedSex == 'boy' || storedSex == 'male';
      final sex = isBoy ? 'boys' : 'girls';

      if (measurementAge != null &&
          (measurementAge > 228 ||
              (widget.indicator == 'weight' && measurementAge > 120))) {
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              widget.indicator == 'weight' && measurementAge > 120
                  ? 'Data rujukan berat mengikut umur tidak tersedia selepas 120 bulan.'
                  : 'Data rujukan pertumbuhan tidak tersedia untuk umur ini.',
            ),
          ),
        );
      }

      final chartAge = measurementAge;
      final year = (chartAge ?? 0) <= 60 ? 2006 : 2007;

      final canPlot = measurementAge != null;

      final rows = snapshot.data!
          .trim()
          .split('\n')
          .skip(1)
          .map((line) => line.trim().split(','))
          .where(
            (row) =>
                row[0] == widget.indicator &&
                row[1] == sex &&
                row[2] == '$year',
          )
          .map((row) => row.skip(3).map(double.parse).toList())
          .toList();

      if (rows.isEmpty) {
        return const Text('Data rujukan pertumbuhan tidak tersedia.');
      }

      final height = (record?['height'] as num?)?.toDouble();

      final weight = (record?['weight'] as num?)?.toDouble();

      final double? value = switch (widget.indicator) {
        'height' => height,
        'weight' => weight,
        'bmi' =>
          height != null && height > 0 && weight != null
              ? weight / math.pow(height / 100, 2)
              : null,
        _ => null,
      };

      final zScore = canPlot && value != null
          ? estimateGrowthZScore(rows, measurementAge, value)
          : null;

      final unit = widget.indicator == 'height'
          ? 'cm'
          : widget.indicator == 'weight'
          ? 'kg'
          : 'BMI (kg/m²)';

      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 300,
                width: double.infinity,
                child: CustomPaint(
                  painter: _GrowthPainter(
                    rows,
                    value == null || !canPlot ? null : measurementAge,
                    value,
                    unit,
                    childSprite: childSprite,
                    isBoy: isBoy,
                    isHeightChart: widget.indicator == 'height',
                    isWeightChart: widget.indicator == 'weight',
                    isBmiChart: widget.indicator == 'bmi',
                    showReferenceLines: record != null,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              if (record == null)
                const Text(
                  'Pilih rekod ukuran untuk melihat kedudukan anak pada carta.',
                )
              else if (value == null)
                const Text(
                  'Nilai ukuran tidak dapat dipaparkan pada carta ini.',
                )
              else if (!canPlot)
                const Text(
                  'Umur ketika ukuran diambil berada di luar julat carta ini.',
                )
              else ...[
                _MeasurementSummary(
                  indicator: widget.indicator,
                  value: value,
                  unit: unit,
                  ageMonths: measurementAge,
                  measurementDate: record['date'] as String,
                  isLatestMeasurement: widget.isLatestMeasurement,
                  onEdit: widget.onEditMeasurement == null
                      ? null
                      : () => widget.onEditMeasurement!(record),
                  zScore: zScore,
                  sex: isBoy ? 'Lelaki' : 'Perempuan',
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

class _GrowthPainter extends CustomPainter {
  final List<List<double>> rows;
  final int? age;
  final double? value;
  final String unit;
  final ui.Image? childSprite;
  final bool isBoy;
  final bool isHeightChart;
  final bool isWeightChart;
  final bool isBmiChart;
  final bool showReferenceLines;

  _GrowthPainter(
    this.rows,
    this.age,
    this.value,
    this.unit, {
    required this.childSprite,
    required this.isBoy,
    required this.isHeightChart,
    required this.isWeightChart,
    required this.isBmiChart,
    required this.showReferenceLines,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (rows.length < 2) return;

    // Keep the unit label above the top Y-axis tick on every indicator chart.
    final plot = Rect.fromLTRB(
      20,
      30,
      size.width - (isHeightChart || isWeightChart || isBmiChart ? 38 : 30),
      size.height - 36,
    );

    if (plot.width <= 0 || plot.height <= 0) return;

    final domainStart = rows.first[0];
    final domainEnd = rows.last[0];
    final domainSpan = domainEnd - domainStart;
    final visibleSpan = math.min(36.0, domainSpan).toDouble();
    var start = domainStart;
    var end = domainEnd;
    if (age != null && visibleSpan < domainSpan) {
      start = math
          .max(domainStart, ((age! - 24) / 12).floor() * 12.0)
          .toDouble();
      start = math.min(start, domainEnd - visibleSpan).toDouble();
      end = start + visibleSpan;
    }

    final visibleRows = rows
        .where((row) => row[0] >= start && row[0] <= end)
        .toList();
    final values = visibleRows.expand((r) => r.skip(1)).toList();

    var minY = values.reduce(math.min);
    var maxY = values.reduce(math.max);

    if (value != null && value!.isFinite) {
      minY = math.min(minY, value!);
      maxY = math.max(maxY, value!);
    }

    final pad = (maxY - minY) * 0.06;

    minY = math.max(0, minY - pad);
    maxY += pad;

    double x(double month) =>
        plot.left + (month - start) / (end - start) * plot.width;

    List<double> valuesAtMonth(double month) {
      for (var i = 1; i < rows.length; i++) {
        if (rows[i][0] >= month) {
          final lower = rows[i - 1];
          final upper = rows[i];
          final fraction = (month - lower[0]) / (upper[0] - lower[0]);
          return List.generate(
            lower.length,
            (index) => lower[index] + (upper[index] - lower[index]) * fraction,
          );
        }
      }
      return rows.last;
    }

    final visibleEndRow = valuesAtMonth(end);

    double y(double n) =>
        plot.bottom - (n - minY) / (maxY - minY) * plot.height;

    void label(
      String text,
      Offset offset, {
      bool prominent = false,
      bool bold = false,
      Color? color,
      double? fontSize,
    }) {
      (TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color:
                color ??
                (prominent
                    ? growthGreenDark
                    : bold
                    ? Colors.black87
                    : Colors.black54),
            fontSize:
                fontSize ??
                (prominent
                    ? 12
                    : bold
                    ? 11
                    : 10),
            fontWeight: prominent || bold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout()).paint(canvas, offset);
    }

    if ((isHeightChart || isWeightChart || isBmiChart) && showReferenceLines) {
      Path areaBelowCurve(int curveIndex) {
        final area = Path()
          ..moveTo(x(rows.first[0]), y(rows.first[curveIndex]));
        for (final row in rows.skip(1)) {
          area.lineTo(x(row[0]), y(row[curveIndex]));
        }
        return area
          ..lineTo(plot.right, plot.bottom)
          ..lineTo(plot.left, plot.bottom)
          ..close();
      }

      canvas.save();
      canvas.clipRect(plot);
      if (isBmiChart) {
        Path areaAboveCurve(int curveIndex) {
          final area = Path()
            ..moveTo(x(rows.first[0]), y(rows.first[curveIndex]));
          for (final row in rows.skip(1)) {
            area.lineTo(x(row[0]), y(row[curveIndex]));
          }
          return area
            ..lineTo(x(rows.last[0]), plot.top)
            ..lineTo(x(rows.first[0]), plot.top)
            ..close();
        }

        final isUnderFiveReference = rows.first[0] <= 60;
        if (isUnderFiveReference) {
          canvas.drawPath(
            areaAboveCurve(5),
            Paint()..color = const Color(0x33FFDA5C),
          );
        }
        final overweightIndex = isUnderFiveReference ? 6 : 5;
        final obesityIndex = isUnderFiveReference ? 7 : 6;
        canvas
          ..drawPath(
            areaBelowCurve(2),
            Paint()..color = const Color(0x55FFDA5C),
          )
          ..drawPath(
            areaBelowCurve(1),
            Paint()..color = const Color(0x66F28B9A),
          )
          ..drawPath(
            areaAboveCurve(overweightIndex),
            Paint()..color = const Color(0x55FFDA5C),
          )
          ..drawPath(
            areaAboveCurve(obesityIndex),
            Paint()..color = const Color(0x66F28B9A),
          );
      } else {
        canvas
          ..drawPath(
            areaBelowCurve(2),
            Paint()..color = const Color(0x55FFDA5C),
          )
          ..drawPath(
            areaBelowCurve(1),
            Paint()..color = const Color(0x66F28B9A),
          );
      }
      canvas.restore();
    }

    final grid = Paint()..color = const Color(0xFFE9EEF0);

    for (var i = 0; i <= 4; i++) {
      final n = minY + (maxY - minY) * i / 4;

      canvas.drawLine(Offset(plot.left, y(n)), Offset(plot.right, y(n)), grid);

      label(
        n.toStringAsFixed(n < 30 ? 1 : 0),
        Offset(-6, y(n) - 6),
        bold: true,
      );
    }

    final xTicks = <double>[start];
    for (var month = start + 12; month < end; month += 12) {
      xTicks.add(month);
    }
    if ((xTicks.last - end).abs() > 0.01) xTicks.add(end);
    for (final month in xTicks) {
      canvas.drawLine(
        Offset(x(month), plot.top),
        Offset(x(month), plot.bottom),
        grid,
      );
      label(
        '${month.round()}',
        Offset(x(month) - 8, plot.bottom + 3),
        bold: true,
      );
    }

    final axisPaint = Paint()
      ..color = const Color(0xFF343A40)
      ..strokeWidth = 1.8;
    canvas
      ..drawLine(
        Offset(plot.left, plot.top),
        Offset(plot.left, plot.bottom),
        axisPaint,
      )
      ..drawLine(
        Offset(plot.left, plot.bottom),
        Offset(plot.right, plot.bottom),
        axisPaint,
      );

    canvas.save();
    canvas.clipRect(plot);

    if (showReferenceLines) {
      for (var i = 1; i <= 7; i++) {
        final path = Path();

        for (var n = 0; n < rows.length; n++) {
          final row = rows[n];

          if (n == 0) {
            path.moveTo(x(row[0]), y(row[i]));
          } else {
            path.lineTo(x(row[0]), y(row[i]));
          }
        }

        final isMedian = i == 4;
        final isUnderFiveReference = rows.first[0] <= 60;
        final bmiAtRiskCutoff = 5;
        final bmiOverweightCutoff = isUnderFiveReference ? 6 : 5;
        final bmiObesityCutoff = isUnderFiveReference ? 7 : 6;
        final isSevereCutoff =
            ((isHeightChart || isWeightChart) && i == 1) ||
            (isBmiChart && (i == 1 || i == bmiObesityCutoff));
        final isLowGrowthCutoff =
            ((isHeightChart || isWeightChart) && i == 2) ||
            (isBmiChart &&
                (i == 2 ||
                    i == bmiOverweightCutoff ||
                    (isUnderFiveReference && i == bmiAtRiskCutoff)));
        final isBmiAtRiskLine =
            isBmiChart && isUnderFiveReference && i == bmiAtRiskCutoff;

        canvas.drawPath(
          path,
          Paint()
            ..color = isHeightChart || isWeightChart || isBmiChart
                ? isMedian
                      ? const Color(0xFF32966A)
                      : isSevereCutoff
                      ? const Color(0xFFE77886)
                      : isBmiAtRiskLine
                      ? const Color(0xFFE6C34F)
                      : isLowGrowthCutoff
                      ? const Color(0xFFE2AC19)
                      : const Color(0xFFB9C7C8)
                : isMedian
                ? const Color(0xFF32966A)
                : const Color(0xFFB9C7C8)
            ..style = PaintingStyle.stroke
            ..strokeWidth = isMedian || isSevereCutoff || isLowGrowthCutoff
                ? 2.2
                : 1.2,
        );
      }

      if (isHeightChart || isWeightChart || isBmiChart) {
        label(
          isBmiChart
              ? 'Zon kurus'
              : isHeightChart
              ? 'Kawasan bantut'
              : 'Kawasan kurang berat',
          Offset(
            plot.left +
                plot.width *
                    (isBmiChart
                        ? 0.08
                        : isHeightChart
                        ? 0.58
                        : 0.23),
            plot.bottom - 16,
          ),
          prominent: true,
          color: const Color(0xFF8B6500),
        );
        if (isBmiChart) {
          label(
            'Zon berat berlebihan',
            Offset(plot.left + plot.width * 0.52, plot.top + 8),
            prominent: true,
            color: const Color(0xFF8B6500),
            fontSize: 10,
          );
        }
      }
    }

    if (showReferenceLines && age != null && value != null && value!.isFinite) {
      final sprite = childSprite;
      if (sprite != null) {
        final markerRect = Rect.fromCenter(
          center: Offset(x(age!.toDouble()), y(value!)),
          width: 28,
          height: 38,
        );
        canvas.drawImageRect(
          sprite,
          _childSourceRect(sprite, isBoy: isBoy),
          markerRect,
          Paint()..filterQuality = FilterQuality.high,
        );
      }
    }

    canvas.restore();

    if ((isHeightChart || isWeightChart || isBmiChart) && showReferenceLines) {
      for (var i = 1; i <= 7; i++) {
        final zScore = i - 4;
        final zLabel = zScore > 0 ? '+$zScore SD' : '$zScore SD';
        final isMedian = i == 4;
        final isMinusTwoCutoff = i == 2;
        final isUnderFiveReference = rows.first[0] <= 60;
        final bmiAtRiskCutoff = 5;
        final bmiOverweightCutoff = isUnderFiveReference ? 6 : 5;
        final bmiObesityCutoff = isUnderFiveReference ? 7 : 6;
        final isSevereCutoff = i == 1 || (isBmiChart && i == bmiObesityCutoff);
        final isBmiRiskLine =
            isBmiChart &&
            (i == 1 ||
                i == 2 ||
                (isUnderFiveReference && i == bmiAtRiskCutoff) ||
                i == bmiOverweightCutoff ||
                i == bmiObesityCutoff);
        final color = isSevereCutoff
            ? const Color(0xFFD95C6C)
            : isMinusTwoCutoff || (isBmiChart && isBmiRiskLine)
            ? const Color(0xFF9A6A00)
            : const Color(0xFF59666B);
        label(
          zLabel,
          Offset(plot.right + 4, y(visibleEndRow[i]) - 6),
          prominent: true,
          color: isMedian ? const Color(0xFF247A55) : color,
        );
      }
    }

    label(
      isHeightChart
          ? 'Tinggi (cm)'
          : isWeightChart
          ? 'Berat (kg)'
          : unit,
      const Offset(0, 0),
      prominent: true,
    );

    label(
      'Umur (bulan)',
      Offset(plot.center.dx - 38, size.height - 14),
      prominent: true,
    );
  }

  @override
  bool shouldRepaint(covariant _GrowthPainter oldDelegate) => true;
}

double? estimateGrowthZScore(
  List<List<double>> rows,
  int ageMonths,
  double value,
) {
  if (rows.isEmpty || !value.isFinite) return null;
  final row = rows.firstWhere(
    (item) => item[0].round() == ageMonths,
    orElse: () => rows.reduce(
      (a, b) => (a[0] - ageMonths).abs() <= (b[0] - ageMonths).abs() ? a : b,
    ),
  );
  for (var i = 1; i < row.length - 1; i++) {
    final lower = row[i];
    final upper = row[i + 1];
    if (value >= lower && value <= upper) {
      return (i - 4) + (value - lower) / (upper - lower);
    }
  }
  if (value < row[1]) return -3 + (value - row[1]) / (row[2] - row[1]);
  return 3 + (value - row.last) / (row.last - row[row.length - 2]);
}

Rect _childSourceRect(ui.Image image, {required bool isBoy}) {
  final w = image.width.toDouble();
  final h = image.height.toDouble();
  return isBoy
      ? Rect.fromLTRB(w * 0.62, h * 0.50, w * 0.95, h * 0.92)
      : Rect.fromLTRB(w * 0.63, h * 0.10, w * 0.94, h * 0.56);
}

class _MeasurementSummary extends StatelessWidget {
  final String indicator;
  final double value;
  final String unit;
  final int ageMonths;
  final String measurementDate;
  final bool isLatestMeasurement;
  final VoidCallback? onEdit;
  final double? zScore;
  final String sex;

  const _MeasurementSummary({
    required this.indicator,
    required this.value,
    required this.unit,
    required this.ageMonths,
    required this.measurementDate,
    required this.isLatestMeasurement,
    required this.onEdit,
    required this.zScore,
    required this.sex,
  });

  @override
  Widget build(BuildContext context) {
    final isHeight = indicator == 'height';
    final isWeight = indicator == 'weight';
    final isBmi = indicator == 'bmi';
    final hasZScore = (isHeight || isWeight || isBmi) && zScore != null;
    final measurementLabel = indicator == 'height'
        ? 'Tinggi (cm)'
        : indicator == 'weight'
        ? 'Berat (kg)'
        : 'BMI';
    final bmiOverweight =
        isBmi && hasZScore && zScore! > (ageMonths <= 60 ? 2 : 1);
    final bmiAtRisk =
        isBmi && ageMonths <= 60 && hasZScore && zScore! > 1 && zScore! <= 2;
    final bmiObesity =
        isBmi && hasZScore && zScore! > (ageMonths <= 60 ? 3 : 2);
    final bmiThinness = isBmi && hasZScore && zScore! < -2;
    final bmiSevereThinness = isBmi && hasZScore && zScore! < -3;
    final severe = isBmi
        ? bmiSevereThinness || bmiObesity
        : hasZScore && zScore! < -3;
    final belowMinusTwo = isBmi
        ? bmiThinness || bmiAtRisk || bmiOverweight
        : hasZScore && zScore! < -2;
    final status = isBmi
        ? bmiSevereThinness
              ? 'Terlalu kurus'
              : bmiThinness
              ? 'Kurus'
              : bmiObesity
              ? 'Obesiti'
              : bmiOverweight
              ? 'Berat berlebihan'
              : bmiAtRisk
              ? 'Risiko berat berlebihan'
              : 'BMI sesuai umur'
        : isHeight
        ? severe
              ? 'Bantut teruk'
              : belowMinusTwo
              ? 'Bantut'
              : 'Tidak bantut'
        : severe
        ? 'Kurang berat teruk'
        : belowMinusTwo
        ? 'Kurang berat badan'
        : 'Berat sesuai umur';
    final statusColor = severe
        ? const Color(0xFFB6324B)
        : belowMinusTwo
        ? const Color(0xFF8A6500)
        : const Color(0xFF216747);
    final statusBackground = severe
        ? const Color(0xFFFFE1E5)
        : belowMinusTwo
        ? const Color(0xFFFFF2BF)
        : const Color(0xFFE5F5EB);
    final scoreBackground = severe
        ? const Color(0xFFF2AEB8)
        : belowMinusTwo
        ? const Color(0xFFFFE082)
        : const Color(0xFFB8DEC6);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E8EF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  isLatestMeasurement ? 'Ukuran anak terkini' : 'Ukuran anak',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: growthGreenDark,
                  ),
                ),
              ),
              Text(
                _formatMeasurementDate(measurementDate),
                style: const TextStyle(fontSize: 12, color: Color(0xFF7A8088)),
              ),
              IconButton(
                onPressed: onEdit,
                tooltip: 'Edit ukuran',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 30,
                  height: 30,
                ),
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.edit_outlined, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _measurementFact(
                  measurementLabel,
                  value.toStringAsFixed(1),
                ),
              ),
              Container(width: 1, height: 34, color: const Color(0xFFD5D9E0)),
              Expanded(
                child: Center(
                  child: _measurementFact('Umur (bulan)', '$ageMonths'),
                ),
              ),
              Container(width: 1, height: 34, color: const Color(0xFFD5D9E0)),
              Expanded(child: Center(child: _measurementFact('Jantina', sex))),
            ],
          ),
          if (hasZScore) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: statusBackground,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: statusColor.withValues(alpha: 0.35)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isHeight
                              ? 'Skor HAZ'
                              : isWeight
                              ? 'Skor WAZ'
                              : 'Skor BMI ikut umur',
                          style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: scoreBackground,
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Text(
                            zScore!.toStringAsFixed(2),
                            style: TextStyle(
                              color: statusColor,
                              fontSize: 23,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          status,
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          isBmi
                              ? bmiSevereThinness
                                    ? 'BMI jauh di bawah julat sesuai'
                                    : bmiThinness
                                    ? 'BMI di bawah julat sesuai'
                                    : bmiObesity
                                    ? 'BMI jauh di atas julat sesuai'
                                    : bmiOverweight
                                    ? 'BMI di atas julat sesuai'
                                    : bmiAtRisk
                                    ? 'BMI menghampiri julat berlebihan'
                                    : 'BMI dalam julat sesuai'
                              : isHeight
                              ? severe
                                    ? 'Tinggi jauh di bawah julat biasa'
                                    : belowMinusTwo
                                    ? 'Tinggi di bawah julat biasa'
                                    : 'Tinggi dalam julat biasa'
                              : severe
                              ? 'Berat jauh di bawah julat biasa'
                              : belowMinusTwo
                              ? 'Berat di bawah julat biasa'
                              : 'Berat dalam julat biasa',
                          style: TextStyle(color: statusColor, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Bacaan skor ${isHeight
                  ? 'HAZ'
                  : isWeight
                  ? 'WAZ'
                  : 'BMI ikut umur'}',
              style: TextStyle(
                color: growthGreenDark,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isWeight || isBmi ? 8 : 0,
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      'Status',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (isWeight || isBmi) const SizedBox(width: 14),
                  Expanded(
                    flex: 3,
                    child: Text(
                      'Julat skor',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            if (isHeight) ...[
              _hazRangeRow(
                'Tidak bantut',
                'Skor -2 dan ke atas',
                const Color(0xFFE5F5EB),
                bold: !belowMinusTwo,
              ),
              _hazRangeRow(
                'Bantut',
                'Skor antara -3 hingga kurang daripada -2',
                const Color(0xFFFFF2BF),
                bold: belowMinusTwo && !severe,
              ),
              _hazRangeRow(
                'Bantut teruk',
                'Skor kurang daripada -3',
                const Color(0xFFFFE1E5),
                bold: severe,
              ),
            ] else if (isWeight) ...[
              _hazRangeRow(
                'Berat sesuai\numur',
                'Skor -2 dan\nke atas',
                const Color(0xFFE5F5EB),
                bold: !belowMinusTwo,
                columnGap: 14,
                verticalPadding: 8,
              ),
              _hazRangeRow(
                'Kurang berat\nbadan',
                'Skor antara -3 hingga\nkurang daripada -2',
                const Color(0xFFFFF2BF),
                bold: belowMinusTwo && !severe,
                columnGap: 14,
                verticalPadding: 8,
              ),
              _hazRangeRow(
                'Kurang berat\nbadan teruk',
                'Skor kurang daripada\n-3',
                const Color(0xFFFFE1E5),
                bold: severe,
                columnGap: 14,
                verticalPadding: 8,
              ),
            ] else ...[
              _hazRangeRow(
                'Obesiti',
                ageMonths <= 60
                    ? 'Skor lebih daripada +3'
                    : 'Skor lebih daripada +2',
                const Color(0xFFFFE1E5),
                bold: bmiObesity,
                verticalPadding: 7,
              ),
              _hazRangeRow(
                'Berat berlebihan',
                ageMonths <= 60
                    ? 'Skor lebih daripada +2 hingga +3'
                    : 'Skor lebih daripada +1 hingga +2',
                const Color(0xFFFFF2BF),
                bold: bmiOverweight && !bmiObesity,
                verticalPadding: 7,
              ),
              if (ageMonths <= 60)
                _hazRangeRow(
                  'Risiko berat berlebihan',
                  'Skor lebih daripada +1 hingga +2',
                  const Color(0xFFFFF2BF),
                  bold: bmiAtRisk,
                  verticalPadding: 7,
                ),
              _hazRangeRow(
                'BMI sesuai umur',
                'Skor -2 hingga +1',
                const Color(0xFFE5F5EB),
                bold: !bmiThinness && !bmiAtRisk && !bmiOverweight,
                verticalPadding: 7,
              ),
              _hazRangeRow(
                'Kurus',
                'Skor -3 hingga kurang daripada -2',
                const Color(0xFFFFF2BF),
                bold: bmiThinness && !bmiSevereThinness,
                verticalPadding: 7,
              ),
              _hazRangeRow(
                'Terlalu kurus',
                'Skor kurang daripada -3',
                const Color(0xFFFFE1E5),
                bold: bmiSevereThinness,
                verticalPadding: 7,
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _measurementFact(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
      Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
    ],
  );

  Widget _hazRangeRow(
    String range,
    String meaning,
    Color color, {
    required bool bold,
    double columnGap = 0,
    double verticalPadding = 6,
  }) {
    final textStyle = TextStyle(
      fontSize: 12,
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
    );
    final rangeLines = range.split('\n');

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 3),
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: verticalPadding),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(5),
        border: bold
            ? Border.all(color: statusColorFor(color), width: 1.2)
            : null,
      ),
      child: Row(
        crossAxisAlignment: columnGap > 0
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < rangeLines.length; i++)
                  Text(rangeLines[i], style: textStyle),
              ],
            ),
          ),
          SizedBox(width: columnGap),
          Expanded(flex: 3, child: Text(meaning, style: textStyle)),
        ],
      ),
    );
  }

  Color statusColorFor(Color background) =>
      background == const Color(0xFFE5F5EB)
      ? const Color(0xFF32966A)
      : background == const Color(0xFFFFF2BF)
      ? const Color(0xFFE2AC19)
      : const Color(0xFFE77886);
}

String _formatMeasurementDate(String date) {
  final parsed = DateTime.parse(date);
  const months = [
    'Jan',
    'Feb',
    'Mac',
    'Apr',
    'Mei',
    'Jun',
    'Jul',
    'Ogo',
    'Sep',
    'Okt',
    'Nov',
    'Dis',
  ];
  final day = parsed.day.toString().padLeft(2, '0');
  return '$day ${months[parsed.month - 1]} ${parsed.year}';
}

class MonthlyProgress extends StatelessWidget {
  final Map<String, Object?> child;
  final List<Map<String, Object?>> records;
  final Future<String>? reference;
  final bool isWeightForAge;
  final bool isBmiForAge;

  const MonthlyProgress({
    super.key,
    required this.child,
    required this.records,
    required this.reference,
    required this.isWeightForAge,
    required this.isBmiForAge,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Padding(
        padding: EdgeInsets.only(top: 12, bottom: 8),
        child: Text(
          'Perkembangan bulanan',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
      if (records.isEmpty)
        const Card(
          color: Colors.white,
          elevation: 0,
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text('Tambah ukuran untuk melihat perkembangan bulanan.'),
          ),
        )
      else
        FutureBuilder<String>(
          future:
              reference ??
              rootBundle.loadString('assets/who/growth_curves.csv'),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Card(
                color: Colors.white,
                elevation: 0,
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Carta perkembangan tak dapat dimuatkan.'),
                ),
              );
            }
            if (!snapshot.hasData) {
              return const SizedBox(
                height: 230,
                child: Center(child: CircularProgressIndicator()),
              );
            }

            final birth = DateTime.parse(child['birth'] as String);
            final sexValue = (child['sex'] as String? ?? '').toLowerCase();
            final sex = sexValue == 'boy' || sexValue == 'male'
                ? 'boys'
                : 'girls';
            final referenceRows =
                snapshot.data!
                    .trim()
                    .split('\n')
                    .skip(1)
                    .map((line) => line.trim().split(','))
                    .where((row) {
                      if (row.length < 11 ||
                          row[0] !=
                              (isWeightForAge
                                  ? 'weight'
                                  : isBmiForAge
                                  ? 'bmi'
                                  : 'height') ||
                          row[1] != sex) {
                        return false;
                      }
                      final month = int.tryParse(row[3]);
                      return month != null &&
                          row[2] == (month <= 60 ? '2006' : '2007');
                    })
                    .map((row) => row.skip(3).map(double.parse).toList())
                    .toList()
                  ..sort((a, b) => a[0].compareTo(b[0]));

            final points = <_MonthlyGrowthPoint>[];
            final maxAge = isWeightForAge ? 120 : 228;
            for (final record in records) {
              final measuredAt = DateTime.parse(record['date'] as String);
              final age = measuredAt.difference(birth).inDays / (365.2425 / 12);
              final height = (record['height'] as num?)?.toDouble();
              final weight = (record['weight'] as num?)?.toDouble();
              final value = isBmiForAge
                  ? height != null && height > 0 && weight != null
                        ? weight / math.pow(height / 100, 2)
                        : double.nan
                  : (record[isWeightForAge ? 'weight' : 'height'] as num)
                        .toDouble();
              if (age >= 0 && age <= maxAge && value.isFinite) {
                points.add(_MonthlyGrowthPoint(age, value));
              }
            }
            if (points.isEmpty && (isWeightForAge || isBmiForAge)) {
              return Card(
                color: Colors.white,
                elevation: 0,
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    isWeightForAge
                        ? 'Data rujukan berat mengikut umur tidak tersedia selepas 120 bulan.'
                        : 'Rekod tinggi dan berat diperlukan untuk carta BMI.',
                  ),
                ),
              );
            }
            points.sort((a, b) => a.ageMonths.compareTo(b.ageMonths));
            final ageDomain = _monthlyAgeDomain(
              points,
              maxAge: isWeightForAge ? 120 : 228,
            );

            return Card(
              color: Colors.white,
              elevation: 0,
              margin: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: Color(0xFFE5E8EF)),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final chartWidth = math.max(
                      constraints.maxWidth,
                      (ageDomain[1] - ageDomain[0]) * 34 + 94,
                    );
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        height: 250,
                        width: chartWidth,
                        child: CustomPaint(
                          painter: _MonthlyGrowthPainter(
                            referenceRows,
                            points,
                            isWeightForAge: isWeightForAge,
                            isBmiForAge: isBmiForAge,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            );
          },
        ),
    ],
  );
}

class _MonthlyGrowthPoint {
  final double ageMonths;
  final double value;

  const _MonthlyGrowthPoint(this.ageMonths, this.value);
}

List<double> _monthlyAgeDomain(
  List<_MonthlyGrowthPoint> points, {
  int maxAge = 228,
}) {
  if (points.isEmpty) return [0, 10];

  final minAge = points.map((point) => point.ageMonths).reduce(math.min);
  final maxPointAge = points.map((point) => point.ageMonths).reduce(math.max);
  var start = math.max(0, (minAge / 5).floor() * 5).toDouble();
  final end = math
      .min(maxAge, math.max((maxPointAge / 5).ceil() * 5.0, start + 10))
      .toDouble();
  if (end - start < 10) start = math.max(0, end - 10).toDouble();
  return [start, end];
}

class _MonthlyGrowthPainter extends CustomPainter {
  final List<List<double>> rows;
  final List<_MonthlyGrowthPoint> points;
  final bool isWeightForAge;
  final bool isBmiForAge;

  const _MonthlyGrowthPainter(
    this.rows,
    this.points, {
    required this.isWeightForAge,
    required this.isBmiForAge,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (rows.isEmpty || points.isEmpty || size.width <= 0 || size.height <= 0) {
      return;
    }

    final ageDomain = _monthlyAgeDomain(
      points,
      maxAge: isWeightForAge ? 120 : 228,
    );
    final start = ageDomain[0];
    final end = ageDomain[1];
    if (end <= start) return;

    final visibleRows = rows
        .where((row) => row[0] >= start && row[0] <= end)
        .toList();
    if (visibleRows.isEmpty) return;

    final allY = <double>[
      ...visibleRows.expand((row) => row.skip(1)),
      ...points.map((point) => point.value),
    ];
    final yTickStep = isBmiForAge ? 2.0 : 5.0;
    final minY =
        (allY.reduce(math.min) / yTickStep).floor() * yTickStep - yTickStep;
    final maxY = (allY.reduce(math.max) / yTickStep).ceil() * yTickStep;
    final ySpan = math.max(5, maxY - minY).toDouble();
    // Reserve a dedicated gutter for Y-axis labels so they do not cross the
    // vertical axis or crowd the rotated axis title.
    final plot = Rect.fromLTRB(46, 14, size.width - 48, size.height - 48);
    if (plot.width <= 0 || plot.height <= 0) return;

    double x(double month) =>
        plot.left + (month - start) / (end - start) * plot.width;
    double y(double value) =>
        plot.bottom - (value - minY) / ySpan * plot.height;

    List<double> valuesAtMonth(double month) {
      for (var i = 1; i < rows.length; i++) {
        if (rows[i][0] >= month) {
          final lower = rows[i - 1];
          final upper = rows[i];
          final fraction = (month - lower[0]) / (upper[0] - lower[0]);
          return List.generate(
            lower.length,
            (index) => lower[index] + (upper[index] - lower[index]) * fraction,
          );
        }
      }
      return rows.last;
    }

    final gridPaint = Paint()
      ..color = const Color(0xFFE1E5E9)
      ..strokeWidth = 0.8;
    final textStyle = const TextStyle(color: Color(0xFF33383D), fontSize: 10);

    void drawLabel(
      String text,
      Offset center, {
      TextStyle? style,
      bool centered = true,
      bool rightAligned = false,
    }) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style ?? textStyle),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout();
      painter.paint(
        canvas,
        Offset(
          centered
              ? center.dx - painter.width / 2
              : rightAligned
              ? center.dx - painter.width
              : center.dx,
          center.dy - painter.height / 2,
        ),
      );
    }

    for (var value = minY; value <= maxY; value += yTickStep) {
      final yy = y(value);
      canvas.drawLine(Offset(plot.left, yy), Offset(plot.right, yy), gridPaint);
      drawLabel(
        value.toStringAsFixed(0),
        Offset(plot.left - 5, yy),
        centered: false,
        rightAligned: true,
      );
    }

    final firstTick = start.toInt();
    for (var month = firstTick.toDouble(); month <= end; month += 1) {
      final xx = x(month);
      canvas.drawLine(Offset(xx, plot.top), Offset(xx, plot.bottom), gridPaint);
      // Keep the first month label clear of the vertical axis at the origin.
      final labelX = month == firstTick ? xx + 10 : xx;
      drawLabel(
        month.toInt().toString(),
        Offset(labelX, plot.bottom + 11),
        style: const TextStyle(color: Color(0xFF33383D), fontSize: 9),
      );
    }

    final axisPaint = Paint()
      ..color = const Color(0xFF343A40)
      ..strokeWidth = 1.5;
    canvas
      ..drawLine(
        Offset(plot.left, plot.top),
        Offset(plot.left, plot.bottom),
        axisPaint,
      )
      ..drawLine(
        Offset(plot.left, plot.bottom),
        Offset(plot.right, plot.bottom),
        axisPaint,
      );

    canvas.save();
    canvas.clipRect(plot);
    final isUnderFive = end <= 60;
    if (isBmiForAge) {
      Path areaBelowCurve(int curveIndex) {
        final path = Path()
          ..moveTo(x(start), y(valuesAtMonth(start)[curveIndex]));
        for (var month = start + 1; month <= end; month += 1) {
          path.lineTo(x(month), y(valuesAtMonth(month)[curveIndex]));
        }
        return path
          ..lineTo(x(end), plot.bottom)
          ..lineTo(x(start), plot.bottom)
          ..close();
      }

      Path areaAboveCurve(int curveIndex) {
        final path = Path()
          ..moveTo(x(start), y(valuesAtMonth(start)[curveIndex]));
        for (var month = start + 1; month <= end; month += 1) {
          path.lineTo(x(month), y(valuesAtMonth(month)[curveIndex]));
        }
        return path
          ..lineTo(x(end), plot.top)
          ..lineTo(x(start), plot.top)
          ..close();
      }

      canvas
        ..drawPath(areaBelowCurve(2), Paint()..color = const Color(0x55FFDA5C))
        ..drawPath(areaBelowCurve(1), Paint()..color = const Color(0x66F28B9A));
      if (isUnderFive) {
        canvas.drawPath(
          areaAboveCurve(5),
          Paint()..color = const Color(0x33FFDA5C),
        );
      }
      canvas
        ..drawPath(
          areaAboveCurve(isUnderFive ? 6 : 5),
          Paint()..color = const Color(0x55FFDA5C),
        )
        ..drawPath(
          areaAboveCurve(isUnderFive ? 7 : 6),
          Paint()..color = const Color(0x66F28B9A),
        );
    }
    for (var index = 1; index <= 7; index++) {
      final path = Path();
      var isFirst = true;
      for (var month = start; month <= end; month += 1) {
        final values = valuesAtMonth(month);
        final point = Offset(x(month), y(values[index]));
        if (isFirst) {
          path.moveTo(point.dx, point.dy);
          isFirst = false;
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      final isMedian = index == 4;
      final isBmiSevereCutoff = isBmiForAge && index == (isUnderFive ? 7 : 6);
      final isBmiOverweightCutoff =
          isBmiForAge && index == (isUnderFive ? 6 : 5);
      final isBmiAtRiskCutoff = isBmiForAge && isUnderFive && index == 5;
      final curveColor = isMedian
          ? const Color(0xFF32966A)
          : isBmiForAge && (index == 1 || isBmiSevereCutoff)
          ? const Color(0xFFE77886)
          : isBmiForAge && (index == 2 || isBmiOverweightCutoff)
          ? const Color(0xFFE2AC19)
          : isBmiAtRiskCutoff
          ? const Color(0xFFE6C34F)
          : const Color(0xFF9AA3A8);
      canvas.drawPath(
        path,
        Paint()
          ..color = curveColor
          ..style = PaintingStyle.stroke
          ..strokeWidth =
              isMedian ||
                  (isBmiForAge &&
                      (index == 1 ||
                          index == 2 ||
                          isBmiSevereCutoff ||
                          isBmiOverweightCutoff ||
                          isBmiAtRiskCutoff))
              ? 2.2
              : 1.2,
      );
    }

    final sortedPoints = [...points]
      ..sort((a, b) => a.ageMonths.compareTo(b.ageMonths));
    final childPath = Path();
    for (var i = 0; i < sortedPoints.length; i++) {
      final point = sortedPoints[i];
      final position = Offset(x(point.ageMonths), y(point.value));
      if (i == 0) {
        childPath.moveTo(position.dx, position.dy);
      } else {
        childPath.lineTo(position.dx, position.dy);
      }
    }
    canvas.drawPath(
      childPath,
      Paint()
        ..color = const Color(0xFF32966A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2,
    );
    for (final point in sortedPoints) {
      canvas.drawCircle(
        Offset(x(point.ageMonths), y(point.value)),
        4,
        Paint()..color = const Color(0xFF32966A),
      );
    }
    canvas.restore();

    const sdLabels = [
      '-3 SD',
      '-2 SD',
      '-1 SD',
      '0 SD',
      '+1 SD',
      '+2 SD',
      '+3 SD',
    ];
    for (var index = 1; index <= 7; index++) {
      final isBmiSevereCutoff = isBmiForAge && index == (isUnderFive ? 7 : 6);
      final isBmiCutoff =
          isBmiForAge &&
          (index == 1 ||
              index == 2 ||
              isBmiSevereCutoff ||
              index == (isUnderFive ? 6 : 5));
      final labelColor = index == 4
          ? const Color(0xFF216747)
          : isBmiForAge && (index == 1 || isBmiSevereCutoff)
          ? const Color(0xFFD95C6C)
          : isBmiCutoff
          ? const Color(0xFF9A6A00)
          : const Color(0xFF59666B);
      drawLabel(
        sdLabels[index - 1],
        Offset(plot.right + 4, y(valuesAtMonth(end)[index])),
        style: TextStyle(
          color: labelColor,
          fontSize: 10,
          fontWeight: index == 4 ? FontWeight.bold : FontWeight.w600,
        ),
        centered: false,
      );
    }

    drawLabel(
      'Umur (bulan)',
      Offset(plot.center.dx, size.height - 8),
      style: const TextStyle(
        color: Color(0xFF216747),
        fontSize: 11,
        fontWeight: FontWeight.w500,
      ),
    );

    canvas.save();
    canvas.translate(11, plot.center.dy);
    canvas.rotate(-math.pi / 2);
    drawLabel(
      isWeightForAge
          ? 'Berat (kg)'
          : isBmiForAge
          ? 'BMI (kg/m²)'
          : 'Tinggi (cm)',
      Offset.zero,
      style: const TextStyle(
        color: Color(0xFF216747),
        fontSize: 11,
        fontWeight: FontWeight.w500,
      ),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MonthlyGrowthPainter oldDelegate) =>
      oldDelegate.rows != rows ||
      oldDelegate.points != points ||
      oldDelegate.isWeightForAge != isWeightForAge ||
      oldDelegate.isBmiForAge != isBmiForAge;
}

class GrowthReminders {
  static const _channel = MethodChannel('growwell/growth_reminders');

  static final _notifications = FlutterLocalNotificationsPlugin();

  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<void> cancelLegacy() async {
    if (!supported) {
      return;
    }

    try {
      await _notifications.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );

      await _notifications.cancel(id: 731002);
    } catch (_) {
      // The new reminder is scheduled separately; retry on the next launch.
    }
  }

  static Future<bool> schedule({
    required String childId,
    required String childName,
    required String latestDate,
  }) async {
    if (!supported) {
      return false;
    }

    await _notifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );

    await _notifications.cancel(id: 731002);

    final android = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    final allowed = await android?.requestNotificationsPermission();

    await _channel.invokeMethod<void>('schedule', {
      'childId': childId,
      'name': childName,
      'date': latestDate,
    });

    return allowed != false;
  }
}
