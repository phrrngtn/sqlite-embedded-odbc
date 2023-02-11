select openrowset_clob(
        'Driver={ODBC Driver 17 for SQL Server};Server=.\TGRID4ALL;Database=ReportServer;Trusted_Connection=yes',
        'WITH JSON_P AS (SELECT fruit FROM OPENJSON(cast(? as varchar(max))) WITH (fruit varchar(max)) AS JP), J(json_clob) AS (SELECT * FROM sys.databases as d1 JOIN JSON_P as jp  ON (d1.name =  jp.fruit) FOR JSON PATH) SELECT CAST(J.json_clob as varchar(max)) FROM J',
        '[{"fruit": "tgrid4all"}, {"fruit":"WideWorldImporters"}]'
    );
-- this is the CTE that we wrap around the bind parameter 
WITH JSON_P AS (
    SELECT fruit -- xref https://stackoverflow.com/a/31874636/40387
    FROM OPENJSON(cast(? as varchar(max))) -- critical to CAST the placeholder to varchar(max)
        WITH (
            -- we can provide the schema inline 
            fruit varchar(max)
        ) AS JP
),
J(json_clob) AS (
    SELECT *
    FROM sys.databases as d1
        JOIN JSON_P as jp ON (d1.name = jp.fruit) FOR JSON PATH -- this casts the result-set to JSON array of objects
) -- and coerce that to a varchar(max) so we read the entire thing as one scalar
-- without the coerce, the JSON is interpreted as a string and gets truncated
SELECT CAST(J.json_clob as varchar(max))
FROM J


declare @the_param varchar(max) = ?;
WITH JSON_P AS (
    SELECT fruit
    FROM OPENJSON(cast(@the_param as varchar(max))) WITH (fruit varchar(max)) AS JP
),
COLOR(color) AS (
    select color
    FROM OPENJSON(@the_param) WITH (color varchar(max)) as JC
),
J(json_clob) AS (
    SELECT *
    FROM sys.databases as d1
        JOIN JSON_P as jp ON (d1.name = jp.fruit)
        JOIN COLOR ON (COLOR.color = '' green '') FOR JSON PATH
)
SELECT CAST(J.json_clob as varchar(max))
FROM J




select openrowset_clob(
        'Driver={ODBC Driver 17 for SQL Server};Server=.\TGRID4ALL;Database=ReportServer;Trusted_Connection=yes',
        '
declare @the_param varchar(max) = ?;
WITH JSON_P AS (
    SELECT [database]
    FROM OPENJSON(cast(@the_param as varchar(max))) WITH ([database] varchar(max)) AS JP
),
COLOR(color) AS (
    select color
    FROM OPENJSON(@the_param) WITH (color varchar(max)) as JC
),
J(json_clob) AS (
    SELECT d1.*
    FROM sys.databases as d1
        JOIN JSON_P as jp ON (d1.name = jp.[database])
        JOIN COLOR ON (COLOR.color = ''green'') 
    FOR JSON PATH
)
SELECT CAST(J.json_clob as varchar(max))
FROM J',
'[{"database": "tgrid4all", "color" : "green"}, {"database":"WideWorldImporters", "color" : "red"}]'
);