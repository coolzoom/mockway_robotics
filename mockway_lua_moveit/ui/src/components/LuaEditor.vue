<script setup>
import { ref } from 'vue'
import BlocklyEditor from './BlocklyEditor.vue'

const emit = defineEmits(['close'])

const CACHE_KEY = 'lua_script_cache'
const MODE_KEY = 'program_editor_mode'

const defaultScript = `-- Robot Lua Script
-- Available API:
--   GetJoints()       -> table {j1, j2, j3, j4, j5, j6}
--   GetPose()         -> table {x, y, z, rx, ry, rz}
--   PTP(joints)       -> int (point-to-point motion)
--   Lin(pose)         -> int (linear motion)
--   Sleep(ms)         -> void (delay in milliseconds)
--   print(...)        -> void (output to console)

local joints = GetJoints()
print("Current joints:")
for i = 1, 6 do
    print("  J" .. i .. " = " .. string.format("%.2f", joints[i]))
end
`

const script = ref(localStorage.getItem(CACHE_KEY) || defaultScript)
const output = ref('')
const isRunning = ref(false)
const hasError = ref(false)

// Mode switching
const editorMode = ref(localStorage.getItem(MODE_KEY) || 'lua')
const blocklyEditorRef = ref(null)
const generatedLua = ref('')

const setMode = (mode) => {
  editorMode.value = mode
  localStorage.setItem(MODE_KEY, mode)
}

const onBlocklyCodeChange = (code) => {
  generatedLua.value = code
}

const runScript = async () => {
  if (isRunning.value) return
  isRunning.value = true
  output.value = ''
  hasError.value = false

  let codeToRun = script.value
  if (editorMode.value === 'blockly') {
    codeToRun = blocklyEditorRef.value?.generateLua() || ''
    if (!codeToRun.trim()) {
      output.value = 'No blocks to run. Drag blocks to the workspace first.'
      hasError.value = true
      isRunning.value = false
      return
    }
  }

  try {
    const res = await fetch('/api/lua', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ script: codeToRun })
    })

    const data = await res.json()

    if (data.success) {
      output.value = data.output || data.message
      hasError.value = false
    } else {
      output.value = data.error || data.message
      hasError.value = true
    }
  } catch (err) {
    output.value = 'Connection error: ' + err.message
    hasError.value = true
  } finally {
    isRunning.value = false
    if (editorMode.value === 'lua') {
      localStorage.setItem(CACHE_KEY, script.value)
    }
  }
}

const clearOutput = () => {
  output.value = ''
  hasError.value = false
}

const handleTab = (e) => {
  const textarea = e.target
  const start = textarea.selectionStart
  const end = textarea.selectionEnd
  script.value = script.value.substring(0, start) + '    ' + script.value.substring(end)
  requestAnimationFrame(() => {
    textarea.selectionStart = textarea.selectionEnd = start + 4
  })
}
</script>

