import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import '../../config/theme.dart';
import '../../config/app_images.dart';
import '../../providers/study_provider.dart';
import '../../widgets/glass_widgets.dart';
import '../../models/subject.dart';

/// ──────────────────────────────────────────────────────────────────────────────
/// SubjectDetailScreen — Notes list with PDF downloads and content viewer.
/// ──────────────────────────────────────────────────────────────────────────────
class SubjectDetailScreen extends StatefulWidget {
  const SubjectDetailScreen({super.key});

  @override
  State<SubjectDetailScreen> createState() => _SubjectDetailScreenState();
}

class _SubjectDetailScreenState extends State<SubjectDetailScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final subjectId = ModalRoute.of(context)?.settings.arguments as String?;
    final study = context.watch<StudyProvider>();
    final subject = subjectId != null ? study.getSubjectById(subjectId) : null;

    if (subject == null) {
      return GradientScaffold(
        showAppBar: false,
        child: SafeArea(
          child: Column(
            children: [
              _backBar(context, 'Subject'),
              const Expanded(child: Center(child: Text('Subject not found'))),
            ],
          ),
        ),
      );
    }

    return GradientScaffold(
      showAppBar: false,
      child: SafeArea(
        child: Column(
          children: [
            _backBar(context, subject.name),
            Expanded(
              child: ListView(
                controller: _scrollController,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                children: [
                  _buildHeader(context, subject),
                  ...subject.notes.map((note) => _buildNoteCard(context, note)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _backBar(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
      child: Row(
        children: [
          IconButton(icon: const Icon(Icons.arrow_back_ios_rounded), onPressed: () {
            HapticFeedback.lightImpact();
            Navigator.pop(context);
          }),
          Expanded(child: Text(title, style: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.w700, color: AppTheme.textP(context)))),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, Subject subject) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          children: [
            SizedBox(
              height: 180, width: double.infinity,
              child: CachedNetworkImage(
                imageUrl: AppImages.categoryImage(subject.name),
                fit: BoxFit.cover,
                placeholder: (_, __) => Shimmer.fromColors(
                  baseColor: AppTheme.primaryColor.withValues(alpha: 0.08),
                  highlightColor: AppTheme.primaryColor.withValues(alpha: 0.04),
                  child: Container(color: Colors.white),
                ),
                errorWidget: (_, __, ___) => Container(
                  decoration: BoxDecoration(gradient: AppTheme.heroGradient),
                ),
              ),
            ),
            Container(
              height: 180,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [
                    AppTheme.primaryDark.withValues(alpha: 0.5),
                    AppTheme.primaryColor.withValues(alpha: 0.85),
                  ],
                ),
              ),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(subject.name, style: GoogleFonts.plusJakartaSans(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)),
                  const SizedBox(height: 6),
                  Text(subject.description, style: GoogleFonts.inter(fontSize: 13, color: Colors.white70, height: 1.5),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(20)),
                    child: Text('${subject.notes.length} study notes', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoteCard(BuildContext context, StudyNote note) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AnimatedGlassCard(
        onTap: () => _showNoteDetail(context, note),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(note.title,
                      style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.textP(context)),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
                if (note.pdfUrl != null && note.pdfUrl!.isNotEmpty)
                  GestureDetector(
                    onTap: () => _openPdf(note.pdfUrl!),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.errorRed.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.picture_as_pdf_rounded, color: AppTheme.errorRed, size: 20),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(note.content,
                maxLines: 3, overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textS(context), height: 1.5)),
            const SizedBox(height: 8),
            Text('Updated ${_formatDate(note.lastUpdated)}',
                style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textS(context).withValues(alpha: 0.6))),
          ],
        ),
      ),
    );
  }

  void _showNoteDetail(BuildContext context, StudyNote note) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, ctrl) => Container(
          decoration: BoxDecoration(
            color: AppTheme.scaffold(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: ListView(
            controller: ctrl,
            padding: const EdgeInsets.all(24),
            children: [
              Center(
                child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
              ),
              const SizedBox(height: 20),
              Text(note.title, style: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.w800, color: AppTheme.textP(context))),
              const SizedBox(height: 16),
              Text(note.content, style: GoogleFonts.inter(fontSize: 14, height: 1.7, color: AppTheme.textP(context))),
              if (note.pdfUrl != null && note.pdfUrl!.isNotEmpty) ...[
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: () => _openPdf(note.pdfUrl!),
                    icon: const Icon(Icons.picture_as_pdf_rounded),
                    label: Text('Open PDF', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.errorRed,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openPdf(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  String _formatDate(DateTime d) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }
}
