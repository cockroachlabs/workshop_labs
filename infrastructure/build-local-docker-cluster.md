# Deploy a 9 nodes cluster on localhost using Docker

Following are instructions to simulate the deployment of a 9 nodes cluster across 3 regions.

![docker-arch](/media/docker-arch.png)

## Setup

Create the required networks. We create 1 network for each region, plus 1 network for each inter-region cnnection.

```bash
# region networks
docker network create --driver=bridge --subnet=172.27.0.0/16 --ip-range=172.27.0.0/24 --gateway=172.27.0.1 us-west2-net
docker network create --driver=bridge --subnet=172.28.0.0/16 --ip-range=172.28.0.0/24 --gateway=172.28.0.1 us-east4-net
docker network create --driver=bridge --subnet=172.29.0.0/16 --ip-range=172.29.0.0/24 --gateway=172.29.0.1 europe-west2-net
# global networks
docker network create --driver=bridge --subnet=172.30.0.0/16 --ip-range=172.30.0.0/24 --gateway=172.30.0.1 uswest-useast-net
docker network create --driver=bridge --subnet=172.31.0.0/16 --ip-range=172.31.0.0/24 --gateway=172.31.0.1 useast-euwest-net
docker network create --driver=bridge --subnet=172.32.0.0/16 --ip-range=172.32.0.0/24 --gateway=172.32.0.1 uswest-euwest-net
```

Each node is associated to its region's network, which will attach to the docker instance's `eth0` NIC. We also specify the node IP address with the `--ip` flag and the IP addresses of all nodes in its region using the `--add-host` flag. This will create an entry in the docker instance `/etc/hosts` file, which has precedence over DNS lookups. It will come clear later why this is important.

**Note:** below commands expect you to have the `haproxy.cfg` files inside a `data` directory. Clone this repo if that makes it easier for you.

