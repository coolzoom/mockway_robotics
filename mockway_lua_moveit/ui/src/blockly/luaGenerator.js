import * as Blockly from 'blockly/core'

// ======================== Create Lua Generator ========================

const Order = {
  ATOMIC: 0,         // literals, ()
  EXPONENT: 1,       // ^
  UNARY: 2,          // not, #, - (unary)
  MULTIPLICATIVE: 3, // * / %
  ADDITIVE: 4,       // + -
  CONCATENATION: 5,  // ..
  RELATIONAL: 6,     // < > <= >= ~= ==
  AND: 7,            // and
  OR: 8,             // or
  NONE: 99
}

const luaGenerator = new Blockly.Generator('Lua')

luaGenerator.ORDER_ATOMIC        = Order.ATOMIC
luaGenerator.ORDER_EXPONENT      = Order.EXPONENT
luaGenerator.ORDER_UNARY         = Order.UNARY
luaGenerator.ORDER_MULTIPLICATIVE = Order.MULTIPLICATIVE
luaGenerator.ORDER_ADDITIVE      = Order.ADDITIVE
luaGenerator.ORDER_CONCATENATION = Order.CONCATENATION
luaGenerator.ORDER_RELATIONAL    = Order.RELATIONAL
luaGenerator.ORDER_AND           = Order.AND
luaGenerator.ORDER_OR            = Order.OR
luaGenerator.ORDER_NONE          = Order.NONE

luaGenerator.STATEMENT_PREFIX = null
luaGenerator.STATEMENT_SUFFIX = null
luaGenerator.INDENT = '    '

luaGenerator.scrub_ = function (block, code, thisOnly) {
  const nextBlock = block.nextConnection && block.nextConnection.targetBlock()
  if (nextBlock && !thisOnly) {
    return code + this.blockToCode(nextBlock)
  }
  return code
}

luaGenerator.init = function (_workspace) {}

luaGenerator.finish = function (code) {
  return code
}

// ======================== Helpers ========================

function valueToCode(block, name, order) {
  return luaGenerator.valueToCode(block, name, order) || '0'
}

function buildTable(block, labels) {
  const vals = labels.map(l => valueToCode(block, l, Order.NONE))
  return '{' + vals.join(', ') + '}'
}

// ======================== Servo Blocks ========================

luaGenerator.forBlock['robot_servo_mode'] = function (block) {
  const mode = block.getFieldValue('MODE')
  return `ServoMode("${mode}")\n`
}

luaGenerator.forBlock['robot_servo_joint'] = function (block) {
  const index = block.getFieldValue('INDEX')
  const vel = valueToCode(block, 'VEL', Order.NONE)
  return `ServoJoint(${index}, ${vel})\n`
}

luaGenerator.forBlock['robot_servo_joints'] = function (block) {
  const table = buildTable(block, ['V1','V2','V3','V4','V5','V6'])
  return `ServoJoints(${table})\n`
}

luaGenerator.forBlock['robot_servo_cart'] = function (block) {
  const vals = ['VX','VY','VZ','RX','RY','RZ'].map(l => valueToCode(block, l, Order.NONE))
  return `ServoCart(${vals.join(', ')})\n`
}

luaGenerator.forBlock['robot_servo_stop'] = function () {
  return 'ServoStop()\n'
}

// ======================== PTP Motion Blocks ========================

luaGenerator.forBlock['robot_move_named'] = function (block) {
  const name = block.getFieldValue('NAME')
  return `MoveNamed("${name}")\n`
}

luaGenerator.forBlock['robot_move_j'] = function (block) {
  const table = buildTable(block, ['J1','J2','J3','J4','J5','J6'])
  return `MoveJ(${table})\n`
}

luaGenerator.forBlock['robot_move_pose'] = function (block) {
  const vals = ['X','Y','Z','Roll','Pitch','Yaw'].map(l => valueToCode(block, l, Order.NONE))
  return `MovePose(${vals.join(', ')})\n`
}

// ======================== Linear Motion Blocks ========================

