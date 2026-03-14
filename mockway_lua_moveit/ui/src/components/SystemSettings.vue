<script setup>
import { ref, onMounted } from 'vue'

const emit = defineEmits(['close'])

const config = ref(null)
const loading = ref(true)
const saving = ref(false)
const error = ref('')
const successMsg = ref('')

// 展开/折叠状态
const expandedBuses = ref({})
const expandedRobot = ref(true)
const expandedDH = ref(false)
const expandedAxisData = ref(false)

onMounted(async () => {
  try {
    const res = await fetch('/api/config')
    if (!res.ok) throw new Error('Failed to load config')
    config.value = await res.json()
    // 默认展开所有总线
    config.value.buses.forEach((_, i) => {
      expandedBuses.value[i] = true
    })
  } catch (e) {
    error.value = e.message
  } finally {
    loading.value = false
  }
})

async function saveConfig() {
  saving.value = true
  error.value = ''
  successMsg.value = ''
  try {
    const res = await fetch('/api/config', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(config.value)
    })
    const data = await res.json()
    if (!res.ok) throw new Error(data.error || 'Save failed')
    successMsg.value = 'Saved successfully'
    setTimeout(() => successMsg.value = '', 2000)
  } catch (e) {
    error.value = e.message
  } finally {
    saving.value = false
  }
}

function addMotor(busIndex) {
  config.value.buses[busIndex].motors.push({
    joint_index: 0,
    enabled: false,
    can_id: 1,
    motor_type: 'DM4310',
    kp: 50.0,
    kd: 1.0,
    direction: 1
  })
}

function removeMotor(busIndex, motorIndex) {
  config.value.buses[busIndex].motors.splice(motorIndex, 1)
}

function addBus() {
  const idx = config.value.buses.length
  config.value.buses.push({
    type: 'usb2can',
    port: '',
    motors: []
  })
  expandedBuses.value[idx] = true
}

function removeBus(busIndex) {
  config.value.buses.splice(busIndex, 1)
  // 重建 expandedBuses
  const newExpanded = {}
  config.value.buses.forEach((_, i) => {
    newExpanded[i] = expandedBuses.value[i >= busIndex ? i + 1 : i] ?? true
  })
  expandedBuses.value = newExpanded
}

const dhLabels = ['alpha', 'a', 'd', 'theta']
const axisFields = [
  { key: 'axis_type', label: 'Type', step: 1 },
  { key: 'axis_max_vel', label: 'Max Vel' },
  { key: 'axis_max_acc', label: 'Max Acc' },
  { key: 'axis_max_dec', label: 'Max Dec' },
  { key: 'axis_max_jerk', label: 'Max Jerk' },
  { key: 'axis_positive_limit', label: '+Limit' },
  { key: 'axis_negative_limit', label: '-Limit' }
]
</script>

