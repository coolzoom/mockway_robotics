<script setup>
import { computed } from 'vue'
import { useRobotSSE } from '../composables/useRobotSSE.js'

const { jointAngles, commandJoints, endPose } = useRobotSSE()

const labels = ['Joint 1 Angle', 'Joint 2 Angle', 'Joint 3 Angle', 'Joint 4 Angle', 'Joint 5 Angle', 'Joint 6 Angle']

const orbitalData = computed(() =>
  labels.map((label, index) => {
    const cmdValue = commandJoints.value[index] || 0
    const actValue = jointAngles.value[index] || 0
    // fill: map command angle from [-180, 180] to [0, 100]
    const fill = Math.min(100, Math.max(0, ((cmdValue + 180) / 360) * 100))
    return { label, cmdValue, actValue, unit: '°', fill, decimals: 1 }
  })
)

const poseLabels = [
  { label: 'X', unit: 'mm' },
  { label: 'Y', unit: 'mm' },
  { label: 'Z', unit: 'mm' },
  { label: 'Rx', unit: '°' },
  { label: 'Ry', unit: '°' },
  { label: 'Rz', unit: '°' }
]

const cartesianPose = computed(() =>
  poseLabels.map((item, index) => ({
    label: item.label,
    value: Number((endPose.value[index] || 0).toFixed(1)),
    unit: item.unit
  }))
)

const formatValue = (value, decimals) => {
  return value.toFixed(decimals)
}
</script>

<template>
  <aside class="right-panel">
    <div v-for="(item, index) in orbitalData" :key="index" class="orbital-item">
      <span class="orbital-label">{{ item.label }}</span>
      <div class="orbital-bar-container">
        <div class="orbital-bar">
          <div class="orbital-bar-fill" :style="{ width: item.fill + '%' }"></div>
        </div>
        <div class="orbital-values">
          <span class="orbital-value">
            {{ formatValue(item.cmdValue, item.decimals) }}<span class="orbital-unit">{{ item.unit }}</span>
          </span>
          <span class="orbital-value-actual">
            {{ formatValue(item.actValue, item.decimals) }}<span class="orbital-unit-actual">{{ item.unit }}</span>
          </span>
        </div>
      </div>
    </div>

    <!-- Cartesian Pose -->
    <div class="cartesian-panel">
      <div class="cartesian-title">Cartesian Pose</div>
      <div class="cartesian-grid">
        <div v-for="(pose, index) in cartesianPose" :key="index" class="cartesian-item">
          <span class="cartesian-label">{{ pose.label }}</span>
          <span class="cartesian-value">{{ pose.value }}</span>
          <span class="cartesian-unit">{{ pose.unit }}</span>
        </div>
      </div>
    </div>


  </aside>
</template>

<style scoped>
.right-panel {
  display: flex;
  flex-direction: column;
  gap: 6px;
  padding-top: 8px;
}

.orbital-item {
  display: flex;
  flex-direction: column;
  gap: 1px;
}

.orbital-label {
  font-size: 12px;
  color: var(--text-secondary);
  letter-spacing: 0.3px;
}

.orbital-bar-container {
  display: flex;
  align-items: flex-start;
  gap: 10px;
}

.orbital-bar {
  width: 75px;
  height: 4px;
  background: rgba(59, 130, 246, 0.15);
  border-radius: 2px;
  overflow: hidden;
  margin-top: 7px;
}

.orbital-bar-fill {
  height: 100%;
  background: linear-gradient(90deg, var(--accent-blue), var(--accent-cyan));
  border-radius: 2px;
  transition: width 0.5s ease;
  box-shadow: 0 0 6px rgba(59, 130, 246, 0.4);
}

.orbital-values {
  display: flex;
  flex-direction: column;
  min-width: 105px;
  align-items: flex-end;
}

.orbital-value {
  font-family: 'Oxanium', sans-serif;
  font-size: 18px;
  font-weight: 500;
  color: var(--text-primary);
  text-align: right;
  line-height: 1.1;
}

.orbital-unit {
  font-size: 14px;
  color: var(--text-secondary);
  margin-left: 3px;
}

.orbital-value-actual {
  font-family: 'Oxanium', sans-serif;
  font-size: 12px;
  font-weight: 400;
  color: var(--text-secondary);
  text-align: right;
  line-height: 1.1;
  opacity: 0.6;
}

.orbital-unit-actual {
  font-size: 10px;
  color: var(--text-secondary);
  margin-left: 2px;
}

.cartesian-panel {
  background: rgba(10, 14, 26, 0.6);
  border: 1px solid var(--border-color);
  border-radius: 8px;
  padding: 10px;
  margin-top: 2px;
}

.cartesian-title {
  font-size: 10px;
  color: var(--text-secondary);
  text-transform: uppercase;
  letter-spacing: 2px;
  margin-bottom: 8px;
  text-align: center;
}

.cartesian-grid {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 6px;
}

.cartesian-item {
  display: flex;
  flex-direction: column;
  align-items: center;
  padding: 5px 4px;
  background: rgba(0, 0, 0, 0.3);
  border-radius: 4px;
}

.cartesian-label {
  font-size: 9px;
  color: var(--text-secondary);
  text-transform: uppercase;
  letter-spacing: 1px;
  margin-bottom: 2px;
}

.cartesian-value {
  font-family: 'Oxanium', sans-serif;
  font-size: 15px;
  font-weight: 500;
  color: var(--text-primary);
  line-height: 1;
}

.cartesian-unit {
  font-size: 9px;
  color: var(--text-secondary);
  margin-top: 1px;
}


</style>