luaGenerator.forBlock['robot_move_l'] = function (block) {
  const vals = ['X','Y','Z','Roll','Pitch','Yaw'].map(l => valueToCode(block, l, Order.NONE))
  return `MoveL(${vals.join(', ')})\n`
}

luaGenerator.forBlock['robot_move_l_rel'] = function (block) {
  const vals = ['DX','DY','DZ','DRX','DRY','DRZ'].map(l => valueToCode(block, l, Order.NONE))
  return `MoveLRel(${vals.join(', ')})\n`
}

luaGenerator.forBlock['robot_move_l_rel_tool'] = function (block) {
  const vals = ['DX','DY','DZ','DRX','DRY','DRZ'].map(l => valueToCode(block, l, Order.NONE))
  return `MoveLRelTool(${vals.join(', ')})\n`
}

// ======================== Parameter Blocks ========================

luaGenerator.forBlock['robot_set_vel_scale'] = function (block) {
  const factor = valueToCode(block, 'FACTOR', Order.NONE)
  return `SetVelScale(${factor})\n`
}

luaGenerator.forBlock['robot_set_acc_scale'] = function (block) {
  const factor = valueToCode(block, 'FACTOR', Order.NONE)
  return `SetAccScale(${factor})\n`
}

luaGenerator.forBlock['robot_set_plan_time'] = function (block) {
  const seconds = valueToCode(block, 'SECONDS', Order.NONE)
  return `SetPlanTime(${seconds})\n`
}

luaGenerator.forBlock['robot_set_planner'] = function (block) {
  const planner = block.getFieldValue('PLANNER')
  return `SetPlanner("${planner}")\n`
}

// ======================== Status Blocks ========================

luaGenerator.forBlock['robot_get_joints'] = function () {
  return ['GetJoints()', Order.ATOMIC]
}

luaGenerator.forBlock['robot_get_pose'] = function () {
  return ['GetPose()', Order.ATOMIC]
}

// ======================== Tool Blocks ========================

luaGenerator.forBlock['robot_sleep'] = function (block) {
  const ms = valueToCode(block, 'MS', Order.NONE)
  return `Sleep(${ms})\n`
}

luaGenerator.forBlock['robot_log'] = function (block) {
  const msg = valueToCode(block, 'MSG', Order.NONE)
  return `Log(${msg})\n`
}

luaGenerator.forBlock['robot_log_warn'] = function (block) {
  const msg = valueToCode(block, 'MSG', Order.NONE)
  return `LogWarn(${msg})\n`
}

luaGenerator.forBlock['robot_log_error'] = function (block) {
  const msg = valueToCode(block, 'MSG', Order.NONE)
  return `LogError(${msg})\n`
}

luaGenerator.forBlock['robot_ok'] = function () {
  return ['Ok()', Order.ATOMIC]
}

luaGenerator.forBlock['robot_deg_rad'] = function (block) {
  const deg = valueToCode(block, 'DEG', Order.NONE)
  return [`DegRad(${deg})`, Order.ATOMIC]
}

luaGenerator.forBlock['robot_rad_deg'] = function (block) {
  const rad = valueToCode(block, 'RAD', Order.NONE)
  return [`RadDeg(${rad})`, Order.ATOMIC]
}

luaGenerator.forBlock['robot_print'] = function (block) {
  const text = valueToCode(block, 'TEXT', Order.NONE)
  return `print(${text})\n`
}

// ======================== Data Blocks ========================

luaGenerator.forBlock['robot_table_index'] = function (block) {
  const table = valueToCode(block, 'TABLE', Order.ATOMIC)
  const index = valueToCode(block, 'INDEX', Order.NONE)
  return [`${table}[${index}]`, Order.ATOMIC]
}

// ======================== Built-in Block Generators ========================

luaGenerator.forBlock['math_number'] = function (block) {
  const num = Number(block.getFieldValue('NUM'))
  return [String(num), Order.ATOMIC]
}

luaGenerator.forBlock['text'] = function (block) {
  const text = block.getFieldValue('TEXT') || ''
  const escaped = text.replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/\n/g, '\\n')
  return [`"${escaped}"`, Order.ATOMIC]
}

