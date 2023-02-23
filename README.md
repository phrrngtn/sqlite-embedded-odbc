# sqlite-embedded-odbc


SQLite extension (`openrowset`) for executing queries against remote ODBC connections. It is loosely inspired
by the `OPENROWSET` function in SQL Server although in this case, there are two *scalar* functions:
* `openrowset_clob`
```sql
select openrowset_clob('Driver={ODBC Driver 17 for SQL Server};Server=.\TGRID4ALL;Database=ReportServer;Trusted_Connection=yes', 'SELECT @@servername as servername, getutcdate() as date, suser_name() as me FOR JSON PATH');
[{"servername":"LAPTOP-M6BP34C4\\TGRID4ALL","date":"2023-02-11T22:50:08.210","me":"LAPTOP-M6BP34C4\\phrrn"}]
```
* `openrowset_json`
```sql
SELECT JE.value->'$.servername' as servername, JE.value->'$.date' as [date], JE.value->'$.me' as me FROM json_each((select openrowset_json('Driver={ODBC Driver 17 for SQL Server};Server=.\TGRID4ALL;Database=ReportServer;Trusted_Connection=yes', 'SELECT @@servername as servername, getutcdate() as [date], suser_name() as me'))) as JE;
servername|date|me
"LAPTOP-M6BP34C4\\TGRID4ALL"|"2023-02-11 23:00:27.590000000"|"LAPTOP-M6BP34C4\\phrrn"
```


```sql
select openrowset_clob(
    -- this is a connection string which will be used by nanodbc to connect
        'Driver={ODBC Driver 17 for SQL Server};Server=.\TGRID4ALL;Database=ReportServer;Trusted_Connection=yes',
    -- this is the query that will be executed on the remote side.
    -- note that query contains a placeholder ('?'). These are positional
    -- and assumed to be string values. In this example, the string is a JSON array-of-dicts
    -- which we expand out in the JSON_P 
        '
declare @the_param varchar(max) = ?;
WITH DB AS (
    SELECT [database]
    FROM OPENJSON(cast(@the_param as varchar(max))) WITH ([database] varchar(max)) AS JD
),
COLOR(color) AS (
    select color
    FROM OPENJSON(@the_param) WITH (color varchar(max)) as JC
),
J(json_clob) AS (
    SELECT d1.*
    FROM sys.databases as d1
        JOIN DB as db ON (d1.name = db.[database])
        JOIN COLOR ON (COLOR.color = ''green'') 
    FOR JSON PATH
)
-- it is important to cast this to a string so that
-- it is passed back to odbc as a single value
SELECT CAST(J.json_clob as varchar(max))
FROM J',
-- pass in a pseudo "table-valued parameter" as a placehold bind value.
-- The string is a JSON array of dicts which will be expanded as a CTE
-- in the remote query
'[{"database": "tgrid4all", "color" : "green"}, {"database":"WideWorldImporters", "color" : "red"}]'
);
```
Loading
=======
```sql
-- On Windows, Linux and Mac.
sqlite> .load ./openrowset
```

Building
========
I followed the instructions in https://visitlab.pages.fi.muni.cz/tutorials/vs-code/index.html to use CMake and vcpkg.

Background
==========
xref https://github.com/nanodbc/nanodbc/discussions/357

> I am interested in embedding nanodbc within SQLite as an extension with a view to implementing some Foreign Data Wrapper capabilities within SQLite. Ultimately, I would like to map remote tables into local virtual tables