<template>
  <Teleport to="body">
    <div class="modal-overlay" @click.self="emit('close')">
      <div class="modal-container">
        <!-- Title Bar -->
        <div class="modal-titlebar">
          <div class="titlebar-left">
            <svg viewBox="0 0 24 24" class="titlebar-icon">
              <path d="M9.4 16.6L4.8 12l4.6-4.6L8 6l-6 6 6 6 1.4-1.4zm5.2 0l4.6-4.6-4.6-4.6L16 6l6 6-6 6-1.4-1.4z"/>
            </svg>
            <span>Program Editor</span>
          </div>
          <div class="toggle-group">
            <button :class="['toggle-btn', { active: editorMode === 'lua' }]" @click="setMode('lua')">Lua</button>
            <button :class="['toggle-btn', { active: editorMode === 'blockly' }]" @click="setMode('blockly')">Blockly</button>
          </div>
          <button class="btn-close" @click="emit('close')">
            <svg viewBox="0 0 24 24"><path d="M19 6.41L17.59 5 12 10.59 6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 12 13.41 17.59 19 19 17.59 13.41 12z"/></svg>
          </button>
        </div>

        <!-- Body -->
        <div class="modal-body">
          <!-- Left: Editor Area -->
          <div class="editor-section">
            <div class="editor-toolbar">
              <div class="toolbar-actions">
                <button class="btn btn-clear" @click="clearOutput" :disabled="isRunning">
                  <svg viewBox="0 0 24 24"><path d="M6 19c0 1.1.9 2 2 2h8c1.1 0 2-.9 2-2V7H6v12zM19 4h-3.5l-1-1h-5l-1 1H5v2h14V4z"/></svg>
                  Clear
                </button>
                <button class="btn btn-run" @click="runScript" :disabled="isRunning">
                  <svg viewBox="0 0 24 24" v-if="!isRunning"><path d="M8 5v14l11-7z"/></svg>
                  <div class="spinner" v-else></div>
                  {{ isRunning ? 'Running...' : 'Run' }}
                </button>
              </div>
            </div>
            <div class="editor-wrapper">
              <!-- Lua text editor -->
              <textarea
                v-show="editorMode === 'lua'"
                v-model="script"
                class="code-textarea"
                spellcheck="false"
                autocomplete="off"
                autocorrect="off"
                autocapitalize="off"
                @keydown.tab.prevent="handleTab"
              ></textarea>
              <!-- Blockly visual editor -->
              <BlocklyEditor
                v-show="editorMode === 'blockly'"
                ref="blocklyEditorRef"
                @codeChange="onBlocklyCodeChange"
              />
            </div>
          </div>

          <!-- Right: Output & Context Panel -->
          <div class="right-section">
            <!-- Output Panel -->
            <div class="output-section">
              <div class="panel-header">
                <svg viewBox="0 0 24 24" class="panel-icon">
                  <path d="M20 4H4c-1.1 0-2 .9-2 2v12c0 1.1.9 2 2 2h16c1.1 0 2-.9 2-2V6c0-1.1-.9-2-2-2zm0 14H4V8h16v12zm-2-1h-6v-2h6v2zm-8-3l-4-4 1.41-1.41L10 11.17l4.59-4.58L16 8l-6 6z"/>
                </svg>
                <span>Output</span>
                <div :class="['status-dot', { connected: !hasError && output, error: hasError }]"></div>
              </div>
              <div :class="['output-content', { 'has-error': hasError }]">
                <pre v-if="output">{{ output }}</pre>
                <span v-else class="output-placeholder">Script output will appear here...</span>
              </div>
            </div>

            <!-- Lua mode: API Reference -->
            <div v-show="editorMode === 'lua'" class="api-section">
              <div class="panel-header">
                <svg viewBox="0 0 24 24" class="panel-icon">
                  <path d="M14 2H6c-1.1 0-2 .9-2 2v16c0 1.1.9 2 2 2h12c1.1 0 2-.9 2-2V8l-6-6zm-1 7V3.5L18.5 9H13zM6 20V4h5v5h5v11H6z"/>
                </svg>
                <span>API Reference</span>
              </div>
              <div class="api-content">
                <div class="api-item">
                  <code>GetJoints()</code>
                  <span>Get current joint angles {j1..j6}</span>
                </div>
                <div class="api-item">
                  <code>GetPose()</code>
                  <span>Get end-effector pose {x,y,z,rx,ry,rz}</span>
                </div>
                <div class="api-item">
                  <code>PTP(joints)</code>
                  <span>Point-to-point joint motion</span>
                </div>
                <div class="api-item">
                  <code>Lin(pose)</code>
                  <span>Linear cartesian motion</span>
                </div>
                <div class="api-item">
                  <code>Sleep(ms)</code>
                  <span>Delay execution (milliseconds)</span>
                </div>
                <div class="api-item">
                  <code>print(...)</code>
                  <span>Print values to output</span>
                </div>
              </div>
            </div>

            <!-- Blockly mode: Generated Lua Preview -->
            <div v-show="editorMode === 'blockly'" class="generated-section">
              <div class="panel-header">
                <svg viewBox="0 0 24 24" class="panel-icon">
                  <path d="M9.4 16.6L4.8 12l4.6-4.6L8 6l-6 6 6 6 1.4-1.4zm5.2 0l4.6-4.6-4.6-4.6L16 6l6 6-6 6-1.4-1.4z"/>
                </svg>
                <span>Generated Lua</span>
              </div>
              <div class="generated-content">
                <pre v-if="generatedLua">{{ generatedLua }}</pre>
                <span v-else class="output-placeholder">Drag blocks to generate Lua code...</span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  </Teleport>
</template>

<style scoped>
/* Overlay */
.modal-overlay {
  position: fixed;
  inset: 0;
  z-index: 1000;
  display: flex;
  align-items: center;
  justify-content: center;
  background: rgba(0, 0, 0, 0.2);
  backdrop-filter: blur(2px);
  animation: fadeIn 0.2s ease;
}

