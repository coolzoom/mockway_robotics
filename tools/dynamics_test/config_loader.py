#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# Copyright (c) 2025. Li Jianbin. All rights reserved.
# MIT License

"""
Mockway Robot - Configuration Loader for Dynamics Test

This module provides configuration loading and validation for the real-time
torque compensation control system.
"""

import sys
import yaml
from pathlib import Path
from typing import List, Optional
from dataclasses import dataclass

# Add motor driver to path
sys.path.append(str(Path(__file__).parent.parent / "motor_gui"))
from dm_motor_driver import MotorType


# Motor type string to enum mapping
MOTOR_TYPE_MAP = {
    "DM_J4310_2EC": MotorType.DM_J4310_2EC,
    "DM4340": MotorType.DM4340,
}

# USB-CAN 适配器类型（与 motor_gui/dm_motor_driver.create_can_adapter 一致）
CAN_ADAPTER_TYPES = {
    'damiao': '达妙 USB-CAN',
    '达妙': '达妙 USB-CAN',
    '达妙 usb-can': '达妙 USB-CAN',
    'dm': '达妙 USB-CAN',
    'witmotion': '维特 USB-CAN',
    'wit': '维特 USB-CAN',
    '维特': '维特 USB-CAN',
    '维特 usb-can': '维特 USB-CAN',
}


def normalize_can_adapter_type(adapter_type: str) -> str:
    """将配置中的适配器类型规范化为 damiao 或 witmotion"""
    key = (adapter_type or 'damiao').strip().lower()
    if key in ('达妙 usb-can', 'damiao', 'dm', '达妙'):
        return 'damiao'
    if key in ('witmotion', 'wit', '维特', '维特 usb-can'):
        return 'witmotion'
    raise ValueError(
        f"未知的 CAN 适配器类型: {adapter_type!r}，"
        f"可选: damiao（达妙 USB-CAN）, witmotion（维特 USB-CAN）"
    )


def can_adapter_display_name(adapter_type: str) -> str:
    """返回适配器类型的显示名称"""
    key = (adapter_type or '').strip().lower()
    return CAN_ADAPTER_TYPES.get(key, adapter_type)


@dataclass
class MotorConfig:
    """单个电机的配置"""
    motor_id: int
    motor_type: MotorType
    master_id: int
    description: str = ""
    direction: int = 1  # 电机旋转方向: 1=正向(与关节同向), -1=反向(与关节反向)
    compensation_enabled: bool = False  # 是否对该关节输出补偿力矩（逐轴调试）
    torque_scale: float = 1.0  # 该关节补偿力矩缩放 (0~2，1=模型计算值)
    kd: Optional[float] = None  # 已弃用：补偿关节请用纯 t_ff (kp=0,kd=0)
    hold_kp: Optional[float] = None  # 未补偿关节位置保持 kp (None=使用全局 hold_kp)
    hold_kd: Optional[float] = None  # 未补偿关节位置保持 kd


@dataclass
class DynamicsTestConfig:
    """完整的动力学测试配置"""
    can_port: str
    can_adapter_type: str  # "damiao" 或 "witmotion"
    can_serial_baudrate: int
    can_baudrate: int
    motors: List[MotorConfig]
    control_rate: int
    compensation_mode: str
    kp: float
    kd: float
    torque_scale: float  # 全局补偿力矩缩放
    tau_filter_cutoff_hz: float  # 补偿力矩低通滤波 (0=关闭)
    hold_inactive_joints: bool  # 未补偿关节锁定启动时姿态，避免前臂摆动干扰 g(q)
    hold_kp: float  # 未补偿关节 MIT 位置保持 kp
    hold_kd: float  # 未补偿关节 MIT 位置保持 kd
    torque_ramp_sec: float  # 补偿力矩软启动时长 (s)，0=立即满力矩
    log_interval: float
    verbose: bool


