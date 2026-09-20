/// ──────────────────────────────────────────────────────────────────────────
/// Frosted Scholar Design System (v1.6)
/// ──────────────────────────────────────────────────────────────────────────
/// Compact premium glass. Controlled blur, balanced 12–16px spacing,
/// teal/violet accents, restrained motion, readable in light AND dark.
///
/// One import gives you every token and primitive:
/// ```dart
/// import 'package:upsc_daily_edge/design_system/frosted_scholar.dart';
/// ```
///
/// TOKENS (never hardcode — reference these):
///   • FsSpace / FsSpacing / FsRadii / FsA11y  — spacing, radii, touch floors
///   • FsColors / FsBlur / FsGlass             — accents, surfaces, blur
///   • FsType / FsMotion                       — type ramp, durations, curves
///
/// PRIMITIVES (compose these, don't rebuild them):
///   • FsCard, FsSectionHeader, FsTag          — surfaces
///   • FsButton (filled/tonal/outline), FsIconButton
///   • FsTextField, FsSearchField              — inputs
///   • FsSkeleton, FsLoading, FsEmptyState, FsErrorState — states
library;

export 'fs_spacing.dart';
export 'fs_colors.dart';
export 'fs_typography.dart';
export 'fs_surfaces.dart';
export 'fs_buttons.dart';
export 'fs_inputs.dart';
export 'fs_states.dart';
