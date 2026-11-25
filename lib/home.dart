import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'database.dart';

class HomeScreen extends StatefulWidget {
  final String ownerId;
  final ValueChanged<int> onNavigate;

  const HomeScreen({
    super.key,
    required this.ownerId,
    required this.onNavigate,
  });

  static const Color headerBlue = Color(0xFF1E88E5);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GrowthRepository repo = GrowthRepository();

  List<Map<String, Object?>> children = [];
  Map<String, Object?>? selectedChild;
  Map<String, Object?>? latestMeasurement;

  bool loading = true;
  bool saving = false;
  String? error;
  double? haz;

  @override
  void initState() {
    super.initState();
    loadChildren();
  }

  Future<void> loadChildren({String? selectId}) async {
    if (!mounted) return;

    setState(() {
      loading = true;
      error = null;
    });

    try {
      final result = await repo.children(widget.ownerId);

      result.sort(
        (a, b) => (a['name'] ?? '').toString().toLowerCase().compareTo(
          (b['name'] ?? '').toString().toLowerCase(),
        ),
      );

      Map<String, Object?>? current;

      if (result.isNotEmpty) {
        current = result.firstWhere(
          (c) => c['id'] == selectId,
          orElse: () => result.firstWhere(
            (c) => c['id'] == selectedChild?['id'],
            orElse: () => result.first,
          ),
        );
      }

      List<Map<String, Object?>> measurements = [];

      if (current != null) {
        measurements = await repo.measurements(
          widget.ownerId,
          current['id'].toString(),
        );
      }

      measurements.sort((a, b) {
        final dateA =
            DateTime.tryParse((a['date'] ?? '').toString()) ?? DateTime(1900);

        final dateB =
            DateTime.tryParse((b['date'] ?? '').toString()) ?? DateTime(1900);

        return dateB.compareTo(dateA);
      });

      final newest = measurements.isNotEmpty ? measurements.first : null;

      double? calculatedHaz;

      if (current != null && newest != null) {
        final height = (newest['height'] as num?)?.toDouble();

        if (height != null && height > 0) {
          final csv = await rootBundle.loadString(
            'assets/who/growth_curves.csv',
          );

          calculatedHaz = calculateHaz(csv, current, height);
        }
      }

      if (!mounted) return;

      setState(() {
        children = result;
        selectedChild = current;
        latestMeasurement = newest;
        haz = calculatedHaz;
        loading = false;
      });
    } catch (e) {
      debugPrint('Growth load failed: $e');

      if (!mounted) return;

      setState(() {
        error = e.toString();
        loading = false;
      });
    }
  }

  double? calculateHaz(String csv, Map<String, Object?> child, double height) {
    final birth = DateTime.tryParse((child['birth'] ?? '').toString());

    if (birth == null) return null;

    final now = DateTime.now();

    final months = (now.year - birth.year) * 12 + now.month - birth.month;

    if (months < 0 || months > 228) return null;

    final sex = (child['sex'] ?? '').toString().toLowerCase();

    final tableSex = sex == 'boy' || sex == 'male' ? 'boys' : 'girls';

    final year = months <= 60 ? '2006' : '2007';

    final rows = csv.split(RegExp(r'\r?\n'));

    for (final line in rows) {
      final r = line.split(',');

      if (r.length < 11) continue;

      if (r[0].trim() != 'height') continue;
      if (r[1].trim() != tableSex) continue;
      if (r[2].trim() != year) continue;

      final month = int.tryParse(r[3].trim());

      if (month != months) continue;

      final sd = r
          .sublist(4, 11)
          .map((v) => double.tryParse(v.trim()))
          .toList();

      if (sd.any((v) => v == null)) return null;

      final values = sd.cast<double>();

      if (height <= values.first) {
        return -3;
      }

      if (height >= values.last) {
        return 3;
      }

      for (int i = 0; i < values.length - 1; i++) {
        if (height >= values[i] && height <= values[i + 1]) {
          final fraction = (height - values[i]) / (values[i + 1] - values[i]);

          return (i - 3) + fraction;
        }
      }
    }

    return null;
  }

