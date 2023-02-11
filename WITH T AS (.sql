WITH T AS (
    select c.relname as object_name,
        ns.nspname AS "schema_name",
        c.oid as object_id,
        a.attname as "column_name",
        a.attnum as column_number,
        format_type(a.atttypid, a.atttypmod) AS data_type,
        a.atttypmod as max_length,
        NULL as "precision",
        NULL as "scale",
        a.attnotnull,
        a.atthasdef,
        a.attidentity,
        col_description (c.oid, a.attnum) AS column_comment
    FROM pg_class AS c
        JOIN pg_namespace as ns ON (c.relnamespace = ns.oid)
        JOIN pg_attribute as a ON (c.oid = a.attrelid)
    WHERE ns.nspname NOT IN (''pg_toast'', ''pg_catalog'', ''information_schema'')
)
SELECT json_agg(T)::text FROM T;

--
WITH C(connection_string) AS (
    select template_render(
            template.odbc_template,
            json_object(
                'server',
                server,
                'port',
                port,
                'database',
                database,
                'username',
                username,
                'password',
                password
            ),
            json_object('expression', json_array('<<', '>>'))
        )
    FROM rule4_dataserver as ds
        JOIN odbc_template as template ON (
            ds.dialect = template.dialect
            and template.name = 'connection'
        )
    WHERE ds.dialect = 'postgres'
)
SELECT connection_string,
    OPENROWSET_JSON(
        C.connection_string,
        "SELECT boot_val,reset_val FROM pg_settings"
    )
FROM C;

/*


*/

WITH C(connection_string) AS (
    select template_render(
            template.odbc_template,
            json_object(
                'server',
                server,
                'port',
                port,
                'database',
                database,
                'username',
                username,
                'password',
                password
            ),
            json_object('expression', json_array('<<', '>>'))
        )
    FROM rule4_dataserver as ds
        JOIN odbc_template as template ON (
            ds.dialect = template.dialect
            and template.name = 'connection'
        )
    WHERE ds.dialect = 'postgres'
)
SELECT JE.value
FROM C,
    json_each(
        openrowset_clob(
            C.connection_string,
            'WITH T AS (SELECT * FROM food_des) SELECT json_agg(T)::text FROM T;'
        )
    ) as JE;

CREATE VIEW rule4_dataserver_connection_string(dataserver_name, connection_string) 
AS

create virtual table [rule4_dataserver_connection_string] 
using define((
        WITH T(dataserver_name, database_name) AS (
            SELECT E.value->>'$.dataserver_name' as dataserver_name,
                   E.value->>'$.database_name'   as database_name
              FROM JSON_EACH(:j) AS E
            )
        select ds.dataserver_name,
            template_render(
            template.odbc_template,
            json_object(
                'server',
                server,
                'port',
                port,
                'database', T.database_name,
                'username',
                cred.username,
                'password',
                cred.password
            ),
            json_object('expression', json_array('<<', '>>'))
        ) as connection_string
    FROM T
    JOIN rule4_dataserver as ds
       ON (T.dataserver_name = ds.dataserver_name)
        JOIN odbc_template as template ON (
            ds.dialect = template.dialect
            and template.name = 'connection_tvp'
        )
    LEFT OUTER JOIN rule4_credential as cred
    ON (ds.dataserver_name = cred.dataserver_name)
));

CREATE TABLE rule4_dataserver (dataserver_name varchar PRIMARY KEY,
                             dialect varchar not null,
                             server varchar not null,
                             port varchar null
                            );
CREATE TABLE rule4_credential(
                              dataserver_name VARCHAR REFERENCES rule4_dataserver(dataserver_name),
                              username varchar NOT NULL,
                              password varchar null,
                              PRIMARY KEY(dataserver_name, [username])
                              );


INSERT INTO rule4_dataserver VALUES('TGRID_MSSQL', 'mssql','.\TGRID4ALL',NULL);
INSERT INTO rule4_dataserver VALUES('PG_mac', 'postgres','Pauls-Mac-mini.local','5432');

INSERT INTO rule4_credential(dataserver_name, username, password)
VALUES ('PG_mac', 'tgrid', 'tgrid');