@keyframes fadeIn {
  from { opacity: 0; }
  to { opacity: 1; }
}

/* Modal Container */
.modal-container {
  display: flex;
  flex-direction: column;
  width: 90vw;
  max-width: 1200px;
  height: 78vh;
  background: rgba(10, 14, 26, 0.6);
  border: 1px solid rgba(59, 130, 246, 0.35);
  border-radius: 12px;
  box-shadow:
    0 0 40px rgba(59, 130, 246, 0.12),
    0 24px 80px rgba(0, 0, 0, 0.5);
  overflow: hidden;
  animation: slideUp 0.25s ease;
}

@keyframes slideUp {
  from { opacity: 0; transform: translateY(20px); }
  to { opacity: 1; transform: translateY(0); }
}

/* Title Bar */
.modal-titlebar {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 12px 18px;
  background: rgba(15, 23, 42, 0.5);
  border-bottom: 1px solid rgba(59, 130, 246, 0.25);
  flex-shrink: 0;
}

.titlebar-left {
  display: flex;
  align-items: center;
  gap: 10px;
  font-family: 'Oxanium', sans-serif;
  font-size: 13px;
  font-weight: 500;
  text-transform: uppercase;
  letter-spacing: 2px;
  color: var(--accent-blue);
}

.titlebar-icon {
  width: 18px;
  height: 18px;
  fill: var(--accent-blue);
}

/* Toggle Group */
.toggle-group {
  display: flex;
  border: 1px solid rgba(59, 130, 246, 0.3);
  border-radius: 6px;
  overflow: hidden;
}

.toggle-btn {
  padding: 5px 14px;
  background: transparent;
  border: none;
  font-family: 'Rajdhani', sans-serif;
  font-size: 12px;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 1px;
  color: var(--text-secondary);
  cursor: pointer;
  transition: all 0.2s;
}

.toggle-btn + .toggle-btn {
  border-left: 1px solid rgba(59, 130, 246, 0.3);
}

.toggle-btn.active {
  background: rgba(59, 130, 246, 0.2);
  color: var(--accent-blue);
}

.toggle-btn:hover:not(.active) {
  background: rgba(59, 130, 246, 0.08);
  color: var(--text-primary);
}

.btn-close {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 30px;
  height: 30px;
  background: rgba(255, 255, 255, 0.05);
  border: 1px solid rgba(255, 255, 255, 0.1);
  border-radius: 6px;
  cursor: pointer;
  transition: all 0.2s;
}

.btn-close svg {
  width: 16px;
  height: 16px;
  fill: var(--text-secondary);
  transition: fill 0.2s;
}

.btn-close:hover {
  background: rgba(239, 68, 68, 0.15);
  border-color: var(--accent-red);
}

.btn-close:hover svg {
  fill: var(--accent-red);
}

/* Body */
.modal-body {
  display: grid;
  grid-template-columns: 1fr 300px;
  gap: 16px;
  padding: 16px;
  flex: 1;
  min-height: 0;
}

/* Editor */
.editor-section {
  display: flex;
  flex-direction: column;
  background: rgba(15, 23, 42, 0.35);
  border: 1px solid rgba(59, 130, 246, 0.2);
  border-radius: 8px;
  overflow: hidden;
  min-height: 0;
}

.editor-toolbar {
  display: flex;
  justify-content: flex-end;
  align-items: center;
  padding: 8px 12px;
  background: rgba(15, 23, 42, 0.4);
  border-bottom: 1px solid rgba(59, 130, 246, 0.15);
  flex-shrink: 0;
}

.toolbar-actions {
  display: flex;
  gap: 8px;
}

.btn {
  display: flex;
  align-items: center;
  gap: 5px;
  padding: 5px 12px;
  border: 1px solid;
  border-radius: 4px;
  font-family: 'Rajdhani', sans-serif;
  font-size: 12px;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 1px;
  cursor: pointer;
  transition: all 0.2s;
}

.btn svg {
  width: 13px;
  height: 13px;
}

.btn:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}

.btn-run {
  background: rgba(34, 197, 94, 0.12);
  border-color: rgba(34, 197, 94, 0.5);
  color: var(--accent-green);
}

.btn-run svg {
  fill: var(--accent-green);
}

