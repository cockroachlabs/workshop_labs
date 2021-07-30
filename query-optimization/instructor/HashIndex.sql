SET experimental_enable_hash_sharded_indexes=on;

CREATE TABLE mytable(
   id uuid default gen_random_uuid(),
   ts TIMESTAMP default now(),
   name string,
   PRIMARY KEY (ts, id),
   INDEX idx_ts (ts ASC)
);

CREATE TABLE mytable_hashidx(
   id uuid default gen_random_uuid(),
   ts TIMESTAMP default now(),
   name string,
   PRIMARY KEY (ts, id) USING HASH WITH BUCKET_COUNT = 3,
   INDEX idx_tshash (ts ASC) USING HASH WITH BUCKET_COUNT = 3
);

insert into mytable (name) select 'name'||generate_series(1, 1000000)::string;
insert into mytable_hashidx (name) select 'name'||generate_series(1, 1000000)::string;

analyze mytable;
analyze mytable_hashidx;

explain select count (*) from mytable_hashidx where ts > '2021-06-01 00:00:00+00:00';
explain select ts from mytable_hashidx where ts > '2021-06-30 00:21:00+00:00' limit 100;

-- use tpcc order_line table
use tpcc;
CREATE INDEX ON order_line (ol_delivery_d ASC) USING HASH WITH BUCKET_COUNT = 3;
explain select count (*) from order_line where ol_delivery_d > '2006-01-02 00:00:00+00:00';
explain select ol_w_id, ol_d_id, ol_number from order_line where ol_delivery_d > '2006-01-02 00:00:00+00:00' limit 100;
