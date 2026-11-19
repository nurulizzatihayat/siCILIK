import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'database.dart';

const Color settingCharcoal = Color(0xFF34363B);
const Color settingDark = Color(0xFF24252B);
const Color settingPanel = Color(0xFFF0F1F3);
const Color settingChip = Color(0xFFE5E6E9);
const Color settingMuted = Color(0xFF858891);
const Color settingBorder = Color(0xFFE5E6EA);

class Setting extends StatefulWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  const Setting({
    super.key,
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  @override
  State<Setting> createState() => _SettingState();
}

class _SettingState extends State<Setting> {
  bool _loggingOut = false;

  Future<String> getUserName() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) return 'User';

    final profile = await DatabaseHelper.getProfile(user.uid);

    if (profile == null) return 'User';

    return profile['name'] as String? ?? 'User';
  }

  Future<void> _openWebsite() async {
    final Uri url = Uri.parse('https://YOUR-WEBSITE.com');

    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      debugPrint('Could not open website');
    }
  }

  Future<void> _sendEnquiry() async {
    final Uri url = Uri.parse('https://YOUR-WEBSITE.com');

    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      debugPrint('Could not open website');
    }
  }

  Future<void> _openDietGuide() async {
    final Uri url = Uri.parse('assets/Panduan-Diet-v2026.pdf');

    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      debugPrint('Could not open diet guide');
    }
  }

  Future<void> _logout() async {
    setState(() => _loggingOut = true);

    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tidak dapat log keluar. Sila cuba lagi.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _loggingOut = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: settingCharcoal,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _buildHeader(),

              Expanded(
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(28),
                  ),
                  child: Container(
                    color: settingPanel,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
                      children: [
                        _buildSectionTitle('AKAUN'),
                        const SizedBox(height: 12),

                        _buildAccountCard(),

                        const SizedBox(height: 14),

                        SizedBox(
                          height: 50,
                          child: FilledButton.icon(
                            onPressed: _loggingOut ? null : _logout,
                            icon: _loggingOut
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.logout_rounded),
                            label: Text(
                              _loggingOut ? 'Sedang keluar...' : 'Log Keluar',
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: settingCharcoal,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: settingCharcoal
                                  .withValues(alpha: 0.6),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        _buildSectionTitle('Tetapan Lain'),
                        const SizedBox(height: 12),

                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: settingBorder),
                          ),
                          child: Column(
                            children: [
                              _buildContactTile(
                                icon: Icons.language_rounded,
                                title: 'Laman Web Rasmi',
                                subtitle: 'Semak maklumat lanjut di laman web rasmi kami.',
                                onTap: _openWebsite,
                              ),

                              const Divider(
                                height: 1,
                                indent: 16,
                                endIndent: 16,
                                color: settingBorder,
                              ),

                              _buildContactTile(
                                icon: Icons.email_outlined,
                                title: 'Hantaran Pertanyaan',
                                subtitle: 'Hubungi orang yang bertanggungjawab untuk bertanya soalan.',
                                onTap: _sendEnquiry,
                              ),

                              const Divider(
                                height: 1,
                                indent: 16,
                                endIndent: 16,
                                color: settingBorder,
                              ),

                              _buildContactTile(
                                icon: Icons.book_outlined,
                                title: 'Panduan Diet',
                                subtitle: 'Baca panduan diet yang lengkap.',
                                onTap: _openDietGuide,
                              ),

                              const Divider(
                                height: 1,
                                indent: 16,
                                endIndent: 16,
                                color: settingBorder,
                              ),

                              _buildContactTile(
                                icon: Icons.info_outline_rounded,
                                title: 'Tentang',
                                subtitle: 'Memastikan tumbesaran anak anda sihat dan ibu bapa gembira.',
                                onTap: () {
                                  showAboutDialog(
                                    context: context,
                                    applicationName: 'siCILIK',
                                    applicationVersion: '1.0.0',
                                    applicationLegalese: 'Mula mengurus tumbesaran anak anda hari ini!',
                                  );
                                },
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 28),

                        const Center(
                          child: Text(
                            'Mula mengurus tumbesaran anak anda hari ini!',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: settingMuted, fontSize: 12),
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
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 24,
            backgroundColor: Colors.white,
            child: Icon(
              Icons.settings_rounded,
              color: settingCharcoal,
              size: 24,
            ),
          ),

          const SizedBox(width: 12),

          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tetapan',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Urus akaun dan tetapan anda.',
                  style: TextStyle(color: Colors.white, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.bold,
        color: settingMuted,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _buildAccountCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: settingBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: settingChip,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.person_outline_rounded,
              color: settingCharcoal,
              size: 26,
            ),
          ),

          const SizedBox(width: 14),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Log masuk sebagai',
                  style: TextStyle(color: settingMuted, fontSize: 12),
                ),
                const SizedBox(height: 5),

                FutureBuilder<String>(
                  future: getUserName(),
                  builder: (context, snapshot) {
                    final user = FirebaseAuth.instance.currentUser;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          snapshot.data ?? 'Loading...',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: settingDark,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          user?.email ?? 'No email available',
                          style: const TextStyle(
                            fontSize: 12,
                            color: settingMuted,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: settingBorder),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Icon(icon, color: settingCharcoal),
        title: Text(
          title,
          style: const TextStyle(
            color: settingDark,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(color: settingMuted, fontSize: 12),
        ),
        trailing: const Icon(Icons.chevron_right_rounded, color: settingMuted),
        onTap: onTap,
      ),
    );
  }

  Widget _buildContactTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Icon(icon, color: settingCharcoal),
      title: Text(
        title,
        style: const TextStyle(
          color: settingDark,
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: settingMuted, fontSize: 12),
      ),
      trailing: const Icon(Icons.chevron_right_rounded, color: settingMuted),
      onTap: onTap,
    );
  }
}
