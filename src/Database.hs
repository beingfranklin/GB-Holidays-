module Database where

import Database.HDBC
  ( IConnection (commit, prepare, run),
    SqlValue,
    Statement (executeMany),
    fromSql,
    quickQuery',
    toSql,
  )
import qualified Data.ByteString.Lazy.Char8 as L8
-- import qualified Data.Map as Map

import Database.HDBC.Sqlite3 (Connection, connectSqlite3)
import Parse

-- | This is a function that creates the tables
--  |if the tables do not exists yet
initialiseDB :: IO Connection
initialiseDB = do
  conn <- connectSqlite3 "HolidayRecord.sqlite"
  run
    conn
    "CREATE TABLE IF NOT EXISTS holidays (\
    \ id INTEGER PRIMARY KEY NOT NULL,\
    \ date VARCHAR(40) NOT NULL, \
    \ localName VARCHAR(40) NOT NULL, \
    \ name VARCHAR(40) NOT NULL \
    \)"
    []
  commit conn
  run
    conn
    "CREATE TABLE IF NOT EXISTS countries (\
    \ id INTEGER PRIMARY KEY NOT NULL,\
    \ countryCode VARCHAR(40) NOT NULL, \
    \ global BOOL DEFAULT NULL, \
    \ fixed BOOL DEFAULT NULL \
    \)"
    []
  commit conn
  run
    conn
    "CREATE TABLE IF NOT EXISTS country_holidays (\
    \ id INTEGER PRIMARY KEY NOT NULL,\
    \ countryCode VARCHAR(40) DEFAULT NULL,\
    \ localName VARCHAR(40) DEFAULT NULL \
    \)"
    []
  commit conn
  return conn

-- | This function will insert the holiday records into the database
insertDB :: Connection -> [HolidayRecord] -> IO ()
insertDB conn records = do
  let xs = records 
  stmt <- prepare conn "INSERT INTO holidays (date,localName,name) VALUES (?,?,?)"
  putStrLn "Adding"
  executeMany stmt (map (\x -> [toSql (date x), toSql (localName x), toSql (name x)]) xs)
  commit conn

-- | This function will insert the country records into the dsatabase
insertLB :: Connection -> [HolidayRecord] -> IO ()
insertLB conn records = do
  let xs = records
  stmt <- prepare conn "INSERT INTO countries (countryCode,global,fixed) VALUES (?,?,?)"
  putStrLn "Adding"
  executeMany stmt (map (\x -> [toSql (countryCode x), toSql (global x), toSql (fixed x)]) xs)
  commit conn

-- | This function will insert the country_holidays records into the dsatabase
insertSB :: Connection -> [HolidayRecord] -> IO ()
insertSB conn records = do
  let xs = records
  stmt <- prepare conn "INSERT INTO country_holidays (countryCode,localName) VALUES (?,?)"
  putStrLn "Adding"
  executeMany stmt (map (\x -> [toSql (countryCode x), toSql (localName x)]) xs)
  commit conn

-- | This function will select all the holidays of a given country
queryDB :: Connection -> String -> IO [[SqlValue]]
queryDB conn countryCode =
  do
    quickQuery'
      conn
      "SELECT localName FROM country_holidays WHERE countryCode =(?)"
      [toSql countryCode]

-- | This function will select all the holidays in the date specified of a given country
selectHolidaysInDateRange :: Connection -> String -> String -> IO [String]
selectHolidaysInDateRange conn startDate endDate = do
  res <- quickQuery' conn "SELECT localName FROM holidays WHERE date BETWEEN (?) AND (?)" [toSql startDate, toSql endDate]
  return $ map fromSql $ concat res

-- | This function will call all the names on the database.
getNames :: Connection -> IO [String]
getNames conn = do
  res <- quickQuery' conn "SELECT name FROM holidays" []
  return $ map fromSql $ concat res

-- | This function will call all the names on the database.
getLocalNames :: Connection -> Bool -> IO [String]
getLocalNames conn isGlobal = do
  res <-
    quickQuery'
      conn
      "SELECT country_holidays.localName FROM country_holidays \
      \INNER JOIN countries \
      \ON countries.id = country_holidays.id \
      \WHERE countries.global=(?)"
      [toSql isGlobal]
  return $ map fromSql $ concat res

recordToSqlValues :: HolidayRecord -> [SqlValue]
recordToSqlValues holidays =
  [ toSql $ date holidays,
    toSql $ localName holidays,
    toSql $ name holidays
  ]

holidayToSqlValues :: HolidayRecord -> [SqlValue]
holidayToSqlValues countries =
  [ toSql $ countryCode countries,
    toSql $ global countries,
    toSql $ fixed countries
  ]

prepareInsertRecordStmt :: Connection -> IO Statement
prepareInsertRecordStmt conn = prepare conn "INSERT INTO holidays VALUES (?,?)"

prepareSelectRecordStma :: Connection -> IO Statement
prepareSelectRecordStma conn = prepare conn "SELECT FROM Country_holidays VALUES (?,?)"

saveHolidayRecord :: [HolidayRecord] -> Connection -> IO ()
saveHolidayRecord records conn = do
  stmt <- prepareInsertRecordStmt conn
  executeMany stmt (map recordToSqlValues records)
  commit conn

savecountriesRecord :: [HolidayRecord] -> Connection -> IO ()
savecountriesRecord record conn = do
  stma <- prepareSelectRecordStma conn
  executeMany stma (map recordToSqlValues record)
  commit conn

sqlRowToString :: [[SqlValue]] -> [String]
sqlRowToString xs = map (fromSql :: SqlValue -> String) (concat xs)

-- | Method to retrieve all the SQLs on the database.
getUnprocessedSQLHolidays :: Connection -> IO [HolidayRecord]
getUnprocessedSQLHolidays conn = do
  res <-
    quickQuery'
      conn
      "SELECT holidays.date, holidays.localName, holidays.name, countries.countryCode, countries.global, countries.fixed FROM holidays \
      \INNER JOIN countries \
      \WHERE countries.id=holidays.id \
      \ORDER BY countries.id ASC"
      []
  return $ map (\xs -> HolidayRecord(fromSql (xs !! 0)) (fromSql (xs !! 1)) (fromSql (xs !! 2)) (fromSql (xs !! 3)) (fromSql (xs !! 4)) (fromSql (xs !! 5))) res


encode :: ToJSON a => a -> L8.ByteString

convertToJSON :: Connection -> IO
convertToJSON conn = do
  res <- getUnprocessedSQLHolidays conn
  return encode res