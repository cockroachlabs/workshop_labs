import logging
import argparse
import sys
from os import path as osPath, makedirs, rename, listdir, rmdir, remove, environ, getcwd
import os
import json
import sys
import requests
import psycopg2
import psycopg2.errorcodes
import datetime

__appname__ = 'hottest_ranges3'
__version__ = '0.7.0'
__authors__ = ['Glenn Fawcett']
__credits__ = ['Cockroach Labs']

# Globals and Constants
################################
class dbstr:
  def __init__(self, database, user, host, port):
    self.database = database
    self.user = user
    # self.sslmode = sslmode
    self.host = host
    self.port = port

class G:
    """Globals and Constants"""
    LOG_DIRECTORY_NAME = 'logs'

class SQL:
    selectRangeId = """
    SELECT database_name, table_name, index_name 
    FROM crdb_internal.ranges 
    WHERE range_id = {}
    """
# Helper Functions
################################

def makeDirIfNeeded(d):
    """ create if doesn't exhist """
    if not osPath.exists(d):
        makedirs(d)
        logging.debug('Create needed directory at: {}'.format(d))  

def onestmt(conn, sql):
    with conn.cursor() as cur:
        cur.execute(sql)

def getcon(dc):
    myconn = psycopg2.connect(
        database=dc.database,
        user=dc.user,
        sslmode='disable',
        port=dc.port,
        host=dc.host
    )
    return myconn

def queriesPerSecond(rangeInfo):
    for node in rangeInfo["nodes"]:
        nodeID = node["nodeId"]
        if nodeID == node["range"]["state"]["state"]["lease"]["replica"]["nodeId"]:
            return node["range"]["stats"]["queriesPerSecond"]
    return 0


def nodes(rangeInfo):
    return [node["nodeId"] for node in rangeInfo["nodes"]]


def leaseholder(rangeInfo):
    return rangeInfo["nodes"][0]["range"]["state"]["state"]["lease"]["replica"]["nodeId"]

def lookupRange(rangeId, mycon):
    with mycon:
        with mycon.cursor() as cur:
            cur.execute(SQL.selectRangeId.format(rangeId))
            rows = cur.fetchall()
            # print([str(cell) for cell in rows[0]])
    return [str(cell) for cell in rows[0]]
        



####
#### MAIN
####
def getArgs():
    """ Get command line args """
    desc = 'Find Hottest Ranges for CockroachDB'
    parser = argparse.ArgumentParser(description=desc)
    parser.add_argument("-v", "--verbose", action="store_true", default=False, help='Verbose logging')
    parser.add_argument("-o", "--console-log", dest='console_log', default=False, help='send log to console and files')
    parser.add_argument("-z", "--logdir", dest='log_dir', default=False, help='send log to console and files')
    parser.add_argument("-l", "--host", dest='host', default='glenn-bpf-0001.roachprod.crdb.io', help='Host AdminUI')
    parser.add_argument("-d", "--db", dest='database', default='defaultdb', help='Database Name')
    parser.add_argument("-r", "--adminport", dest='adminport', default='26258', help='AdminUI Port')
    parser.add_argument("-p", "--dbport", dest='dbport', default='26257', help='Database Port')
    parser.add_argument("-u", "--user", dest='user', default='root', help='Datbase User')
    parser.add_argument("-n", "--numtop", dest='numtop', default=10, help='Number of Top Ranges to Display')
    options = parser.parse_args()
    return options

def main():

    # get command line args
    options = getArgs()
 
    if options.console_log:
        config = {}
        config['log_dir'] = os.getcwd()
        base_logging_path = osPath.join(config['log_dir'], G.LOG_DIRECTORY_NAME, __appname__)
        makeDirIfNeeded(base_logging_path)
        general_logging_path = osPath.join(base_logging_path, 'GENERAL')
        makeDirIfNeeded(general_logging_path)
        formatter = logging.Formatter('%(asctime)s %(levelname)s %(message)s')
        level = logging.DEBUG if options.verbose else logging.INFO
        handler = logging.FileHandler(osPath.join(general_logging_path, 'general_{}.log'.format(datetime.datetime.now().strftime('%Y%m%d%H%M%S%f')[:-3])))
        handler.setFormatter(formatter)
        console_handler = logging.StreamHandler()
        console_handler.setFormatter(formatter)

    # response = requests.get('http://glenn-bpf-0001.roachprod.crdb.io:26258/_status/raft', verify=False)
    response = requests.get('http://' + options.host + ':' + options.adminport + '/_status/raft', verify=False)

    ranges = json.loads(response.content)["ranges"]
    sorted_ranges = sorted(ranges.values(), key=lambda x: queriesPerSecond(x), reverse=True)

    mycon = getcon(dbstr(options.database, options.user, options.host, options.dbport))
    mycon.set_session(autocommit=True)

    # Print Header for output
    print("rank %8s\t%10s\t%10s\t%12s\t%s" % ("rangeId", "QPS", "Nodes", "leaseHolder", "DBname, TableName, IndexName"))

    for i in range(min(len(sorted_ranges), int(options.numtop))):
        hotObj=lookupRange(sorted_ranges[i]["rangeId"], mycon)
        print("%3d: %8s\t%10f\t%10s\t%12s\t%s" % (i+1, sorted_ranges[i]["rangeId"], queriesPerSecond(sorted_ranges[i]), nodes(sorted_ranges[i]), leaseholder(sorted_ranges[i]), hotObj))


#  Run Main
####################################
if __name__ == '__main__':
    main()