def motor_type_from_string(type_str: str) -> MotorType:
    """
    将字符串转换为 MotorType 枚举

    Args:
        type_str: 电机型号字符串

    Returns:
        MotorType 枚举值

    Raises:
        ValueError: 如果电机型号无效
    """
    if type_str not in MOTOR_TYPE_MAP:
        available_types = ", ".join(MOTOR_TYPE_MAP.keys())
        raise ValueError(
            f"无效的电机型号: '{type_str}'\n"
            f"可用的电机型号: {available_types}"
        )
    return MOTOR_TYPE_MAP[type_str]


def get_default_config() -> DynamicsTestConfig:
    """
    返回硬编码的默认配置（向后兼容）

    Returns:
        DynamicsTestConfig: 默认配置对象
    """
    # 默认电机配置（3个电机）
    default_motors = [
        MotorConfig(
            motor_id=1,
            motor_type=MotorType.DM_J4310_2EC,
            master_id=0,
            description="Joint 1 - Shoulder",
            direction=1
        ),
        MotorConfig(
            motor_id=2,
            motor_type=MotorType.DM4340,
            master_id=0,
            description="Joint 2 - Elbow",
            direction=1
        ),
        MotorConfig(
            motor_id=3,
            motor_type=MotorType.DM4340,
            master_id=0,
            description="Joint 3 - Forearm",
            direction=-1
        ),
    ]

    return DynamicsTestConfig(
        can_port="COM9",
        can_adapter_type="damiao",
        can_serial_baudrate=921600,
        can_baudrate=1000000,
        motors=default_motors,
        control_rate=200,
        compensation_mode="gravity",
        kp=0.0,
        kd=0.005,
        torque_scale=1.0,
        tau_filter_cutoff_hz=0.0,
        hold_inactive_joints=True,
        hold_kp=50.0,
        hold_kd=1.0,
        torque_ramp_sec=2.0,
        log_interval=0.5,
        verbose=False
    )


def validate_config(config: DynamicsTestConfig) -> List[str]:
    """
    验证配置有效性

    Args:
        config: 配置对象

    Returns:
        错误消息列表（如果为空则配置有效）
    """
    errors = []

    # 验证电机数量
    if len(config.motors) == 0:
        errors.append("至少需要配置一个电机")

    # 验证电机ID唯一性
    motor_ids = [m.motor_id for m in config.motors]
    if len(motor_ids) != len(set(motor_ids)):
        errors.append("电机ID必须唯一")

    # 验证控制频率
    if config.control_rate <= 0:
        errors.append(f"控制频率必须大于0 (当前: {config.control_rate})")

    # 验证补偿模式
    valid_modes = ["gravity", "full_dynamics", "none"]
    if config.compensation_mode not in valid_modes:
        errors.append(
            f"无效的补偿模式: '{config.compensation_mode}' "
            f"(可用: {', '.join(valid_modes)})"
        )

    # 验证控制参数
    if config.kp < 0:
        errors.append(f"kp必须非负 (当前: {config.kp})")

    if config.kd < 0:
        errors.append(f"kd必须非负 (当前: {config.kd})")

    if config.torque_scale <= 0 or config.torque_scale > 2.0:
        errors.append(f"全局 torque_scale 须在 (0, 2] 内 (当前: {config.torque_scale})")

    if config.tau_filter_cutoff_hz < 0:
        errors.append(f"tau_filter_cutoff_hz 不能为负 (当前: {config.tau_filter_cutoff_hz})")

    for motor in config.motors:
        if motor.torque_scale <= 0 or motor.torque_scale > 2.0:
            errors.append(
                f"电机{motor.motor_id} torque_scale 须在 (0, 2] 内 "
                f"(当前: {motor.torque_scale})"
            )
        if motor.kd is not None and motor.kd < 0:
            errors.append(f"电机{motor.motor_id} kd 不能为负 (当前: {motor.kd})")

    # 验证CAN端口
    if not config.can_port:
        errors.append("CAN端口不能为空")

    # 验证 USB-CAN 适配器类型
    try:
        normalize_can_adapter_type(config.can_adapter_type)
    except ValueError as e:
        errors.append(str(e))

    # 验证波特率
    if config.can_serial_baudrate <= 0:
        errors.append(f"CAN串口波特率必须大于0 (当前: {config.can_serial_baudrate})")

    if config.can_baudrate <= 0:
        errors.append(f"CAN总线波特率必须大于0 (当前: {config.can_baudrate})")

    return errors


