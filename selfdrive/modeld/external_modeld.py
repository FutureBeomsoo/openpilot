#!/usr/bin/env python3
"""
External ModelV2 Receiver for openpilot v0.9.4 (68aba7c)

This daemon receives ModelV2 messages from an external source via ZMQ
and republishes them to openpilot's internal messaging system.

External ModelV2 Data Requirements:
- position: XYZTData (33 points: x, y, z, t)
- orientation: XYZTData (33 points: x, y, z - only z used for yaw)
- orientationRate: XYZTData (33 points: x, y, z - only z used for yaw rate)
- velocity: XYZTData (33 points: x, y, z)
- acceleration: XYZTData (33 points: x, y, z)
- laneLines: List[XYZTData] (4 lines)
- laneLineProbs: List[float] (4 values)
- laneLineStds: List[float] (4 values)
- roadEdges: List[XYZTData] (2 edges)
- roadEdgeStds: List[float] (2 values)
- leads: List[LeadDataV3] (3 leads)
- meta: MetaData (desire state, disengage predictions, etc.)

The LateralPlanner will use this data to compute curvatures via lat_mpc.

Usage:
1. Set UseExternalModel=1 in params
2. Optionally set ExternalModelV2Addr and ExternalModelV2Topic
3. Run openpilot - external_modeld will start instead of modeld
4. Send ModelV2 data via ZMQ in JSON format

Example JSON format for external data:
{
  "position": {"x": [...], "y": [...], "z": [...], "t": [...]},
  "orientation": {"x": [...], "y": [...], "z": [...]},
  "orientationRate": {"x": [...], "y": [...], "z": [...]},
  "velocity": {"x": [...], "y": [...], "z": [...]},
  "meta": {"desireState": [...], "engagedProb": 0.0, ...},
  ...
}
"""

import os
import time
import json
import numpy as np
import zmq

from common.params import Params
from common.realtime import DT_MDL, config_realtime_process, Priority
import cereal.messaging as messaging
from cereal import log
from system.swaglog import cloudlog

# Constants matching driving.h and modeldata.h
TRAJECTORY_SIZE = 33
MODEL_FREQ = 20
DESIRE_LEN = 8

# T_IDXS: quadratic spacing from 0 to 10 seconds
T_IDXS = np.array([10.0 * (i / (TRAJECTORY_SIZE - 1)) ** 2 for i in range(TRAJECTORY_SIZE)], dtype=np.float32)

# Default external source configuration
EXTERNAL_ZMQ_ADDR = os.environ.get('EXTERNAL_MODELV2_ADDR', 'tcp://localhost:5557')
EXTERNAL_ZMQ_TOPIC = os.environ.get('EXTERNAL_MODELV2_TOPIC', 'modelV2')


