# Migrate from PostGres to CRDB

## Simple Migration via pgdump
The postgres `pgdump` utility dumps data and DDL from PostGres into a SQL file.  This can be done at the database level and is an easy way to migrate a small database.  CockroachDB is able to use the `IMPORT` command to read pgdump file and import the database into CRDB.  The CockroachDB [migration documentation](https://www.cockroachlabs.com/docs/stable/migrate-from-postgres.html) describes the process.

Connect to your `tpcc` database.
* Student#1 : tpcc1
* Student#2 : tpcc2
...
* Student#21 : tpcc21

Change you database context and run the IMPORT like so:

```

USE tpcc42;

IMPORT PGDUMP 'gs://pg2crdb/testpg_pgdump.sql.gz';
```

After the import is complete, verify the tables that were added.

```
show tables;
  table_name
+------------+
  mytab1
(1 row)


show create table mytab1;
  table_name |              create_statement
+------------+--------------------------------------------+
  mytab1     | CREATE TABLE mytab1 (
             |     s INT8 NULL,
             |     md5 STRING NULL,
             |     code STRING NULL,
             |     FAMILY "primary" (s, md5, code, rowid)
             | )
(1 row)


select code, count(*) from mytab1 group by 1;
  code | count
+------+-------+
  aaa  |     5
  bbb  |   995
(2 rows)

```


