<script setup>
import { ref, onMounted, onUnmounted, watch } from 'vue'
import * as THREE from 'three'
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js'
import { STLLoader } from 'three/examples/jsm/loaders/STLLoader.js'
import { ColladaLoader } from 'three/examples/jsm/loaders/ColladaLoader.js'
import URDFLoader from 'urdf-loader'
import { useRobotSSE } from '../composables/useRobotSSE.js'

const { jointAngles } = useRobotSSE()

const containerRef = ref(null)
let scene, camera, renderer, controls, robot, animationId
let endEffectorLink = null
let axesHelper = null
let trajectoryLine = null
let trajectoryPoints = []
const MAX_TRAJECTORY_POINTS = 500
let resizeObserver = null

// Update robot joints when SSE data changes
watch(jointAngles, (angles) => {
  if (!robot || !robot.joints) return

  // Try common URDF joint naming conventions
  const jointNames = Object.keys(robot.joints)
  const movableJoints = jointNames.filter(name => {
    const joint = robot.joints[name]
    return joint.jointType && joint.jointType !== 'fixed'
  })

  movableJoints.forEach((name, index) => {
    if (index < angles.length) {
      robot.joints[name].setJointValue(angles[index] * Math.PI / 180)
    }
  })

  updateTrajectory()
})

const handleResize = () => {
  if (!containerRef.value || !renderer || !camera) return
  const width = containerRef.value.clientWidth
  const height = containerRef.value.clientHeight
  if (width === 0 || height === 0) return
  camera.aspect = width / height
  camera.updateProjectionMatrix()
  renderer.setSize(width, height)
}

const initScene = () => {
  const width = containerRef.value.clientWidth || 260
  const height = containerRef.value.clientHeight || 380

  // Scene
  scene = new THREE.Scene()

  // Camera - positioned to view the robot from a good angle
  camera = new THREE.PerspectiveCamera(35, width / height, 0.1, 1000)
  camera.position.set(3, 2, 4)
  camera.lookAt(0, 0, 0)

  // Renderer
  renderer = new THREE.WebGLRenderer({
    antialias: true,
    alpha: true
  })
  renderer.setSize(width, height)
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2))
  renderer.setClearColor(0x000000, 0)
  renderer.toneMapping = THREE.ACESFilmicToneMapping
  renderer.toneMappingExposure = 1.2
  containerRef.value.appendChild(renderer.domElement)

  // Orbit Controls - for mouse interaction
  controls = new OrbitControls(camera, renderer.domElement)
  controls.enableDamping = true
  controls.dampingFactor = 0.05
  controls.enableZoom = true
  controls.enablePan = false
  controls.minDistance = 3
  controls.maxDistance = 12
  controls.minPolarAngle = Math.PI * 0.1
  controls.maxPolarAngle = Math.PI * 0.9
  controls.rotateSpeed = 0.5
  controls.target.set(0, 0, 0)

  // Observe container resize
  resizeObserver = new ResizeObserver(handleResize)
  resizeObserver.observe(containerRef.value)

  // Lights
  setupLights()

  // Load URDF Robot model
  loadURDFModel()

  // Start animation loop
  animate()
}

const setupLights = () => {
  // Ambient light
  const ambientLight = new THREE.AmbientLight(0xffffff, 1.2)
  scene.add(ambientLight)

  // Main key light (top right)
  const keyLight = new THREE.DirectionalLight(0xffffff, 2.0)
  keyLight.position.set(3, 4, 5)
  scene.add(keyLight)

  // Fill light (left side, softer)
  const fillLight = new THREE.DirectionalLight(0x88aaff, 0.8)
  fillLight.position.set(-4, 2, 3)
  scene.add(fillLight)

  // Rim light (back)
  const rimLight = new THREE.DirectionalLight(0xffffff, 1.0)
  rimLight.position.set(0, 2, -5)
  scene.add(rimLight)

  // Bottom fill
  const bottomLight = new THREE.DirectionalLight(0x4466aa, 0.6)
  bottomLight.position.set(0, -3, 2)
  scene.add(bottomLight)
}

