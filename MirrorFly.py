#!/usr/bin/python

import sys
import struct
import os
import datetime
import requests
import json
import time

def read_from_stdin(bytes):
  if hasattr(sys.stdin, 'buffer'):
    return sys.stdin.buffer.read(bytes)
  else:
    return sys.stdin.read(bytes)

def log(string):
    with open('/opt/ejabberd/sso-auth.log', 'a') as f:
        f.write(str(datetime.datetime.now()) + ': ' + string + '\n')

def read():
    (pkt_size,) = struct.unpack('>H', read_from_stdin(2))
    pkt = sys.stdin.read(pkt_size)
    cmd = pkt.split(':')[0]
    if cmd == 'auth':
        log('requested input' + pkt)
        u, s, p, l = pkt.split(':', 5)[1:]
        if u == "wrong":
            write(False)
        elif p == 'allow':
            write(True)
        else:
            rurl = str("https://"+l)
            #dt = datetime.now()
            currentTimestamp = int(time.time())
            obj = {'password': p, 'username': u,'currentTimestamp':currentTimestamp}
            headers = {'Content-Type': 'application/json'}
            r = requests.post(rurl, data=json.dumps(obj), headers=headers)
            if ((r.status_code == 200 or r.status_code == 202 or r.status_code == 201) and (json.loads(r.text)['status'] == 200 or json.loads(r.text)['status'] == 201)):
                write(True)
            else:
                write(False)
    elif cmd == 'isuser':
        u, s = pkt.split(':', 2)[1:]
        if u == "wrong":
            write(False)
        else:
            write(True)
    elif cmd == 'setpass':
        u, s, p = pkt.split(':', 3)[1:]
        write(True)
    elif cmd == 'tryregister':
        u, s, p = pkt.split(':', 3)[1:]
        write(True)
    elif cmd == 'removeuser':
        u, s = pkt.split(':', 2)[1:]
        write(True)
    elif cmd == 'removeuser3':
        u, s, p = pkt.split(':', 3)[1:]
        write(True)
    else:
        write(False)
    read()

def write(result):
    if result:
        sys.stdout.write('\x00\x02\x00\x01')
    else:
        sys.stdout.write('\x00\x02\x00\x00')
    sys.stdout.flush()

if __name__ == "__main__":
    try:
        read()
    except struct.error:
        pass
