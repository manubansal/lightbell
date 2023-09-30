#!/usr/bin/env python3


from event import Event
from ring_doorbell import Ring, Auth
from pprint import pprint
import configparser
import os
import argparse
import json
import logging
from enum import Enum
from datetime import datetime, timezone, timedelta
import time
import util

logging.basicConfig()
logger = logging.getLogger()
logger.setLevel(logging.INFO)

TOKEN_STATE = Enum("TOKEN_STATE", ["BAD_CACHE", "FROM_CACHE", "BRAND_NEW", "OTP_FAILED", "RETRY_WITH_OTP", "BAD_REFRESH", "GOOD_REFRESH"])

CHECK_INTERVAL_IN_SECONDS = 1

configFilePath = os.path.expanduser('~') + '/.ring'
cacheFilePath = os.path.expanduser('~') + '/.ring_cache'

parser = argparse.ArgumentParser(
                    prog='ring',
                    description='controller for cloud ring',
                    epilog=
'''
Example: ./ring -d 'Front Door' status | happy controlling!
''')


parser.add_argument('cmd')           # positional argument
parser.add_argument('-d', '--device', required=True)      # option that takes a value
parser.add_argument('-o', '--otp', default=None)      # option that takes a value
parser.add_argument('-i', '--ignore_cache', action='store_true', default=False)      # option that takes a value
parser.add_argument('--no_refresh', action='store_true', default=False)      # option that takes a value

class RingAccount:

  def save_cache(self, json_value):
    print('saving to cache')
    with open(cacheFilePath, 'w') as f:
      f.write(json.dumps(json_value))

  def load_cache(self):
    print('loading from cache')
    cache = None
    try:
      with open(cacheFilePath, 'r') as f:
        cache = json.load(f)
      logger.debug('content loaded from cache: %s', cache)
    except Exception as e:
      logger.error('error loading from cache: %s', e)

    return cache


  def login(self, auth, otp_code=None):
    config = configparser.RawConfigParser()   
    config.read(configFilePath)

    username = config.get('global', 'username')
    password = config.get('global', 'password')

    tokens = None
    try:
      tokens = auth.fetch_token(username, password, otp_code)
    except Exception as e:
      print(e)
      pass

    return tokens


  def _get_tokens(self, otp_code, ignore_cache=False):

    status = None

    if not ignore_cache:
      tokens = self.load_cache()
      if tokens:
        print('tokens loaded from cache')
        auth = Auth("YourProject/0.1", token=tokens)
        
        status = TOKEN_STATE.FROM_CACHE
        return tokens, auth, status

      status = TOKEN_STATE.BAD_CACHE
      print('could not load tokens from cache')

    else:
      print('ignored loading of tokens from cache')

    print('trying to get fresh tokens by logging in, will use otp_code if provided')
    auth = Auth("YourProject/0.1", None, None)

    tokens = self.login(auth, otp_code)
    if tokens:
      print('tokens received, done')
      
      self.save_cache(tokens)

      status = TOKEN_STATE.BRAND_NEW
      return tokens, auth, status

    if otp_code:
      print('otp_code provided but could not get tokens, done')
      status = TOKEN_STATE.OTP_FAILED
      return tokens, auth, status

    print('otp_code not provided, try again with otp_code if 2FA is enabled and you just got an otp_code')
    status = TOKEN_STATE.RETRY_WITH_OTP
    return tokens, auth, status

  def get_tokens(self, otp_code, ignore_cache=False, no_refresh=False):
    tokens, auth, status = self._get_tokens(otp_code, ignore_cache)

    if status == TOKEN_STATE.FROM_CACHE and not no_refresh:
      # force refresh of token and cache since we reloaded from cache; it's
      # likely that this application restarted after a long period and the
      # current access_token is expired.
      try:
        tokens = auth.refresh_tokens()
        self.save_cache(tokens)
        status = TOKEN_STATE.GOOD_REFRESH


      except Exception as e:
        print(e)
        status = TOKEN_STATE.BAD_REFRESH
        import pdb; pdb.set_trace()

    return tokens, auth, status


class BellEvent(Event):
  def __init__(self, bell):
    self.bell = bell

  def bell_has_dings_since(self, time_since):

    bell = self.bell

    time_now = datetime.now(timezone.utc)
    #pprint(ring.session['profile'])
    bell.update()
    history = [e for e in bell.history() if e['kind'] != 'motion']
    hi = [(e['kind'], e['created_at'], str(e['created_at']), time_now - e['created_at']) for e in history]
    hi2 = [(kind, at, age.total_seconds(), age.total_seconds()/60) for (kind, at, _, age) in hi]
    logger.debug(hi2)

    #recent_dings = [(kind, at, age) for (kind, _, at, age) in hi2 if kind == 'ding' and age.total_seconds() <= delta_in_seconds]
    recent_dings = [(kind, at, age) for (kind, at, _, age) in hi if kind == 'ding' and at >= time_since]
    most_recent_ding_age_seconds = hi2[0][2] if len(hi2) > 0 else None
    logger.debug(recent_dings)

    return recent_dings, len(recent_dings) > 0, most_recent_ding_age_seconds

  def has_event_happened():
    return self.bell_has_dings_since(time_since)


def start_checking(bell_event, check_interval_in_seconds):
  check_interval = timedelta(seconds = check_interval_in_seconds)
  while True:
    time_now = datetime.now(timezone.utc)
    time_since = time_now - check_interval
    recent_dings, has_recent_dings, most_recent_ding_age_seconds = bell_event.bell_has_dings_since(time_since)
    #import pdb; pdb.set_trace()
    logger.info('has_recent_dings: %s, most_recent_ding_age_seconds: %s', has_recent_dings, most_recent_ding_age_seconds)

    util.wait_until(time_now + check_interval)


def main():

  logger.info('parsing args')
  args = parser.parse_args()

  ring_account = RingAccount()
  tokens, auth, status = ring_account.get_tokens(args.otp, args.ignore_cache, args.no_refresh)
  if status not in [TOKEN_STATE.BRAND_NEW, TOKEN_STATE.FROM_CACHE, TOKEN_STATE.GOOD_REFRESH]:
    logger.error('could not get login to succeed, exiting...')
    return

  ring = Ring(auth)
  ring.update_data()
  devices = ring.devices()
  bell = [d for d in devices['doorbots'] if d.name == args.device][0]
  bell_event = BellEvent(bell)

  start_checking(bell_event, CHECK_INTERVAL_IN_SECONDS)


if __name__ == "__main__":
  main()
