// SectionHeader — Figma Code Connect
// Replace FIGMA_COMPONENT_URL with your Figma component URL

import figma from '@figma/code-connect';

figma.connect('FIGMA_COMPONENT_URL_SECTION_HEADER', {
  props: {
    title: figma.string('Title'),
    actionLabel: figma.string('Action Label'),
  },
  example: (props) => `
SectionHeader(
  title: "${props.title}",
  ${props.actionLabel ? `actionLabel: "${props.actionLabel}",\n  onAction: () {},` : ''}
)`,
});
