#!/usr/bin/env python3


from ring_doorbell import Ring, Auth
from pprint import pprint
import configparser
import os
import argparse
import json

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


def save_cache(json_value):
  print('saving to cache')
  with open(cacheFilePath, 'w') as f:
    f.write(json.dumps(json_value))

def load_cache():
  print('loading from cache')
  cache = None
  try:
    with open(cacheFilePath, 'r') as f:
      cache = json.load(f)
  except Exception as e:
    print(e)
    pass

  return cache


def login(auth, otp_code=None):
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

def get_tokens(otp_code, ignore_cache=False):

  if not ignore_cache:
    tokens = load_cache()
    if tokens:
      print('tokens loaded from cache')
      auth = Auth("YourProject/0.1", token=tokens)
      return tokens, auth

    print('could not load tokens from cache')

  else:
    print('ignored loading of tokens from cache')

  print('trying to get fresh tokens by logging in, will use otp_code if provided')
  auth = Auth("YourProject/0.1", None, None)

  tokens = login(auth, otp_code)
  if tokens:
    print('tokens received, done')
    
    save_cache(tokens)

    return tokens, auth

  if otp_code:
    print('otp_code provided but could not get tokens, done')
    return tokens, auth

  print('otp_code not provided, try again with otp_code if 2FA is enabled and you just got an otp_code')
  return tokens, auth


def main():

  args = parser.parse_args()

  tokens, auth = get_tokens(args.otp, args.ignore_cache)

  ring = Ring(auth)
  ring.update_data()
  devices = ring.devices()

  bell = [d for d in devices['doorbots'] if d.name == args.device][0]

  #pprint(ring.session['profile'])
  bell.update()
  pprint(bell.history())


if __name__ == "__main__":
  main()
