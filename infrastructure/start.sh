#!/bin/sh

mkdir -p data/us-east4
cp ./haproxy.cfg data/us-east4/

docker network create --driver=bridge --subnet=172.28.0.0/16 --ip-range=172.28.0.0/24 --gateway=172.28.0.1 us-east4-net
docker run -d --name=roach-newyork-1 --hostname=roach-newyork-1 --net=us-east4-net -p 8080:8080 -v "roach-newyork-1-data:/cockroach/cockroach-data" cockroachdb/cockroach:latest start --insecure --join=roach-newyork-1,roach-newyork-2,roach-newyork-3 --locality=region=us-east4,zone=a
docker run -d --name=roach-newyork-2 --hostname=roach-newyork-2 --net=us-east4-net -p 8081:8080 -v "roach-newyork-2-data:/cockroach/cockroach-data" cockroachdb/cockroach:latest start --insecure --join=roach-newyork-1,roach-newyork-2,roach-newyork-3 --locality=region=us-east4,zone=b
docker run -d --name=roach-newyork-3 --hostname=roach-newyork-3 --net=us-east4-net -p 8082:8080 -v "roach-newyork-3-data:/cockroach/cockroach-data" cockroachdb/cockroach:latest start --insecure --join=roach-newyork-1,roach-newyork-2,roach-newyork-3 --locality=region=us-east4,zone=c
docker run -d --name haproxy-newyork --net=us-east4-net -p 26257:26257 -v `pwd`/data/us-east4/:/usr/local/etc/haproxy:ro haproxy:1.7  

docker exec -it roach-newyork-1 ./cockroach init --insecure

