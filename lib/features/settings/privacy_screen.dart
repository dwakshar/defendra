import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/colors.dart';
import '../../core/theme/typography.dart';

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DefendraColors.canvas,
      appBar: AppBar(title: const Text('PRIVACY')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 48),
        children: [
          // Headline statement
          Text(
            'No data leaves\nyour phone.',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 28,
              fontWeight: FontWeight.w500,
              color: DefendraColors.text,
              height: 1.2,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'The model runs locally. Open source.',
            style: DefendraType.mono.copyWith(color: DefendraColors.muted),
          ),
          const SizedBox(height: 28),

          // Architecture guarantee
          _PrivacyCard(
            children: [
              _Bullet(
                text:
                    'No network layer in the architecture — there is no HTTP '
                    'client, no API endpoint, no background sync service. '
                    'The privacy guarantee is structural, not policy-based.',
              ),
              _CardDivider(),
              _Bullet(
                text:
                    'SMS text is processed in-process memory, scored by the '
                    'on-device TFLite model, then discarded. The verdict and '
                    'metadata are stored locally in a Hive database.',
              ),
              _CardDivider(),
              _Bullet(
                text:
                    'No analytics SDK, no crash reporter, no ad framework. '
                    'Zero third-party data egress.',
              ),
            ],
          ),
          const SizedBox(height: 20),

          // What is stored
          _SectionLabel('STORED ON-DEVICE'),
          const SizedBox(height: 8),
          _PrivacyCard(
            children: [
              _StorageRow(key_: 'scan_results', value: 'Hive box — sender, body, verdict, timestamp'),
              _CardDivider(),
              _StorageRow(key_: 'settings', value: 'Hive box — threshold, language, whitelist'),
            ],
          ),
          const SizedBox(height: 20),

          // Permissions
          _SectionLabel('PERMISSIONS USED'),
          const SizedBox(height: 8),
          _PrivacyCard(
            children: [
              _StorageRow(key_: 'READ_SMS', value: 'Scan incoming message body'),
              _CardDivider(),
              _StorageRow(key_: 'RECEIVE_SMS', value: 'Intercept SMS as it arrives'),
              _CardDivider(),
              _StorageRow(key_: 'POST_NOTIFICATIONS', value: 'Alert on high-confidence scam'),
            ],
          ),
          const SizedBox(height: 20),

          // Source / distribution
          _SectionLabel('DISTRIBUTION'),
          const SizedBox(height: 8),
          _PrivacyCard(
            children: [
              _LinkRow(
                label: 'Source code',
                url: 'github.com/defendra/defendra',
                onCopy: () => Clipboard.setData(
                  const ClipboardData(text: 'https://github.com/defendra/defendra'),
                ),
              ),
              _CardDivider(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Text(
                  'Distributed as a direct APK and via F-Droid. '
                  'No Play Store build. No Google Play Services dependency.',
                  style: DefendraType.monoSmall,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared sub-widgets
// ---------------------------------------------------------------------------

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: DefendraType.monoSmall);
  }
}

class _PrivacyCard extends StatelessWidget {
  const _PrivacyCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: DefendraColors.card,
        border: Border.all(color: DefendraColors.border, width: 0.5),
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
      Container(height: 0.5, color: DefendraColors.border);
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              width: 4,
              height: 4,
              decoration: const BoxDecoration(
                color: DefendraColors.muted,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: DefendraType.monoSmall),
          ),
        ],
      ),
    );
  }
}

class _StorageRow extends StatelessWidget {
  const _StorageRow({required this.key_, required this.value});
  final String key_;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              key_,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: DefendraColors.text,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: DefendraType.monoSmall),
          ),
        ],
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({
    required this.label,
    required this.url,
    required this.onCopy,
  });
  final String label;
  final String url;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Text(label, style: DefendraType.body),
          const Spacer(),
          GestureDetector(
            onTap: () {
              onCopy();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('URL copied', style: DefendraType.monoSmall),
                  backgroundColor: DefendraColors.card,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                    side: const BorderSide(
                        color: DefendraColors.border, width: 0.5),
                  ),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            child: Text(
              url,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11,
                fontWeight: FontWeight.w400,
                color: DefendraColors.muted,
                decoration: TextDecoration.underline,
                decorationColor: DefendraColors.border,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
