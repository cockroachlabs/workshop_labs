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

<<<<<<< HEAD
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

=======
>>>>>>> ca6ca061470ddf0172abb6e6d06aba894bed6856
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

# New York
echo "Run docker containers in New York"
docker run -d --name=roach-newyork-1 --hostname=roach-newyork-1 --ip=172.28.1.11 --cap-add NET_ADMIN --net=us-east-1-net --add-host=roach-newyork-1:172.28.1.11 --add-host=roach-newyork-2:172.28.1.12 --add-host=roach-newyork-3:172.28.1.13 -p 8080:8080 -v "roach-newyork-1-data:/cockroach/cockroach-data" crdb start --insecure --join=roach-newyork-1,roach-newyork-2,roach-newyork-3 --locality=region=us-east-1,zone=a
docker run -d --name=roach-newyork-2 --hostname=roach-newyork-2 --ip=172.28.1.12 --cap-add NET_ADMIN --net=us-east-1-net --add-host=roach-newyork-1:172.28.1.11 --add-host=roach-newyork-2:172.28.1.12 --add-host=roach-newyork-3:172.28.1.13 -p 8081:8080 -v "roach-newyork-2-data:/cockroach/cockroach-data" crdb start --insecure --join=roach-newyork-1,roach-newyork-2,roach-newyork-3 --locality=region=us-east-1,zone=b
docker run -d --name=roach-newyork-3 --hostname=roach-newyork-3 --ip=172.28.1.13 --cap-add NET_ADMIN --net=us-east-1-net --add-host=roach-newyork-1:172.28.1.11 --add-host=roach-newyork-2:172.28.1.12 --add-host=roach-newyork-3:172.28.1.13 -p 8082:8080 -v "roach-newyork-3-data:/cockroach/cockroach-data" crdb start --insecure --join=roach-newyork-1,roach-newyork-2,roach-newyork-3 --locality=region=us-east-1,zone=c
# New York HAProxy
echo "Run HAProxy in New York"
docker run -d --name haproxy-newyork --ip=172.28.1.10 -p 26257:26257 --net=us-east-1-net -v `pwd`/data/us-east-1/:/usr/local/etc/haproxy:ro haproxy:1.7  

# Initialize the multi-regional cluster
echo "Initializing cluster"
docker exec -it roach-newyork-1 ./cockroach init --insecure
}

configureSQL(){
echo "configuring database"
cockroach sql --url "postgresql://localhost:26257/defaultdb?sslmode=disable" -e "UPSERT into system.locations VALUES ('region', 'us-east-1', 37.478397, -76.453077),('region', 'us-west-2', 43.804133, -120.554201),('region', 'eu-west-1', 53.142367, -7.692054);"
cockroach sql --url "postgresql://localhost:26257/defaultdb?sslmode=disable" -e "SET CLUSTER SETTING cluster.organization = \"${CRDB_ORG}\";"
cockroach sql --url "postgresql://localhost:26257/defaultdb?sslmode=disable" -e "SET CLUSTER SETTING enterprise.license = \"${CRDB_LIC}\";"
}

loadTestData(){
    docker exec -it roach-newyork-1 bash -c "./cockroach workload init movr --drop --db movr postgres://root@127.0.0.1:26257?sslmode=disable --num-histories 50000 --num-rides 50000 --num-users 1000 --num-vehicles 100"
}
startDocker
sleep 10
configureSQL
loadTestData