  String get ageText {
    if (selectedChild == null) return '';

    final birth = DateTime.tryParse((selectedChild!['birth'] ?? '').toString());

    if (birth == null) return 'Umur tidak diketahui';

    final now = DateTime.now();

    int months = (now.year - birth.year) * 12 + now.month - birth.month;

    if (now.day < birth.day) months--;

    if (months < 0) return 'Umur tidak diketahui';

    return '$months bulan';
  }

  GrowthStatus get growthStatus {
    if (haz == null) return GrowthStatus.normal;

    if (haz! < -3) {
      return GrowthStatus.severeStunting;
    }

    if (haz! < -2) {
      return GrowthStatus.stunting;
    }

    return GrowthStatus.normal;
  }

  Future<void> openChildDialog({Map<String, Object?>? existing}) async {
    final nameController = TextEditingController(
      text: existing?['name']?.toString() ?? '',
    );

    DateTime? birth = existing == null
        ? null
        : DateTime.tryParse(existing['birth']?.toString() ?? '');

    String sex = existing?['sex']?.toString() ?? 'boy';

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(existing == null ? 'Tambah Anak' : 'Kemas Kini Anak'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Nama anak',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.calendar_month),
                      title: Text(
                        birth == null
                            ? 'Pilih tarikh lahir'
                            : '${birth!.day}/${birth!.month}/${birth!.year}',
                      ),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: dialogContext,
                          initialDate: birth ?? DateTime.now(),
                          firstDate: DateTime(2000),
                          lastDate: DateTime.now(),
                        );

                        if (picked != null) {
                          setDialogState(() {
                            birth = picked;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: sex,
                      decoration: const InputDecoration(
                        labelText: 'Jantina',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'boy', child: Text('Lelaki')),
                        DropdownMenuItem(value: 'girl', child: Text('Perempuan')),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() {
                            sex = value;
                          });
                        }
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Batal'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (nameController.text.trim().isEmpty || birth == null) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Sila masukkan nama dan tarikh lahir.',
                          ),
                        ),
                      );
                      return;
                    }

                    Navigator.pop(dialogContext, {
                      'name': nameController.text.trim(),
                      'birth':
                          '${birth!.year}-${birth!.month.toString().padLeft(2, '0')}-${birth!.day.toString().padLeft(2, '0')}',
                      'sex': sex,
                    });
                  },
                  child: Text(existing == null ? 'Tambah' : 'Simpan'),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();

    if (result == null || !mounted) return;

    setState(() => saving = true);

    try {
      if (existing == null) {
        final newId = await repo.addChild(
          widget.ownerId,
          result['name'],
          result['birth'],
          result['sex'],
        );

        await loadChildren(selectId: newId);
      } else {
        await repo.updateChild(
          widget.ownerId,
          existing['id'].toString(),
          result['name'],
          result['birth'],
          result['sex'],
        );

        await loadChildren(selectId: existing['id'].toString());
      }
    } catch (e) {
      debugPrint('Child save failed: $e');

      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal menyimpan maklumat anak: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => saving = false);
      }
    }
  }

  Widget addChildCard() {
    return Card(
      elevation: 1,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: saving ? null : () => openChildDialog(),
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: Color(0xFFE3F0FD),
                child: Icon(
                  Icons.person_add_alt_1,
                  color: HomeScreen.headerBlue,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tambah Anak',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      'Tambah anak lain untuk memantau tumbesaran mereka.',
                      style: TextStyle(color: Colors.black54, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Icon(Icons.add_circle_outline, color: HomeScreen.headerBlue),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HomeScreen.headerBlue,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const _Header(),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: Color(0xFFF5F8FC),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: loading
                    ? const Center(child: CircularProgressIndicator())
                    : error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.error_outline,
                                color: Colors.red,
                                size: 42,
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Gagal memuatkan data tumbesaran.',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              Text(error!, textAlign: TextAlign.center),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: loadChildren,
                                child: const Text('Cuba Lagi'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (children.isNotEmpty) ...[
                              const Text(
                                'Pilih Anak',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: children.map((c) {
                                  final selected =
                                      c['id'] == selectedChild?['id'];

                                  return ChoiceChip(
                                    label: Text(
                                      c['name']?.toString() ?? 'Anak',
                                    ),
                                    selected: selected,
                                    onSelected: (_) {
                                      loadChildren(
                                        selectId: c['id'].toString(),
                                      );
                                    },
                                  );
                                }).toList(),
                              ),
                              const SizedBox(height: 16),
                              ProfileCard(
                                name: selectedChild?['name']?.toString() ?? '',
                                age: ageText,
                                gender: switch (selectedChild?['sex']?.toString()) {
                                  'boy' => 'Lelaki',
                                  'girl' => 'Perempuan',
                                  final s => s ?? '',
                                },
                                onEditPressed: () {
                                  openChildDialog(existing: selectedChild);
                                },
                              ),
                            ] else ...[
                              const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(20),
                                  child: Text(
                                    'Anda belum menambah anak.',
                                    style: TextStyle(fontSize: 16),
                                  ),
                                ),
                              ),
                            ],

                            const SizedBox(height: 16),
                            addChildCard(),

                            if (selectedChild != null) ...[
                              const SizedBox(height: 24),
                              IntrinsicHeight(
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: MeasurementTile(
                                        label: 'Tinggi',
                                        value:
                                            latestMeasurement?['height'] == null
                                            ? '--'
                                            : '${(latestMeasurement!['height'] as num).toStringAsFixed(1)} cm',
                                        subtitle: 'Terkini',
                                      ),
                                    ),
                                    const VerticalDivider(width: 1),
                                    Expanded(
                                      child: MeasurementTile(
                                        label: 'Berat',
                                        value:
                                            latestMeasurement?['weight'] == null
                                            ? '--'
                                            : '${(latestMeasurement!['weight'] as num).toStringAsFixed(1)} kg',
                                        subtitle: 'Terkini',
                                      ),
                                    ),
                                    const VerticalDivider(width: 1),
                                    Expanded(
                                      child: MeasurementTile(
                                        label: 'BMI',
                                        value:
                                            latestMeasurement?['height'] ==
                                                    null ||
                                                latestMeasurement?['weight'] ==
                                                    null
                                            ? '--'
                                            : ((latestMeasurement!['weight']
                                                              as num)
                                                          .toDouble() /
                                                      (((latestMeasurement!['height']
                                                                      as num)
                                                                  .toDouble() /
                                                              100) *
                                                          ((latestMeasurement!['height']
                                                                      as num)
                                                                  .toDouble() /
                                                              100)))
                                                  .toStringAsFixed(1),
                                        subtitle: 'Dikira',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 24),
                              const Text(
                                'Status Tumbesaran (Tinggi Mengikut Umur)',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 12),
                              if (haz != null)
                                GrowthStatusCard(
                                  title: growthStatus.title,
                                  zScoreText:
                                      'Skor-Z Tinggi Mengikut Umur (HAZ): ${haz!.toStringAsFixed(1)}',
                                  rangeText: growthStatus.rangeText,
                                  color: growthStatus.color,
                                )
                              else
                                const Text(
                                  'Status tumbesaran tidak tersedia. Sila semak tarikh lahir, ukuran dan data tumbesaran WHO.',
                                  style: TextStyle(color: Colors.black54),
                                ),
                              const SizedBox(height: 12),
                              const RecommendedActionCard(
                                message: 'Sediakan makanan berkhasiat dan pantau tumbesaran secara berkala. Dapatkan nasihat profesional kesihatan untuk penilaian lanjut.',
                              ),
                              const SizedBox(height: 20),
                              const HomeCarousel(
                                images: [
                                  'assets/carousel/Tip Bantut.png',
                                  'assets/carousel/Tip KZM.png',
                                  'assets/carousel/Keperluan Tidur_.png',
                                  'assets/carousel/Keperluan Aktiviti Fizikal.png',
                                ],
                              ),
                              const SizedBox(height: 20),
                              GridView.count(
                                crossAxisCount: 2,
                                childAspectRatio: 1.6,
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                mainAxisSpacing: 12,
                                crossAxisSpacing: 12,
                                children: [
                                  QuickActionButton(
                                    label: 'Carta Tumbesaran',
                                    icon: Icons.bar_chart,
                                    color: const Color(0xFF1E88E5),
                                    onTap: () => widget.onNavigate(1),
                                  ),
                                  QuickActionButton(
                                    label: 'Pelan Makanan',
                                    icon: Icons.restaurant,
                                    color: const Color(0xFF2EA862),
                                    onTap: () => widget.onNavigate(2),
                                  ),
                                  QuickActionButton(
                                    label: 'Resipi Sihat',
                                    icon: Icons.menu_book,
                                    color: const Color(0xFF7E57C2),
                                    onTap: () => widget.onNavigate(3),
                                  ),
                                  QuickActionButton(
                                    label: 'Tetapan',
                                    icon: Icons.settings,
                                    color: const Color(0xFF607D8B),
                                    onTap: () => widget.onNavigate(4),
                                  ),
                                ],
                              ),
                            ],
                            if (saving)
                              const Padding(
                                padding: EdgeInsets.all(12),
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              ),
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
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 24,
            backgroundColor: Colors.white,
            child: Icon(Icons.eco, color: HomeScreen.headerBlue),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'siCILIK',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Aplikasi untuk melihat progres anak anda!',
                  style: TextStyle(color: Colors.white, fontSize: 13),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.notifications_none, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

enum GrowthStatus {
  normal(
    'Tumbesaran Normal',
    'Dalam julat normal (HAZ ≥ -2 SD)',
    Color(0xFF2E9E5B),
  ),
  stunting(
    'Bantut Dikesan',
    'Bawah -2 SD (julat bantut)',
    Color(0xFFD32F2F),
  ),
  severeStunting(
    'Bantut Teruk Dikesan',
    'Bawah -3 SD (julat bantut teruk)',
    Color(0xFFB71C1C),
  );

  final String title;
  final String rangeText;
  final Color color;

  const GrowthStatus(this.title, this.rangeText, this.color);
}

// child profile

class ChildProfile {
  final String name;
  final int ageYears;
  final int ageMonths;
  final String gender;
  final double heightCm;
  final double weightKg;
  final double haz; // Height-for-Age Z-score

  const ChildProfile({
    required this.name,
    required this.ageYears,
    required this.ageMonths,
    required this.gender,
    required this.heightCm,
    required this.weightKg,
    required this.haz,
  });

  // Temporary sample data, matching the design
  static const ChildProfile adam = ChildProfile(
    name: 'Adam',
    ageYears: 4,
    ageMonths: 2,
    gender: 'Lelaki',
    heightCm: 92.0,
    weightKg: 13.5,
    haz: -2.4,
  );

  String get ageText => '$ageYears tahun $ageMonths bulan';

  double get bmi => weightKg / ((heightCm / 100) * (heightCm / 100));

  GrowthStatus get status {
    if (haz < -3) return GrowthStatus.severeStunting;
    if (haz < -2) return GrowthStatus.stunting;
    return GrowthStatus.normal;
  }
}

//growthstatuscard

class GrowthStatusCard extends StatelessWidget {
  final String title;
  final String zScoreText;
  final String rangeText;
  final Color color;

  const GrowthStatusCard({
    super.key,
    required this.title,
    required this.zScoreText,
    required this.rangeText,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.accessibility_new, size: 44, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  zScoreText,
                  style: TextStyle(color: color, fontWeight: FontWeight.w600),
                ),
                Text(rangeText),
              ],
            ),
          ),
          Icon(Icons.info, size: 20, color: color),
        ],
      ),
    );
  }
}

