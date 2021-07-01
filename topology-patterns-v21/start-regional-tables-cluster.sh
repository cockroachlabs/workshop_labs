#!/bin/sh
# Create docker containers for CockroachDB topology workshop

startDocker(){
# Check to see if docker is running
DOCKER_VER=`pgrep -x docker`
if [ -z "${DOCKER_VER}" ]
then
      echo "Docker process not found. Exit script."
      exit 0
else
      echo "Running docker process found. Building docker image with tage named crdb."
fi

# Check to see if CRDB_LIC is set as an env var
if [[ -z "${CRDB_LIC}" ]]; then
  echo "Environment variable - CRDB_LIC - is not set. Please configure the var and re-run the script."
  exit 0
else
  echo "CRDB_LIC env var is set. Proceeding."
fi

# Check to see if CRDB_ORG is set as an env var
if [[ -z "${CRDB_ORG}" ]]; then
  echo "Environment variable - CRDB_ORG - is not set. Please configure the var and re-run the script."
  exit 0
else
  echo "CRDB_ORG env var is set. Proceeding."
fi

# Build the image with tag name 'crdb'
BUILD_IMAGE=`docker build -t crdb .`
echo $BUILD_IMAGE

# region networks
echo "Create region networks in docker"
docker network create --driver=bridge --subnet=172.27.1.0/16 --ip-range=172.27.1.0/24 --gateway=172.27.1.1 us-west-2-net
docker network create --driver=bridge --subnet=172.28.1.0/16 --ip-range=172.28.1.0/24 --gateway=172.28.1.1 us-east-1-net
docker network create --driver=bridge --subnet=172.29.1.0/16 --ip-range=172.29.1.0/24 --gateway=172.29.1.1 eu-west-1-net

# inter-regional networks
echo "Create inter-regional networks in docker"
docker network create --driver=bridge --subnet=172.30.1.0/16 --ip-range=172.30.1.0/24 --gateway=172.30.1.1 uswest-useast-net
docker network create --driver=bridge --subnet=172.31.1.0/16 --ip-range=172.31.1.0/24 --gateway=172.31.1.1 useast-euwest-net
docker network create --driver=bridge --subnet=172.32.1.0/16 --ip-range=172.32.1.0/24 --gateway=172.32.1.1 uswest-euwest-net

# Seattle
echo "Run docker containers in Seattle"
docker run -d --name=roach-seattle-1 --hostname=roach-seattle-1 --ip=172.27.1.11 --cap-add NET_ADMIN --net=us-west-2-net --add-host=roach-seattle-1:172.27.1.11 --add-host=roach-seattle-2:172.27.1.12 --add-host=roach-seattle-3:172.27.1.13 -p 8080:8080 -v "roach-seattle-1-data:/cockroach/cockroach-data" crdb start --insecure --join=roach-seattle-1,roach-newyork-1,roach-london-1 --locality=region=us-west-2,zone=a
docker run -d --name=roach-seattle-2 --hostname=roach-seattle-2 --ip=172.27.1.12 --cap-add NET_ADMIN --net=us-west-2-net --add-host=roach-seattle-1:172.27.1.11 --add-host=roach-seattle-2:172.27.1.12 --add-host=roach-seattle-3:172.27.1.13 -p 8081:8080 -v "roach-seattle-2-data:/cockroach/cockroach-data" crdb start --insecure --join=roach-seattle-1,roach-newyork-1,roach-london-1 --locality=region=us-west-2,zone=b
docker run -d --name=roach-seattle-3 --hostname=roach-seattle-3 --ip=172.27.1.13 --cap-add NET_ADMIN --net=us-west-2-net --add-host=roach-seattle-1:172.27.1.11 --add-host=roach-seattle-2:172.27.1.12 --add-host=roach-seattle-3:172.27.1.13 -p 8082:8080 -v "roach-seattle-3-data:/cockroach/cockroach-data" crdb start --insecure --join=roach-seattle-1,roach-newyork-1,roach-london-1 --locality=region=us-west-2,zone=c
# Seattle HAProxy
echo "Run HAProxy in Seattle"
docker run -d --name haproxy-seattle --ip=172.27.1.10 -p 26257:26257 --net=us-west-2-net -v `pwd`/data/us-west-2/:/usr/local/etc/haproxy:ro haproxy:1.7  

# New York
echo "Run docker containers in New York"
docker run -d --name=roach-newyork-1 --hostname=roach-newyork-1 --ip=172.28.1.11 --cap-add NET_ADMIN --net=us-east-1-net --add-host=roach-newyork-1:172.28.1.11 --add-host=roach-newyork-2:172.28.1.12 --add-host=roach-newyork-3:172.28.1.13 -p 8180:8080 -v "roach-newyork-1-data:/cockroach/cockroach-data" crdb start --insecure --join=roach-seattle-1,roach-newyork-1,roach-london-1 --locality=region=us-east-1,zone=a
docker run -d --name=roach-newyork-2 --hostname=roach-newyork-2 --ip=172.28.1.12 --cap-add NET_ADMIN --net=us-east-1-net --add-host=roach-newyork-1:172.28.1.11 --add-host=roach-newyork-2:172.28.1.12 --add-host=roach-newyork-3:172.28.1.13 -p 8181:8080 -v "roach-newyork-2-data:/cockroach/cockroach-data" crdb start --insecure --join=roach-seattle-1,roach-newyork-1,roach-london-1 --locality=region=us-east-1,zone=b
docker run -d --name=roach-newyork-3 --hostname=roach-newyork-3 --ip=172.28.1.13 --cap-add NET_ADMIN --net=us-east-1-net --add-host=roach-newyork-1:172.28.1.11 --add-host=roach-newyork-2:172.28.1.12 --add-host=roach-newyork-3:172.28.1.13 -p 8182:8080 -v "roach-newyork-3-data:/cockroach/cockroach-data" crdb start --insecure --join=roach-seattle-1,roach-newyork-1,roach-london-1 --locality=region=us-east-1,zone=c
# New York HAProxy
echo "Run HAProxy in New York"
docker run -d --name haproxy-newyork --ip=172.28.1.10 -p 26258:26257 --net=us-east-1-net -v `pwd`/data/us-east-1/:/usr/local/etc/haproxy:ro haproxy:1.7  

# London
echo "Run docker containers in London"
docker run -d --name=roach-london-1 --hostname=roach-london-1 --ip=172.29.1.11 --cap-add NET_ADMIN --net=eu-west-1-net --add-host=roach-london-1:172.29.1.11 --add-host=roach-london-2:172.29.1.12 --add-host=roach-london-3:172.29.1.13 -p 8280:8080 -v "roach-london-1-data:/cockroach/cockroach-data" crdb start --insecure --join=roach-seattle-1,roach-newyork-1,roach-london-1 --locality=region=eu-west-1,zone=a
docker run -d --name=roach-london-2 --hostname=roach-london-2 --ip=172.29.1.12 --cap-add NET_ADMIN --net=eu-west-1-net --add-host=roach-london-1:172.29.1.11 --add-host=roach-london-2:172.29.1.12 --add-host=roach-london-3:172.29.1.13 -p 8281:8080 -v "roach-london-2-data:/cockroach/cockroach-data" crdb start --insecure --join=roach-seattle-1,roach-newyork-1,roach-london-1 --locality=region=eu-west-1,zone=b
docker run -d --name=roach-london-3 --hostname=roach-london-3 --ip=172.29.1.13 --cap-add NET_ADMIN --net=eu-west-1-net --add-host=roach-london-1:172.29.1.11 --add-host=roach-london-2:172.29.1.12 --add-host=roach-london-3:172.29.1.13 -p 8282:8080 -v "roach-london-3-data:/cockroach/cockroach-data" crdb start --insecure --join=roach-seattle-1,roach-newyork-1,roach-london-1 --locality=region=eu-west-1,zone=c
# London HAProxy
echo "Run docker HAProxy in London"
docker run -d --name haproxy-london --ip=172.29.1.10 -p 26259:26257 --net=eu-west-1-net -v `pwd`/data/eu-west-1/:/usr/local/etc/haproxy:ro haproxy:1.7  

# Initialize the multi-regional cluster
echo "Initializing cluster"
docker exec -it roach-newyork-1 ./cockroach init --insecure

echo "Add network delays between each region"
# Seattle
for j in 1 2 3
do
    docker network connect uswest-useast-net roach-seattle-$j
    docker network connect uswest-euwest-net roach-seattle-$j
    docker exec roach-seattle-$j tc qdisc add dev eth1 root netem delay 30ms
    docker exec roach-seattle-$j tc qdisc add dev eth2 root netem delay 90ms
done

# New York
for j in 1 2 3
do
    docker network connect uswest-useast-net roach-newyork-$j
    docker network connect useast-euwest-net roach-newyork-$j
    docker exec roach-newyork-$j tc qdisc add dev eth1 root netem delay 32ms
    docker exec roach-newyork-$j tc qdisc add dev eth2 root netem delay 60ms
done

# London
for j in 1 2 3
do
    docker network connect useast-euwest-net roach-london-$j
    docker network connect uswest-euwest-net roach-london-$j
    docker exec roach-london-$j tc qdisc add dev eth1 root netem delay 62ms
    docker exec roach-london-$j tc qdisc add dev eth2 root netem delay 88ms
done
}

configureSQL(){
echo "configuring database"
#cockroach sql --insecure -e "UPSERT into system.locations VALUES ('region', 'us-east-1', 37.478397, -76.453077),('region', 'us-west-2', 43.804133, -120.554201),('region', 'eu-west-1', 53.142367, -7.692054);"
cockroach sql --insecure -e "SET CLUSTER SETTING cluster.organization = \"${CRDB_ORG}\";"
cockroach sql --insecure -e "SET CLUSTER SETTING enterprise.license = \"${CRDB_LIC}\";"
}

loadTestData(){
    docker exec -it roach-newyork-1 bash -c "./cockroach workload init movr --drop --db movr postgres://root@127.0.0.1:26257?sslmode=disable --num-histories 50000 --num-rides 50000 --num-users 1000 --num-vehicles 100"
}

startDocker
sleep 10
configureSQL
loadTestData