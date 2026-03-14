import * as Blockly from 'blockly/core'

export const darkTheme = Blockly.Theme.defineTheme('robotDark', {
  name: 'robotDark',
  base: Blockly.Themes.Classic,
  componentStyles: {
    workspaceBackgroundColour: '#0d1220',
    toolboxBackgroundColour: '#111827',
    toolboxForegroundColour: '#e2e8f0',
    flyoutBackgroundColour: '#1a2332',
    flyoutForegroundColour: '#cbd5e1',
    flyoutOpacity: 0.95,
    scrollbarColour: 'rgba(59, 130, 246, 0.35)',
    scrollbarOpacity: 0.6,
    insertionMarkerColour: '#3b82f6',
    insertionMarkerOpacity: 0.4,
    cursorColour: '#3b82f6'
  },
  fontStyle: {
    family: 'Rajdhani, sans-serif',
    weight: '600',
    size: 12
  },
  startHats: false
})
