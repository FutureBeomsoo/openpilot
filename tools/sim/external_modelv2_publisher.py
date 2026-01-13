#!/usr/bin/env python3
"""
External ModelV2 Publisher for testing openpilot v0.9.4

This script publishes modelV2 messages to test the External Model mode.
When UseExternalModel is enabled, modeld stops publishing modelV2,
and this script can provide modelV2 for vehicle control testing.

Unlike external_modeld.py (which receives from external ZMQ source),
this tool generates fake modelV2 data directly for testing purposes.

Usage:
  python tools/sim/external_modelv2_publisher.py

  # With keyboard control
  python tools/sim/external_modelv2_publisher.py --keyboard

Note: v0.9.4 doesn't have action field (desiredCurvature, desiredAcceleration).
      LateralPlanner computes curvatures from position/orientation via lat_mpc.
      To control steering, modify the position.y trajectory (lateral offset).
"""

import time
import argparse
import cereal.messaging as messaging
from cereal import log

# Constants for v0.9.4
TRAJECTORY_SIZE = 33
PUBLISH_RATE = 20  # Hz
DESIRE_LEN = 8

# T_IDXS: quadratic spacing from 0 to 10 seconds (same as modeld)
T_IDXS = [float(10.0 * (i / (TRAJECTORY_SIZE - 1)) ** 2) for i in range(TRAJECTORY_SIZE)]
T_IDXS_LIST = T_IDXS


