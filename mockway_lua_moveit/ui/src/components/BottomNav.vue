<script setup>
const props = defineProps({
  activeNavIcon: {
    type: String,
    default: 'overview'
  }
})

const emit = defineEmits(['update:activeNavIcon'])

const setActiveNavIcon = (iconId) => {
  emit('update:activeNavIcon', iconId)
}
</script>

<template>
  <nav class="bottom-nav">
    <div class="nav-icons">
      <!-- Overview -->
      <div
        :class="['nav-icon', { active: activeNavIcon === 'overview' }]"
        @click="setActiveNavIcon('overview')"
      >
        <svg viewBox="0 0 24 24">
          <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm0 18c-4.41 0-8-3.59-8-8s3.59-8 8-8 8 3.59 8 8-3.59 8-8 8zm-1-13h2v6h-2zm0 8h2v2h-2z"/>
        </svg>
        <span>Overview</span>
      </div>

      <!-- Motion -->
      <div
        :class="['nav-icon', { active: activeNavIcon === 'motion' }]"
        @click="setActiveNavIcon('motion')"
      >
        <svg viewBox="0 0 24 24">
          <path d="M13.49 5.48c1.1 0 2-.9 2-2s-.9-2-2-2-2 .9-2 2 .9 2 2 2zm-3.6 13.9l1-4.4 2.1 2v6h2v-7.5l-2.1-2 .6-3c1.3 1.5 3.3 2.5 5.5 2.5v-2c-1.9 0-3.5-1-4.3-2.4l-1-1.6c-.4-.6-1-1-1.7-1-.3 0-.5.1-.8.1l-5.2 2.2v4.7h2v-3.4l1.8-.7-1.6 8.1-4.9-1-.4 2 7 1.4z"/>
        </svg>
        <span>Motion</span>
      </div>

      <!-- Program -->
      <div
        :class="['nav-icon', { active: activeNavIcon === 'program' }]"
        @click="setActiveNavIcon('program')"
      >
        <svg viewBox="0 0 24 24">
          <path d="M9.4 16.6L4.8 12l4.6-4.6L8 6l-6 6 6 6 1.4-1.4zm5.2 0l4.6-4.6-4.6-4.6L16 6l6 6-6 6-1.4-1.4z"/>
        </svg>
        <span>Program</span>
      </div>

      <!-- Settings -->
      <div
        :class="['nav-icon', { active: activeNavIcon === 'settings' }]"
        @click="setActiveNavIcon('settings')"
      >
        <svg viewBox="0 0 24 24">
          <path d="M19.14,12.94c0.04-0.3,0.06-0.61,0.06-0.94c0-0.32-0.02-0.64-0.07-0.94l2.03-1.58c0.18-0.14,0.23-0.41,0.12-0.61 l-1.92-3.32c-0.12-0.22-0.37-0.29-0.59-0.22l-2.39,0.96c-0.5-0.38-1.03-0.7-1.62-0.94L14.4,2.81c-0.04-0.24-0.24-0.41-0.48-0.41 h-3.84c-0.24,0-0.43,0.17-0.47,0.41L9.25,5.35C8.66,5.59,8.12,5.92,7.63,6.29L5.24,5.33c-0.22-0.08-0.47,0-0.59,0.22L2.74,8.87 C2.62,9.08,2.66,9.34,2.86,9.48l2.03,1.58C4.84,11.36,4.8,11.69,4.8,12s0.02,0.64,0.07,0.94l-2.03,1.58 c-0.18,0.14-0.23,0.41-0.12,0.61l1.92,3.32c0.12,0.22,0.37,0.29,0.59,0.22l2.39-0.96c0.5,0.38,1.03,0.7,1.62,0.94l0.36,2.54 c0.05,0.24,0.24,0.41,0.48,0.41h3.84c0.24,0,0.44-0.17,0.47-0.41l0.36-2.54c0.59-0.24,1.13-0.56,1.62-0.94l2.39,0.96 c0.22,0.08,0.47,0,0.59-0.22l1.92-3.32c0.12-0.22,0.07-0.47-0.12-0.61L19.14,12.94z M12,15.6c-1.98,0-3.6-1.62-3.6-3.6 s1.62-3.6,3.6-3.6s3.6,1.62,3.6,3.6S13.98,15.6,12,15.6z"/>
        </svg>
        <span>Settings</span>
      </div>
    </div>

  </nav>
</template>

<style scoped>
.bottom-nav {
  display: flex;
  justify-content: center;
  align-items: center;
  padding: 15px 0 8px;
  margin-top: auto;
}

.nav-icons {
  display: flex;
  gap: 2px;
}

.nav-icon {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 6px;
  padding: 10px 13px;
  cursor: pointer;
  transition: all 0.2s;
  border-radius: 6px;
  min-width: 55px;
}

.nav-icon:hover {
  background: rgba(255, 255, 255, 0.05);
}

.nav-icon.active {
  background: rgba(255, 255, 255, 0.08);
}

.nav-icon svg {
  width: 24px;
  height: 24px;
  fill: var(--text-secondary);
  transition: fill 0.2s;
}

.nav-icon.active svg {
  fill: var(--accent-orange);
}

.nav-icon:hover svg {
  fill: var(--text-primary);
}

.nav-icon span {
  font-size: 9px;
  text-transform: uppercase;
  letter-spacing: 0.3px;
  color: var(--text-secondary);
  transition: color 0.2s;
}

.nav-icon.active span {
  color: var(--text-primary);
}

</style>
