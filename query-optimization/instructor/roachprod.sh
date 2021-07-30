############################
# Standard Roachprod Demos
############################

export CLUSTER="${USER:0:6}-test"
export NODES=3
export CNODES=$(($NODES-1))
export VERSION=v21.1.6

### Create
roachprod create ${CLUSTER} -n ${NODES}
roachprod stage ${CLUSTER} workload
roachprod stage ${CLUSTER} release ${VERSION}
roachprod start ${CLUSTER}

roachprod admin ${CLUSTER}:1 --open --ips
roachprod run ${CLUSTER}:1 -- "./cockroach workload fixtures import tpcc --warehouses=400 --db=tpcc"
roachprod put ${CLUSTER}:1 schema.sql .
#roachprod run ${CLUSTER}:1 -- "./cockroach sql --insecure -f schema.sql"
roachprod run ${CLUSTER}:1 -- "./cockroach sql --insecure -e 'select 1;'"

roachprod sql ${CLUSTER}:1