<template>
  <Teleport to="body">
    <div class="modal-overlay" @click.self="emit('close')">
      <div class="modal-container">
        <!-- Title Bar -->
        <div class="modal-titlebar">
          <div class="titlebar-left">
            <svg viewBox="0 0 24 24" class="titlebar-icon">
              <path d="M19.14 12.94c.04-.3.06-.61.06-.94 0-.32-.02-.64-.07-.94l2.03-1.58a.49.49 0 00.12-.61l-1.92-3.32a.49.49 0 00-.59-.22l-2.39.96c-.5-.38-1.03-.7-1.62-.94l-.36-2.54a.484.484 0 00-.48-.41h-3.84c-.24 0-.43.17-.47.41l-.36 2.54c-.59.24-1.13.57-1.62.94l-2.39-.96a.49.49 0 00-.59.22L2.74 8.87c-.12.21-.08.47.12.61l2.03 1.58c-.05.3-.07.62-.07.94s.02.64.07.94l-2.03 1.58a.49.49 0 00-.12.61l1.92 3.32c.12.22.37.29.59.22l2.39-.96c.5.38 1.03.7 1.62.94l.36 2.54c.05.24.24.41.48.41h3.84c.24 0 .44-.17.47-.41l.36-2.54c.59-.24 1.13-.56 1.62-.94l2.39.96c.22.08.47 0 .59-.22l1.92-3.32c.12-.22.07-.47-.12-.61l-2.01-1.58zM12 15.6A3.6 3.6 0 1115.6 12 3.611 3.611 0 0112 15.6z"/>
            </svg>
            <span>System Settings</span>
          </div>
          <button class="btn-close" @click="emit('close')">
            <svg viewBox="0 0 24 24"><path d="M19 6.41L17.59 5 12 10.59 6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 12 13.41 17.59 19 19 17.59 13.41 12z"/></svg>
          </button>
        </div>

        <!-- Content -->
        <div class="modal-body" v-if="loading">
          <div class="loading-text">Loading configuration...</div>
        </div>

        <div class="modal-body" v-else-if="!config">
          <div class="error-text">{{ error || 'Failed to load config' }}</div>
        </div>

        <div class="modal-body" v-else>
          <!-- ===== Buses Section ===== -->
          <div class="section">
            <div class="section-header" @click="expandedBuses = Object.fromEntries(Object.keys(expandedBuses).map(k => [k, !Object.values(expandedBuses).every(v => v)]))">
              <span class="section-title">Buses</span>
              <button class="btn-add" @click.stop="addBus">+ Add Bus</button>
            </div>

            <div v-for="(bus, bi) in config.buses" :key="bi" class="bus-block">
              <div class="bus-header" @click="expandedBuses[bi] = !expandedBuses[bi]">
                <span class="chevron">{{ expandedBuses[bi] ? '▾' : '▸' }}</span>
                <span class="bus-label">Bus {{ bi + 1 }}: {{ bus.type }} — {{ bus.port || '(no port)' }}</span>
                <button class="btn-remove" @click.stop="removeBus(bi)">×</button>
              </div>

              <div v-if="expandedBuses[bi]" class="bus-content">
                <div class="field-row">
                  <label>Type</label>
                  <select v-model="bus.type" class="field-input">
                    <option value="usb2can">usb2can</option>
                    <option value="socketcan">socketcan</option>
                  </select>
                </div>
                <div class="field-row">
                  <label>Port</label>
                  <input v-model="bus.port" class="field-input" />
                </div>

                <div class="motor-section">
                  <div class="motor-header-row">
                    <span class="sub-title">Motors</span>
                    <button class="btn-add btn-small" @click="addMotor(bi)">+ Add</button>
                  </div>

                  <div v-for="(motor, mi) in bus.motors" :key="mi" class="motor-card">
                    <div class="motor-title-row">
                      <span class="motor-label">Motor {{ mi + 1 }} (J{{ motor.joint_index + 1 }})</span>
                      <button class="btn-remove btn-small" @click="removeMotor(bi, mi)">×</button>
                    </div>
                    <div class="motor-fields">
                      <div class="field-row compact">
                        <label>Joint Index</label>
                        <input type="number" v-model.number="motor.joint_index" class="field-input num" min="0" max="5" step="1" />
                      </div>
                      <div class="field-row compact">
                        <label>Enabled</label>
                        <label class="switch">
                          <input type="checkbox" v-model="motor.enabled" />
                          <span class="slider"></span>
                        </label>
                      </div>
                      <div class="field-row compact">
                        <label>CAN ID</label>
                        <input type="number" v-model.number="motor.can_id" class="field-input num" min="1" step="1" />
                      </div>
                      <div class="field-row compact">
                        <label>Motor Type</label>
                        <input v-model="motor.motor_type" class="field-input" />
                      </div>
                      <div class="field-row compact">
                        <label>Kp</label>
                        <input type="number" v-model.number="motor.kp" class="field-input num" step="0.1" />
                      </div>
                      <div class="field-row compact">
                        <label>Kd</label>
                        <input type="number" v-model.number="motor.kd" class="field-input num" step="0.1" />
                      </div>
                      <div class="field-row compact">
                        <label>Direction</label>
                        <select v-model.number="motor.direction" class="field-input num">
                          <option :value="1">1</option>
                          <option :value="-1">-1</option>
                        </select>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>

          <!-- ===== Robot Section ===== -->
          <div class="section">
            <div class="section-header" @click="expandedRobot = !expandedRobot">
              <span class="chevron">{{ expandedRobot ? '▾' : '▸' }}</span>
              <span class="section-title">Robot</span>
            </div>

            <div v-if="expandedRobot" class="section-content">
              <div class="field-row">
                <label>Model</label>
                <input v-model="config.robot.model" class="field-input" />
              </div>
              <div class="field-row">
                <label>Ts (s)</label>
                <input type="number" v-model.number="config.robot.ts" class="field-input num" step="0.001" />
              </div>
              <div class="field-row">
                <label>Manual Ratio</label>
                <input type="number" v-model.number="config.robot.manual_ratio" class="field-input num" step="0.01" />
              </div>
              <div class="field-row">
                <label>Global Ratio</label>
                <input type="number" v-model.number="config.robot.global_ratio" class="field-input num" step="0.01" />
              </div>
              <div class="field-row">
                <label>Aux Axis Num</label>
                <input type="number" v-model.number="config.robot.aux_axis_num" class="field-input num" step="1" />
              </div>
              <div class="field-row">
                <label>Speed Down Mode</label>
                <input type="number" v-model.number="config.robot.online_speed_down_mode" class="field-input num" step="1" />
              </div>

              <!-- DH Parameters -->
              <div class="sub-section">
                <div class="sub-header" @click="expandedDH = !expandedDH">
                  <span class="chevron">{{ expandedDH ? '▾' : '▸' }}</span>
                  <span class="sub-title">DH Parameters</span>
                </div>
                <div v-if="expandedDH" class="dh-table">
                  <div class="dh-header-row">
                    <span class="dh-cell dh-label">Axis</span>
                    <span v-for="l in dhLabels" :key="l" class="dh-cell">{{ l }}</span>
                  </div>
                  <div v-for="(row, ri) in config.robot.dh" :key="ri" class="dh-row">
                    <span class="dh-cell dh-label">J{{ ri + 1 }}</span>
                    <input v-for="(val, ci) in row" :key="ci"
                      type="number"
                      v-model.number="config.robot.dh[ri][ci]"
                      class="dh-cell dh-input"
                      step="0.1"
                    />
                  </div>
                </div>
              </div>

              <!-- Axis Data -->
              <div class="sub-section">
                <div class="sub-header" @click="expandedAxisData = !expandedAxisData">
                  <span class="chevron">{{ expandedAxisData ? '▾' : '▸' }}</span>
                  <span class="sub-title">Axis Data</span>
                </div>
                <div v-if="expandedAxisData" class="axis-table">
                  <div class="axis-table-header">
                    <span class="at-cell at-label">Axis</span>
                    <span v-for="f in axisFields" :key="f.key" class="at-cell">{{ f.label }}</span>
                  </div>
                  <div v-for="(ax, ai) in config.robot.axis_data" :key="ai" class="axis-table-row">
                    <span class="at-cell at-label">J{{ ai + 1 }}</span>
                    <input v-for="f in axisFields" :key="f.key"
                      type="number"
                      v-model.number="ax[f.key]"
                      class="at-cell at-input"
                      :step="f.step || 0.1"
                    />
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>

        <!-- Footer -->
        <div class="modal-footer" v-if="config">
          <div class="footer-status">
            <span v-if="error" class="status-error">{{ error }}</span>
            <span v-if="successMsg" class="status-success">{{ successMsg }}</span>
          </div>
          <div class="footer-buttons">
            <button class="btn btn-cancel" @click="emit('close')">Cancel</button>
            <button class="btn btn-save" :disabled="saving" @click="saveConfig">
              {{ saving ? 'Saving...' : 'Save' }}
            </button>
          </div>
        </div>
      </div>
    </div>
  </Teleport>
