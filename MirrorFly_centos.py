#!/usr/bin/python
import sys
from struct import *
import os
import datetime
import requests
import json
import time 

#url = 'https://api-uikit-uat.contus.us/api/v1/login'


def log(string):
    with open('/opt/ejabberd/sso-auth.log', 'a') as f:
        f.write(str(datetime.datetime.now()) + ': ' + string + '\n')



def from_ejabberd():
    input_length = sys.stdin.read(2)
    (size,) = unpack('>h', input_length)
    input = sys.stdin.read(size)
    log('requested input' + input)
    return input.split(':')

def to_ejabberd(bool):
    answer = 0
    if bool:
        answer = 1
    token = pack('>hh', 2, answer)
    sys.stdout.write(token)
    sys.stdout.flush()

def auth(username, server, password,url):  
    rurl = str("https://"+url)
    currentTimestamp = int(time.time())
    obj = {'password': password, 'username': username,'currentTimestamp':currentTimestamp}
    headers = {'Content-Type': 'application/json'}
    r = requests.post(rurl, data=json.dumps(obj), headers=headers)
    
    if ((r.status_code == 200 or r.status_code == 202 or r.status_code == 201) and (json.loads(r.text)['status'] == 200 or json.loads(r.text)['status'] == 201)):
        return True
    else:
        return False

def check_password(username, server, password):
    return False

def isuser(username, server):
    return True

def setpass(username, server, password):
    return False

while True:
    data = from_ejabberd()
    success = False
    if data[0] == "auth":
        success = auth(data[1], data[2], data[3], data[4])
    elif data[0] == "isuser":
        success = isuser(data[1], data[2])
    elif data[0] == "setpass":
        success = setpass(data[1], data[2], data[3])
    elif data[0] == "check_password":
        success = auth(data[1], data[2], data[3])
    to_ejabberd(success)