def create_default_modelv2_data():
  """Create default/fallback ModelV2 data structure"""
  return {
    'frameId': 0,
    'frameIdExtra': 0,
    'frameAge': 0,
    'frameDropPerc': 0.0,
    'timestampEof': 0,
    'modelExecutionTime': 0.0,
    'gpuExecutionTime': 0.0,
    'position': {
      'x': T_IDXS.tolist(),  # Use T_IDXS as default x positions
      'y': [0.0] * TRAJECTORY_SIZE,
      'z': [0.0] * TRAJECTORY_SIZE,
      't': T_IDXS.tolist(),
    },
    'orientation': {
      'x': [0.0] * TRAJECTORY_SIZE,
      'y': [0.0] * TRAJECTORY_SIZE,
      'z': [0.0] * TRAJECTORY_SIZE,  # yaw
      't': T_IDXS.tolist(),
    },
    'orientationRate': {
      'x': [0.0] * TRAJECTORY_SIZE,
      'y': [0.0] * TRAJECTORY_SIZE,
      'z': [0.0] * TRAJECTORY_SIZE,  # yaw rate
      't': T_IDXS.tolist(),
    },
    'velocity': {
      'x': [10.0] * TRAJECTORY_SIZE,  # Default forward velocity
      'y': [0.0] * TRAJECTORY_SIZE,
      'z': [0.0] * TRAJECTORY_SIZE,
      't': T_IDXS.tolist(),
    },
    'acceleration': {
      'x': [0.0] * TRAJECTORY_SIZE,
      'y': [0.0] * TRAJECTORY_SIZE,
      'z': [0.0] * TRAJECTORY_SIZE,
      't': T_IDXS.tolist(),
    },
    'laneLines': [
      {'x': T_IDXS.tolist(), 'y': [-1.8] * TRAJECTORY_SIZE, 'z': [0.0] * TRAJECTORY_SIZE, 't': T_IDXS.tolist()},  # left far
      {'x': T_IDXS.tolist(), 'y': [-1.8] * TRAJECTORY_SIZE, 'z': [0.0] * TRAJECTORY_SIZE, 't': T_IDXS.tolist()},  # left near
      {'x': T_IDXS.tolist(), 'y': [1.8] * TRAJECTORY_SIZE, 'z': [0.0] * TRAJECTORY_SIZE, 't': T_IDXS.tolist()},   # right near
      {'x': T_IDXS.tolist(), 'y': [1.8] * TRAJECTORY_SIZE, 'z': [0.0] * TRAJECTORY_SIZE, 't': T_IDXS.tolist()},   # right far
    ],
    'laneLineProbs': [0.0, 0.5, 0.5, 0.0],
    'laneLineStds': [1.0, 0.3, 0.3, 1.0],
    'roadEdges': [
      {'x': T_IDXS.tolist(), 'y': [-3.0] * TRAJECTORY_SIZE, 'z': [0.0] * TRAJECTORY_SIZE, 't': T_IDXS.tolist()},  # left
      {'x': T_IDXS.tolist(), 'y': [3.0] * TRAJECTORY_SIZE, 'z': [0.0] * TRAJECTORY_SIZE, 't': T_IDXS.tolist()},   # right
    ],
    'roadEdgeStds': [0.5, 0.5],
    'leads': [],  # Will be filled with LeadDataV3
    'leadsV3': [],
    'meta': {
      'engagedProb': 0.0,
      'desirePrediction': [0.0] * (4 * DESIRE_LEN),  # DESIRE_PRED_LEN * DESIRE_LEN
      'desireState': [1.0] + [0.0] * (DESIRE_LEN - 1),  # Default: no desire
      'hardBrakePredicted': False,
      'disengagePredictions': {
        't': [2.0, 4.0, 6.0, 8.0, 10.0],
        'brakeDisengageProbs': [0.0] * 5,
        'gasDisengageProbs': [0.0] * 5,
        'steerOverrideProbs': [0.0] * 5,
        'brake3MetersPerSecondSquaredProbs': [0.0] * 5,
        'brake4MetersPerSecondSquaredProbs': [0.0] * 5,
        'brake5MetersPerSecondSquaredProbs': [0.0] * 5,
      },
    },
    'confidence': 'green',
    'temporalPose': {
      'trans': [0.0, 0.0, 0.0],
      'rot': [0.0, 0.0, 0.0],
      'transStd': [1.0, 1.0, 1.0],
      'rotStd': [1.0, 1.0, 1.0],
    },
    'navEnabled': False,
    'locationMonoTime': 0,
  }


def fill_xyzt_data(builder, data):
  """Fill XYZTData capnp builder from dict"""
  if 'x' in data:
    builder.x = data['x']
  if 'y' in data:
    builder.y = data['y']
  if 'z' in data:
    builder.z = data['z']
  if 't' in data:
    builder.t = data['t']
  # Handle std fields if present
  if 'xStd' in data:
    builder.xStd = data['xStd']
  if 'yStd' in data:
    builder.yStd = data['yStd']
  if 'zStd' in data:
    builder.zStd = data['zStd']


