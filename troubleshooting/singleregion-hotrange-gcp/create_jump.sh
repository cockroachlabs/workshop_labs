echo "get the pgurl of one of the cluster nodes"
NODE_IP=$(roachprod pgurl ${USER}-labs:1)
echo "simple ubuntu box on a starndard 4cpu/16 mem VM"
roachprod create ${USER}-jump -c gce -n 1
echo "install cockroachdb just to have the sql client"
roachprod stage ${USER}-jump release latest
echo "install workload"
roachprod stage ${USER}-jump workload
echo "Test connection to CockroachDB cluster"
roachprod run ${USER}-labs:1 -- "./cockroach sql -e \"SHOW TABLES;\" --url '${NODE_IP}'"