.btn-run:hover:not(:disabled) {
  background: rgba(34, 197, 94, 0.22);
  box-shadow: 0 0 10px rgba(34, 197, 94, 0.25);
}

.btn-clear {
  background: rgba(122, 133, 153, 0.08);
  border-color: rgba(122, 133, 153, 0.25);
  color: var(--text-secondary);
}

.btn-clear svg {
  fill: var(--text-secondary);
}

.btn-clear:hover:not(:disabled) {
  background: rgba(122, 133, 153, 0.18);
  color: var(--text-primary);
}

.btn-clear:hover:not(:disabled) svg {
  fill: var(--text-primary);
}

.spinner {
  width: 13px;
  height: 13px;
  border: 2px solid rgba(34, 197, 94, 0.3);
  border-top-color: var(--accent-green);
  border-radius: 50%;
  animation: spin 0.8s linear infinite;
}

@keyframes spin {
  to { transform: rotate(360deg); }
}

.editor-wrapper {
  flex: 1;
  min-height: 0;
  position: relative;
}

.code-textarea {
  width: 100%;
  height: 100%;
  padding: 14px;
  background: rgba(8, 12, 21, 0.45);
  border: none;
  outline: none;
  resize: none;
  font-family: 'Courier New', 'Consolas', monospace;
  font-size: 13px;
  line-height: 1.6;
  color: #e2e8f0;
  tab-size: 4;
}

.code-textarea:focus {
  background: rgba(8, 12, 21, 0.55);
}

/* Right Section */
.right-section {
  display: flex;
  flex-direction: column;
  gap: 12px;
  min-height: 0;
}

/* Output */
.output-section {
  display: flex;
  flex-direction: column;
  background: rgba(15, 23, 42, 0.35);
  border: 1px solid rgba(59, 130, 246, 0.2);
  border-radius: 8px;
  overflow: hidden;
  flex: 1;
  min-height: 0;
}

.panel-header {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 9px 12px;
  background: rgba(15, 23, 42, 0.4);
  border-bottom: 1px solid rgba(59, 130, 246, 0.15);
  font-family: 'Oxanium', sans-serif;
  font-size: 11px;
  font-weight: 500;
  text-transform: uppercase;
  letter-spacing: 1.5px;
  color: var(--text-secondary);
  flex-shrink: 0;
}

.panel-header .status-dot {
  margin-left: auto;
}

.panel-icon {
  width: 14px;
  height: 14px;
  fill: var(--accent-blue);
}

.status-dot {
  width: 7px;
  height: 7px;
  border-radius: 50%;
  background: var(--text-secondary);
}

.status-dot.connected {
  background: var(--accent-green);
  box-shadow: 0 0 6px var(--accent-green);
}

.status-dot.error {
  background: var(--accent-red);
  box-shadow: 0 0 6px var(--accent-red);
}

.output-content {
  flex: 1;
  padding: 10px 12px;
  background: rgba(8, 12, 21, 0.35);
  overflow-y: auto;
  min-height: 0;
}

.output-content pre {
  font-family: 'Courier New', 'Consolas', monospace;
  font-size: 12px;
  line-height: 1.5;
  color: var(--accent-green);
  white-space: pre-wrap;
  word-break: break-all;
  margin: 0;
}

.output-content.has-error pre {
  color: var(--accent-red);
}

.output-placeholder {
  font-size: 11px;
  color: var(--text-secondary);
  font-style: italic;
}

/* API Reference */
.api-section {
  background: rgba(15, 23, 42, 0.35);
  border: 1px solid rgba(59, 130, 246, 0.2);
  border-radius: 8px;
  overflow: hidden;
  flex-shrink: 0;
}

.api-content {
  padding: 8px 12px;
}

.api-item {
  display: flex;
  flex-direction: column;
  gap: 1px;
  padding: 5px 0;
  border-bottom: 1px solid rgba(59, 130, 246, 0.08);
}

.api-item:last-child {
  border-bottom: none;
}

.api-item code {
  font-family: 'Courier New', 'Consolas', monospace;
  font-size: 11px;
  color: var(--accent-cyan);
}

.api-item span {
  font-size: 10px;
  color: var(--text-secondary);
}

/* Generated Lua Preview (Blockly mode) */
.generated-section {
  display: flex;
  flex-direction: column;
  background: rgba(15, 23, 42, 0.35);
  border: 1px solid rgba(59, 130, 246, 0.2);
  border-radius: 8px;
  overflow: hidden;
  flex: 1;
  min-height: 0;
}

