import getpass
import json
from multiprocessing import Process, Pipe
import sys

import argparse
import httplib2


def readerloop(mesgsource, username, password):
    h = httplib2.Http()
    h.add_credentials(username, password)

    cursor = None
    while True:
        try:
            resp, cont = h.request('https://convore.com/api/live.json?cursor=%s'
                % ('null' if cursor is None else cursor))
            if resp.status != 200:
                raise ValueError('Unexpected HTTP response: %r' % resp)
            assert resp.status == 200
            ret = json.loads(cont)

            for message in ret['messages']:
                cursor = message['_id']
                mesgsource.send(message)
        except KeyboardInterrupt:
            break


class WriterLoop(object):

    def login(self, mesg):
        print "%s logged in." % mesg['user']['username']

    def logout(self, mesg):
        print "%s logged out." % mesg['user']['username']

    def star(self, mesg):
        print """%s starred %s's message, "%s" """ % (mesg['user']['username'],
            mesg['star']['message']['user']['username'], mesg['star']['message']['message'])

    def message(self, mesg):
        print "%s: %s" % (mesg['user']['username'], mesg['message'])

    def mention(self, mesg):
        if mesg['mentioned_user']['username'] == self.username:
            print "%s mentioned us!" % mesg['user']['username']

    def __call__(self, mesgsink, username, password):
        self.username = username
        while True:
            try:
                mesg = mesgsink.recv()
                try:
                    func = getattr(self, mesg['kind'])
                except AttributeError:
                    print mesg
                else:
                    func(mesg)
            except KeyboardInterrupt:
                break


def main():
    parser = argparse.ArgumentParser(description='show a live stream of new Convore content for you')
    parser.add_argument('--username', type=str, help='your Convore username', required=True)
    args = parser.parse_args()

    password = getpass.getpass()

    mesgsource, mesgsink = Pipe()
    reader = Process(target=readerloop, args=(mesgsource, args.username, password))
    reader.start()
    writer = Process(target=WriterLoop(), args=(mesgsink, args.username, password))
    writer.start()

    # Wait until both are done?
    reader.join()
    writer.join()

    return 0


if __name__ == '__main__':
    sys.exit(main())
