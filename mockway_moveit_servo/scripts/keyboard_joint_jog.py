#!/usr/bin/env python3
"""
MoveIt Servo 关节控制节点 (JointJog)
使用键盘控制单个关节的运动 - 速度控制模式

按键说明:
    关节选择:
        1-6 : 选择关节1-6

    关节运动:
        w : 正向转动 (再按停止)
        s : 反向转动 (再按停止)

    速度调整:
        +/= : 增大速度
        -   : 减小速度

    错误处理:
        e : 显示当前错误状态
        c : 清除错误 (暂停后恢复Servo)

    其他:
        空格 : 紧急停止
        Esc/Ctrl+C : 退出程序
"""

import sys
import threading
import rclpy
from rclpy.node import Node
from control_msgs.msg import JointJog
from moveit_msgs.msg import ServoStatus
from moveit_msgs.srv import ServoCommandType

if sys.platform != 'win32':
    import tty
    import termios
    import select


class KeyboardJointJogNode(Node):
    """键盘关节控制节点 - 速度控制模式"""

    JOINT_NAMES = ['joint1', 'joint2', 'joint3', 'joint4', 'joint5', 'joint6']

    # MoveIt Servo 状态码定义
    STATUS_CODES = {
        0: ('NO_WARNING', '正常'),
        1: ('DECELERATE_FOR_APPROACHING_SINGULARITY', '接近奇异点,减速中'),
        2: ('HALT_FOR_SINGULARITY', '奇异点停止'),
        3: ('DECELERATE_FOR_LEAVING_SINGULARITY', '离开奇异点,减速中'),
        4: ('DECELERATE_FOR_COLLISION', '接近碰撞,减速中'),
        5: ('HALT_FOR_COLLISION', '碰撞停止'),
        6: ('JOINT_BOUND', '关节限位'),
    }

    def __init__(self):
        super().__init__('keyboard_joint_jog_node')

        # 参数
        self.declare_parameter('joint_speed', 0.5)  # 默认速度 0.5 rad/s
        self.declare_parameter('jog_topic', '/servo_node/delta_joint_cmds')

        self.joint_speed = self.get_parameter('joint_speed').value
        jog_topic = self.get_parameter('jog_topic').value

        # 发布者
        self.jog_pub = self.create_publisher(JointJog, jog_topic, 10)

        # 服务客户端
        self.switch_cmd_type_client = self.create_client(
            ServoCommandType,
            '/servo_node/switch_command_type'
        )

        # 状态订阅
        self.declare_parameter('status_topic', '/servo_node/status')
        status_topic = self.get_parameter('status_topic').value
        self.status_sub = self.create_subscription(
            ServoStatus,
            status_topic,
            self.status_callback,
            10
        )

        # 当前状态
        self.current_status = 0
        self.current_status_msg = ''
        self.last_error_status = 0
        self.last_error_msg = ''

        # 当前选中的关节 (0-5)
        self.selected_joint = 0

        # 当前速度
        self.current_velocity = 0.0
        self.velocity_lock = threading.Lock()

        # 发布定时器 (50Hz)
        self.timer = self.create_timer(0.02, self.publish_jog)

        # 键盘线程
        self.running = True
        self.keyboard_thread = threading.Thread(target=self.keyboard_loop)
        self.keyboard_thread.daemon = True

        if sys.platform != 'win32':
            self.old_settings = termios.tcgetattr(sys.stdin)

        self.get_logger().info('Keyboard Joint Jog Node 已启动 (速度控制模式)')
        self.print_instructions()

    def print_instructions(self):
        msg = """
========================================
  MoveIt Servo 关节控制 (速度控制模式)
========================================
关节选择:
    1-6 : 选择关节1-6

关节运动:
    w : 正向转动 (再按停止)
    s : 反向转动 (再按停止)

速度调整:
    +/= : 增大速度
    -   : 减小速度

错误处理:
    e : 显示当前状态
    c : 清除错误

其他:
    空格   : 紧急停止
    Ctrl+C : 退出

当前: 关节{} | 速度={:.2f} rad/s
========================================
""".format(self.selected_joint + 1, self.joint_speed)
        print(msg)

    def status_callback(self, msg):
        """状态回调"""
        self.current_status = msg.code
        self.current_status_msg = msg.message
        if msg.code != 0:
            self.last_error_status = msg.code
            self.last_error_msg = msg.message

    def show_status(self):
        """显示当前状态"""
        status_info = self.STATUS_CODES.get(self.current_status, ('UNKNOWN', f'未知状态码:{self.current_status}'))
        output = f'\n当前状态: {self.current_status} - {status_info[0]}\n'
        if self.current_status_msg:
            output += f'  消息: {self.current_status_msg}\n'
        else:
            output += f'  说明: {status_info[1]}\n'
        if self.last_error_status != 0 and self.last_error_status != self.current_status:
            last_info = self.STATUS_CODES.get(self.last_error_status, ('UNKNOWN', '未知'))
            output += f'  上次错误: {self.last_error_status} - {last_info[0]}: {self.last_error_msg}\n'
        output += f'当前关节: {self.selected_joint + 1} | 速度: {self.joint_speed:.2f} rad/s\n'
        sys.stdout.write(output)
        sys.stdout.flush()

    def clear_error(self):
        """清除错误"""
        print('\r清除错误中...                    ')
        with self.velocity_lock:
            self.current_velocity = 0.0

        request = ServoCommandType.Request()
        request.command_type = 0  # JOINT_JOG = 0

        if not self.switch_cmd_type_client.wait_for_service(timeout_sec=2.0):
            print('\r清除失败: 服务不可用              ')
            return

        future = self.switch_cmd_type_client.call_async(request)
        rclpy.spin_until_future_complete(self, future, timeout_sec=2.0)

        if future.result() is not None and future.result().success:
            self.last_error_status = 0
            print('\r错误已清除                        ')
        else:
            print('\r清除失败                          ')

    def switch_to_joint_jog_mode(self):
        """切换到JointJog模式"""
        self.get_logger().info('等待 switch_command_type 服务...')
        if not self.switch_cmd_type_client.wait_for_service(timeout_sec=5.0):
            self.get_logger().error('switch_command_type 服务不可用!')
            return False

        request = ServoCommandType.Request()
        request.command_type = 0  # JOINT_JOG = 0

        future = self.switch_cmd_type_client.call_async(request)
        rclpy.spin_until_future_complete(self, future, timeout_sec=5.0)

        if future.result() is not None and future.result().success:
            self.get_logger().info('已切换到 JOINT_JOG 命令模式')
            return True
        else:
            self.get_logger().error('切换命令模式失败!')
            return False

    def get_key(self):
        if sys.platform == 'win32':
            import msvcrt
            if msvcrt.kbhit():
                return msvcrt.getch().decode('utf-8', errors='ignore')
            return None
        else:
            try:
                tty.setraw(sys.stdin.fileno())
                if select.select([sys.stdin], [], [], 0.05)[0]:
                    return sys.stdin.read(1)
                return None
            except Exception:
                return None
            finally:
                termios.tcsetattr(sys.stdin, termios.TCSADRAIN, self.old_settings)

    def keyboard_loop(self):
        while self.running and rclpy.ok():
            key = self.get_key()

            if key is None:
                continue

            if key == '\x03' or key == '\x1b':
                self.running = False
                break

            if key == ' ':
                with self.velocity_lock:
                    self.current_velocity = 0.0
                print(f'\r停止                              ', end='', flush=True)
                continue

            # 关节选择 1-6
            if key in '123456':
                self.selected_joint = int(key) - 1
                with self.velocity_lock:
                    self.current_velocity = 0.0
                print(f'\r关节{self.selected_joint + 1} | 速度={self.joint_speed:.2f} rad/s  ', end='', flush=True)
                continue

            key = key.lower()

            # 关节运动 - toggle 模式
            if key == 'w':
                with self.velocity_lock:
                    if self.current_velocity > 0:
                        self.current_velocity = 0.0
                        print(f'\r关节{self.selected_joint + 1} 停止              ', end='', flush=True)
                    else:
                        self.current_velocity = self.joint_speed
                        print(f'\r关节{self.selected_joint + 1} 正转 +{self.joint_speed:.2f}   ', end='', flush=True)
            elif key == 's':
                with self.velocity_lock:
                    if self.current_velocity < 0:
                        self.current_velocity = 0.0
                        print(f'\r关节{self.selected_joint + 1} 停止              ', end='', flush=True)
                    else:
                        self.current_velocity = -self.joint_speed
                        print(f'\r关节{self.selected_joint + 1} 反转 {-self.joint_speed:.2f}   ', end='', flush=True)

            # 速度调整
            if key in ['+', '=']:
                self.joint_speed = min(2.0, self.joint_speed * 1.1)
                with self.velocity_lock:
                    if self.current_velocity > 0:
                        self.current_velocity = self.joint_speed
                    elif self.current_velocity < 0:
                        self.current_velocity = -self.joint_speed
                print(f'\r速度: {self.joint_speed:.2f} rad/s          ', end='', flush=True)
            elif key == '-':
                self.joint_speed = max(0.1, self.joint_speed * 0.9)
                with self.velocity_lock:
                    if self.current_velocity > 0:
                        self.current_velocity = self.joint_speed
                    elif self.current_velocity < 0:
                        self.current_velocity = -self.joint_speed
                print(f'\r速度: {self.joint_speed:.2f} rad/s          ', end='', flush=True)

            # 错误处理
            if key == 'e':
                self.show_status()
            elif key == 'c':
                self.clear_error()

    def publish_jog(self):
        if not self.running:
            return

        with self.velocity_lock:
            velocity = self.current_velocity

        msg = JointJog()
        msg.header.stamp = self.get_clock().now().to_msg()
        msg.header.frame_id = ''

        msg.joint_names = self.JOINT_NAMES
        velocities = [0.0] * 6
        velocities[self.selected_joint] = velocity
        msg.velocities = velocities
        msg.duration = 0.0

        self.jog_pub.publish(msg)

    def run(self):
        if not self.switch_to_joint_jog_mode():
            self.get_logger().error('无法切换到JOINT_JOG模式')
            return

        self.keyboard_thread.start()

        try:
            while self.running and rclpy.ok():
                rclpy.spin_once(self, timeout_sec=0.1)
        except KeyboardInterrupt:
            pass

        self.running = False
        with self.velocity_lock:
            self.current_velocity = 0.0
        self.publish_jog()

    def destroy_node(self):
        self.running = False
        if sys.platform != 'win32':
            try:
                termios.tcsetattr(sys.stdin, termios.TCSADRAIN, self.old_settings)
            except Exception:
                pass
        super().destroy_node()


def main(args=None):
    rclpy.init(args=args)
    node = KeyboardJointJogNode()
    try:
        node.run()
    except Exception as e:
        node.get_logger().error(f'错误: {e}')
    finally:
        node.destroy_node()
        rclpy.shutdown()

    if sys.platform != 'win32':
        import os
        os.system('stty sane')
    print('\n关节控制已退出')


if __name__ == '__main__':
    main()
