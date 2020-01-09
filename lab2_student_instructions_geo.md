# Lab2 Geo Partitioning

In this lab we will experiment with Geo Partitioning to best 
understand how to observe and improve performance with Follower Reads and Local Indexes.


## Connecting to CRDB

* DBeaver
* ./cockroach sql --insecure
* psql 

## Connect Info Sheet

*Student, Database, pgurl, adminurl*


## Cluster Configuration
The lab cluster is configured in Google Clould using the following zones:

* us-west1-b
* us-east4-b
* europe-west2-a 


## Command Crib Sheet

https://github.com/glennfawcett/roachcrib



## Activities & Questions

--  Q1 
--
* Are follower reads enabled on your cluster?
* If not, how do you enable follower reads?

-- Q2
--
Connect the the `movr_follower` database.  Do this by using the `west`, `east`, and `europe` connections.

Run the following queries in all regions to measure the performance.

#### without follower reads
```
select locality, rides.* from rides, [show locality] where id = '2ce831ad-2135-4a00-8000-00000001569d' and city = 'boston';

select locality, rides.* from rides, [show locality] where id = '60b65237-0479-4c00-8000-00000002e1db' and city = 'seattle';

select locality, rides.* from rides, [show locality] where id = 'c71d6063-1726-4000-8000-00000005ef20' and city = 'paris';
```

#### with follower reads
```
select locality, rides.* from rides, [show locality] AS OF SYSTEM TIME experimental_follower_read_timestamp() where id = '2ce831ad-2135-4a00-8000-00000001569d'  and city = 'boston';

select locality, rides.* from rides, [show locality] AS OF SYSTEM TIME experimental_follower_read_timestamp() where id = '60b65237-0479-4c00-8000-00000002e1db' and city = 'seattle';

select locality, rides.* from rides, [show locality] AS OF SYSTEM TIME experimental_follower_read_timestamp() where id = 'c71d6063-1726-4000-8000-00000005ef20' and city = 'paris';
```

#### with `as of system time '-4h' `
```
select locality, rides.* from rides, [show locality] AS OF SYSTEM TIME INTERVAL '-4h' where id = '2ce831ad-2135-4a00-8000-00000001569d'  and city = 'boston';

select locality, rides.* from rides, [show locality] AS OF SYSTEM TIME INTERVAL '-4h' where id = '60b65237-0479-4c00-8000-00000002e1db' and city = 'seattle';

select locality, rides.* from rides, [show locality] AS OF SYSTEM TIME INTERVAL '-4h' where id = 'c71d6063-1726-4000-8000-00000005ef20' and city = 'paris';
```

#### with `as of system time '-10s' `
```
select locality, rides.* from rides, [show locality] AS OF SYSTEM TIME INTERVAL '-10s' where id = '2ce831ad-2135-4a00-8000-00000001569d'  and city = 'boston';

select locality, rides.* from rides, [show locality] AS OF SYSTEM TIME INTERVAL '-10s' where id = '60b65237-0479-4c00-8000-00000002e1db' and city = 'seattle';

select locality, rides.* from rides, [show locality] AS OF SYSTEM TIME INTERVAL '-10s' where id = 'c71d6063-1726-4000-8000-00000005ef20' and city = 'paris';
```

* Why does the `as of system time interval '-10s'` query not get good response time across all regions?

* How do you ensure queries to use follower reads with the lease amount of time difference?

-- Q3
--
Run the following query in all regions:

```
select vehicle_city, vehicle_id, count(*) from rides where city='paris' group by 1,2;
```

* How do you get this query to perform the same in all regions?

* Can you make the query perform the same in all regions without relying on follower reads?