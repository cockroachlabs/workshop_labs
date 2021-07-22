echo "get pgurls for the cluster nodes"
CLUSTER_IPS=$(roachprod pgurl ${USER}-labs)
echo "copy workload.sql"
roachprod put ${USER}-jump:1 no_q1_workload.sql
echo "run workload"
roachprod run ${USER}-jump:1 -- "./workload run querybench --query-file no_q1_workload.sql --db=defaultdb --concurrency=48 ${CLUSTER_IPS}"