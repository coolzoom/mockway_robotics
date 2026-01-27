#!/usr/bin/env python3
"""
MoveIt Servo 键盘控制节点
使用键盘控制机械臂末端在笛卡尔空间中的运动

按键说明:
    平移控制 (相对于末端坐标系):
        w/s - X轴 前进/后退
        a/d - Y轴 左/右
        q/e - Z轴 上/下

    旋转控制:
        j/l - 绕X轴 (Roll)
        i/k - 绕Y轴 (Pitch)
        u/o - 绕Z轴 (Yaw)

    速度控制:
        +/= - 增加速度
        -   - 减少速度

    其他:
        空格 - 紧急停止
        Esc/Ctrl+C - 退出程序
"""

import sys
import threading
import rclpy
from rclpy.node import Node
from geometry_msgs.msg import TwistStamped
from moveit_msgs.srv import ServoCommandType

# 处理不同终端的键盘输入
if sys.platform != 'win32':
    import tty
    import termios
    import select


class KeyboardServoNode(Node):
    """键盘控制MoveIt Servo节点"""

    # 按键映射 - 平移
    MOVE_BINDINGS = {
        'w': (1, 0, 0, 0, 0, 0),   # +X
        's': (-1, 0, 0, 0, 0, 0),  # -X
        'a': (0, 1, 0, 0, 0, 0),   # +Y
        'd': (0, -1, 0, 0, 0, 0),  # -Y
        'q': (0, 0, 1, 0, 0, 0),   # +Z
        'e': (0, 0, -1, 0, 0, 0),  # -Z
    }

    # 按键映射 - 旋转
    ROTATE_BINDINGS = {
        'j': (0, 0, 0, 1, 0, 0),   # +Roll (绕X)
        'l': (0, 0, 0, -1, 0, 0),  # -Roll
        'i': (0, 0, 0, 0, 1, 0),   # +Pitch (绕Y)
        'k': (0, 0, 0, 0, -1, 0),  # -Pitch
        'u': (0, 0, 0, 0, 0, 1),   # +Yaw (绕Z)
        'o': (0, 0, 0, 0, 0, -1),  # -Yaw
    }

    # 速度调整
    SPEED_BINDINGS = {
        '+': 1.1,
        '=': 1.1,
        '-': 0.9,
    }

    def __init__(self):
        super().__init__('keyboard_servo_node')

        # 参数声明
        self.declare_parameter('linear_speed', 0.3)
        self.declare_parameter('angular_speed', 0.5)
        self.declare_parameter('twist_topic', '/servo_node/delta_twist_cmds')
        self.declare_parameter('frame_id', 'link6')

        # 获取参数
        self.linear_speed = self.get_parameter('linear_speed').value
        self.angular_speed = self.get_parameter('angular_speed').value
        twist_topic = self.get_parameter('twist_topic').value
        self.frame_id = self.get_parameter('frame_id').value

        # 创建发布者
        self.twist_pub = self.create_publisher(
            TwistStamped,
            twist_topic,
            10
        )

        # 创建切换命令类型的服务客户端
        self.switch_cmd_type_client = self.create_client(
            ServoCommandType,
            '/servo_node/switch_command_type'
        )

        # 当前速度
        self.current_twist = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]

        # 发布定时器 (50Hz，与servo_config中的publish_period匹配)
        self.timer = self.create_timer(0.02, self.publish_twist)

        # 键盘输入线程
        self.running = True
        self.keyboard_thread = threading.Thread(target=self.keyboard_loop)
        self.keyboard_thread.daemon = True

        # 保存原始终端设置
        if sys.platform != 'win32':
            self.old_settings = termios.tcgetattr(sys.stdin)

        self.get_logger().info('Keyboard Servo Node 已启动')
        self.print_instructions()

    def print_instructions(self):
        """打印使用说明"""
        msg = """
========================================
    MoveIt Servo 键盘控制
========================================
平移控制 (相对于末端坐标系):
    w/s : X轴 前进/后退
    a/d : Y轴 左移/右移
    q/e : Z轴 上升/下降

旋转控制:
    j/l : 绕X轴旋转 (Roll)
    i/k : 绕Y轴旋转 (Pitch)
    u/o : 绕Z轴旋转 (Yaw)

速度调整:
    +/= : 加速
    -   : 减速

其他:
    空格   : 紧急停止
    Ctrl+C : 退出

当前速度: 线速度={:.2f} m/s, 角速度={:.2f} rad/s
========================================
""".format(self.linear_speed, self.angular_speed)
        print(msg)

    def get_key(self):
        """获取键盘输入"""
        if sys.platform == 'win32':
            import msvcrt
            if msvcrt.kbhit():
                return msvcrt.getch().decode('utf-8', errors='ignore')
            return None
        else:
            try:
                tty.setraw(sys.stdin.fileno())
                if select.select([sys.stdin], [], [], 0.05)[0]:
                    key = sys.stdin.read(1)
                    return key
                return None
            except Exception:
                return None
            finally:
                termios.tcsetattr(sys.stdin, termios.TCSADRAIN, self.old_settings)

    def keyboard_loop(self):
        """键盘输入处理循环"""
        while self.running and rclpy.ok():
            key = self.get_key()

            if key is None:
                # 无按键时逐渐减速
                for i in range(6):
                    self.current_twist[i] *= 0.7
                    if abs(self.current_twist[i]) < 0.01:
                        self.current_twist[i] = 0.0
                continue

            # 处理特殊键
            if key == '\x03':  # Ctrl+C
                self.get_logger().info('收到Ctrl+C，退出...')
                self.running = False
                break

            if key == '\x1b':  # ESC
                self.get_logger().info('退出键盘控制...')
                self.running = False
                break

            # 空格紧急停止
            if key == ' ':
                self.current_twist = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
                self.get_logger().info('紧急停止!')
                continue

            key = key.lower()

            # 平移控制
            if key in self.MOVE_BINDINGS:
                binding = self.MOVE_BINDINGS[key]
                for i in range(3):
                    self.current_twist[i] = binding[i] * self.linear_speed
                continue

            # 旋转控制
            if key in self.ROTATE_BINDINGS:
                binding = self.ROTATE_BINDINGS[key]
                for i in range(3, 6):
                    self.current_twist[i] = binding[i] * self.angular_speed
                continue

            # 速度调整
            if key in self.SPEED_BINDINGS:
                factor = self.SPEED_BINDINGS[key]
                self.linear_speed *= factor
                self.angular_speed *= factor
                self.linear_speed = max(0.05, min(1.0, self.linear_speed))
                self.angular_speed = max(0.1, min(2.0, self.angular_speed))
                print(f'\r速度: 线速度={self.linear_speed:.2f} m/s, '
                      f'角速度={self.angular_speed:.2f} rad/s    ', end='', flush=True)
                continue

    def publish_twist(self):
        """发布Twist消息"""
        if not self.running:
            return

        msg = TwistStamped()
        msg.header.stamp = self.get_clock().now().to_msg()
        msg.header.frame_id = self.frame_id

        msg.twist.linear.x = self.current_twist[0]
        msg.twist.linear.y = self.current_twist[1]
        msg.twist.linear.z = self.current_twist[2]
        msg.twist.angular.x = self.current_twist[3]
        msg.twist.angular.y = self.current_twist[4]
        msg.twist.angular.z = self.current_twist[5]

        self.twist_pub.publish(msg)

    def switch_to_twist_mode(self):
        """切换Servo到Twist命令模式"""
        self.get_logger().info('等待 switch_command_type 服务...')
        if not self.switch_cmd_type_client.wait_for_service(timeout_sec=5.0):
            self.get_logger().error('switch_command_type 服务不可用!')
            return False

        request = ServoCommandType.Request()
        request.command_type = 1  # TWIST = 1

        future = self.switch_cmd_type_client.call_async(request)
        rclpy.spin_until_future_complete(self, future, timeout_sec=5.0)

        if future.result() is not None and future.result().success:
            self.get_logger().info('已切换到 TWIST 命令模式')
            return True
        else:
            self.get_logger().error('切换命令模式失败!')
            return False

    def run(self):
        """运行节点"""
        # 先切换到TWIST模式
        if not self.switch_to_twist_mode():
            self.get_logger().error('无法切换到TWIST模式，退出')
            return

        # 启动键盘线程
        self.keyboard_thread.start()

        # ROS spin
        try:
            while self.running and rclpy.ok():
                rclpy.spin_once(self, timeout_sec=0.1)
        except KeyboardInterrupt:
            pass

        # 清理
        self.running = False
        self.current_twist = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
        self.publish_twist()

    def destroy_node(self):
        """销毁节点时的清理"""
        self.running = False
        # 恢复终端设置
        if sys.platform != 'win32':
            try:
                termios.tcsetattr(sys.stdin, termios.TCSADRAIN, self.old_settings)
            except Exception:
                pass
        super().destroy_node()


def main(args=None):
    rclpy.init(args=args)

    node = KeyboardServoNode()
    try:
        node.run()
    except Exception as e:
        node.get_logger().error(f'错误: {e}')
    finally:
        node.destroy_node()
        rclpy.shutdown()

    # 恢复终端设置
    if sys.platform != 'win32':
        import os
        os.system('stty sane')

    print('\n键盘控制已退出')


if __name__ == '__main__':
    main()
