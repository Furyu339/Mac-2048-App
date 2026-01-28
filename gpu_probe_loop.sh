#!/bin/bash
while true; do
  /usr/bin/powermetrics --samplers gpu_power -n 1 > /tmp/gpu_power.txt
  sleep 2
done