```bash
# Seattle
docker run -d --name=roach-seattle-1 --hostname=roach-seattle-1 --ip=172.27.0.11 --cap-add NET_ADMIN --net=us-west2-net --add-host=roach-seattle-1:172.27.0.11 --add-host=roach-seattle-2:172.27.0.12 --add-host=roach-seattle-3:172.27.0.13 -p 8080:8080 -v "roach-seattle-1-data:/cockroach/cockroach-data" cockroachdb/cockroach:v20.1.5 start --insecure --join=roach-seattle-1,roach-newyork-1,roach-london-1 --locality=region=us-west2,zone=a
docker run -d --name=roach-seattle-2 --hostname=roach-seattle-2 --ip=172.27.0.12 --cap-add NET_ADMIN --net=us-west2-net --add-host=roach-seattle-1:172.27.0.11 --add-host=roach-seattle-2:172.27.0.12 --add-host=roach-seattle-3:172.27.0.13 -p 8081:8080 -v "roach-seattle-2-data:/cockroach/cockroach-data" cockroachdb/cockroach:v20.1.5 start --insecure --join=roach-seattle-1,roach-newyork-1,roach-london-1 --locality=region=us-west2,zone=b
docker run -d --name=roach-seattle-3 --hostname=roach-seattle-3 --ip=172.27.0.13 --cap-add NET_ADMIN --net=us-west2-net --add-host=roach-seattle-1:172.27.0.11 --add-host=roach-seattle-2:172.27.0.12 --add-host=roach-seattle-3:172.27.0.13 -p 8082:8080 -v "roach-seattle-3-data:/cockroach/cockroach-data" cockroachdb/cockroach:v20.1.5 start --insecure --join=roach-seattle-1,roach-newyork-1,roach-london-1 --locality=region=us-west2,zone=c
# Seattle HAProxy
docker run -d --name haproxy-seattle --ip=172.27.0.10 -p 26257:26257 --net=us-west2-net -v `pwd`/data/us-west2/:/usr/local/etc/haproxy:ro haproxy:1.7  

# New York
docker run -d --name=roach-newyork-1 --hostname=roach-newyork-1 --ip=172.28.0.11 --cap-add NET_ADMIN --net=us-east4-net --add-host=roach-newyork-1:172.28.0.11 --add-host=roach-newyork-2:172.28.0.12 --add-host=roach-newyork-3:172.28.0.13 -p 8180:8080 -v "roach-newyork-1-data:/cockroach/cockroach-data" cockroachdb/cockroach:v20.1.5 start --insecure --join=roach-seattle-1,roach-newyork-1,roach-london-1 --locality=region=us-east4,zone=a
docker run -d --name=roach-newyork-2 --hostname=roach-newyork-2 --ip=172.28.0.12 --cap-add NET_ADMIN --net=us-east4-net --add-host=roach-newyork-1:172.28.0.11 --add-host=roach-newyork-2:172.28.0.12 --add-host=roach-newyork-3:172.28.0.13 -p 8181:8080 -v "roach-newyork-2-data:/cockroach/cockroach-data" cockroachdb/cockroach:v20.1.5 start --insecure --join=roach-seattle-1,roach-newyork-1,roach-london-1 --locality=region=us-east4,zone=b
docker run -d --name=roach-newyork-3 --hostname=roach-newyork-3 --ip=172.28.0.13 --cap-add NET_ADMIN --net=us-east4-net --add-host=roach-newyork-1:172.28.0.11 --add-host=roach-newyork-2:172.28.0.12 --add-host=roach-newyork-3:172.28.0.13 -p 8182:8080 -v "roach-newyork-3-data:/cockroach/cockroach-data" cockroachdb/cockroach:v20.1.5 start --insecure --join=roach-seattle-1,roach-newyork-1,roach-london-1 --locality=region=us-east4,zone=c
# New York HAProxy
docker run -d --name haproxy-newyork --ip=172.28.0.10 -p 26258:26257 --net=us-east4-net -v `pwd`/data/us-east4/:/usr/local/etc/haproxy:ro haproxy:1.7  

# London
docker run -d --name=roach-london-1 --hostname=roach-london-1 --ip=172.29.0.11 --cap-add NET_ADMIN --net=europe-west2-net --add-host=roach-london-1:172.29.0.11 --add-host=roach-london-2:172.29.0.12 --add-host=roach-london-3:172.29.0.13 -p 8280:8080 -v "roach-london-1-data:/cockroach/cockroach-data" cockroachdb/cockroach:v20.1.5 start --insecure --join=roach-seattle-1,roach-newyork-1,roach-london-1 --locality=region=europe-west2,zone=a
docker run -d --name=roach-london-2 --hostname=roach-london-2 --ip=172.29.0.12 --cap-add NET_ADMIN --net=europe-west2-net --add-host=roach-london-1:172.29.0.11 --add-host=roach-london-2:172.29.0.12 --add-host=roach-london-3:172.29.0.13 -p 8281:8080 -v "roach-london-2-data:/cockroach/cockroach-data" cockroachdb/cockroach:v20.1.5 start --insecure --join=roach-seattle-1,roach-newyork-1,roach-london-1 --locality=region=europe-west2,zone=b
docker run -d --name=roach-london-3 --hostname=roach-london-3 --ip=172.29.0.13 --cap-add NET_ADMIN --net=europe-west2-net --add-host=roach-london-1:172.29.0.11 --add-host=roach-london-2:172.29.0.12 --add-host=roach-london-3:172.29.0.13 -p 8282:8080 -v "roach-london-3-data:/cockroach/cockroach-data" cockroachdb/cockroach:v20.1.5 start --insecure --join=roach-seattle-1,roach-newyork-1,roach-london-1 --locality=region=europe-west2,zone=c
# London HAProxy
docker run -d --name haproxy-london --ip=172.29.0.10 -p 26259:26257 --net=europe-west2-net -v `pwd`/data/europe-west2/:/usr/local/etc/haproxy:ro haproxy:1.7  
```

Initialize the cluster

```bash
docker exec -it roach-newyork-1 ./cockroach init --insecure
```

