# Simulating a Single-Region CockroachDB Cluster on localhost with Docker

Following are instructions to simulate the deployment of a 3 nodes [CockroachDB](https://www.cockroachlabs.com/product/) cluster across 1 region on localhost using Docker. This is especially useful for testing, training and development work.

## Setup

Create the `haproxy.cfg` files for the HAProxy in each region.

```bash
# us-east4
mkdir -p data/us-east4
cat - >data/us-east4/haproxy.cfg <<EOF

global
  maxconn 4096

defaults
    mode                tcp
    # Timeout values should be configured for your specific use.
    # See: https://cbonte.github.io/haproxy-dconv/1.8/configuration.html#4-timeout%20connect
    timeout connect     10s
    timeout client      10m
    timeout server      10m
    # TCP keep-alive on client side. Server already enables them.
    option              clitcpka

listen psql
    bind :26257
    mode tcp
    balance roundrobin
    option httpchk GET /health?ready=1
    server cockroach1 roach-newyork-1:26257 check port 8080
    server cockroach2 roach-newyork-3:26257 check port 8080
    server cockroach3 roach-newyork-2:26257 check port 8080

EOF
```

Create the docker network and containers

```bash
# create the Network bridge
docker network create --driver=bridge --subnet=172.28.0.0/16 --ip-range=172.28.0.0/24 --gateway=172.28.0.1 us-east4-net

# New York
docker run -d --name=roach-newyork-1 --hostname=roach-newyork-1 --net=us-east4-net -p 8080:8080 -v "roach-newyork-1-data:/cockroach/cockroach-data" cockroachdb/cockroach:latest start --insecure --join=roach-newyork-1,roach-newyork-2,roach-newyork-3 --locality=region=us-east4,zone=a
docker run -d --name=roach-newyork-2 --hostname=roach-newyork-2 --net=us-east4-net -p 8081:8080 -v "roach-newyork-2-data:/cockroach/cockroach-data" cockroachdb/cockroach:latest start --insecure --join=roach-newyork-1,roach-newyork-2,roach-newyork-3 --locality=region=us-east4,zone=b
docker run -d --name=roach-newyork-3 --hostname=roach-newyork-3 --net=us-east4-net -p 8082:8080 -v "roach-newyork-3-data:/cockroach/cockroach-data" cockroachdb/cockroach:latest start --insecure --join=roach-newyork-1,roach-newyork-2,roach-newyork-3 --locality=region=us-east4,zone=c
# New York HAProxy
docker run -d --name haproxy-newyork --net=us-east4-net -p 26257:26257 -v `pwd`/data/us-east4/:/usr/local/etc/haproxy:ro haproxy:1.7  
```

Initialize the cluster

```bash
docker exec -it roach-newyork-1 ./cockroach init --insecure
```

At this point you should be able to view the CockroachDB Admin UI at <http://localhost:8080>.

## References

[CockroachDB Docs](https://www.cockroachlabs.com/docs/stable/index.html)

[CockroachDB docker image](https://hub.docker.com/r/cockroachdb/cockroach)

[HAProxy Docs](https://cbonte.github.io/haproxy-dconv/)

[HAProxy docker image](https://hub.docker.com/_/haproxy)

## Clean up

Stop and remove containers, delete the data volumes.

```bash
for j in 1 2 3
do
    docker stop roach-newyork-$j
    docker rm roach-newyork-$j
    docker volume rm roach-newyork-$j-data
done
```
