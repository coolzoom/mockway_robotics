import * as Blockly from 'blockly/core'

// ======================== Colors ========================
const SERVO_HUE  = 30    // orange
const MOTION_HUE = 140   // green
const PARAM_HUE  = 270   // purple
const STATUS_HUE = 210   // blue
const TOOL_HUE   = 45    // yellow
const DATA_HUE   = 230   // grey-blue

// ======================== Servo Blocks ========================

Blockly.Blocks['robot_servo_mode'] = {
  init() {
    this.appendDummyInput()
      .appendField('ServoMode')
      .appendField(new Blockly.FieldDropdown([
        ['joint_jog', 'joint_jog'],
        ['twist',     'twist']
      ]), 'MODE')
    this.setPreviousStatement(true, null)
    this.setNextStatement(true, null)
    this.setColour(SERVO_HUE)
    this.setTooltip('ServoMode(mode) — switch servo command type: joint_jog or twist')
  }
}

Blockly.Blocks['robot_servo_joint'] = {
  init() {
    this.appendDummyInput()
      .appendField('ServoJoint  J')
      .appendField(new Blockly.FieldDropdown([
        ['1','1'],['2','2'],['3','3'],['4','4'],['5','5'],['6','6']
      ]), 'INDEX')
    this.appendValueInput('VEL').setCheck('Number').appendField('vel deg/s')
    this.setInputsInline(true)
    this.setPreviousStatement(true, null)
    this.setNextStatement(true, null)
    this.setColour(SERVO_HUE)
    this.setTooltip('ServoJoint(idx, vel) — single joint velocity jog (deg/s). Non-blocking.')
  }
}

Blockly.Blocks['robot_servo_joints'] = {
  init() {
    this.appendValueInput('V1').setCheck('Number').appendField('ServoJoints  V1')
    ;['V2','V3','V4','V5','V6'].forEach(l => {
      this.appendValueInput(l).setCheck('Number').appendField(l)
    })
    this.setInputsInline(true)
    this.setPreviousStatement(true, null)
    this.setNextStatement(true, null)
    this.setColour(SERVO_HUE)
    this.setTooltip('ServoJoints({v1..v6}) — 6-axis velocity jog (deg/s). Non-blocking.')
  }
}

Blockly.Blocks['robot_servo_cart'] = {
  init() {
    this.appendValueInput('VX').setCheck('Number').appendField('ServoCart  Vx')
    ;['VY','VZ','RX','RY','RZ'].forEach(l => {
      this.appendValueInput(l).setCheck('Number').appendField(l)
    })
    this.setInputsInline(true)
    this.setPreviousStatement(true, null)
    this.setNextStatement(true, null)
    this.setColour(SERVO_HUE)
    this.setTooltip('ServoCart(vx,vy,vz,rx,ry,rz) — Cartesian velocity jog: Vx/Vy/Vz mm/s, Rx/Ry/Rz deg/s. Non-blocking.')
  }
}

Blockly.Blocks['robot_servo_stop'] = {
  init() {
    this.appendDummyInput().appendField('ServoStop()')
    this.setPreviousStatement(true, null)
    this.setNextStatement(true, null)
    this.setColour(SERVO_HUE)
    this.setTooltip('ServoStop() — stop servo motion by publishing zero velocity')
  }
}

// ======================== PTP Motion Blocks ========================

Blockly.Blocks['robot_move_named'] = {
  init() {
    this.appendDummyInput()
      .appendField('MoveNamed')
      .appendField(new Blockly.FieldTextInput('home'), 'NAME')
    this.setPreviousStatement(true, null)
    this.setNextStatement(true, null)
    this.setColour(MOTION_HUE)
    this.setTooltip('MoveNamed(name) — PTP motion to SRDF named state (blocking)')
  }
}

Blockly.Blocks['robot_move_j'] = {
  init() {
    this.appendValueInput('J1').setCheck('Number').appendField('MoveJ  J1')
    ;['J2','J3','J4','J5','J6'].forEach(l => {
      this.appendValueInput(l).setCheck('Number').appendField(l)
    })
    this.setInputsInline(true)
    this.setPreviousStatement(true, null)
    this.setNextStatement(true, null)
    this.setColour(MOTION_HUE)
    this.setTooltip('MoveJ({j1..j6}) — PTP motion to joint positions (deg, blocking)')
  }
}