def load_config(config_path: Optional[str] = None) -> DynamicsTestConfig:
    """
    加载配置文件

    Args:
        config_path: 配置文件路径（如果为None，使用默认路径）

    Returns:
        DynamicsTestConfig: 配置对象

    Raises:
        FileNotFoundError: 如果指定的配置文件不存在
        yaml.YAMLError: 如果YAML格式错误
        ValueError: 如果配置验证失败
    """
    # 如果没有指定路径，使用默认路径
    if config_path is None:
        config_path = Path(__file__).parent / "dynamics_test.yaml"
    else:
        config_path = Path(config_path)

    # 检查文件是否存在
    if not config_path.exists():
        print(f"警告: 配置文件不存在: {config_path}")
        print("使用默认配置")
        return get_default_config()

    # 读取并解析YAML
    try:
        with open(config_path, 'r', encoding='utf-8') as f:
            yaml_data = yaml.safe_load(f)
    except yaml.YAMLError as e:
        print(f"错误: YAML格式错误")
        print(f"  文件: {config_path}")
        print(f"  错误: {e}")
        print("\n使用默认配置")
        return get_default_config()
    except Exception as e:
        print(f"错误: 无法读取配置文件: {e}")
        print("使用默认配置")
        return get_default_config()

    # 解析配置
    try:
        # CAN配置
        can_config = yaml_data.get('can', {})
        can_port = can_config.get('port', 'COM9')
        can_adapter_type = normalize_can_adapter_type(
            can_config.get('adapter_type', 'damiao')
        )
        can_serial_baudrate = can_config.get('serial_baudrate', 921600)
        can_baudrate = can_config.get('can_baudrate', 1000000)

        # 控制配置
        control_config = yaml_data.get('control', {})
        control_rate = control_config.get('rate', 200)
        compensation_mode = control_config.get('compensation_mode', 'gravity')
        global_torque_scale = control_config.get('torque_scale', 1.0)
        tau_filter_cutoff_hz = control_config.get('tau_filter_cutoff_hz', 0.0)
        hold_inactive_joints = control_config.get('hold_inactive_joints', True)
        hold_kp = control_config.get('hold_kp', 50.0)
        hold_kd = control_config.get('hold_kd', 1.0)
        torque_ramp_sec = control_config.get('torque_ramp_sec', 2.0)

        # MIT参数
        mit_params = control_config.get('mit_params', {})
        kp = mit_params.get('kp', 0.0)
        kd = mit_params.get('kd', 1.0)

        # 日志配置
        logging_config = yaml_data.get('logging', {})
        log_interval = logging_config.get('print_status_interval', 0.5)
        verbose = logging_config.get('verbose', False)

        # 电机配置
        motors_data = yaml_data.get('motors', [])
        motors = []
        for motor_data in motors_data:
            motor = MotorConfig(
                motor_id=motor_data.get('id'),
                motor_type=motor_type_from_string(motor_data.get('type')),
                master_id=motor_data.get('master_id', 0),
                description=motor_data.get('description', ''),
                direction=motor_data.get('direction', 1),
                compensation_enabled=motor_data.get('compensation_enabled', False),
                torque_scale=motor_data.get('torque_scale', 1.0),
                kd=motor_data.get('kd'),
                hold_kp=motor_data.get('hold_kp'),
                hold_kd=motor_data.get('hold_kd'),
            )
            motors.append(motor)

        # 创建配置对象
        config = DynamicsTestConfig(
            can_port=can_port,
            can_adapter_type=can_adapter_type,
            can_serial_baudrate=can_serial_baudrate,
            can_baudrate=can_baudrate,
            motors=motors,
            control_rate=control_rate,
            compensation_mode=compensation_mode,
            kp=kp,
            kd=kd,
            torque_scale=global_torque_scale,
            tau_filter_cutoff_hz=tau_filter_cutoff_hz,
            hold_inactive_joints=hold_inactive_joints,
            hold_kp=hold_kp,
            hold_kd=hold_kd,
            torque_ramp_sec=torque_ramp_sec,
            log_interval=log_interval,
            verbose=verbose
        )

        # 验证配置
        errors = validate_config(config)
        if errors:
            print(f"错误: 配置验证失败:")
            for error in errors:
                print(f"  - {error}")
            print("\n使用默认配置")
            return get_default_config()

        return config

    except ValueError as e:
        print(f"错误: 配置解析失败: {e}")
        print("使用默认配置")
        return get_default_config()
    except KeyError as e:
        print(f"错误: 缺少必需的配置字段: {e}")
        print("使用默认配置")
        return get_default_config()
    except Exception as e:
        print(f"错误: 加载配置时发生未知错误: {e}")
        print("使用默认配置")
        return get_default_config()


