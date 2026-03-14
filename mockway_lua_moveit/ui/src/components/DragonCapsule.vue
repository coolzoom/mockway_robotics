<script setup>
import Dragon3D from './Dragon3D.vue'
import { useRobotSSE } from '../composables/useRobotSSE.js'

const { errorId } = useRobotSSE()
</script>

<template>
  <div class="capsule-section">
    <div class="dragon-center">
      <Dragon3D />

      <!-- Robot Status -->
      <div class="cabin-mics">
        <span v-if="errorId === 0" class="cabin-mics-text">Robot Status: <span class="cabin-mics-status status-ok">Operating</span></span>
        <span v-else class="cabin-mics-text">Robot Status: <span class="cabin-mics-status status-error">ERROR</span></span>
      </div>
    </div>
  </div>
</template>

<style scoped>
.capsule-section {
  display: flex;
  flex-direction: column;
  align-items: center;
  width: 100%;
  flex: 1;
  min-height: 0;
}

.dragon-center {
  display: flex;
  flex-direction: column;
  align-items: center;
  width: 100%;
  flex: 1;
  min-height: 0;
}

.cabin-mics {
  margin-top: 10px;
  text-align: center;
}

.cabin-mics-text {
  font-size: 12px;
  color: var(--text-secondary);
  text-transform: uppercase;
  letter-spacing: 2px;
}

.cabin-mics-status {
  font-weight: 600;
}

.status-ok {
  color: #00ff88;
  animation: pulse 1.5s ease-in-out infinite;
}

.status-error {
  color: var(--accent-red);
  animation: pulse 1.5s ease-in-out infinite;
}

@keyframes pulse {
  0%, 100% { opacity: 1; }
  50% { opacity: 0.5; }
}

@media (max-width: 1024px) {
  .capsule-section {
    margin-top: 0;
  }

  .cabin-mics-text {
    font-size: 11px;
  }
}

@media (max-width: 768px) {
  .cabin-mics {
    margin-top: 8px;
  }

  .cabin-mics-text {
    font-size: 10px;
  }
}
</style>
