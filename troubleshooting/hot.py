#!/usr/env python

import json
import sys

#biggestRange = 0
#biggestRaftLog = 0

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

if len(sys.argv) != 2:
    print("Usage: python %s <ranges-file>" % sys.argv[0])
    sys.exit(1)

with open(sys.argv[1]) as ranges_file:    
    ranges = json.load(ranges_file)["ranges"]
sorted_ranges = sorted(ranges.values(), key=lambda x: queriesPerSecond(x), reverse=True)

print("rank\trangeId\tQPS\tlh\tnodes")

for i in range(min(len(sorted_ranges), 10)):
    print("%3d:\t%s\t%d\t%s\t%s" % (i+1, sorted_ranges[i]["rangeId"], queriesPerSecond(sorted_ranges[i]), leaseholder(sorted_ranges[i]), nodes(sorted_ranges[i])))
