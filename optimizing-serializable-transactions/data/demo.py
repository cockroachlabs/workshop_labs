import psycopg
import random
import logging


class Demo:

    def __init__(self, args: dict):
        # args is a dict of string passed with the --args flag
        # user passed a yaml/json, in python that's a dict object

        self.demo: int = int(args.get('demo', 1))
        self.limit: int = int(args.get('limit', 100))

        # self.schema holds the DDL
        self.schema: str = ""

        # self.load holds the data generation YAML
        # definition to populate the tables
        self.load: str = ""

    # the 'init' method is executed once, when the --init flag is passed

    def init(self, conn: psycopg.Connection):
        with conn.cursor() as cur:
            logging.info(cur.execute('select version();').fetchone())

    # the run method returns a list of transactions to be executed continuosly,
    # sequentially, as in a cycle.
    def run(self):
        if self.demo == 1:
            return [self.select_high, self.select_low, self.select_normal, self.select_follower_read, self.select_normal_different_id, self.update_low]
        elif self.demo == 2:
            return [self.select_high, self.select_low, self.select_normal, self.select_follower_read, self.select_normal_different_id, self.update_high]
        elif self.demo == 3:
            return [self.select_normal, self.bulk_inserts]
        else:
            return [self.update_sfu]

    # conn is an instance of a psycopg connection object
    # conn is set with autocommit=True, so no need to send a commit message
    def select_high(self, conn: psycopg.Connection):
        with conn.transaction() as tx:
            with conn.cursor() as cur:
                cur.execute("SET TRANSACTION PRIORITY HIGH")
                cur.execute("SELECT * FROM alerts WHERE customer_id=9743")

    def select_low(self, conn: psycopg.Connection):
        with conn.transaction() as tx:
            with conn.cursor() as cur:
                cur.execute("SET TRANSACTION PRIORITY LOW")
                cur.execute("SELECT * FROM alerts WHERE customer_id=9743")

    def select_normal(self, conn: psycopg.Connection):
        with conn.transaction() as tx:
            with conn.cursor() as cur:
                cur.execute("SELECT * FROM alerts WHERE customer_id=9743")

    def select_follower_read(self, conn: psycopg.Connection):
        with conn.cursor() as cur:
            cur.execute(
                "SELECT * FROM alerts AS OF SYSTEM TIME follower_read_timestamp() WHERE customer_id=9743")

    def select_normal_different_id(self, conn: psycopg.Connection):
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM alerts WHERE customer_id=9800")

    def update_low(self, conn: psycopg.Connection):
        with conn.transaction() as tx:
            with conn.cursor() as cur:
                cur.execute("SET TRANSACTION PRIORITY LOW")
                cur.execute(
                    "UPDATE alerts SET cstatus = cstatus, updated_at = NOW() WHERE customer_id = 9743")

    def update_high(self, conn: psycopg.Connection):
        with conn.transaction() as tx:
            with conn.cursor() as cur:
                cur.execute("SET TRANSACTION PRIORITY HIGH")
                cur.execute(
                    "UPDATE alerts SET cstatus = cstatus, updated_at = NOW() WHERE customer_id = 9743")

    def bulk_inserts(self, conn: psycopg.Connection):
        with conn.transaction() as tx:
            with conn.cursor() as cur:
                cur.execute("SET TRANSACTION PRIORITY HIGH")
                cur.execute("""
                    UPDATE alerts 
                    SET 
                        cstatus = cstatus, 
                        updated_at = NOW() 
                    WHERE 
                        severity = %s 
                    LIMIT %s
                    """,
                            (random.randint(0, 10), self.limit)
                            )

    def update_sfu(self, conn: psycopg.Connection):
        with conn.cursor() as cur:
            cur.execute(
                "UPDATE alerts SET cstatus = cstatus, updated_at = now() WHERE customer_id=9743")