</template>

<style scoped>
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

.modal-container {
  display: flex;
  flex-direction: column;
  width: 90vw;
  max-width: 800px;
  max-height: 85vh;
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
  flex: 1;
  overflow-y: auto;
  padding: 16px 18px;
}

.loading-text, .error-text {
  font-family: 'Rajdhani', sans-serif;
  font-size: 14px;
  color: var(--text-secondary);
  text-align: center;
  padding: 30px 0;
}

.error-text {
  color: var(--accent-red);
}

/* Sections */
.section {
  margin-bottom: 16px;
}

.section-header {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 8px 0;
  cursor: pointer;
  user-select: none;
}

.section-title {
  font-family: 'Oxanium', sans-serif;
  font-size: 14px;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 2px;
  color: var(--accent-cyan);
}

.chevron {
  font-size: 12px;
  color: var(--text-secondary);
  width: 14px;
}

.section-content {
  padding-left: 4px;
}

/* Bus */
.bus-block {
  margin-bottom: 10px;
  border: 1px solid rgba(59, 130, 246, 0.15);
  border-radius: 8px;
  overflow: hidden;
}

.bus-header {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 8px 12px;
  background: rgba(15, 23, 42, 0.3);
  cursor: pointer;
  user-select: none;
}

.bus-label {
  flex: 1;
  font-family: 'Rajdhani', sans-serif;
  font-size: 13px;
  font-weight: 600;
  color: var(--text-primary);
  letter-spacing: 0.5px;
}

