// GlassCard & GradientScaffold — Figma Code Connect
// Replace FIGMA_COMPONENT_URL with your Figma component URLs

import figma from '@figma/code-connect';

// GradientScaffold — base layout for every screen
figma.connect('FIGMA_COMPONENT_URL_GRADIENT_SCAFFOLD', {
  props: {
    title: figma.string('Title'),
    showAppBar: figma.boolean('Show App Bar'),
    centerTitle: figma.boolean('Center Title'),
  },
  example: (props) => `
GradientScaffold(
  title: "${props.title}",
  showAppBar: ${props.showAppBar},
  centerTitle: ${props.centerTitle},
  child: /* your content */,
)`,
});

// GlassCard — frosted glassmorphic card
figma.connect('FIGMA_COMPONENT_URL_GLASS_CARD', {
  props: {
    radius: figma.enum('Radius', {
      Small: '12',
      Medium: '22',
      Large: '28',
    }),
    blur: figma.enum('Blur', {
      Light: '8',
      Medium: '12',
      Heavy: '20',
    }),
  },
  example: (props) => `
GlassCard(
  radius: ${props.radius},
  blur: ${props.blur},
  child: /* your content */,
)`,
});