const loadURDFModel = () => {
  const loader = new URDFLoader()

  // Set up the package path resolver for mesh files
  // The URDF uses package://mockway_description/meshes/xxx.stl
  // Map the package name to the correct base path
  loader.packages = {
    'mockway_description': window.location.origin
  }

  // Optional: Custom mesh loading callback for more control
  loader.loadMeshCb = (path, manager, done) => {
    // Replace package:// URLs with actual paths
    const correctedPath = path.replace('package://mockway_description', '')
    console.log('Loading mesh from:', correctedPath)

    const ext = correctedPath.split('.').pop().toLowerCase()

    if (ext === 'dae') {
      const colladaLoader = new ColladaLoader(manager)
      colladaLoader.load(
        correctedPath,
        (collada) => {
          done(collada.scene)
        },
        undefined,
        (err) => {
          console.error('Error loading DAE mesh:', correctedPath, err)
          done(null)
        }
      )
    } else {
      const stlLoader = new STLLoader(manager)
      stlLoader.load(
        correctedPath,
        (geometry) => {
          const material = new THREE.MeshPhongMaterial({
            color: 0x999999,
            specular: 0x111111,
            shininess: 200
          })
          const mesh = new THREE.Mesh(geometry, material)
          done(mesh)
        },
        undefined,
        (err) => {
          console.error('Error loading STL mesh:', correctedPath, err)
          done(null)
        }
      )
    }
  }

  loader.load(
    '/urdf/mockway_description.urdf',
    (urdfRobot) => {
      robot = urdfRobot

      // Adjust the model's position and scale to fit the viewport
      // Lower the base position and make the model larger
      robot.position.set(0, -0.8, 0)
      robot.scale.set(4.5, 4.5, 4.5)

      // Rotate to make Z-axis point up (URDF/ROS convention)
      // In Three.js, Y is up by default, so we rotate -90° around X-axis
      // to align URDF's Z-up to Three.js's Y-up
      robot.rotation.x = -Math.PI / 2

      scene.add(robot)
      setupEndEffector()

      console.log('URDF Robot loaded successfully')
      console.log('Robot structure:', robot)
    },
    undefined,
    (error) => {
      console.error('Error loading URDF model:', error)
    }
  )
}

const setupEndEffector = () => {
  if (!robot || !robot.links) return

  endEffectorLink = robot.links['link6']
  if (!endEffectorLink) {
    console.warn('End-effector link6 not found')
    return
  }

  // Coordinate axes on end-effector (RGB = XYZ)
  axesHelper = new THREE.AxesHelper(0.05)
  axesHelper.material.depthTest = false
  axesHelper.renderOrder = 999
  endEffectorLink.add(axesHelper)

  // Trajectory line
  const geometry = new THREE.BufferGeometry()
  const positions = new Float32Array(MAX_TRAJECTORY_POINTS * 3)
  const colors = new Float32Array(MAX_TRAJECTORY_POINTS * 3)
  geometry.setAttribute('position', new THREE.BufferAttribute(positions, 3))
  geometry.setAttribute('color', new THREE.BufferAttribute(colors, 3))
  geometry.setDrawRange(0, 0)

  const material = new THREE.LineBasicMaterial({
    vertexColors: true,
    transparent: true,
    opacity: 0.9
  })

  trajectoryLine = new THREE.Line(geometry, material)
  trajectoryLine.frustumCulled = false
  scene.add(trajectoryLine)
}

const updateTrajectory = () => {
  if (!endEffectorLink || !trajectoryLine) return

  // Force world matrix update through the chain
  robot.updateMatrixWorld(true)

  const worldPos = new THREE.Vector3()
  endEffectorLink.getWorldPosition(worldPos)

  // Skip if position hasn't changed enough
  if (trajectoryPoints.length > 0) {
    const last = trajectoryPoints[trajectoryPoints.length - 1]
    if (worldPos.distanceTo(last) < 0.001) return
  }

  trajectoryPoints.push(worldPos.clone())

  if (trajectoryPoints.length > MAX_TRAJECTORY_POINTS) {
    trajectoryPoints.shift()
  }

  // Update positions and colors (fade from dim to bright cyan)
  const posAttr = trajectoryLine.geometry.attributes.position
  const colAttr = trajectoryLine.geometry.attributes.color
  const count = trajectoryPoints.length

  for (let i = 0; i < count; i++) {
    const t = count > 1 ? i / (count - 1) : 1
    posAttr.array[i * 3] = trajectoryPoints[i].x
    posAttr.array[i * 3 + 1] = trajectoryPoints[i].y
    posAttr.array[i * 3 + 2] = trajectoryPoints[i].z
    // Fade: older points dimmer, newer points brighter cyan
    colAttr.array[i * 3] = t * 0.2          // R
    colAttr.array[i * 3 + 1] = t * 0.9 + 0.1 // G
    colAttr.array[i * 3 + 2] = t             // B
  }

  posAttr.needsUpdate = true
  colAttr.needsUpdate = true
  trajectoryLine.geometry.setDrawRange(0, count)
}

const animate = () => {
  animationId = requestAnimationFrame(animate)

  // Update controls
  if (controls) {
    controls.update()
  }

  renderer.render(scene, camera)
}

onMounted(() => {
  initScene()
})

onUnmounted(() => {
  if (resizeObserver) {
    resizeObserver.disconnect()
  }
  if (animationId) {
    cancelAnimationFrame(animationId)
  }
  if (controls) {
    controls.dispose()
  }
  if (renderer) {
    renderer.dispose()
  }
  if (axesHelper) {
    axesHelper.geometry.dispose()
    axesHelper.material.dispose()
  }
  if (trajectoryLine) {
    trajectoryLine.geometry.dispose()
    trajectoryLine.material.dispose()
  }
  trajectoryPoints = []
})
</script>

<template>
  <div ref="containerRef" class="dragon-3d-container"></div>
</template>

<style scoped>
.dragon-3d-container {
  width: 100%;
  height: 100%;
  display: flex;
  justify-content: center;
  align-items: center;
  cursor: grab;
}

.dragon-3d-container:active {
  cursor: grabbing;
}

.dragon-3d-container canvas {
  filter: drop-shadow(0 0 20px rgba(100, 150, 255, 0.15));
}
</style>
