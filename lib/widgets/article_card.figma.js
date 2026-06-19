// ArticleCard — Figma Code Connect
// Replace FIGMA_COMPONENT_URL with your Figma component URL
// e.g. https://www.figma.com/design/XXXXX/UPSC-Daily-Edge?node-id=123-456

import figma from '@figma/code-connect';

figma.connect('FIGMA_COMPONENT_URL_ARTICLE_CARD', {
  props: {
    compact: figma.boolean('Compact'),
    featured: figma.boolean('Featured'),
    category: figma.enum('Category', {
      Polity: '"polity"',
      Economy: '"economy"',
      Environment: '"environment"',
      Science: '"science"',
      International: '"international"',
      Social: '"social"',
      Geography: '"geography"',
      History: '"history"',
    }),
  },
  example: (props) => `
ArticleCard(
  article: article,
  compact: ${props.compact},
  featured: ${props.featured},
)`,
});