Blockly.Blocks['robot_move_pose'] = {
  init() {
    this.appendValueInput('X').setCheck('Number').appendField('MovePose  X')
    ;['Y','Z','Roll','Pitch','Yaw'].forEach(l => {
      this.appendValueInput(l).setCheck('Number').appendField(l)
    })
    this.setInputsInline(true)
    this.setPreviousStatement(true, null)
    this.setNextStatement(true, null)
    this.setColour(MOTION_HUE)
    this.setTooltip('MovePose(x,y,z,roll,pitch,yaw) — PTP to Cartesian pose (mm, deg, blocking)')
  }
}

// ======================== Linear Motion Blocks ========================

Blockly.Blocks['robot_move_l'] = {
  init() {
    this.appendValueInput('X').setCheck('Number').appendField('MoveL  X')
    ;['Y','Z','Roll','Pitch','Yaw'].forEach(l => {
      this.appendValueInput(l).setCheck('Number').appendField(l)
    })
    this.setInputsInline(true)
    this.setPreviousStatement(true, null)
    this.setNextStatement(true, null)
    this.setColour(MOTION_HUE)
    this.setTooltip('MoveL(x,y,z,roll,pitch,yaw) — linear motion to Cartesian pose (mm, deg, blocking)')
  }
}

Blockly.Blocks['robot_move_l_rel'] = {
  init() {
    this.appendValueInput('DX').setCheck('Number').appendField('MoveLRel  dX')
    ;['DY','DZ','DRX','DRY','DRZ'].forEach(l => {
      this.appendValueInput(l).setCheck('Number').appendField(l)
    })
    this.setInputsInline(true)
    this.setPreviousStatement(true, null)
    this.setNextStatement(true, null)
    this.setColour(MOTION_HUE)
    this.setTooltip('MoveLRel(dx,dy,dz,drx,dry,drz) — relative linear in base frame (mm, deg, blocking)')
  }
}

Blockly.Blocks['robot_move_l_rel_tool'] = {
  init() {
    this.appendValueInput('DX').setCheck('Number').appendField('MoveLRelTool  dX')
    ;['DY','DZ','DRX','DRY','DRZ'].forEach(l => {
      this.appendValueInput(l).setCheck('Number').appendField(l)
    })
    this.setInputsInline(true)
    this.setPreviousStatement(true, null)
    this.setNextStatement(true, null)
    this.setColour(MOTION_HUE)
    this.setTooltip('MoveLRelTool(dx,dy,dz,drx,dry,drz) — relative linear in tool frame (mm, deg, blocking)')
  }
}

// ======================== Parameter Blocks ========================

Blockly.Blocks['robot_set_vel_scale'] = {
  init() {
    this.appendValueInput('FACTOR').setCheck('Number').appendField('SetVelScale')
    this.setPreviousStatement(true, null)
    this.setNextStatement(true, null)
    this.setColour(PARAM_HUE)
    this.setTooltip('SetVelScale(f) — set max velocity scaling factor [0.01, 1.0]')
  }
}

Blockly.Blocks['robot_set_acc_scale'] = {
  init() {
    this.appendValueInput('FACTOR').setCheck('Number').appendField('SetAccScale')
    this.setPreviousStatement(true, null)
    this.setNextStatement(true, null)
    this.setColour(PARAM_HUE)
    this.setTooltip('SetAccScale(f) — set max acceleration scaling factor [0.01, 1.0]')
  }
}

Blockly.Blocks['robot_set_plan_time'] = {
  init() {
    this.appendValueInput('SECONDS').setCheck('Number').appendField('SetPlanTime')
    this.appendDummyInput().appendField('s')
    this.setInputsInline(true)
    this.setPreviousStatement(true, null)
    this.setNextStatement(true, null)
    this.setColour(PARAM_HUE)
    this.setTooltip('SetPlanTime(t) — set planning timeout (seconds)')
  }
}

Blockly.Blocks['robot_set_planner'] = {
  init() {
    this.appendDummyInput()
      .appendField('SetPlanner')
      .appendField(new Blockly.FieldDropdown([
        ['RRTConnect', 'RRTConnect'],
        ['RRT',        'RRT'],
        ['PRM',        'PRM'],
        ['LIN',        'LIN'],
        ['CIRC',       'CIRC'],
        ['PTP',        'PTP']
      ]), 'PLANNER')
    this.setPreviousStatement(true, null)
    this.setNextStatement(true, null)
    this.setColour(PARAM_HUE)
    this.setTooltip('SetPlanner(id) — switch motion planner')
  }
}

