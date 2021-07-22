# default machine type is n1-standard-4 (4 vCPUs / 16GB MEM)
roachprod create ${USER}-labs -c gce -n 3
roachprod stage ${USER}-labs release latest
roachprod start ${USER}-labs
roachprod run ${USER}-labs:1 -- "./cockroach sql --insecure -e \"SET CLUSTER SETTING enterprise.license ='${CRDB_LIC}';\""

# generate test data
roachprod run ${USER}-labs:1 -- "sudo apt-get update && sudo apt-get install python3-pip -y"
roachprod run ${USER}-labs:1 -- "pip3 install --user --upgrade pip carota"
roachprod run ${USER}-labs:1 -- "pip install psycopg2-binary"
roachprod run ${USER}-labs:1 -- "echo export PATH=/home/ubuntu/.local/bin:\\\$PATH >> ~/.bashrc"
echo "generating 7.5 million rows..."
roachprod run ${USER}-labs:1 -- "/home/ubuntu/.local/bin/carota -r 7500000 -t 'int::start=1,end=28,seed=0; uuid::seed=0; choices::list=O R,weights=9 1,seed=0; int::start=1,end=3572420,seed=0; date::start=2020-12-15,delta=7,seed=0; choices::list=A R,weights=99 1,seed=0; date::start=2020-10-10,delta=180,seed=0' -o c.csv"
roachprod run ${USER}-labs:1 -- "sudo mkdir -p /mnt/data1/cockroach/extern/"
roachprod run ${USER}-labs:1 -- "sudo mv c.csv /mnt/data1/cockroach/extern/"