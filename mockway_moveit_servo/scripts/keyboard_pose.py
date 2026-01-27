#!/usr/bin/env python3
"""
MoveIt Servo 位姿控制节点 (Pose)
使用键盘控制末端执行器的目标位姿

按键说明:
    位置控制:
        w/s : X轴 前进/后退
        a/d : Y轴 左/右
        q/e : Z轴 上/下

    姿态控制 (欧拉角增量):
        j/l : 绕X轴旋转 (Roll)
        i/k : 绕Y轴旋转 (Pitch)
        u/o : 绕Z轴旋转 (Yaw)

    步长控制:
        +/= : 增加步长
        -   : 减少步长

    其他:
        r     : 重置到当前位姿
        空格  : 紧急停止
        Esc   : 退出程序
"""

import sys
import threading
import math
import rclpy
from rclpy.node import Node
from geometry_msgs.msg import PoseStamped
from tf2_ros import Buffer, TransformListener
from moveit_msgs.srv import ServoCommandType

if sys.platform != 'win32':
    import tty
    import termios
    import select


def euler_to_quaternion(roll, pitch, yaw):
    """欧拉角转四元数 (ZYX顺序)"""
    cr, cp, cy = math.cos(roll/2), math.cos(pitch/2), math.cos(yaw/2)
    sr, sp, sy = math.sin(roll/2), math.sin(pitch/2), math.sin(yaw/2)

    w = cr * cp * cy + sr * sp * sy
    x = sr * cp * cy - cr * sp * sy
    y = cr * sp * cy + sr * cp * sy
    z = cr * cp * sy - sr * sp * cy
    return x, y, z, w


def quaternion_to_euler(x, y, z, w):
    """四元数转欧拉角 (ZYX顺序)"""
    # Roll (x-axis rotation)
    sinr_cosp = 2 * (w * x + y * z)
    cosr_cosp = 1 - 2 * (x * x + y * y)
    roll = math.atan2(sinr_cosp, cosr_cosp)

    # Pitch (y-axis rotation)
    sinp = 2 * (w * y - z * x)
    if abs(sinp) >= 1:
        pitch = math.copysign(math.pi / 2, sinp)
    else:
        pitch = math.asin(sinp)

    # Yaw (z-axis rotation)
    siny_cosp = 2 * (w * z + x * y)
    cosy_cosp = 1 - 2 * (y * y + z * z)
    yaw = math.atan2(siny_cosp, cosy_cosp)

    return roll, pitch, yaw