//measurement tile

class MeasurementTile extends StatelessWidget {
  final String label;
  final String value;
  final String subtitle;
  final Color? badgeColor; // if set, the subtitle is shown as a colored pill

  const MeasurementTile({
    super.key,
    required this.label,
    required this.value,
    required this.subtitle,
    this.badgeColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.black54, fontSize: 14),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        if (badgeColor != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            decoration: BoxDecoration(
              color: badgeColor!.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              subtitle,
              style: TextStyle(
                color: badgeColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          )
        else
          Text(
            subtitle,
            style: const TextStyle(color: Colors.black45, fontSize: 13),
          ),
      ],
    );
  }
}

//quick action button

class QuickActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const QuickActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 1,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: Colors.white, size: 26),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

//recommended action card

class RecommendedActionCard extends StatelessWidget {
  final String message;

  const RecommendedActionCard({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1CC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF3DC9A)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.medical_services_outlined,
            size: 40,
            color: Color(0xFFE0A100),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Tindakan Disyorkan',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(message, style: const TextStyle(fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

//profile card

class ProfileCard extends StatelessWidget {
  final String name;
  final String age;
  final String gender;
  final VoidCallback? onEditPressed;

  const ProfileCard({
    super.key,
    required this.name,
    required this.age,
    required this.gender,
    this.onEditPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const CircleAvatar(
          radius: 36,
          backgroundColor: Color(0xFFD6E6F7),
          // Placeholder. Swap for backgroundImage: AssetImage('assets/adam.png') later.
          child: Icon(Icons.person, size: 40, color: Color(0xFF1E88E5)),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(age, style: const TextStyle(color: Colors.black54)),
              Text(gender, style: const TextStyle(color: Colors.black54)),
            ],
          ),
        ),
        TextButton.icon(
          onPressed: onEditPressed,
          icon: const Icon(Icons.edit, size: 16),
          label: const Text('Kemas Kini Profil'),
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF1E88E5),
            backgroundColor: const Color(0xFFE3F0FD),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ),
      ],
    );
  }
}