.bus-content {
  padding: 10px 12px;
}

/* Fields */
.field-row {
  display: flex;
  align-items: center;
  gap: 10px;
  margin-bottom: 8px;
}

.field-row.compact {
  margin-bottom: 5px;
}

.field-row label {
  font-family: 'Rajdhani', sans-serif;
  font-size: 12px;
  font-weight: 600;
  color: var(--text-secondary);
  letter-spacing: 0.5px;
  min-width: 100px;
  text-align: right;
}

.field-input {
  flex: 1;
  max-width: 220px;
  padding: 4px 8px;
  background: rgba(15, 23, 42, 0.5);
  border: 1px solid rgba(59, 130, 246, 0.2);
  border-radius: 4px;
  font-family: 'Oxanium', sans-serif;
  font-size: 12px;
  color: var(--text-primary);
  outline: none;
  transition: border-color 0.2s;
}

.field-input:focus {
  border-color: var(--accent-blue);
}

.field-input.num {
  max-width: 100px;
  text-align: right;
}

select.field-input {
  cursor: pointer;
}

/* Toggle switch */
.switch {
  position: relative;
  display: inline-block;
  width: 36px;
  height: 20px;
  min-width: 36px;
}

.switch input {
  opacity: 0;
  width: 0;
  height: 0;
}

.slider {
  position: absolute;
  cursor: pointer;
  top: 0; left: 0; right: 0; bottom: 0;
  background: rgba(255, 255, 255, 0.1);
  border-radius: 20px;
  transition: 0.2s;
}

.slider::before {
  content: '';
  position: absolute;
  height: 14px;
  width: 14px;
  left: 3px;
  bottom: 3px;
  background: var(--text-secondary);
  border-radius: 50%;
  transition: 0.2s;
}

.switch input:checked + .slider {
  background: rgba(59, 130, 246, 0.3);
}

.switch input:checked + .slider::before {
  transform: translateX(16px);
  background: var(--accent-blue);
}

/* Motor */
.motor-section {
  margin-top: 8px;
}

.motor-header-row {
  display: flex;
  align-items: center;
  gap: 10px;
  margin-bottom: 6px;
}

.sub-title {
  font-family: 'Oxanium', sans-serif;
  font-size: 12px;
  font-weight: 500;
  text-transform: uppercase;
  letter-spacing: 1.5px;
  color: var(--accent-blue);
}

.motor-card {
  border: 1px solid rgba(59, 130, 246, 0.12);
  border-radius: 6px;
  padding: 8px 10px;
  margin-bottom: 6px;
  background: rgba(15, 23, 42, 0.2);
}

.motor-title-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 6px;
}

.motor-label {
  font-family: 'Rajdhani', sans-serif;
  font-size: 12px;
  font-weight: 600;
  color: var(--accent-cyan);
  letter-spacing: 0.5px;
}

.motor-fields {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 0 16px;
}

/* Buttons */
.btn-add {
  padding: 2px 10px;
  background: rgba(34, 197, 94, 0.1);
  border: 1px solid rgba(34, 197, 94, 0.3);
  border-radius: 4px;
  font-family: 'Rajdhani', sans-serif;
  font-size: 11px;
  font-weight: 600;
  color: var(--accent-green);
  cursor: pointer;
  transition: all 0.2s;
}