class ExternalModelV2Publisher:
  def __init__(self):
    self.pm = messaging.PubMaster(['modelV2'])
    self.sm = messaging.SubMaster(['carState', 'carControl', 'controlsState'])

    self.frame_id = 0

    # Control parameters
    # In v0.9.4, we control via trajectory (position.y for lateral, velocity.x for longitudinal)
    self.lateral_offset = 0.0  # meters, positive = right
    self.target_speed = 10.0   # m/s
    self.lane_width = 3.7      # meters

  def create_xyzt_data(self, x=None, y=None, z=None, t=None):
    """Create XYZTData dict with default values"""
    return {
      't': t if t is not None else T_IDXS_LIST,
      'x': x if x is not None else [0.0] * TRAJECTORY_SIZE,
      'y': y if y is not None else [0.0] * TRAJECTORY_SIZE,
      'z': z if z is not None else [0.0] * TRAJECTORY_SIZE,
    }

  def fill_xyzt(self, builder, data):
    """Fill XYZTData capnp builder"""
    builder.t = data['t']
    builder.x = data['x']
    builder.y = data['y']
    builder.z = data['z']

  def create_lead_v3_data(self, prob=0.0, distance=100.0):
    """Create LeadDataV3 dict"""
    n = 6  # lead prediction timestamps
    return {
      'prob': prob,
      'probTime': 0.0,
      't': [0.0, 2.0, 4.0, 6.0, 8.0, 10.0],
      'x': [distance] * n,
      'xStd': [1.0] * n,
      'y': [0.0] * n,
      'yStd': [1.0] * n,
      'v': [0.0] * n,
      'vStd': [1.0] * n,
      'a': [0.0] * n,
      'aStd': [1.0] * n,
    }

  def fill_lead_v3(self, builder, data):
    """Fill LeadDataV3 capnp builder"""
    builder.prob = data['prob']
    builder.probTime = data['probTime']
    builder.t = data['t']
    builder.x = data['x']
    builder.xStd = data['xStd']
    builder.y = data['y']
    builder.yStd = data['yStd']
    builder.v = data['v']
    builder.vStd = data['vStd']
    builder.a = data['a']
    builder.aStd = data['aStd']

  def publish(self):
    """Publish modelV2 message"""
    self.sm.update(0)

    # Get current vehicle state
    v_ego = float(self.sm['carState'].vEgo) if self.sm.valid['carState'] else float(self.target_speed)

    # Create message
    msg = messaging.new_message('modelV2')
    modelV2 = msg.modelV2

    # Frame info
    modelV2.frameId = self.frame_id
    modelV2.frameIdExtra = self.frame_id
    modelV2.frameAge = 0
    modelV2.frameDropPerc = 0.0
    modelV2.timestampEof = int(time.monotonic() * 1e9)
    modelV2.modelExecutionTime = 0.05
    modelV2.gpuExecutionTime = 0.03

    # Position prediction (future trajectory)
    # x: forward distance based on speed and time
    # y: lateral offset (controls steering via lat_mpc)
    # z: vertical (usually 0)
    positions_x = [float(v_ego * t) for t in T_IDXS]
    positions_y = [float(self.lateral_offset)] * TRAJECTORY_SIZE  # constant lateral offset
    positions_z = [0.0] * TRAJECTORY_SIZE
    self.fill_xyzt(modelV2.init('position'), self.create_xyzt_data(
      x=positions_x, y=positions_y, z=positions_z))

    # Velocity prediction
    velocities_x = [float(self.target_speed)] * TRAJECTORY_SIZE
    velocities_y = [0.0] * TRAJECTORY_SIZE
    velocities_z = [0.0] * TRAJECTORY_SIZE
    self.fill_xyzt(modelV2.init('velocity'), self.create_xyzt_data(
      x=velocities_x, y=velocities_y, z=velocities_z))

    # Acceleration prediction
    self.fill_xyzt(modelV2.init('acceleration'), self.create_xyzt_data())

    # Orientation prediction (yaw in z component)
    self.fill_xyzt(modelV2.init('orientation'), self.create_xyzt_data())

    # Orientation rate prediction (yaw rate in z component)
    self.fill_xyzt(modelV2.init('orientationRate'), self.create_xyzt_data())

    # Lane lines (4 lines: left-left, left, right, right-right)
    lane_lines = modelV2.init('laneLines', 4)
    half_lane = self.lane_width / 2
    lane_y_positions = [
      -half_lane - self.lane_width,  # left-left
      -half_lane,                     # left
      half_lane,                      # right
      half_lane + self.lane_width,   # right-right
    ]
    for i, y_pos in enumerate(lane_y_positions):
      lane_data = self.create_xyzt_data(
        x=positions_x,
        y=[y_pos] * TRAJECTORY_SIZE,
        z=[0.0] * TRAJECTORY_SIZE
      )
      self.fill_xyzt(lane_lines[i], lane_data)
    modelV2.laneLineProbs = [0.3, 0.9, 0.9, 0.3]
    modelV2.laneLineStds = [0.5, 0.2, 0.2, 0.5]

    # Road edges
    road_edges = modelV2.init('roadEdges', 2)
    edge_positions = [-half_lane - self.lane_width - 1.0, half_lane + self.lane_width + 1.0]
    for i, y_pos in enumerate(edge_positions):
      edge_data = self.create_xyzt_data(
        x=positions_x,
        y=[y_pos] * TRAJECTORY_SIZE,
        z=[0.0] * TRAJECTORY_SIZE
      )
      self.fill_xyzt(road_edges[i], edge_data)
    modelV2.roadEdgeStds = [0.5, 0.5]

    # Lead cars (3 leads, all with low probability for testing)
    leads = modelV2.init('leadsV3', 3)
    for i in range(3):
      lead_data = self.create_lead_v3_data(prob=0.0, distance=100.0 + i * 10.0)
      self.fill_lead_v3(leads[i], lead_data)

    # Meta data
    meta = modelV2.init('meta')
    meta.engagedProb = 1.0
    meta.desirePrediction = [0.0] * (4 * DESIRE_LEN)
    meta.desireState = [1.0] + [0.0] * (DESIRE_LEN - 1)  # No desire
    meta.hardBrakePredicted = False

    # Disengage predictions
    disengage = meta.init('disengagePredictions')
    disengage.t = [2.0, 4.0, 6.0, 8.0, 10.0]
    disengage.brakeDisengageProbs = [0.0] * 5
    disengage.gasDisengageProbs = [0.0] * 5
    disengage.steerOverrideProbs = [0.0] * 5
    disengage.brake3MetersPerSecondSquaredProbs = [0.0] * 5
    disengage.brake4MetersPerSecondSquaredProbs = [0.0] * 5
    disengage.brake5MetersPerSecondSquaredProbs = [0.0] * 5

    # Confidence
    modelV2.confidence = log.ModelDataV2.ConfidenceClass.green

    # Temporal pose (v0.9.4 specific)
    temporal_pose = modelV2.init('temporalPose')
    temporal_pose.trans = [v_ego, 0.0, 0.0]
    temporal_pose.rot = [0.0, 0.0, 0.0]
    temporal_pose.transStd = [1.0, 1.0, 1.0]
    temporal_pose.rotStd = [1.0, 1.0, 1.0]

    # v0.9.4 specific fields
    modelV2.navEnabled = False
    modelV2.locationMonoTime = 0

    # Mark message as valid
    msg.valid = True

    # Send message
    self.pm.send('modelV2', msg)
    self.frame_id += 1

  def set_lateral_offset(self, offset: float):
    """Set lateral offset (positive = move right, negative = move left)"""
    self.lateral_offset = float(max(-2.0, min(2.0, offset)))  # meters

  def set_target_speed(self, speed: float):
    """Set target speed"""
    self.target_speed = float(max(0.0, min(40.0, speed)))  # m/s


