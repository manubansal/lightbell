from datetime import datetime, timezone, timedelta
import time

def wait_until(timestamp):
  now = datetime.now(timezone.utc)
  delta = (timestamp - now).total_seconds()
  if delta >= 0:
    time.sleep(delta)