def print_config_summary(config: DynamicsTestConfig):
    """
    打印配置摘要

    Args:
        config: 配置对象
    """
    print("\n" + "="*60)
    print("配置摘要")
    print("="*60)
    print(f"CAN端口: {config.can_port}")
    print(f"USB-CAN适配器: {can_adapter_display_name(config.can_adapter_type)}")
    print(f"CAN串口波特率: {config.can_serial_baudrate}")
    print(f"CAN总线波特率: {config.can_baudrate}")
    print(f"\n电机数量: {len(config.motors)}")
    for i, motor in enumerate(config.motors, 1):
        print(f"  电机{i}:")
        print(f"    CAN ID: {motor.motor_id}")
        print(f"    型号: {motor.motor_type.name}")
        print(f"    主机ID: {motor.master_id}")
        direction_str = "正向(与关节同向)" if motor.direction == 1 else "反向(与关节反向)"
        print(f"    旋转方向: {motor.direction} ({direction_str})")
        comp_str = "开启" if motor.compensation_enabled else "关闭"
        print(f"    补偿开关: {comp_str}")
        if motor.compensation_enabled:
            print(f"    补偿力度: {motor.torque_scale:.2f} × 模型力矩")
        elif config.hold_inactive_joints:
            hkp = motor.hold_kp if motor.hold_kp is not None else config.hold_kp
            hkd = motor.hold_kd if motor.hold_kd is not None else config.hold_kd
            print(f"    姿态保持: kp={hkp}, kd={hkd}")
        if motor.description:
            print(f"    描述: {motor.description}")
    print(f"\n控制频率: {config.control_rate} Hz")
    print(f"补偿模式: {config.compensation_mode}")
    print(f"全局补偿力度: {config.torque_scale:.2f} × 模型力矩")
    if config.tau_filter_cutoff_hz > 0:
        print(f"力矩低通滤波: {config.tau_filter_cutoff_hz} Hz")
    if config.hold_inactive_joints:
        print(f"未补偿关节姿态保持: kp={config.hold_kp}, kd={config.hold_kd}")
    if config.torque_ramp_sec > 0:
        print(f"补偿力矩软启动: {config.torque_ramp_sec:.1f} s")
    print(f"MIT参数: kp={config.kp}, kd={config.kd} (补偿关节固定 kp=0,kd=0 纯 t_ff)")
    print(f"日志间隔: {config.log_interval} 秒")
    print(f"详细输出: {config.verbose}")
    print("="*60 + "\n")


if __name__ == "__main__":
    """测试配置加载"""
    print("测试配置加载模块\n")

    # 测试默认配置
    print("1. 测试默认配置:")
    default_config = get_default_config()
    print_config_summary(default_config)

    # 测试加载配置文件
    print("\n2. 测试加载配置文件:")
    config_path = Path(__file__).parent / "dynamics_test.yaml"
    if config_path.exists():
        config = load_config(str(config_path))
        print_config_summary(config)
    else:
        print(f"配置文件不存在: {config_path}")

    print("\n配置加载模块测试完成")