We then attach each node to the inter-regional networks. These networks will attach to new NICs, `eth1` and `eth2`. We then use `tc qdisc` to add an arbitrary latency to each new NIC.

Connectivity between nodes in the same "region" will go through the region network, over `eth0`, and connectivity among nodes in different regions via the inter-regional network, over `eth1` and `eth2`.

**Note:** with the connection to the global network, the containers internal DNS is sometimes scrambled up: issuing, say, `nslookup roach-seattle-1` from host `roach-seattle-2` will return either an IP address from the region network or from the inter-regional networks. If the hostname does not resolve to the region network's IP, traffic will go through `eth1` or `eth2` which has the latency applied, causing intra-region connectivity to look very slow. To resolve such a problem we use static IP addresses added to each node's `/etc/hosts` file. This makes sure that in-region hostnames resolve to the region's IP address, thus forcing the connection to go over `eth0` instead of `eth1` or `eth2`.

**Note:** we should possibly create a new docker image out of a Dockerfile, as to not download and install the required packages for each node.

```bash
# Seattle
for j in 1 2 3
do
    docker network connect uswest-useast-net roach-seattle-$j
    docker network connect uswest-euwest-net roach-seattle-$j
    docker exec roach-seattle-$j bash -c "apt-get update && apt-get install -y iproute2 iputils-ping dnsutils"
    docker exec roach-seattle-$j tc qdisc add dev eth1 root netem delay 30ms
    docker exec roach-seattle-$j tc qdisc add dev eth2 root netem delay 90ms
done

# New York
for j in 1 2 3
do
    docker network connect uswest-useast-net roach-newyork-$j
    docker network connect useast-euwest-net roach-newyork-$j
    docker exec roach-newyork-$j bash -c "apt-get update && apt-get install -y iproute2 iputils-ping dnsutils"
    docker exec roach-newyork-$j tc qdisc add dev eth1 root netem delay 32ms
    docker exec roach-newyork-$j tc qdisc add dev eth2 root netem delay 60ms
done

# London
for j in 1 2 3
do
    docker network connect useast-euwest-net roach-london-$j
    docker network connect uswest-euwest-net roach-london-$j
    docker exec roach-london-$j bash -c "apt-get update && apt-get install -y iproute2 iputils-ping dnsutils"
    docker exec roach-london-$j tc qdisc add dev eth1 root netem delay 62ms
    docker exec roach-london-$j tc qdisc add dev eth2 root netem delay 88ms
done
```

### Cluster configuration

Open a SQL shell

```bash
# ----------------------------
# ports mapping:
# 26257: haproxy-seattle
# 26258: haproxy-newyork
# 26259: haproxy-london
# ----------------------------

# use cockroach sql, defauls to localhost:26257
cockroach sql --insecure

# or use the --url param for another host:
cockroach sql --url "postgresql://localhost:26258/defaultdb?sslmode=disable"

# or a locally installed sql client, like psql
psql -h localhost -p 26257 -U root postgres
```

Run below SQL statements:

```sql
SET CLUSTER SETTING cluster.organization = "Cockroach Labs - Production Testing";
SET CLUSTER SETTING enterprise.license = "xxxx-yyyy-zzzz";

UPSERT into system.locations VALUES
        ('region', 'us-east4', 37.478397, -76.453077),
        ('region', 'us-west2', 43.804133, -120.554201),
        ('region', 'europe-west2', 51.5073509, -0.1277583);
```

At this point you should be able to open your browser at <http://localhost:8080> and view the CockroachDB Admin UI. Check the map and the latency table:

![crdb-map](/media/crdb-map.png)

![crdb-latency](/media/crdb-latency.png)

## Clean up

Stop and remove containers, delete the data volumes, delete the network bridges

```bash
for i in seattle newyork london
do
    for j in 1 2 3
    DO
        docker stop roach-$i-$j
        docker rm roach-$i-$j
        docker volume rm roach-$i-$j-data
    done
done
docker network rm us-east4-net us-west2-net europe-west2-net uswest-useast-net useast-euwest-net uswest-euwest-net
```
