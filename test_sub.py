#!/usr/bin/env python3
import cereal.messaging as messaging

from cereal import log

# sm = messaging.SubMaster(['sensorEvents']) // legray, 안됨
sm = messaging.SubMaster(["accelerometer"])
i = 1
while 1:
  sm.update()
  print("================================")
  if sm.updated["accelerometer"]:
    # print("print 1 : ", sm["modelV2"])
    print("print 2 : ", sm["accelerometer"])
  else:
    print("No new message received.", i)
  i += 1