def fill_lead_v3(builder, data):
  """Fill LeadDataV3 capnp builder from dict"""
  builder.prob = data.get('prob', 0.0)
  builder.probTime = data.get('probTime', 0.0)
  builder.t = data.get('t', [0.0, 2.0, 4.0, 6.0, 8.0, 10.0])
  builder.x = data.get('x', [0.0] * 6)
  builder.xStd = data.get('xStd', [1.0] * 6)
  builder.y = data.get('y', [0.0] * 6)
  builder.yStd = data.get('yStd', [1.0] * 6)
  builder.v = data.get('v', [0.0] * 6)
  builder.vStd = data.get('vStd', [1.0] * 6)
  builder.a = data.get('a', [0.0] * 6)
  builder.aStd = data.get('aStd', [1.0] * 6)


def fill_meta(builder, data):
  """Fill MetaData capnp builder from dict"""
  builder.engagedProb = data.get('engagedProb', 0.0)
  builder.desirePrediction = data.get('desirePrediction', [0.0] * (4 * DESIRE_LEN))
  builder.desireState = data.get('desireState', [1.0] + [0.0] * (DESIRE_LEN - 1))
  builder.hardBrakePredicted = data.get('hardBrakePredicted', False)

  # Disengage predictions
  disengage_data = data.get('disengagePredictions', {})
  disengage = builder.init('disengagePredictions')
  disengage.t = disengage_data.get('t', [2.0, 4.0, 6.0, 8.0, 10.0])
  disengage.brakeDisengageProbs = disengage_data.get('brakeDisengageProbs', [0.0] * 5)
  disengage.gasDisengageProbs = disengage_data.get('gasDisengageProbs', [0.0] * 5)
  disengage.steerOverrideProbs = disengage_data.get('steerOverrideProbs', [0.0] * 5)
  disengage.brake3MetersPerSecondSquaredProbs = disengage_data.get('brake3MetersPerSecondSquaredProbs', [0.0] * 5)
  disengage.brake4MetersPerSecondSquaredProbs = disengage_data.get('brake4MetersPerSecondSquaredProbs', [0.0] * 5)
  disengage.brake5MetersPerSecondSquaredProbs = disengage_data.get('brake5MetersPerSecondSquaredProbs', [0.0] * 5)


def fill_temporal_pose(builder, data):
  """Fill Pose capnp builder from dict"""
  builder.trans = data.get('trans', [0.0, 0.0, 0.0])
  builder.rot = data.get('rot', [0.0, 0.0, 0.0])
  builder.transStd = data.get('transStd', [1.0, 1.0, 1.0])
  builder.rotStd = data.get('rotStd', [1.0, 1.0, 1.0])


