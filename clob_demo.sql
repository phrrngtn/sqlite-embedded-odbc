WITH T(clob_of_json) AS (
    select openrowset_clob(
            'Driver={SQL Server};Server={.\TGRID4ALL};Database={tgrid4all};Trusted_Connection=yes',
            'WITH J(clob_of_json) AS (
             SELECT --TOP 1000
                object_name(object_id)        AS [object_name],
                object_schema_name(object_id) AS schema_name,
                name                          AS column_name,
                column_id,
                type_name(system_type_id)     AS system_type_name,
                max_length,
                precision,
                scale,
                is_nullable,
                is_rowguidcol,
                is_identity,
                is_computed
                FROM sys.columns
            FOR JSON PATH
            )
            SELECT clob_of_json
            FROM J'
        ) as clob_of_json
),
J AS (
    SELECT JE.value
    FROM T,
        JSON_EACH(T.clob_of_json) as JE
),
RS AS (
    SELECT value ->> '$.object_name' as [object_name],
           value ->> '$.schema_name' as [schema_name],
           value->>'$.column_name' as column_name,
           value->'$.column_id' as database_id,
           value->'$.system_type_name' as system_type_name
    FROM J
)
SELECT count(*) 
FROM RS;




-- internal system tables and views. May be useful for 
-- decoding contents of the tables or generating lowest common denominator 
-- VIEWs.

WITH T(clob_json) AS (
	select o.name as [object_name],
	o.type,
	o.type_desc,
	c.* 
	FROM sys.all_objects as o 
	JOIN sys.all_columns as c
	ON (o.object_id = c.object_id)
	where o.[type] in ('S', 'V')
	FOR JSON PATH
)
SELECT clob_json as sql_server_system_tables_metadata FROM T;


-- want to get all of the tables and table-like objects for the following uses:
-- 1) full text index of names
-- 2) comparison between two databases. rudimentary: tables and columns only. No indexes or constraints
-- 3) track changes over time.

WITH T(clob_json) AS (
SELECT  [name]						AS [object_name],
		object_id					AS [object_id],
        schema_name([schema_id])	AS [schema_name],
		[type],
		[type_desc],
		create_date, -- use for incremental scraping. NB: will not work correct with database restores
		modify_date  -- incremental scraping
FROM sys.objects     -- we don't want system objects cluttering the results.
WHERE [type] NOT IN ('S', 'IT') -- we don't need system or internal objects
FOR JSON PATH
)
SELECT clob_json as sql_server_table_metadata
FROM T;


WITH T(clob_json) AS (
SELECT 
                object_name(c.[object_id])        AS [object_name],
                object_schema_name(c.[object_id]) AS schema_name,
                c.[object_id]                     AS [object_id],
                c.[name]                          AS column_name,
                column_id                         AS column_number,
                type_name(system_type_id)         AS data_type,
                max_length,
                precision,
                scale,
                is_nullable,
                is_rowguidcol,
                is_identity,
                is_computed
                FROM sys.columns as c
				JOIN sys.objects as o
				ON (c.object_id = o.object_id)
				WHERE o.[type] NOT IN (''S'', ''IT'')
FOR JSON PATH
)
SELECT clob_json as sql_server_column_metadata
FROM T;

/*

incremental scrape of 

1) list of databases
2) list of tables
3) list of columns

use each scrape to close out end of validity intervals of stuff that has been deleted since last sample.
use the hierarchy: database -> table -> column




*/


WITH T(clob_json) AS (
SELECT  [name]						AS [object_name],
		object_id					AS [object_id],
        schema_name([schema_id])	AS [schema_name],
		[type],
		[type_desc],
		create_date, -- use for incremental scraping. NB: will not work correct with database restores
		modify_date  -- incremental scraping
FROM sys.objects     -- do not want system objects cluttering the results.
WHERE [type] NOT IN (''S'', ''IT'') --  no system or internal objects
FOR JSON PATH
)
SELECT clob_json as sql_server_table_metadata
FROM T;


WITH Q AS (
        select t.name,
               t.odbc_template,
               conn.dataserver_name,
               ds.*,
               conn.*
        FROM rule4_dataserver_connection_string(
            (select json_group_array(json_object('dataserver_name', dataserver_name,
                                                  'database_name', database_name
                                                )
                                    ) 
             FROM rule4_database_of_interest
            )
        ) as conn
        JOIN rule4_dataserver as ds
           ON (conn.dataserver_name = ds.dataserver_name)
        JOIN odbc_template as t
         ON (ds.dialect = t.dialect
             and t.name IN ( 'list_columns', 'list_tables')
            )
        )
        SELECT dataserver_name,
               name,
               LENGTH(openrowset_clob(connection_string, odbc_template))
        FROM Q
        where dataserver_name <> 'PG_MAC';;

WITH Q AS (select t.name, t.odbc_template, c.dataserver_name, ds.*, c.* FROM rule4_dataserver_connection_string((select json_group_array(json_object('dataserver_name', dataserver_name, 'database_name', database_name)) FROM rule4_database_of_interest)) as c JOIN rule4_dataserver as ds ON (c.dataserver_name = ds.dataserver_name) JOIN odbc_template as t ON (ds.dialect = t.dialect) and t.name IN ( 'list_columns', 'list_tables')) SELECT dataserver_name, name, LENGTH(openrowset_clob(connection_string, odbc_template)) FROM Q;