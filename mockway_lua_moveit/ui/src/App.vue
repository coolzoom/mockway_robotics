<script setup>
import { ref } from 'vue'
import StatusPanel from './components/StatusPanel.vue'
import GaugeRow from './components/GaugeRow.vue'
import DragonCapsule from './components/DragonCapsule.vue'
import OrbitalData from './components/OrbitalData.vue'
import BottomNav from './components/BottomNav.vue'
import LuaEditor from './components/LuaEditor.vue'
import ManualControl from './components/ManualControl.vue'
import SystemSettings from './components/SystemSettings.vue'

const activeNavIcon = ref('overview')
</script>

<template>
  <div class="container">
    <header class="header">
      <h1>Mockway</h1>
    </header>

    <main class="main-content">
      <!-- Left Panel -->
      <StatusPanel />

      <!-- Center Panel -->
      <section class="center-panel">
        <GaugeRow />
        <DragonCapsule />
      </section>

      <!-- Right Panel -->
      <OrbitalData />
    </main>

    <!-- Lua Editor Modal Overlay -->
    <LuaEditor
      v-if="activeNavIcon === 'program'"
      @close="activeNavIcon = 'overview'"
    />

    <!-- Manual Control Modal Overlay -->
    <ManualControl
      v-if="activeNavIcon === 'motion'"
      @close="activeNavIcon = 'overview'"
    />

    <!-- System Settings Modal Overlay -->
    <SystemSettings
      v-if="activeNavIcon === 'settings'"
      @close="activeNavIcon = 'overview'"
    />

    <!-- Bottom Navigation -->
    <BottomNav
      v-model:activeNavIcon="activeNavIcon"
    />
  </div>
</template>

<style>
@import url('https://fonts.googleapis.com/css2?family=Rajdhani:wght@300;400;500;600;700&family=Oxanium:wght@200;300;400;500;600;700&display=swap');

* {
  margin: 0;
  padding: 0;
  box-sizing: border-box;
}

:root {
  --bg-primary: #0a0e1a;
  --bg-secondary: #111827;
  --bg-card: rgba(20, 30, 50, 0.6);
  --text-primary: #ffffff;
  --text-secondary: #7a8599;
  --accent-blue: #3b82f6;
  --accent-cyan: #06b6d4;
  --accent-green: #22c55e;
  --accent-yellow: #eab308;
  --accent-orange: #f97316;
  --accent-red: #ef4444;
  --border-color: rgba(59, 130, 246, 0.3);
  --glow-blue: rgba(59, 130, 246, 0.4);
}

html, body {
  height: 100%;
}

body {
  font-family: 'Rajdhani', sans-serif;
  background: var(--bg-primary);
  color: var(--text-primary);
  min-height: 100vh;
  overflow-x: hidden;
  background:
    radial-gradient(ellipse 100% 50% at 50% 0%, rgba(25, 40, 70, 0.5) 0%, transparent 60%),
    linear-gradient(180deg, #0d1220 0%, #080c15 100%);
}

#app {
  width: 100%;
  min-height: 100vh;
}

.container {
  width: 100%;
  max-width: 1520px;
  margin: 0 auto;
  padding: 15px 35px 20px;
  height: 100vh;
  display: flex;
  flex-direction: column;
}

.header {
  text-align: center;
  padding: 8px 0 15px;
}

.header h1 {
  font-family: 'Oxanium', sans-serif;
  font-size: 26px;
  font-weight: 400;
  letter-spacing: 10px;
  text-transform: uppercase;
  color: var(--text-primary);
}

.main-content {
  display: grid;
  grid-template-columns: 250px 1fr 240px;
  gap: 30px;
  flex: 1;
  min-height: 0;
  overflow: hidden;
}

.center-panel {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: flex-start;
  padding-top: 5px;
  min-height: 0;
}

</style>
