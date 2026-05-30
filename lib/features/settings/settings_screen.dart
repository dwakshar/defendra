import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../core/theme/colors.dart';
import '../../core/theme/typography.dart';
import '../../data/models/scan_record.dart';
import '../onboarding/onboarding_screen.dart';
import 'privacy_screen.dart';
import 'settings_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: context.dCanvas,
      appBar: AppBar(title: const Text('SETTINGS')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
        children: [
          _SectionLabel('DETECTION'),
          const SizedBox(height: 8),
          _SensitivityCard(),
          const SizedBox(height: 24),

          _SectionLabel('PREFERENCES'),
          const SizedBox(height: 8),
          _SettingsCard(children: [_LanguageRow()]),
          const SizedBox(height: 24),

          _SectionLabel('WHITELIST'),
          const SizedBox(height: 8),
          _WhitelistCard(),
          const SizedBox(height: 24),

          _SectionLabel('APPEARANCE'),
          const SizedBox(height: 8),
          _SettingsCard(children: [_LightModeRow()]),
          const SizedBox(height: 24),

          _SectionLabel('DATA'),
          const SizedBox(height: 8),
          _SettingsCard(children: [
            _ExportRow(),
            _CardDivider(),
            _FactoryResetRow(),
          ]),
          const SizedBox(height: 24),

          _SettingsCard(children: [_PrivacyLinkRow()]),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sensitivity card — slider + live value
// ---------------------------------------------------------------------------

class _SensitivityCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final threshold = ref.watch(sensitivityProvider);

    return Container(
      decoration: BoxDecoration(
        color: context.dCard,
        border: Border.all(color: context.dBorder, width: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Notification threshold', style: context.dtBody),
              const Spacer(),
              Text(
                threshold.toStringAsFixed(2),
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: context.dText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Scam alerts fire above this confidence score',
            style: context.dtMonoSmall,
          ),
          const SizedBox(height: 8),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: context.dText,
              inactiveTrackColor: context.dBorder,
              thumbColor: context.dText,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              trackHeight: 1.0,
              overlayShape: SliderComponentShape.noOverlay,
            ),
            child: Slider(
              value: threshold,
              min: 0.50,
              max: 1.00,
              divisions: 10,
              onChanged: (v) =>
                  ref.read(sensitivityProvider.notifier).set(v),
            ),
          ),
          Row(
            children: [
              Text('0.50', style: context.dtMonoSmall),
              const Spacer(),
              Text('1.00', style: context.dtMonoSmall),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Language row
// ---------------------------------------------------------------------------

class _LanguageRow extends ConsumerWidget {
  static const _options = [
    ('auto', 'Auto'),
    ('en', 'English'),
    ('hi', 'हिंदी'),
    ('hinglish', 'Hinglish'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(languageProvider);
    final label = _options
        .firstWhere((o) => o.$1 == lang, orElse: () => _options.first)
        .$2;

    return _TapRow(
      label: 'Language',
      value: label,
      onTap: () => _showPicker(context, ref, lang),
    );
  }

  void _showPicker(BuildContext context, WidgetRef ref, String current) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: context.dCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: context.dBorder, width: 0.5),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Text('Language', style: context.dtMonoSmall),
              ),
              Container(height: 0.5, color: context.dBorder),
              for (final opt in _options) ...[
                InkWell(
                  onTap: () {
                    ref.read(languageProvider.notifier).set(opt.$1);
                    Navigator.pop(ctx);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    child: Row(
                      children: [
                        Text(opt.$2, style: context.dtBody),
                        const Spacer(),
                        if (opt.$1 == current)
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: context.dMuted,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (opt != _options.last)
                  Container(height: 0.5, color: context.dBorder),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Whitelist card
// ---------------------------------------------------------------------------

class _WhitelistCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final senders = ref.watch(whitelistProvider);

    return Container(
      decoration: BoxDecoration(
        color: context.dCard,
        border: Border.all(color: context.dBorder, width: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (senders.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Text(
                'No senders whitelisted',
                style: context.dtMonoSmall,
              ),
            ),
          for (final sender in senders) ...[
            _WhitelistSenderRow(
              sender: sender,
              onRemove: () =>
                  ref.read(whitelistProvider.notifier).remove(sender),
            ),
            _CardDivider(),
          ],
          InkWell(
            onTap: () => _showAddDialog(context, ref),
            borderRadius: BorderRadius.vertical(
              top: senders.isEmpty ? const Radius.circular(8) : Radius.zero,
              bottom: const Radius.circular(8),
            ),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Text('Add sender', style: context.dtBody),
                  const Spacer(),
                  Icon(Icons.add, size: 16, color: context.dMuted),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddDialog(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: context.dCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: context.dBorder, width: 0.5),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Add sender', style: context.dtMono),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                style: context.dtMono.copyWith(fontSize: 13),
                cursorColor: context.dMuted,
                decoration: InputDecoration(
                  hintText: 'e.g. HDFCBK, AD-SBIUPI',
                  hintStyle: context.dtMonoSmall,
                  filled: true,
                  fillColor: context.dSurface,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide:
                        BorderSide(color: context.dBorder, width: 0.5),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide:
                        BorderSide(color: context.dMuted, width: 0.5),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: TextButton.styleFrom(
                        foregroundColor: context.dMuted),
                    child: Text('Cancel', style: context.dtMonoSmall),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () {
                      ref
                          .read(whitelistProvider.notifier)
                          .add(controller.text);
                      Navigator.pop(ctx);
                    },
                    style: TextButton.styleFrom(
                        foregroundColor: context.dText),
                    child: Text(
                      'Add',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: context.dText,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    controller.dispose();
  }
}

class _WhitelistSenderRow extends StatelessWidget {
  const _WhitelistSenderRow(
      {required this.sender, required this.onRemove});
  final String sender;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Text(
            sender,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: context.dText,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: onRemove,
            child: Icon(Icons.close, size: 14, color: context.dMuted),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Light mode row
// ---------------------------------------------------------------------------

class _LightModeRow extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(lightModeProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Text('Light mode', style: context.dtBody),
          const Spacer(),
          Text(
            enabled ? 'on' : 'off',
            style: context.dtMonoSmall,
          ),
          const SizedBox(width: 12),
          Switch(
            value: enabled,
            onChanged: (_) =>
                ref.read(lightModeProvider.notifier).toggle(),
            activeThumbColor: context.dText,
            activeTrackColor: context.dMuted,
            inactiveThumbColor: context.dMuted,
            inactiveTrackColor: context.dBorder,
            trackOutlineColor:
                WidgetStateProperty.all(Colors.transparent),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Export row
// ---------------------------------------------------------------------------

class _ExportRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return _TapRow(
      label: 'Export JSON',
      value: 'scan history → clipboard',
      onTap: () => _export(context),
    );
  }

  Future<void> _export(BuildContext context) async {
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(VerdictAdapter());
    if (!Hive.isAdapterRegistered(1)) { Hive.registerAdapter(ScanRecordAdapter()); }
    final box = await Hive.openBox<ScanRecord>('scan_results');
    final records = box.values.toList();

    final json = jsonEncode(records
        .map((r) => {
              'id': r.id,
              'sender': r.sender,
              'body': r.body,
              'verdict': r.verdict.name,
              'confidence': r.confidence,
              'triggeredRules': r.triggeredRules,
              'category': r.category,
              'timestamp': r.timestamp.toIso8601String(),
              'simSlot': r.simSlot,
            })
        .toList());

    await Clipboard.setData(ClipboardData(text: json));
    if (context.mounted) {
      _showSnack(context, '${records.length} records copied to clipboard');
    }
  }

  void _showSnack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: context.dtMonoSmall),
        backgroundColor: context.dCard,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(color: context.dBorder, width: 0.5),
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Factory reset row
// ---------------------------------------------------------------------------

class _FactoryResetRow extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      onTap: () => _confirm(context, ref),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Text(
              'Factory reset',
              style:
                  context.dtBody.copyWith(color: DefendraColors.scam),
            ),
            const Spacer(),
            Text('clear all data', style: context.dtMonoSmall),
          ],
        ),
      ),
    );
  }

  Future<void> _confirm(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: context.dCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: context.dBorder, width: 0.5),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Reset all data?', style: context.dtMono),
              const SizedBox(height: 8),
              Text(
                'Permanently deletes all scan history and resets all '
                'settings. This cannot be undone.',
                style: context.dtMonoSmall,
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    style: TextButton.styleFrom(
                        foregroundColor: context.dMuted),
                    child: Text('Cancel', style: context.dtMonoSmall),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: TextButton.styleFrom(
                        foregroundColor: DefendraColors.scam),
                    child: Text(
                      'Reset',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: DefendraColors.scam,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed != true || !context.mounted) return;

    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(VerdictAdapter());
    if (!Hive.isAdapterRegistered(1)) { Hive.registerAdapter(ScanRecordAdapter()); }
    final scanBox = await Hive.openBox<ScanRecord>('scan_results');
    await scanBox.clear();
    await Hive.box('settings').clear();

    ref.invalidate(sensitivityProvider);
    ref.invalidate(languageProvider);
    ref.invalidate(whitelistProvider);
    ref.invalidate(lightModeProvider);

    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const OnboardingScreen()),
      (_) => false,
    );
  }
}

// ---------------------------------------------------------------------------
// Privacy link row
// ---------------------------------------------------------------------------

class _PrivacyLinkRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return _TapRow(
      label: 'Privacy',
      value: 'no data leaves your phone',
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const PrivacyScreen()),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared layout primitives
// ---------------------------------------------------------------------------

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: context.dtMonoSmall);
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: context.dCard,
        border: Border.all(color: context.dBorder, width: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _CardDivider extends StatelessWidget {
  const _CardDivider();

  @override
  Widget build(BuildContext context) =>
      Container(height: 0.5, color: context.dBorder);
}

class _TapRow extends StatelessWidget {
  const _TapRow(
      {required this.label, this.value, required this.onTap});
  final String label;
  final String? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Text(label, style: context.dtBody),
            const Spacer(),
            if (value != null) Text(value!, style: context.dtMonoSmall),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, size: 16, color: context.dMuted),
          ],
        ),
      ),
    );
  }
}
