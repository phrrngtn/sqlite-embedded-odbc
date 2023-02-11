
DROP TABLE IF EXISTS [rule4_dataserver_connection_string];

CREATE VIRTUAL TABLE [rule4_dataserver_connection_string]
using define((
        WITH T(dataserver_name, database_name) AS (
            SELECT E.value->>'$.dataserver_name' as dataserver_name,
                   E.value->>'$.database_name'   as database_name
              FROM JSON_EACH(:j) AS E
            )
        select T.dataserver_name,
            T.database_name,
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