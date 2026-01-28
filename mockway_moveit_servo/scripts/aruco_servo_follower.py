#!/usr/bin/env python3
"""
ArUco Servo Follower - Converts ArUco marker pose to MoveIt Servo twist commands

This node subscribes to the ArUco marker pose and generates velocity commands
to make the robot end-effector track the marker position and orientation.
"""

import rclpy
from rclpy.node import Node
from geometry_msgs.msg import PoseStamped, TwistStamped
from std_srvs.srv import SetBool
import tf2_ros
from tf2_ros import TransformException
import numpy as np
import tf_transformations


class ArucoServoFollower(Node):
    def __init__(self):
        super().__init__('aruco_servo_follower')

        # Declare parameters
        self.declare_parameter('linear_gain', 1.0)
        self.declare_parameter('angular_gain', 0.5)
        self.declare_parameter('max_linear_vel', 0.1)  # m/s
        self.declare_parameter('max_angular_vel', 0.3)  # rad/s
        self.declare_parameter('deadband', 0.005)  # m
        self.declare_parameter('angular_deadband', 0.02)  # rad
        self.declare_parameter('ee_frame', 'link6')
        self.declare_parameter('base_frame', 'base_link')
        self.declare_parameter('aruco_pose_topic', '/aruco_pose')
        self.declare_parameter('twist_output_topic', '/servo_node/delta_twist_cmds')
        self.declare_parameter('control_rate', 50.0)  # Hz
        self.declare_parameter('tracking_enabled', True)

        # Get parameters
        self.linear_gain = self.get_parameter('linear_gain').value
        self.angular_gain = self.get_parameter('angular_gain').value
        self.max_linear_vel = self.get_parameter('max_linear_vel').value
        self.max_angular_vel = self.get_parameter('max_angular_vel').value
        self.deadband = self.get_parameter('deadband').value
        self.angular_deadband = self.get_parameter('angular_deadband').value
        self.ee_frame = self.get_parameter('ee_frame').value
        self.base_frame = self.get_parameter('base_frame').value
        aruco_pose_topic = self.get_parameter('aruco_pose_topic').value
        twist_output_topic = self.get_parameter('twist_output_topic').value
        control_rate = self.get_parameter('control_rate').value
        self.tracking_enabled = self.get_parameter('tracking_enabled').value

        # TF2 buffer and listener
        self.tf_buffer = tf2_ros.Buffer()
        self.tf_listener = tf2_ros.TransformListener(self.tf_buffer, self)

        # Store the latest marker pose
        self.marker_pose = None
        self.marker_pose_time = None

        # Subscriber for ArUco pose
        self.pose_sub = self.create_subscription(
            PoseStamped,
            aruco_pose_topic,
            self.marker_pose_callback,
            10
        )

        # Publisher for twist commands to MoveIt Servo
        self.twist_pub = self.create_publisher(
            TwistStamped,
            twist_output_topic,
            10
        )

        # Service to enable/disable tracking
        self.enable_srv = self.create_service(
            SetBool,
            '~/enable_tracking',
            self.enable_tracking_callback
        )

        # Control loop timer
        self.control_timer = self.create_timer(
            1.0 / control_rate,
            self.control_loop
        )

        self.get_logger().info('ArUco Servo Follower initialized')
        self.get_logger().info(f'Linear gain: {self.linear_gain}, Angular gain: {self.angular_gain}')
        self.get_logger().info(f'Max velocities: linear={self.max_linear_vel} m/s, angular={self.max_angular_vel} rad/s')
        self.get_logger().info(f'Tracking EE frame: {self.ee_frame}, Base frame: {self.base_frame}')

    def marker_pose_callback(self, msg: PoseStamped):
        """Store the latest marker pose."""
        self.marker_pose = msg
        self.marker_pose_time = self.get_clock().now()

    def enable_tracking_callback(self, request, response):
        """Service callback to enable/disable tracking."""
        self.tracking_enabled = request.data
        response.success = True
        response.message = f'Tracking {"enabled" if self.tracking_enabled else "disabled"}'
        self.get_logger().info(response.message)
        return response

    def get_ee_pose_in_base(self):
        """Get the current end-effector pose in the base frame."""
        try:
            transform = self.tf_buffer.lookup_transform(
                self.base_frame,
                self.ee_frame,
                rclpy.time.Time(),
                timeout=rclpy.duration.Duration(seconds=0.1)
            )
            return transform
        except TransformException as ex:
            self.get_logger().warning(f'Could not get EE transform: {ex}')
            return None

    def get_marker_pose_in_base(self):
        """Transform the marker pose to the base frame."""
        if self.marker_pose is None:
            return None

        try:
            # Transform marker pose from camera frame to base frame
            transform = self.tf_buffer.lookup_transform(
                self.base_frame,
                self.marker_pose.header.frame_id,
                rclpy.time.Time(),
                timeout=rclpy.duration.Duration(seconds=0.1)
            )

            # Apply transform to marker pose
            marker_in_base = self.transform_pose(self.marker_pose, transform)
            return marker_in_base

        except TransformException as ex:
            self.get_logger().warning(f'Could not transform marker pose: {ex}')
            return None

    def transform_pose(self, pose: PoseStamped, transform):
        """Apply a transform to a pose."""
        # Extract translation and rotation from transform
        t = transform.transform.translation
        r = transform.transform.rotation

        # Convert to numpy arrays
        trans = np.array([t.x, t.y, t.z])
        rot_quat = np.array([r.x, r.y, r.z, r.w])

        # Get pose position and orientation
        p = pose.pose.position
        o = pose.pose.orientation
        pose_trans = np.array([p.x, p.y, p.z])
        pose_quat = np.array([o.x, o.y, o.z, o.w])

        # Apply rotation to position
        rot_matrix = tf_transformations.quaternion_matrix(rot_quat)[:3, :3]
        new_trans = rot_matrix @ pose_trans + trans

        # Combine rotations
        new_quat = tf_transformations.quaternion_multiply(rot_quat, pose_quat)

        # Create new pose
        new_pose = PoseStamped()
        new_pose.header.frame_id = self.base_frame
        new_pose.header.stamp = self.get_clock().now().to_msg()
        new_pose.pose.position.x = float(new_trans[0])
        new_pose.pose.position.y = float(new_trans[1])
        new_pose.pose.position.z = float(new_trans[2])
        new_pose.pose.orientation.x = float(new_quat[0])
        new_pose.pose.orientation.y = float(new_quat[1])
        new_pose.pose.orientation.z = float(new_quat[2])
        new_pose.pose.orientation.w = float(new_quat[3])

        return new_pose

    def compute_position_error(self, ee_pose, target_pose):
        """Compute position error between EE and target."""
        ee_pos = np.array([
            ee_pose.transform.translation.x,
            ee_pose.transform.translation.y,
            ee_pose.transform.translation.z
        ])
        target_pos = np.array([
            target_pose.pose.position.x,
            target_pose.pose.position.y,
            target_pose.pose.position.z
        ])
        return target_pos - ee_pos

    def compute_orientation_error(self, ee_pose, target_pose):
        """Compute orientation error as axis-angle."""
        # Get quaternions
        ee_quat = np.array([
            ee_pose.transform.rotation.x,
            ee_pose.transform.rotation.y,
            ee_pose.transform.rotation.z,
            ee_pose.transform.rotation.w
        ])
        target_quat = np.array([
            target_pose.pose.orientation.x,
            target_pose.pose.orientation.y,
            target_pose.pose.orientation.z,
            target_pose.pose.orientation.w
        ])

        # Compute relative rotation: q_error = q_target * q_ee^(-1)
        ee_quat_inv = tf_transformations.quaternion_inverse(ee_quat)
        q_error = tf_transformations.quaternion_multiply(target_quat, ee_quat_inv)

        # Convert to axis-angle
        # For small rotations, the axis-angle is approximately [qx, qy, qz] * 2
        # This gives the rotation vector (angular velocity direction * angle)
        angle = 2.0 * np.arccos(np.clip(q_error[3], -1.0, 1.0))
        if angle < 1e-6:
            return np.zeros(3)

        axis = q_error[:3] / np.sin(angle / 2.0)
        return axis * angle

    def clamp_velocity(self, vel, max_vel):
        """Clamp velocity magnitude while preserving direction."""
        magnitude = np.linalg.norm(vel)
        if magnitude > max_vel:
            return vel * (max_vel / magnitude)
        return vel

    def apply_deadband(self, error, deadband):
        """Apply deadband to error."""
        magnitude = np.linalg.norm(error)
        if magnitude < deadband:
            return np.zeros_like(error)
        return error

    def control_loop(self):
        """Main control loop - compute and publish twist commands."""
        if not self.tracking_enabled:
            return

        # Check if we have a recent marker pose (within last 0.5 seconds)
        if self.marker_pose is None or self.marker_pose_time is None:
            return

        time_since_marker = (self.get_clock().now() - self.marker_pose_time).nanoseconds / 1e9
        if time_since_marker > 0.5:
            # Marker data is stale, stop moving
            return

        # Get current EE pose
        ee_pose = self.get_ee_pose_in_base()
        if ee_pose is None:
            return

        # Get marker pose in base frame
        marker_pose = self.get_marker_pose_in_base()
        if marker_pose is None:
            return

        # Compute position error
        pos_error = self.compute_position_error(ee_pose, marker_pose)
        pos_error = self.apply_deadband(pos_error, self.deadband)

        # Compute orientation error
        orient_error = self.compute_orientation_error(ee_pose, marker_pose)
        orient_error = self.apply_deadband(orient_error, self.angular_deadband)

        # Apply proportional control
        linear_vel = self.linear_gain * pos_error
        angular_vel = self.angular_gain * orient_error

        # Clamp velocities
        linear_vel = self.clamp_velocity(linear_vel, self.max_linear_vel)
        angular_vel = self.clamp_velocity(angular_vel, self.max_angular_vel)

        # Create and publish twist message
        twist_msg = TwistStamped()
        twist_msg.header.stamp = self.get_clock().now().to_msg()
        twist_msg.header.frame_id = self.base_frame
        twist_msg.twist.linear.x = float(linear_vel[0])
        twist_msg.twist.linear.y = float(linear_vel[1])
        twist_msg.twist.linear.z = float(linear_vel[2])
        twist_msg.twist.angular.x = float(angular_vel[0])
        twist_msg.twist.angular.y = float(angular_vel[1])
        twist_msg.twist.angular.z = float(angular_vel[2])

        self.twist_pub.publish(twist_msg)


def main(args=None):
    rclpy.init(args=args)
    node = ArucoServoFollower()

    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