def main():
  parser = argparse.ArgumentParser(description='External ModelV2 Publisher for v0.9.4')
  parser.add_argument('--keyboard', action='store_true', help='Enable keyboard control')
  args = parser.parse_args()

  publisher = ExternalModelV2Publisher()
  print("External ModelV2 Publisher for openpilot v0.9.4")
  print(f"Publishing at {PUBLISH_RATE} Hz")
  print("Press Ctrl+C to stop")
  print("")
  print("Note: v0.9.4 uses position.y for lateral control (not action.desiredCurvature)")

  if args.keyboard:
    print("\nKeyboard controls:")
    print("  Left/Right arrows: lateral offset")
    print("  Up/Down arrows: target speed")
    print("  Space: reset to center")
    print("  q: quit")

    try:
      import termios
      import tty
      import sys
      import select

      old_settings = termios.tcgetattr(sys.stdin)
      tty.setcbreak(sys.stdin.fileno())

      lateral = 0.0
      speed = 10.0

      try:
        while True:
          # Check for keyboard input
          if select.select([sys.stdin], [], [], 0)[0]:
            key = sys.stdin.read(1)
            if key == 'q':
              break
            elif key == ' ':
              lateral = 0.0
              speed = 10.0
            elif key == '\x1b':  # Arrow key prefix
              sys.stdin.read(1)  # skip [
              arrow = sys.stdin.read(1)
              if arrow == 'A':  # Up - increase speed
                speed = min(speed + 1.0, 40.0)
              elif arrow == 'B':  # Down - decrease speed
                speed = max(speed - 1.0, 0.0)
              elif arrow == 'C':  # Right - move right
                lateral = min(lateral + 0.1, 2.0)
              elif arrow == 'D':  # Left - move left
                lateral = max(lateral - 0.1, -2.0)

            publisher.set_lateral_offset(lateral)
            publisher.set_target_speed(speed)
            print(f"\rLateral: {lateral:+.2f}m, Speed: {speed:.1f}m/s    ", end='', flush=True)

          publisher.publish()
          time.sleep(1.0 / PUBLISH_RATE)
      finally:
        termios.tcsetattr(sys.stdin, termios.TCSADRAIN, old_settings)

    except ImportError:
      print("Keyboard control not available on this platform")
      args.keyboard = False

  if not args.keyboard:
    # Simple loop without keyboard
    try:
      while True:
        publisher.publish()
        time.sleep(1.0 / PUBLISH_RATE)
    except KeyboardInterrupt:
      pass

  print("\nStopped")


if __name__ == "__main__":
  main()