def build_modelv2_msg(data, valid=True):
  """Build ModelV2 capnp message from dict data"""
  msg = messaging.new_message('modelV2', valid=valid)
  model = msg.modelV2

  # Basic fields
  model.frameId = data.get('frameId', 0)
  model.frameIdExtra = data.get('frameIdExtra', 0)
  model.frameAge = data.get('frameAge', 0)
  model.frameDropPerc = data.get('frameDropPerc', 0.0)
  model.timestampEof = data.get('timestampEof', 0)
  model.modelExecutionTime = data.get('modelExecutionTime', 0.0)
  model.gpuExecutionTime = data.get('gpuExecutionTime', 0.0)
  model.navEnabled = data.get('navEnabled', False)
  model.locationMonoTime = data.get('locationMonoTime', 0)

  # Position, orientation, velocity, acceleration trajectory data
  fill_xyzt_data(model.init('position'), data.get('position', {}))
  fill_xyzt_data(model.init('orientation'), data.get('orientation', {}))
  fill_xyzt_data(model.init('orientationRate'), data.get('orientationRate', {}))
  fill_xyzt_data(model.init('velocity'), data.get('velocity', {}))
  fill_xyzt_data(model.init('acceleration'), data.get('acceleration', {}))

  # Lane lines (4 lines)
  lane_lines_data = data.get('laneLines', [])
  if lane_lines_data:
    lane_lines = model.init('laneLines', len(lane_lines_data))
    for i, line_data in enumerate(lane_lines_data):
      fill_xyzt_data(lane_lines[i], line_data)

  model.laneLineProbs = data.get('laneLineProbs', [0.0] * 4)
  model.laneLineStds = data.get('laneLineStds', [1.0] * 4)

  # Road edges (2 edges)
  road_edges_data = data.get('roadEdges', [])
  if road_edges_data:
    road_edges = model.init('roadEdges', len(road_edges_data))
    for i, edge_data in enumerate(road_edges_data):
      fill_xyzt_data(road_edges[i], edge_data)

  model.roadEdgeStds = data.get('roadEdgeStds', [1.0] * 2)

  # Leads V3 (primary lead data for this version)
  leads_v3_data = data.get('leadsV3', data.get('leads', []))
  if leads_v3_data:
    leads_v3 = model.init('leadsV3', len(leads_v3_data))
    for i, lead_data in enumerate(leads_v3_data):
      fill_lead_v3(leads_v3[i], lead_data)

  # Meta data
  fill_meta(model.init('meta'), data.get('meta', {}))

  # Confidence
  confidence_str = data.get('confidence', 'green').lower()
  if confidence_str == 'red':
    model.confidence = log.ModelDataV2.ConfidenceClass.red
  elif confidence_str == 'yellow':
    model.confidence = log.ModelDataV2.ConfidenceClass.yellow
  else:
    model.confidence = log.ModelDataV2.ConfidenceClass.green

  # Temporal pose
  fill_temporal_pose(model.init('temporalPose'), data.get('temporalPose', {}))

  return msg


def build_camera_odometry_msg(data, frame_id, valid=True):
  """Build cameraOdometry capnp message from pose data"""
  msg = messaging.new_message('cameraOdometry', valid=valid)
  odom = msg.cameraOdometry

  odom.frameId = frame_id
  odom.timestampEof = data.get('timestampEof', 0)

  # Velocity and rotation from temporal pose or separate odometry data
  pose = data.get('temporalPose', {})
  odom_data = data.get('cameraOdometry', {})

  odom.trans = odom_data.get('trans', pose.get('trans', [0.0, 0.0, 0.0]))
  odom.rot = odom_data.get('rot', pose.get('rot', [0.0, 0.0, 0.0]))
  odom.transStd = odom_data.get('transStd', pose.get('transStd', [1.0, 1.0, 1.0]))
  odom.rotStd = odom_data.get('rotStd', pose.get('rotStd', [1.0, 1.0, 1.0]))

  # Additional fields from road transform if available
  road_transform = data.get('roadTransform', {})
  odom.wideFromDeviceEuler = odom_data.get('wideFromDeviceEuler', [0.0, 0.0, 0.0])
  odom.wideFromDeviceEulerStd = odom_data.get('wideFromDeviceEulerStd', [1.0, 1.0, 1.0])
  odom.roadTransformTrans = road_transform.get('trans', odom_data.get('roadTransformTrans', [0.0, 0.0, 0.0]))
  odom.roadTransformTransStd = road_transform.get('transStd', odom_data.get('roadTransformTransStd', [1.0, 1.0, 1.0]))

  return msg