.btn-add:hover {
  background: rgba(34, 197, 94, 0.2);
}

.btn-remove {
  padding: 2px 8px;
  background: rgba(239, 68, 68, 0.1);
  border: 1px solid rgba(239, 68, 68, 0.3);
  border-radius: 4px;
  font-family: 'Rajdhani', sans-serif;
  font-size: 13px;
  font-weight: 700;
  color: var(--accent-red);
  cursor: pointer;
  transition: all 0.2s;
}

.btn-remove:hover {
  background: rgba(239, 68, 68, 0.2);
}

.btn-small {
  font-size: 10px;
  padding: 1px 7px;
}

/* DH Table */
.sub-section {
  margin-top: 12px;
}

.sub-header {
  display: flex;
  align-items: center;
  gap: 6px;
  cursor: pointer;
  user-select: none;
  padding: 4px 0;
}

.dh-table, .axis-table {
  margin-top: 6px;
  overflow-x: auto;
}

.dh-header-row, .dh-row, .axis-table-header, .axis-table-row {
  display: flex;
  gap: 4px;
  align-items: center;
  margin-bottom: 3px;
}

.dh-cell {
  width: 80px;
  text-align: center;
  font-family: 'Oxanium', sans-serif;
  font-size: 11px;
  color: var(--text-secondary);
}

.dh-label {
  width: 40px;
  font-weight: 600;
  color: var(--accent-cyan);
}

.dh-input {
  padding: 3px 4px;
  background: rgba(15, 23, 42, 0.5);
  border: 1px solid rgba(59, 130, 246, 0.2);
  border-radius: 3px;
  color: var(--text-primary);
  outline: none;
}

.dh-input:focus {
  border-color: var(--accent-blue);
}

/* Axis Table */
.at-cell {
  width: 75px;
  text-align: center;
  font-family: 'Oxanium', sans-serif;
  font-size: 10px;
  color: var(--text-secondary);
}

.at-label {
  width: 36px;
  font-weight: 600;
  color: var(--accent-cyan);
}

.at-input {
  padding: 3px 2px;
  background: rgba(15, 23, 42, 0.5);
  border: 1px solid rgba(59, 130, 246, 0.2);
  border-radius: 3px;
  color: var(--text-primary);
  outline: none;
}

.at-input:focus {
  border-color: var(--accent-blue);
}

/* Footer */
.modal-footer {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 10px 18px;
  background: rgba(15, 23, 42, 0.3);
  border-top: 1px solid rgba(59, 130, 246, 0.15);
  flex-shrink: 0;
}

.footer-status {
  font-family: 'Rajdhani', sans-serif;
  font-size: 12px;
}

.status-error {
  color: var(--accent-red);
}

.status-success {
  color: var(--accent-green);
}

.footer-buttons {
  display: flex;
  gap: 8px;
}

.btn {
  padding: 6px 18px;
  border-radius: 6px;
  font-family: 'Rajdhani', sans-serif;
  font-size: 13px;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 1px;
  cursor: pointer;
  transition: all 0.2s;
}

.btn-cancel {
  background: rgba(255, 255, 255, 0.05);
  border: 1px solid rgba(255, 255, 255, 0.15);
  color: var(--text-secondary);
}

.btn-cancel:hover {
  background: rgba(255, 255, 255, 0.1);
  color: var(--text-primary);
}

.btn-save {
  background: rgba(59, 130, 246, 0.2);
  border: 1px solid rgba(59, 130, 246, 0.4);
  color: var(--accent-blue);
}

.btn-save:hover {
  background: rgba(59, 130, 246, 0.3);
}

.btn-save:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}

/* Scrollbar */
.modal-body::-webkit-scrollbar {
  width: 6px;
}

.modal-body::-webkit-scrollbar-track {
  background: transparent;
}

.modal-body::-webkit-scrollbar-thumb {
  background: rgba(59, 130, 246, 0.2);
  border-radius: 3px;
}

.modal-body::-webkit-scrollbar-thumb:hover {
  background: rgba(59, 130, 246, 0.35);
}
</style>
