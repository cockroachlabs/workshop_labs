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
Connect the the `movr_follower` database in three separate sessions. Connect to the `west`, `east`, and `europe` connections.

Run the following queries in all regions to measure the performance.

#### without follower reads
```
SELECT locality, rides.* 
FROM rides, [show locality]  
WHERE id = '2ce831ad-2135-4a00-8000-00000001569d'  
AND city = 'boston';

SELECT locality, rides.* 
FROM rides, [show locality]  
WHERE id = '60b65237-0479-4c00-8000-00000002e1db' 
AND city = 'seattle';

SELECT locality, rides.* 
FROM rides, [show locality]  
WHERE id = 'c71d6063-1726-4000-8000-00000005ef20' 
AND city = 'paris';
```

#### with follower reads
```
SELECT locality, rides.* 
FROM rides, [show locality] AS OF SYSTEM TIME experimental_follower_read_timestamp() 
WHERE id = '2ce831ad-2135-4a00-8000-00000001569d'  
AND city = 'boston';

SELECT locality, rides.* 
FROM rides, [show locality] AS OF SYSTEM TIME experimental_follower_read_timestamp() 
WHERE id = '60b65237-0479-4c00-8000-00000002e1db' 
AND city = 'seattle';

SELECT locality, rides.* 
FROM rides, [show locality] AS OF SYSTEM TIME experimental_follower_read_timestamp() 
WHERE id = 'c71d6063-1726-4000-8000-00000005ef20' 
AND city = 'paris';
```

#### with `as of system time '-4h' `
```
SELECT locality, rides.* 
FROM rides, [show locality] AS OF SYSTEM TIME INTERVAL '-4h' 
WHERE id = '2ce831ad-2135-4a00-8000-00000001569d'  
AND city = 'boston';

SELECT locality, rides.* 
FROM rides, [show locality] AS OF SYSTEM TIME INTERVAL '-4h' 
WHERE id = '60b65237-0479-4c00-8000-00000002e1db' 
AND city = 'seattle';

SELECT locality, rides.* 
FROM rides, [show locality] AS OF SYSTEM TIME INTERVAL '-4h' 
WHERE id = 'c71d6063-1726-4000-8000-00000005ef20' 
AND city = 'paris';
```

#### with `as of system time '-10s' `
```
SELECT locality, rides.* 
FROM rides, [show locality] AS OF SYSTEM TIME INTERVAL '-10s' 
WHERE id = '2ce831ad-2135-4a00-8000-00000001569d'  
AND city = 'boston';

SELECT locality, rides.* 
FROM rides, [show locality] AS OF SYSTEM TIME INTERVAL '-10s' 
WHERE id = '60b65237-0479-4c00-8000-00000002e1db' 
AND city = 'seattle';

SELECT locality, rides.* 
FORM rides, [show locality] AS OF SYSTEM TIME INTERVAL '-10s' 
WHERE id = 'c71d6063-1726-4000-8000-00000005ef20' 
AND city = 'paris';
```

* Why does the `as of system time interval '-10s'` query not get good response time across all regions?

* How do you ensure queries to use follower reads with the lease amount of time difference?

-- Q3
--
Run the following query in all regions:

```
SELECT vehicle_city, vehicle_id, count(*) 
FROM rides 
WHERE city='paris' GROUP BY 1,2;
```

* How do you get this query to perform the same in all regions?

