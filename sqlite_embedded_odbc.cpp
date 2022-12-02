#include <sqlite3ext.h>
SQLITE_EXTENSION_INIT1


#ifdef WIN32
#define SQLITE_EXTENSION_ENTRY_POINT __declspec(dllexport)
#else
#define SQLITE_EXTENSION_ENTRY_POINT
#endif


#include <nanodbc/nanodbc.h>

#include <windows.h>
#include <sql.h>
#include <sqlext.h>

#include <iostream>
#include <cstring>
#include <exception>
#include <iomanip>


#include <nlohmann/json.hpp>

using json = nlohmann::json;
using namespace std;


// This needs to be callable from C
extern "C" SQLITE_EXTENSION_ENTRY_POINT int sqlite_embedded_odbc_init(
      sqlite3 *db,
      char **pzErrMsg,
      const sqlite3_api_routines *pApi);


typedef void (*column_getter_function_pointer)(json& , nanodbc::result&, short);

void get_string_value(json& jv, nanodbc::result& result, short column_number){
  jv = result.get<string>(column_number);
}

void get_float_value(json& jv, nanodbc::result& result, short column_number){
  jv = result.get<float>(column_number);
}

void get_int_value(json& jv, nanodbc::result& result, short column_number){
  jv = result.get<int>(column_number);
}

void get_date_value(json& jv, nanodbc::result& result, short column_number){
  // return as ISO-8601 string
  nanodbc::date d;
  char buffer [50];
  d = result.get<nanodbc::date>(column_number);
  sprintf_s(buffer, "%d-%02d-%02d", d.year,d.month, d.day);
  jv = buffer;
}

void get_timestamp_value(json& jv, nanodbc::result& result, short column_number){
  // return as ISO-8601-ish string
  nanodbc::timestamp ts;
  char buffer [50];
  ts = result.get<nanodbc::timestamp>(column_number);
  sprintf_s(buffer, "%d-%02d-%02d %02d:%02d:%02d.%d", 
                  ts.year,ts.month, ts.day,
                  ts.hour,ts.min, ts.sec, ts.fract);
  jv = buffer;
}

void get_null_value(json& jv, nanodbc::result& result, short column_number){
  jv = nullptr;
}

column_getter_function_pointer 
column_to_function(nanodbc::result& result, short column_number){
  auto sql_type = result.column_datatype(column_number);

  column_getter_function_pointer fp;
  fp = &get_null_value;
  // used  list of SQL types from
  //     https://learn.microsoft.com/en-us/sql/odbc/reference/appendixes/sql-data-types?view=sql-server-ver16
  // and copied to a spreadsheet and manually grouped the types to a getter
  switch (sql_type) {
      case SQL_SMALLINT:
      case SQL_BIT:
      case SQL_INTEGER:
      case SQL_TINYINT:
      case SQL_BIGINT:
          fp =  &get_int_value;
        break;
      case SQL_FLOAT:
      case SQL_REAL:
      case SQL_NUMERIC:
      case SQL_DECIMAL:
      case SQL_DOUBLE:
           fp = &get_float_value;
        break;
      case SQL_VARCHAR:
      case SQL_CHAR:
      case SQL_LONGVARCHAR:
      case SQL_WCHAR:
      case SQL_WVARCHAR:
      case SQL_WLONGVARCHAR:
      case SQL_GUID:
          fp = &get_string_value;
        break; 
      case SQL_BINARY:
      case SQL_VARBINARY:
      case SQL_LONGVARBINARY:
          cout << "do not know how to deal with binary type " << sql_type;
          fp = &get_null_value;
        break;
      case SQL_TYPE_DATE:
          fp = &get_date_value;
        break;
      case SQL_TYPE_TIMESTAMP:
          fp = &get_timestamp_value;
        break;
      default:
          cout << "do not recognise type " << sql_type << " for column " << column_number << "\n";
          fp = &get_null_value;   
      }
  return fp;
}


void result_to_clob(string &clob, nanodbc::result& result){
  result.next();
  clob = result.get<string>(0);
}

void result_to_json(nlohmann::ordered_json& retval, nanodbc::result& result){
  int n = result.columns();
  std::vector<string> column_names(n);
  std::vector<column_getter_function_pointer> function_pointers(n);

  // set up column names and function pointers from the result
  // metadata. Hope that most ODBC drivers will set the types of each column
  // before the results are iterated over.
  for(int i=0; i< result.columns(); i++) {
    column_names[i]=result.column_name(i);
    function_pointers[i] = column_to_function(result, i);
  }
  
  while (result.next())
  {
      // very nice to have the keys in the select order
      nlohmann::ordered_json j;
      for(int i=0; i< result.columns(); i++) {
        json jv;
        // Note that it is much easier to check for null in a type independent
        // way (and set jv to nullptr, which will be serialized as null) than 
        // to do it within a column_getter_function
        if (result.is_null(i)) {
          jv=nullptr;
        } else {
          (*function_pointers[i])(jv,result,i);
        }
        j[column_names[i]]=jv;    
      }
      retval.push_back(j);
  }
}


