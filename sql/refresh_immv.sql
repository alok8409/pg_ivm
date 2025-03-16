-- Create the pgivm schema
CREATE SCHEMA pgivm;

-- Create pg_ivm_immv table inside pgivm schema
CREATE TABLE pgivm.pg_ivm_immv (
  immvrelid regclass NOT NULL,
  viewdef text NOT NULL,
  CONSTRAINT pg_ivm_immv_pkey PRIMARY KEY (immvrelid)
);

-- Grant permissions on pgivm schema to public (optional, adjust as needed)
GRANT ALL ON SCHEMA pgivm TO public;

-- Create the function to create a materialized view (IMMV)
CREATE FUNCTION pgivm.create_immv(text, text)
RETURNS bigint
STRICT
AS 'MODULE_PATHNAME', 'create_immv'
LANGUAGE C;

-- Create trigger functions for IMMV management
CREATE FUNCTION pgivm."IVM_immediate_before"()
RETURNS trigger
AS 'MODULE_PATHNAME', 'IVM_immediate_before'
LANGUAGE C;

CREATE FUNCTION pgivm."IVM_immediate_maintenance"()
RETURNS trigger
AS 'MODULE_PATHNAME', 'IVM_immediate_maintenance'
LANGUAGE C;

CREATE FUNCTION pgivm."IVM_prevent_immv_change"()
RETURNS trigger
AS 'MODULE_PATHNAME', 'IVM_prevent_immv_change'
LANGUAGE C;

-- DDL trigger to remove entries from pg_ivm_immv upon DROP
CREATE FUNCTION pg_catalog.pg_ivm_sql_drop_trigger_func()
RETURNS event_trigger AS $$
DECLARE
    pg_class_oid OID;
    relids REGCLASS[];
BEGIN
    pg_class_oid = 'pg_catalog.pg_class'::regclass;
    -- Find relids to remove
    DELETE FROM pgivm.pg_ivm_immv
    USING pg_catalog.pg_event_trigger_dropped_objects() AS events
    WHERE immvrelid = events.objid AND
          events.classid = pg_class_oid AND events.objsubid = 0;
END
$$ LANGUAGE plpgsql;

CREATE EVENT TRIGGER pgivm.pg_ivm_sql_drop_trigger
ON sql_drop
EXECUTE PROCEDURE pgivm.pg_ivm_sql_drop_trigger_func();

-- Create a table t to use for materialized views (IMMV)
CREATE TABLE t (i int PRIMARY KEY);
INSERT INTO t SELECT generate_series(1, 5);

-- Create the materialized view mv
SELECT pgivm.create_immv('mv', 'SELECT * FROM t');
SELECT immvrelid, ispopulated FROM pgivm.pg_ivm_immv ORDER BY 1;

-- Refresh IMMV with data
SELECT pgivm.refresh_immv('mv', true);
SELECT immvrelid, ispopulated FROM pgivm.pg_ivm_immv ORDER BY 1;

-- Insert new data into table t
INSERT INTO t VALUES(6);
SELECT i FROM mv ORDER BY 1;

-- Make IMMV unpopulated
SELECT pgivm.refresh_immv('mv', false);
SELECT immvrelid, ispopulated FROM pgivm.pg_ivm_immv ORDER BY 1;
SELECT i FROM mv ORDER BY 1;

-- Immediate maintenance is disabled. IMMV can be scannable and is empty.
INSERT INTO t VALUES(7);
SELECT i FROM mv ORDER BY 1;

-- Refresh the IMMV and make it populated
SELECT pgivm.refresh_immv('mv', true);
SELECT immvrelid, ispopulated FROM pgivm.pg_ivm_immv ORDER BY 1;
SELECT i FROM mv ORDER BY 1;

-- Immediate maintenance is enabled.
INSERT INTO t VALUES(8);
SELECT i FROM mv ORDER BY 1;

-- Use qualified name to refresh IMMV
SELECT pgivm.refresh_immv('public.mv', true);

-- Use non-existing IMMV to test error
SELECT pgivm.refresh_immv('mv_not_existing', true);

-- Try to refresh a normal table (error)
SELECT pgivm.refresh_immv('t', true);