.generated-content {
  flex: 1;
  padding: 10px 12px;
  background: rgba(8, 12, 21, 0.35);
  overflow-y: auto;
  min-height: 0;
}

.generated-content pre {
  font-family: 'Courier New', 'Consolas', monospace;
  font-size: 11px;
  line-height: 1.5;
  color: var(--accent-cyan);
  white-space: pre-wrap;
  word-break: break-all;
  margin: 0;
}
</style>

<!-- Global (non-scoped) Blockly dark theme overrides -->
<style>
/* Blockly toolbox */
.blocklyToolboxDiv {
  background: #111827 !important;
  border-right: 1px solid rgba(59, 130, 246, 0.2) !important;
}

.blocklyTreeRow {
  padding: 6px 12px !important;
}

.blocklyTreeLabel {
  font-family: 'Rajdhani', sans-serif !important;
  font-size: 13px !important;
  font-weight: 600 !important;
  letter-spacing: 0.5px !important;
  color: #cbd5e1 !important;
}

.blocklyTreeSelected {
  background-color: rgba(59, 130, 246, 0.15) !important;
}

.blocklyTreeSelected .blocklyTreeLabel {
  color: #e2e8f0 !important;
}

/* Blockly flyout */
.blocklyFlyoutBackground {
  fill: #1a2332 !important;
  fill-opacity: 0.95 !important;
}

/* Blockly scrollbar */
.blocklyScrollbarBackground {
  opacity: 0 !important;
}

.blocklyScrollbarHandle {
  fill: rgba(59, 130, 246, 0.3) !important;
  rx: 4 !important;
  ry: 4 !important;
}

/* Blockly context menu */
.blocklyContextMenu {
  background: #1a2332 !important;
  border: 1px solid rgba(59, 130, 246, 0.25) !important;
  border-radius: 8px !important;
  box-shadow: 0 8px 32px rgba(0, 0, 0, 0.5) !important;
  padding: 4px !important;
}

.blocklyMenuItem {
  font-family: 'Rajdhani', sans-serif !important;
  font-size: 13px !important;
  color: #cbd5e1 !important;
  padding: 6px 12px !important;
  border-radius: 4px !important;
}

.blocklyMenuItemHighlight {
  background: rgba(59, 130, 246, 0.15) !important;
}

.blocklyMenuItemDisabled {
  color: #4a5568 !important;
}

/* Blockly tooltip */
.blocklyTooltipDiv {
  background: #1a2332 !important;
  border: 1px solid rgba(59, 130, 246, 0.25) !important;
  border-radius: 6px !important;
  color: #cbd5e1 !important;
  font-family: 'Rajdhani', sans-serif !important;
  font-size: 12px !important;
  padding: 6px 10px !important;
  box-shadow: 0 4px 16px rgba(0, 0, 0, 0.4) !important;
}

/* Blockly widget div (dropdowns etc.) */
.blocklyWidgetDiv {
  z-index: 1100 !important;
}

.blocklyWidgetDiv .blocklyMenu {
  background: #1a2332 !important;
  border: 1px solid rgba(59, 130, 246, 0.25) !important;
  border-radius: 8px !important;
  box-shadow: 0 8px 32px rgba(0, 0, 0, 0.5) !important;
  padding: 4px !important;
}

.blocklyWidgetDiv .blocklyMenuItem {
  font-family: 'Rajdhani', sans-serif !important;
  color: #cbd5e1 !important;
}

.blocklyWidgetDiv .blocklyMenuItemHighlight {
  background: rgba(59, 130, 246, 0.15) !important;
}

/* Blockly trash can */
.blocklyTrash image {
  opacity: 0.5;
}

/* Blockly zoom controls */
.blocklyZoom image {
  opacity: 0.5;
}

.blocklyZoom image:hover {
  opacity: 0.8;
}

/* Blockly text input (field editor) */
.blocklyHtmlInput {
  font-family: 'Rajdhani', sans-serif !important;
  background: #0d1220 !important;
  color: #e2e8f0 !important;
  border: 1px solid rgba(59, 130, 246, 0.4) !important;
  border-radius: 4px !important;
}

/* Variable modal / prompt dialogs */
.blocklyDialogDiv {
  z-index: 1200 !important;
}
</style>