luaGenerator.forBlock['logic_boolean'] = function (block) {
  const val = block.getFieldValue('BOOL') === 'TRUE' ? 'true' : 'false'
  return [val, Order.ATOMIC]
}

luaGenerator.forBlock['logic_negate'] = function (block) {
  const arg = luaGenerator.valueToCode(block, 'BOOL', Order.UNARY) || 'true'
  return [`not ${arg}`, Order.UNARY]
}

luaGenerator.forBlock['logic_compare'] = function (block) {
  const ops = { EQ: '==', NEQ: '~=', LT: '<', LTE: '<=', GT: '>', GTE: '>=' }
  const op = ops[block.getFieldValue('OP')] || '=='
  const left  = luaGenerator.valueToCode(block, 'A', Order.RELATIONAL) || '0'
  const right = luaGenerator.valueToCode(block, 'B', Order.RELATIONAL) || '0'
  return [`${left} ${op} ${right}`, Order.RELATIONAL]
}

luaGenerator.forBlock['controls_if'] = function (block) {
  let code = ''
  let n = 0
  while (block.getInput('IF' + n)) {
    const cond   = luaGenerator.valueToCode(block, 'IF' + n, Order.NONE) || 'false'
    const branch = luaGenerator.statementToCode(block, 'DO' + n) || ''
    code += (n === 0 ? 'if ' : 'elseif ') + cond + ' then\n' + branch
    n++
  }
  if (block.getInput('ELSE')) {
    const elseBranch = luaGenerator.statementToCode(block, 'ELSE') || ''
    code += 'else\n' + elseBranch
  }
  code += 'end\n'
  return code
}

luaGenerator.forBlock['controls_repeat_ext'] = function (block) {
  const times  = luaGenerator.valueToCode(block, 'TIMES', Order.NONE) || '0'
  const branch = luaGenerator.statementToCode(block, 'DO') || ''
  return `for _i = 1, ${times} do\n${branch}end\n`
}

luaGenerator.forBlock['controls_whileUntil'] = function (block) {
  const mode = block.getFieldValue('MODE')
  let cond = luaGenerator.valueToCode(block, 'BOOL', Order.NONE) || 'false'
  const branch = luaGenerator.statementToCode(block, 'DO') || ''
  if (mode === 'UNTIL') cond = `not (${cond})`
  return `while ${cond} do\n${branch}end\n`
}

luaGenerator.forBlock['math_arithmetic'] = function (block) {
  const ops = {
    ADD:      [' + ', Order.ADDITIVE],
    MINUS:    [' - ', Order.ADDITIVE],
    MULTIPLY: [' * ', Order.MULTIPLICATIVE],
    DIVIDE:   [' / ', Order.MULTIPLICATIVE],
    POWER:    [' ^ ', Order.EXPONENT]
  }
  const tuple = ops[block.getFieldValue('OP')] || [' + ', Order.ADDITIVE]
  const left  = luaGenerator.valueToCode(block, 'A', tuple[1]) || '0'
  const right = luaGenerator.valueToCode(block, 'B', tuple[1]) || '0'
  return [`${left}${tuple[0]}${right}`, tuple[1]]
}

luaGenerator.forBlock['variables_get'] = function (block) {
  const name = block.getFieldValue('VAR') || 'x'
  return [name, Order.ATOMIC]
}

luaGenerator.forBlock['variables_set'] = function (block) {
  const name = block.getFieldValue('VAR') || 'x'
  const val  = luaGenerator.valueToCode(block, 'VALUE', Order.NONE) || '0'
  return `${name} = ${val}\n`
}

// ======================== statementToCode helper ========================

luaGenerator.statementToCode = function (block, name) {
  const targetBlock = block.getInputTargetBlock(name)
  if (!targetBlock) return ''
  let code = this.blockToCode(targetBlock)
  if (typeof code !== 'string') {
    throw new TypeError('Expecting code from statement block: ' + targetBlock.type)
  }
  if (code) code = this.prefixLines(code, this.INDENT)
  return code
}

export { luaGenerator, Order }
