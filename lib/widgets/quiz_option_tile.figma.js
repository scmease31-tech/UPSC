// QuizOptionTile — Figma Code Connect
// Replace FIGMA_COMPONENT_URL with your Figma component URL

import figma from '@figma/code-connect';

figma.connect('FIGMA_COMPONENT_URL_QUIZ_OPTION', {
  props: {
    text: figma.string('Text'),
    index: figma.enum('Letter', {
      A: '0',
      B: '1',
      C: '2',
      D: '3',
    }),
    isSelected: figma.boolean('Selected'),
    isCorrect: figma.boolean('Correct'),
    isAnswered: figma.boolean('Answered'),
  },
  example: (props) => `
QuizOptionTile(
  text: "${props.text}",
  index: ${props.index},
  isSelected: ${props.isSelected},
  isCorrect: ${props.isCorrect},
  isAnswered: ${props.isAnswered},
  onTap: () {},
)`,
});