static void openrowset_clob_func(
    sqlite3_context *context,
    int argc,
    sqlite3_value **argv)
{
  // TODO: replace with an error
  // TODO: support bind array and/or single bind params
  assert(argc == 2);

  // do some more soundess checking
  if (sqlite3_value_type(argv[0]) == SQLITE_NULL)
    return;

  std::string odbc_connection_string, query_string, clob;

  // hope that overloaded assignment operator will do the right thing.
  // I don't know if there is a cleaner way to do this.
  odbc_connection_string = (reinterpret_cast<const char *>(sqlite3_value_text(argv[0])));
  query_string = (reinterpret_cast<const char *>(sqlite3_value_text(argv[1])));
  // TODO: figure out when to return an error vs sqlite3_result_null
  try
  {
    nanodbc::connection conn(odbc_connection_string);
    auto result = nanodbc::execute(conn, query_string);
    result_to_clob(clob, result);
  }
  catch (std::runtime_error e) {
    std::string message = e.what();
    sqlite3_result_error(context, message.data(), (int)message.length());
    return;
  }

  // TODO: perhaps use the sqlite3_result_blob interface?
  // For the kind of data volumes envisioned, it does not seem necessary 
  // and would likely be a complication. It seems unlikely that we will ever have
  // any kind of data that is sufficiently large to require streaming. Using incremental
  // reads from the underlying ODBC API (if indeed such APIs event exist. I simply don't know)
  // seems like it would be difficult and error prone. This approach should be 'good enough'
  // for the moment.
  sqlite3_result_text(context, clob.data(), (int)clob.length(), SQLITE_TRANSIENT);
  // not sure if we have to do anything with freeing 'expanded'
  // I think it will be taken care of by the runtime simply by going out of scope
  // and that nothing has to be done to it explicitly.
  return;
}


static void openrowset_json_func(
    sqlite3_context *context,
    int argc,
    sqlite3_value **argv)
{
  // TODO: replace with an error
  // TODO: support bind array and/or single bind params
  assert(argc == 2);

  // do some more soundess checking
  if (sqlite3_value_type(argv[0]) == SQLITE_NULL)
    return;

  // makes the order of the keys match up with their position in the select list.
  nlohmann::ordered_json retval;

  std::string odbc_connection_string, query_string, expanded;

  // hope that overloaded assignment operator will do the right thing.
  // I don't know if there is a cleaner way to do this.
  odbc_connection_string = (reinterpret_cast<const char *>(sqlite3_value_text(argv[0])));
  query_string = (reinterpret_cast<const char *>(sqlite3_value_text(argv[1])));
  // TODO: figure out when to return an error vs sqlite3_result_null
  try
  {
    nanodbc::connection conn(odbc_connection_string);
    auto result = nanodbc::execute(conn, query_string);
    result_to_json(retval, result);
    expanded = retval.dump(); // serialize the entire thing to a string
    // given that this is meant for metadata queries, the volume of data is likely to be
    // quite low and this many-functions-calls-per-value naive approach may be OK.
  }
  catch (json::exception e) {
    std::string message = e.what();
    sqlite3_result_error(context, message.data(), (int)message.length());
    return;
  }
  catch (std::runtime_error e) {
    std::string message = e.what();
    sqlite3_result_error(context, message.data(), (int)message.length());
    return;
  }

  // TODO: deal with encodings, preferred encodings etc.
  sqlite3_result_text(context, expanded.data(), (int)expanded.length(), SQLITE_TRANSIENT);
  // not sure if we have to do anything with freeing 'expanded'
  // I think it will be taken care of by the runtime simply by going out of scope
  // and that nothing has to be done to it explicitly.
  return;
}

// we need
//    -DSQLITE_API=__declspec(dllexport) 
// for Windows.
// Note that .load in the shell can take the initialization function name as an 
// argument so that we don't have to rely on naming conventions. Whatever function is used,
// it needs to have C style symbol which is globally visible. Verify with DUMPBIN /EXPORTS  (Windows)
// or nm (Linux) once the dll has been built.

int sqlite_embedded_odbc_init(
    sqlite3 *db,
    char **pzErrMsg,
    const sqlite3_api_routines *pApi)
{
  int rc = SQLITE_OK;
  SQLITE_EXTENSION_INIT2(pApi);
  (void)pzErrMsg; /* Unused parameter */
  rc = sqlite3_create_function(db, "openrowset_json", 2,
                               SQLITE_UTF8 | SQLITE_DETERMINISTIC,
                               0, openrowset_json_func, 0, 0);

  rc = sqlite3_create_function(db, "openrowset_clob", 2,
                               SQLITE_UTF8 | SQLITE_DETERMINISTIC,
                               0, openrowset_clob_func, 0, 0);                               
  return rc;
}