import { ref, onBeforeUnmount, readonly } from 'vue'

const jointAngles = ref([0, -90, 90, 0, 90, 0])
const commandJoints = ref([0, -90, 90, 0, 90, 0])
const endPose = ref([0, 0, 0, 0, 0, 0])
const errorId = ref(0)
const errorMessage = ref('')
const globalRatio = ref(30)
const connected = ref(false)

let eventSource = null
let refCount = 0
let reconnectTimer = null

function connect() {
  if (eventSource) return

  eventSource = new EventSource('/api/joints')

  eventSource.onopen = () => {
    connected.value = true
    console.log('SSE connection established')
  }

  eventSource.onmessage = (event) => {
    try {
      const data = JSON.parse(event.data)
      if (data.joints && Array.isArray(data.joints)) {
        jointAngles.value = data.joints.slice(0, 6)
      }
      if (data.commandJoints && Array.isArray(data.commandJoints)) {
        commandJoints.value = data.commandJoints.slice(0, 6)
      }
      if (data.pose && Array.isArray(data.pose)) {
        endPose.value = data.pose.slice(0, 6)
      }
      if (data.errorId !== undefined) {
        errorId.value = data.errorId
      }
      if (data.errorMessage !== undefined) {
        errorMessage.value = data.errorMessage
      }
      if (data.globalRatio !== undefined) {
        globalRatio.value = data.globalRatio
      }
    } catch (error) {
      console.error('Error parsing SSE data:', error)
    }
  }

  eventSource.onerror = () => {
    connected.value = false
    console.error('SSE connection error')
    disconnect()
    reconnectTimer = setTimeout(connect, 5000)
  }
}

function disconnect() {
  if (eventSource) {
    eventSource.close()
    eventSource = null
  }
}

export function useRobotSSE() {
  refCount++
  if (refCount === 1) {
    connect()
  }

  onBeforeUnmount(() => {
    refCount--
    if (refCount <= 0) {
      refCount = 0
      clearTimeout(reconnectTimer)
      disconnect()
      connected.value = false
    }
  })

  return {
    jointAngles: readonly(jointAngles),
    commandJoints: readonly(commandJoints),
    endPose: readonly(endPose),
    errorId: readonly(errorId),
    errorMessage: readonly(errorMessage),
    globalRatio: readonly(globalRatio),
    connected: readonly(connected)
  }
}
