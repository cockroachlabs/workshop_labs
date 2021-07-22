roachprod put ${USER}-labs:1 import_data.sql
roachprod run ${USER}-labs:1 -- "./cockroach sql --insecure -f import_data.sql"