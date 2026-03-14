<script setup>
import { ref, onMounted, onBeforeUnmount, defineExpose, defineEmits } from 'vue'
import * as Blockly from 'blockly'
import '../blockly/blocks.js'
import { luaGenerator } from '../blockly/luaGenerator.js'
import { createToolbox } from '../blockly/toolbox.js'
import { darkTheme } from '../blockly/theme.js'
import { useRobotSSE } from '../composables/useRobotSSE.js'

const { jointAngles, endPose } = useRobotSSE()

const emit = defineEmits(['codeChange'])

const CACHE_KEY = 'blockly_workspace_cache'

const blocklyDiv = ref(null)
let workspace = null
let resizeObserver = null

const generateLua = () => {
  if (!workspace) return ''
  try {
    return luaGenerator.workspaceToCode(workspace)
  } catch (e) {
    console.warn('Blockly code generation error:', e)
    return '-- Code generation error: ' + e.message + '\n'
  }
}

const onWorkspaceChange = () => {
  // Save to localStorage
  try {
    const xml = Blockly.serialization.workspaces.save(workspace)
    localStorage.setItem(CACHE_KEY, JSON.stringify(xml))
  } catch (e) {
    // ignore save errors
  }
  // Emit generated code
  emit('codeChange', generateLua())
}

onMounted(() => {
  if (!blocklyDiv.value) return

  const toolbox = createToolbox(jointAngles.value, endPose.value)

  workspace = Blockly.inject(blocklyDiv.value, {
    toolbox,
    theme: darkTheme,
    renderer: 'zelos',
    grid: {
      spacing: 25,
      length: 3,
      colour: 'rgba(59, 130, 246, 0.12)',
      snap: true
    },
    zoom: {
      controls: true,
      wheel: true,
      startScale: 0.9,
      maxScale: 2,
      minScale: 0.3,
      scaleSpeed: 1.1
    },
    trashcan: true,
    move: {
      scrollbars: true,
      drag: true,
      wheel: true
    },
    sounds: false
  })

  // Restore from cache
  try {
    const cached = localStorage.getItem(CACHE_KEY)
    if (cached) {
      const json = JSON.parse(cached)
      Blockly.serialization.workspaces.load(json, workspace)
    }
  } catch (e) {
    // ignore restore errors
  }

  // Listen for changes
  workspace.addChangeListener((e) => {
    if (e.isUiEvent) return
    onWorkspaceChange()
  })

  // Initial code generation
  emit('codeChange', generateLua())

  // ResizeObserver for container size changes
  resizeObserver = new ResizeObserver(() => {
    Blockly.svgResize(workspace)
  })
  resizeObserver.observe(blocklyDiv.value)
})

onBeforeUnmount(() => {
  if (resizeObserver) {
    resizeObserver.disconnect()
    resizeObserver = null
  }
  if (workspace) {
    workspace.dispose()
    workspace = null
  }
})

defineExpose({ generateLua })
</script>

<template>
  <div ref="blocklyDiv" class="blockly-container"></div>
</template>

<style scoped>
.blockly-container {
  width: 100%;
  height: 100%;
}
</style>
