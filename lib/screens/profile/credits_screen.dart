import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_fonts.dart';
import '../../config/theme.dart';

/// Attribution for everything the app ships or pulls in.
///
/// This is a user-facing screen on purpose. Several of the licences involved
/// (the Flaticon free licence in particular) require the credit to be visible
/// to end users, not merely recorded somewhere in the source tree.
///
/// Package licences are not hardcoded here — [showLicensePage] renders the
/// LICENSE file of every bundled dependency automatically, so that list cannot
/// drift out of date as dependencies change.
class CreditsScreen extends StatelessWidget {
  const CreditsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(gradient: AppTheme.scaffoldGradient(context)),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text(
            'Credits & Licences',
            style: AppFonts.plusJakartaSans(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppTheme.textP(context),
            ),
          ),
          iconTheme: IconThemeData(color: AppTheme.textP(context)),
        ),
        body: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              _Intro(),
              const SizedBox(height: 20),

              const _Section(
                icon: Icons.text_fields_rounded,
                title: 'Typography',
                children: [
                  _Credit(
                    name: 'Inter',
                    detail: 'Rasmus Andersson and the Inter Project Authors',
                    licence: 'SIL Open Font License 1.1',
                    url: 'https://github.com/rsms/inter',
                  ),
                  _Credit(
                    name: 'Plus Jakarta Sans',
                    detail: 'Tokotype and the Plus Jakarta Sans Project Authors',
                    licence: 'SIL Open Font License 1.1',
                    url: 'https://github.com/tokotype/PlusJakartaSans',
                  ),
                ],
              ),

              const _Section(
                icon: Icons.interests_rounded,
                title: 'Icons',
                children: [
                  _Credit(
                    name: 'Flaticon',
                    detail:
                        'Subject and feature icons throughout the app are by various '
                        'authors on Flaticon, used under the Flaticon Free Licence, '
                        'which requires this credit.',
                    licence: 'Flaticon Free Licence',
                    url: 'https://www.flaticon.com',
                  ),
                  _Credit(
                    name: 'Material Icons',
                    detail: 'Google — the interface icons built into Flutter',
                    licence: 'Apache License 2.0',
                    url: 'https://fonts.google.com/icons',
                  ),
                ],
              ),

              const _Section(
                icon: Icons.photo_library_rounded,
                title: 'Photography',
                children: [
                  _Credit(
                    name: 'Unsplash',
                    detail:
                        'Banner and background photography is served from Unsplash '
                        'and remains the work of its individual photographers.',
                    licence: 'Unsplash Licence',
                    url: 'https://unsplash.com/license',
                  ),
                ],
              ),

              const _Section(
                icon: Icons.animation_rounded,
                title: 'Animations',
                children: [
                  _Credit(
                    name: 'Lottie animations',
                    detail:
                        'Loading, empty-state and celebration animations, rendered '
                        'with the Lottie library.',
                    licence: 'See lottiefiles.com for individual terms',
                    url: 'https://lottiefiles.com',
                  ),
                ],
              ),

              const _Section(
                icon: Icons.newspaper_rounded,
                title: 'Content sources',
                children: [
                  _Credit(
                    name: 'News and current affairs',
                    detail:
                        'Headlines and summaries are drawn from publicly available '
                        'feeds published by The Hindu, The Indian Express, LiveMint, '
                        'India Today and Google News. Copyright in the original '
                        'reporting remains with those publishers, and each item links '
                        'back to its source.',
                    licence: 'Rights retained by the respective publishers',
                    url: null,
                  ),
                  _Credit(
                    name: 'Study material',
                    detail:
                        'Current-affairs analysis is compiled from Drishti IAS and '
                        'Insights on India. All rights remain with those publishers.',
                    licence: 'Rights retained by the respective publishers',
                    url: null,
                  ),
                  _Credit(
                    name: 'Reference data',
                    detail:
                        'Encyclopaedic background from Wikipedia and Wikimedia '
                        'Commons; official notifications from upsc.gov.in and the '
                        'Press Information Bureau; word definitions from the Free '
                        'Dictionary API.',
                    licence: 'Wikipedia content under CC BY-SA',
                    url: 'https://en.wikipedia.org',
                  ),
                ],
              ),

              const _Section(
                icon: Icons.code_rounded,
                title: 'Software',
                children: [
                  _Credit(
                    name: 'Flutter',
                    detail: 'Google — the framework this app is built with',
                    licence: 'BSD 3-Clause',
                    url: 'https://flutter.dev',
                  ),
                ],
              ),

              const SizedBox(height: 8),
              _OpenSourceButton(),
              const SizedBox(height: 24),
              _Disclaimer(),
            ],
          ),
        ),
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.cleanCard(context, radius: 16),
      child: Text(
        'UPSC Daily Edge is built on work generously shared by others. '
        'Everything below is credited under the terms its creators asked for.',
        style: AppFonts.inter(
          fontSize: 13.5,
          height: 1.55,
          color: AppTheme.textS(context),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<Widget> children;

  const _Section({
    required this.icon,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: AppTheme.primaryColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: AppFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textP(context),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

class _Credit extends StatelessWidget {
  final String name;
  final String detail;
  final String licence;
  final String? url;

  const _Credit({
    required this.name,
    required this.detail,
    required this.licence,
    required this.url,
  });

  Future<void> _open(BuildContext context) async {
    final target = url;
    if (target == null) return;
    final uri = Uri.parse(target);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      // Opening the credit link is a convenience; failing to do so is not worth
      // interrupting the user over.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: url == null ? null : () => _open(context),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: AppTheme.cleanCard(context, radius: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      style: AppFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textP(context),
                      ),
                    ),
                  ),
                  if (url != null)
                    Icon(Icons.open_in_new_rounded,
                        size: 14, color: AppTheme.textT(context)),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                detail,
                style: AppFonts.inter(
                  fontSize: 12.5,
                  height: 1.5,
                  color: AppTheme.textS(context),
                ),
              ),
              const SizedBox(height: 7),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  licence,
                  style: AppFonts.inter(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primaryColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OpenSourceButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: () => showLicensePage(
          context: context,
          applicationName: 'UPSC Daily Edge',
          applicationLegalese:
              'Bundled open-source licences, collected automatically.',
        ),
        icon: const Icon(Icons.article_outlined, size: 18),
        label: Text(
          'Open-source licences',
          style: AppFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w600),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: AppTheme.primaryColor,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}

class _Disclaimer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.textT(context).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        'UPSC Daily Edge is an independent study aid. It is not affiliated with, '
        'endorsed by, or connected to the Union Public Service Commission or any '
        'government body. "UPSC" is used only to describe the examination this '
        'app helps you prepare for. All trademarks belong to their owners.',
        style: AppFonts.inter(
          fontSize: 11.5,
          height: 1.55,
          color: AppTheme.textT(context),
        ),
      ),
    );
  }
}
