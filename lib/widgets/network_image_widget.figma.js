// NetworkImageWidget — Figma Code Connect
// Replace FIGMA_COMPONENT_URL with your Figma component URL

import figma from '@figma/code-connect';

figma.connect('FIGMA_COMPONENT_URL_NETWORK_IMAGE', {
  props: {
    borderRadius: figma.enum('Border Radius', {
      None: '0',
      Small: '8',
      Medium: '16',
      Large: '24',
    }),
    fit: figma.enum('Fit', {
      Cover: 'BoxFit.cover',
      Contain: 'BoxFit.contain',
      Fill: 'BoxFit.fill',
    }),
    showOverlay: figma.boolean('Show Overlay'),
  },
  example: (props) => `
NetworkImageWidget(
  imageUrl: "https://example.com/image.jpg",
  borderRadius: ${props.borderRadius},
  fit: ${props.fit},
  showOverlay: ${props.showOverlay},
)`,
});
