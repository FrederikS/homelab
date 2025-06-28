#!/bin/bash
grep -q open /proc/acpi/button/lid/*/state
if [ $? -eq 0 ]; then
  # Lid is open, turn screen on
  export DISPLAY=:0
  xset dpms force on
else
  # Lid is closed, turn screen off
  export DISPLAY=:0
  xset dpms force off
fi