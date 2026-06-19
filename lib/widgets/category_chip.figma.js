// CategoryChip — Figma Code Connect
// Replace FIGMA_COMPONENT_URL with your Figma component URL

import figma from '@figma/code-connect';

figma.connect('FIGMA_COMPONENT_URL_CATEGORY_CHIP', {
  props: {
    label: figma.string('Label'),
    isSelected: figma.boolean('Selected'),
    iconPath: figma.string('Icon Path'),
  },
  example: (props) => `
CategoryChip(
  label: "${props.label}",
  isSelected: ${props.isSelected},
  onTap: () {},
  ${props.iconPath ? `iconPath: "${props.iconPath}",` : ''}
)`,
});