// ======================== Status Blocks ========================

Blockly.Blocks['robot_get_joints'] = {
  init() {
    this.appendDummyInput().appendField('GetJoints()')
    this.setOutput(true, null)
    this.setColour(STATUS_HUE)
    this.setTooltip('GetJoints() — current joint positions as {j1..j6} (deg)')
  }
}

Blockly.Blocks['robot_get_pose'] = {
  init() {
    this.appendDummyInput().appendField('GetPose()')
    this.setOutput(true, null)
    this.setColour(STATUS_HUE)
    this.setTooltip('GetPose() — current end-effector pose as {x,y,z,roll,pitch,yaw} (mm, deg)')
  }
}

// ======================== Tool Blocks ========================

Blockly.Blocks['robot_sleep'] = {
  init() {
    this.appendValueInput('MS').setCheck('Number').appendField('Sleep')
    this.appendDummyInput().appendField('ms')
    this.setInputsInline(true)
    this.setPreviousStatement(true, null)
    this.setNextStatement(true, null)
    this.setColour(TOOL_HUE)
    this.setTooltip('Sleep(ms) — pause execution (milliseconds)')
  }
}

Blockly.Blocks['robot_log'] = {
  init() {
    this.appendValueInput('MSG').setCheck(null).appendField('Log')
    this.setInputsInline(true)
    this.setPreviousStatement(true, null)
    this.setNextStatement(true, null)
    this.setColour(TOOL_HUE)
    this.setTooltip('Log(msg) — output ROS INFO log message')
  }
}

Blockly.Blocks['robot_log_warn'] = {
  init() {
    this.appendValueInput('MSG').setCheck(null).appendField('LogWarn')
    this.setInputsInline(true)
    this.setPreviousStatement(true, null)
    this.setNextStatement(true, null)
    this.setColour(TOOL_HUE)
    this.setTooltip('LogWarn(msg) — output ROS WARN log message')
  }
}

Blockly.Blocks['robot_log_error'] = {
  init() {
    this.appendValueInput('MSG').setCheck(null).appendField('LogError')
    this.setInputsInline(true)
    this.setPreviousStatement(true, null)
    this.setNextStatement(true, null)
    this.setColour(TOOL_HUE)
    this.setTooltip('LogError(msg) — output ROS ERROR log message')
  }
}

Blockly.Blocks['robot_ok'] = {
  init() {
    this.appendDummyInput().appendField('Ok()')
    this.setOutput(true, 'Boolean')
    this.setColour(TOOL_HUE)
    this.setTooltip('Ok() — returns true while ROS node is running (use as while-loop condition)')
  }
}

Blockly.Blocks['robot_deg_rad'] = {
  init() {
    this.appendValueInput('DEG').setCheck('Number').appendField('DegRad')
    this.setInputsInline(true)
    this.setOutput(true, 'Number')
    this.setColour(TOOL_HUE)
    this.setTooltip('DegRad(d) — convert degrees to radians')
  }
}

Blockly.Blocks['robot_rad_deg'] = {
  init() {
    this.appendValueInput('RAD').setCheck('Number').appendField('RadDeg')
    this.setInputsInline(true)
    this.setOutput(true, 'Number')
    this.setColour(TOOL_HUE)
    this.setTooltip('RadDeg(r) — convert radians to degrees')
  }
}

Blockly.Blocks['robot_print'] = {
  init() {
    this.appendValueInput('TEXT').setCheck(null).appendField('print')
    this.setInputsInline(true)
    this.setPreviousStatement(true, null)
    this.setNextStatement(true, null)
    this.setColour(TOOL_HUE)
    this.setTooltip('print(v) — print value to output')
  }
}

// ======================== Data Blocks ========================

// Table index access  table[index]
Blockly.Blocks['robot_table_index'] = {
  init() {
    this.appendValueInput('TABLE').setCheck(null).appendField('')
    this.appendValueInput('INDEX').setCheck('Number').appendField('[')
    this.appendDummyInput().appendField(']')
    this.setInputsInline(true)
    this.setOutput(true, null)
    this.setColour(DATA_HUE)
    this.setTooltip('Access table element by index (1-based)')
  }
}