/// Auto-sliding carousel of tall infographic images, shown whole (no cropping).
class HomeCarousel extends StatefulWidget {
  final List<String> images;
  final Duration interval;

  const HomeCarousel({
    super.key,
    required this.images,
    this.interval = const Duration(seconds: 5),
  });

  @override
  State<HomeCarousel> createState() => _HomeCarouselState();
}

class _HomeCarouselState extends State<HomeCarousel> {
  final _controller = PageController();
  Timer? _timer;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _restartTimer();
  }

  // Restarted after every page change so a manual swipe gets a full interval.
  void _restartTimer() {
    _timer?.cancel();
    if (widget.images.length < 2) return;
    _timer = Timer(widget.interval, () {
      if (!mounted || !_controller.hasClients) return;
      _controller.animateToPage(
        (_page + 1) % widget.images.length,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);

    return Column(
      children: [
        // Images are 2:3 portrait; match that so they fill the slide exactly.
        AspectRatio(
          aspectRatio: 2 / 3,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: LayoutBuilder(
              builder: (context, constraints) => PageView.builder(
                controller: _controller,
                itemCount: widget.images.length,
                onPageChanged: (i) {
                  setState(() => _page = i);
                  _restartTimer();
                },
                itemBuilder: (context, i) => ColoredBox(
                  color: Colors.white,
                  child: Image.asset(
                    widget.images[i],
                    fit: BoxFit.contain,
                    // Decode at display size; the source files are ~2 MB each.
                    cacheWidth: (constraints.maxWidth * dpr).round(),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < widget.images.length; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: i == _page ? 20 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: i == _page
                      ? const Color(0xFF1E88E5)
                      : Colors.black26,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