class KeyboardPoseNode(Node):
    """键盘位姿控制节点"""

    # 按键映射 - 位置增量
    POSITION_BINDINGS = {
        'w': (1, 0, 0),    # +X
        's': (-1, 0, 0),   # -X
        'a': (0, 1, 0),    # +Y
        'd': (0, -1, 0),   # -Y
        'q': (0, 0, 1),    # +Z
        'e': (0, 0, -1),   # -Z
    }

    # 按键映射 - 姿态增量 (Roll, Pitch, Yaw)
    ROTATION_BINDINGS = {
        'j': (1, 0, 0),    # +Roll
        'l': (-1, 0, 0),   # -Roll
        'i': (0, 1, 0),    # +Pitch
        'k': (0, -1, 0),   # -Pitch
        'u': (0, 0, 1),    # +Yaw
        'o': (0, 0, -1),   # -Yaw
    }

    def __init__(self):
        super().__init__('keyboard_pose_node')

        # 参数
        self.declare_parameter('position_step', 0.01)  # 位置步长 (m)
        self.declare_parameter('rotation_step', 0.05)  # 旋转步长 (rad)
        self.declare_parameter('pose_topic', '/servo_node/pose_target_cmds')
        self.declare_parameter('frame_id', 'base_link')
        self.declare_parameter('ee_frame', 'link6')

        self.position_step = self.get_parameter('position_step').value
        self.rotation_step = self.get_parameter('rotation_step').value
        pose_topic = self.get_parameter('pose_topic').value
        self.frame_id = self.get_parameter('frame_id').value
        self.ee_frame = self.get_parameter('ee_frame').value

        # 发布者
        self.pose_pub = self.create_publisher(PoseStamped, pose_topic, 10)

        # TF监听器
        self.tf_buffer = Buffer()
        self.tf_listener = TransformListener(self.tf_buffer, self)

        # 服务客户端
        self.switch_cmd_type_client = self.create_client(
            ServoCommandType,
            '/servo_node/switch_command_type'
        )

        # 目标位姿
        self.target_position = [0.0, 0.0, 0.0]
        self.target_euler = [0.0, 0.0, 0.0]  # Roll, Pitch, Yaw
        self.pose_initialized = False
        self.pose_updated = False

        # 发布定时器 (50Hz)
        self.timer = self.create_timer(0.02, self.publish_pose)

        # 键盘线程
        self.running = True
        self.keyboard_thread = threading.Thread(target=self.keyboard_loop)
        self.keyboard_thread.daemon = True

        if sys.platform != 'win32':
            self.old_settings = termios.tcgetattr(sys.stdin)

        self.get_logger().info('Keyboard Pose Node 已启动')

    def print_instructions(self):
        msg = """
========================================
    MoveIt Servo 位姿控制 (Pose)
========================================
位置控制:
    w/s : X轴 前进/后退
    a/d : Y轴 左移/右移
    q/e : Z轴 上升/下降

姿态控制:
    j/l : 绕X轴旋转 (Roll)
    i/k : 绕Y轴旋转 (Pitch)
    u/o : 绕Z轴旋转 (Yaw)

步长调整:
    +/= : 增加步长
    -   : 减少步长

其他:
    r      : 重置到当前位姿
    空格   : 停止更新
    Ctrl+C : 退出

位置步长={:.3f}m | 旋转步长={:.3f}rad
当前目标: X={:.3f} Y={:.3f} Z={:.3f}
========================================
""".format(self.position_step, self.rotation_step,
           self.target_position[0], self.target_position[1], self.target_position[2])
        print(msg)

    def get_current_pose(self):
        """从TF获取当前末端位姿"""
        try:
            # 快速检查TF是否可用
            if not self.tf_buffer.can_transform(self.frame_id, self.ee_frame,
                                                 rclpy.time.Time(),
                                                 timeout=rclpy.duration.Duration(seconds=0.5)):
                return False

            trans = self.tf_buffer.lookup_transform(
                self.frame_id,
                self.ee_frame,
                rclpy.time.Time(),
                timeout=rclpy.duration.Duration(seconds=0.5)
            )

            self.target_position = [
                trans.transform.translation.x,
                trans.transform.translation.y,
                trans.transform.translation.z
            ]

            q = trans.transform.rotation
            self.target_euler = list(quaternion_to_euler(q.x, q.y, q.z, q.w))

            self.pose_initialized = True
            self.get_logger().info(
                f'当前位姿: pos=[{self.target_position[0]:.3f}, '
                f'{self.target_position[1]:.3f}, {self.target_position[2]:.3f}]'
            )
            return True
        except Exception as e:
            self.get_logger().warn(f'获取当前位姿失败: {e}')
            return False

    def switch_to_pose_mode(self):
        """切换到Pose模式"""
        self.get_logger().info('等待 switch_command_type 服务...')
        if not self.switch_cmd_type_client.wait_for_service(timeout_sec=5.0):
            self.get_logger().error('switch_command_type 服务不可用!')
            return False

        request = ServoCommandType.Request()
        request.command_type = 2  # POSE = 2

        future = self.switch_cmd_type_client.call_async(request)
        rclpy.spin_until_future_complete(self, future, timeout_sec=5.0)

        if future.result() is not None and future.result().success:
            self.get_logger().info('已切换到 POSE 命令模式')
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
                self.pose_updated = False
                self.get_logger().info('停止位姿更新')
                continue

            key_lower = key.lower()

            # 重置位姿
            if key_lower == 'r':
                if self.get_current_pose():
                    self.print_instructions()
                continue

            # 位置控制
            if key_lower in self.POSITION_BINDINGS:
                delta = self.POSITION_BINDINGS[key_lower]
                for i in range(3):
                    self.target_position[i] += delta[i] * self.position_step
                self.pose_updated = True
                print(f'\r目标位置: X={self.target_position[0]:.3f} '
                      f'Y={self.target_position[1]:.3f} Z={self.target_position[2]:.3f}    ',
                      end='', flush=True)
                continue

            # 姿态控制
            if key_lower in self.ROTATION_BINDINGS:
                delta = self.ROTATION_BINDINGS[key_lower]
                for i in range(3):
                    self.target_euler[i] += delta[i] * self.rotation_step
                self.pose_updated = True
                print(f'\r目标姿态: R={self.target_euler[0]:.3f} '
                      f'P={self.target_euler[1]:.3f} Y={self.target_euler[2]:.3f}    ',
                      end='', flush=True)
                continue

            # 步长调整
            if key in ['+', '=']:
                self.position_step = min(0.1, self.position_step * 1.2)
                self.rotation_step = min(0.3, self.rotation_step * 1.2)
                print(f'\r步长: pos={self.position_step:.3f}m rot={self.rotation_step:.3f}rad    ',
                      end='', flush=True)
            elif key == '-':
                self.position_step = max(0.001, self.position_step * 0.8)
                self.rotation_step = max(0.01, self.rotation_step * 0.8)
                print(f'\r步长: pos={self.position_step:.3f}m rot={self.rotation_step:.3f}rad    ',
                      end='', flush=True)

    def publish_pose(self):
        if not self.running or not self.pose_initialized:
            return

        msg = PoseStamped()
        msg.header.stamp = self.get_clock().now().to_msg()
        msg.header.frame_id = self.frame_id

        msg.pose.position.x = self.target_position[0]
        msg.pose.position.y = self.target_position[1]
        msg.pose.position.z = self.target_position[2]

        qx, qy, qz, qw = euler_to_quaternion(*self.target_euler)
        msg.pose.orientation.x = qx
        msg.pose.orientation.y = qy
        msg.pose.orientation.z = qz
        msg.pose.orientation.w = qw

        self.pose_pub.publish(msg)

    def run(self):
        # 尝试获取TF（等待3秒）
        self.get_logger().info('尝试获取当前位姿...')

        pose_found = False
        for i in range(6):
            rclpy.spin_once(self, timeout_sec=0.5)
            if self.get_current_pose():
                pose_found = True
                break

        if not pose_found:
            self.get_logger().warn('TF不可用，使用默认位姿启动')
            self.target_position = [0.2, 0.0, 0.4]
            self.target_euler = [0.0, 0.0, 0.0]
            self.pose_initialized = True

        if not self.switch_to_pose_mode():
            self.get_logger().error('无法切换到POSE模式')
            return

        self.print_instructions()
        self.keyboard_thread.start()

        try:
            while self.running and rclpy.ok():
                rclpy.spin_once(self, timeout_sec=0.1)
        except KeyboardInterrupt:
            pass

        self.running = False

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
    node = KeyboardPoseNode()
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
    print('\n位姿控制已退出')


if __name__ == '__main__':
    main()