class ExternalModelReceiver:
  """Receives ModelV2 data from external source and publishes to openpilot"""

  def __init__(self, zmq_addr=EXTERNAL_ZMQ_ADDR, zmq_topic=EXTERNAL_ZMQ_TOPIC):
    self.zmq_addr = zmq_addr
    self.zmq_topic = zmq_topic

    # ZMQ subscriber setup
    self.context = zmq.Context()
    self.socket = self.context.socket(zmq.SUB)
    self.socket.setsockopt(zmq.RCVTIMEO, 100)  # 100ms timeout
    self.socket.setsockopt(zmq.SUBSCRIBE, zmq_topic.encode())
    self.socket.connect(zmq_addr)

    # openpilot messaging
    self.pm = messaging.PubMaster(['modelV2', 'cameraOdometry'])

    # State
    self.frame_id = 0
    self.last_data = create_default_modelv2_data()
    self.last_recv_time = 0.0
    self.connected = False

  def receive_external_data(self):
    """Receive data from external source"""
    try:
      topic = self.socket.recv_string(zmq.NOBLOCK)
      data_json = self.socket.recv_string(zmq.NOBLOCK)
      data = json.loads(data_json)
      self.last_data = data
      self.last_recv_time = time.monotonic()
      self.connected = True
      return data
    except zmq.Again:
      # No data available, check timeout
      if self.connected and (time.monotonic() - self.last_recv_time) > 0.5:
        self.connected = False
      return None
    except json.JSONDecodeError as e:
      cloudlog.error(f"JSON decode error: {e}")
      return None
    except Exception as e:
      cloudlog.error(f"Receive error: {e}")
      return None

  def publish(self, data=None):
    """Publish ModelV2 and cameraOdometry messages"""
    if data is None:
      data = self.last_data

    # Update frame ID
    self.frame_id += 1
    data['frameId'] = self.frame_id
    data['frameIdExtra'] = self.frame_id
    data['timestampEof'] = int(time.monotonic() * 1e9)

    # Build and send ModelV2
    valid = self.connected
    model_msg = build_modelv2_msg(data, valid=valid)
    self.pm.send('modelV2', model_msg)

    # Build and send cameraOdometry
    odom_msg = build_camera_odometry_msg(data, self.frame_id, valid=valid)
    self.pm.send('cameraOdometry', odom_msg)

  def run(self):
    """Main loop"""
    cloudlog.info(f"External ModelV2 Receiver starting...")
    cloudlog.info(f"  ZMQ Address: {self.zmq_addr}")
    cloudlog.info(f"  ZMQ Topic: {self.zmq_topic}")

    dt = 1.0 / MODEL_FREQ
    last_time = time.monotonic()
    last_log_time = 0.0

    while True:
      # Receive external data if available
      data = self.receive_external_data()

      # Maintain constant publish rate
      current_time = time.monotonic()
      if current_time - last_time >= dt:
        self.publish(data)
        last_time = current_time
      else:
        # Sleep for remaining time
        sleep_time = dt - (current_time - last_time)
        if sleep_time > 0:
          time.sleep(sleep_time)
        self.publish(data)
        last_time = time.monotonic()

      # Log connection status periodically
      if time.monotonic() - last_log_time > 5.0:
        if self.connected:
          cloudlog.info(f"External model connected, frame_id: {self.frame_id}")
        else:
          cloudlog.warning("External model not connected, using default data")
        last_log_time = time.monotonic()

  def cleanup(self):
    """Cleanup resources"""
    self.socket.close()
    self.context.term()


def main():
  config_realtime_process(4, Priority.CTRL_HIGH)

  params = Params()

  # Get configuration from params or environment
  zmq_addr = params.get("ExternalModelV2Addr", encoding='utf-8')
  if not zmq_addr:
    zmq_addr = EXTERNAL_ZMQ_ADDR

  zmq_topic = params.get("ExternalModelV2Topic", encoding='utf-8')
  if not zmq_topic:
    zmq_topic = EXTERNAL_ZMQ_TOPIC

  receiver = ExternalModelReceiver(zmq_addr, zmq_topic)

  try:
    receiver.run()
  except KeyboardInterrupt:
    cloudlog.info("Shutting down external_modeld...")
  finally:
    receiver.cleanup()


if __name__ == "__main__":
  main()
