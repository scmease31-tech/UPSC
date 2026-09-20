import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import '../../config/theme.dart';
import '../../config/app_images.dart';
import '../../providers/study_provider.dart';
import '../../widgets/glass_widgets.dart';
import '../../models/subject.dart';
import 'package:upsc_daily_edge/design_system/frosted_scholar.dart';

/// ──────────────────────────────────────────────────────────────────────────────
/// SubjectDetailScreen — Notes list with PDF downloads and content viewer.
/// Migrated to the Frosted Scholar design system (tokens + primitives).
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
              const Expanded(
                child: FsEmptyState(
                  icon: Icons.search_off_rounded,
                  title: 'Subject not found',
                  message: 'This subject may have been removed or is unavailable.',
                ),
              ),
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
                padding: const EdgeInsets.fromLTRB(
                    FsSpace.lg, FsSpace.xs, FsSpace.lg, 100),
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
      padding: const EdgeInsets.fromLTRB(FsSpace.xs, FsSpace.xs, FsSpace.lg, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_rounded),
            onPressed: () {
              HapticFeedback.lightImpact();
              Navigator.pop(context);
            },
          ),
          Expanded(
            child: Text(title,
                style: FsType.title(context),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, Subject subject) {
    return Padding(
      padding: const EdgeInsets.only(bottom: FsSpace.lg),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(FsRadii.lg),
        child: Stack(
          children: [
            SizedBox(
              height: 180,
              width: double.infinity,
              child: CachedNetworkImage(
                imageUrl: AppImages.categoryImage(subject.name),
                fit: BoxFit.cover,
                placeholder: (_, __) => Shimmer.fromColors(
                  baseColor: AppTheme.primaryColor.withValues(alpha: 0.08),
                  highlightColor: AppTheme.primaryColor.withValues(alpha: 0.04),
                  child: Container(color: Colors.white),
                ),
                errorWidget: (_, __, ___) => Container(
                  decoration: const BoxDecoration(gradient: AppTheme.heroGradient),
                ),
              ),
            ),
            Container(
              height: 180,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppTheme.primaryDark.withValues(alpha: 0.5),
                    AppTheme.primaryColor.withValues(alpha: 0.85),
                  ],
                ),
              ),
              padding: const EdgeInsets.all(FsSpace.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(subject.name,
                      style: FsType.display(context).copyWith(color: Colors.white)),
                  const SizedBox(height: FsSpace.xs),
                  Text(subject.description,
                      style: FsType.caption(context).copyWith(color: Colors.white70),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: FsSpace.md),
                  FsTag(
                    label: '${subject.notes.length} study notes',
                    color: Colors.white,
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
      padding: const EdgeInsets.only(bottom: FsSpace.md),
      child: FsCard(
        onTap: () => _showNoteDetail(context, note),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(note.title,
                      style: FsType.subtitle(context),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ),
                if (note.pdfUrl != null && note.pdfUrl!.isNotEmpty)
                  FsIconButton(
                    icon: Icons.picture_as_pdf_rounded,
                    color: FsColors.danger,
                    size: 36,
                    tooltip: 'Open PDF',
                    onPressed: () => _openPdf(note.pdfUrl!),
                  ),
              ],
            ),
            const SizedBox(height: FsSpace.xs),
            Text(note.content,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: FsType.caption(context)),
            const SizedBox(height: FsSpace.xs),
            Text('Updated ${_formatDate(note.lastUpdated)}',
                style: FsType.label(context)),
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
        builder: (_, ctrl) => DecoratedBox(
          decoration: BoxDecoration(
            color: AppTheme.scaffold(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(FsRadii.lg)),
          ),
          child: ListView(
            controller: ctrl,
            padding: const EdgeInsets.all(FsSpace.xxl),
            children: [
              Center(
                child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: FsColors.divider(context),
                        borderRadius: BorderRadius.circular(2))),
              ),
              const SizedBox(height: FsSpace.xl),
              Text(note.title, style: FsType.display(context)),
              const SizedBox(height: FsSpace.lg),
              Text(note.content, style: FsType.body(context)),
              if (note.pdfUrl != null && note.pdfUrl!.isNotEmpty) ...[
                const SizedBox(height: FsSpace.xxl),
                FsButton(
                  label: 'Open PDF',
                  icon: Icons.picture_as_pdf_rounded,
                  color: FsColors.danger,
                  expand: true,
                  onPressed: () => _openPdf(note.pdfUrl!),
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
