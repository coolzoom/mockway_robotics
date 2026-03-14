<script setup>
import SpeedGauge from './SpeedGauge.vue'
</script>

<template>
  <div class="gauge-row">
    <SpeedGauge :size="145" />
  </div>
</template>

<style scoped>
.gauge-row {
  display: flex;
  justify-content: center;
  gap: 45px;
  margin-bottom: 15px;
}
</style>
