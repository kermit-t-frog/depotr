#' Initialize the MariaDB backend database
#'
#' @param host Host address, e.g. 'localhost' or 'IP address'
#' @param port Backend port, e.g. 3306
#' @param user User name
#' @param pass Password
#' @param dbname Database name
#' @param ... Other parameters to be passed to the backend connection
#'
#' @return Null
#' @export
#' @importFrom RMariaDB MariaDB
#'
#' @examples
#' \dontrun{
#' initDB('localhost',3306,'adam','the password')
#' }
initDB <- function(host,port,user,pass,dbname,...){
  if (missing(host) || missing(port) || missing(user) || missing(pass)){
    stop("Database connection not properly defined. Need host,port,user,pass.")
  }
  parms <- list(...)
  parms$host <- host
  parms$port <- port
  parms$user <- user
  parms$pass <- pass
  parms$dbname <- dbname
    parms$drv <- RMariaDB::MariaDB()
  options(depotr_db = parms)
}

#' Credentials for user authentification
#'
#' @param username Your depot user
#' @param password Your depot password
#'
#' @return
#' @export
#'
#' @examples
#' \dontrun{
#' authenticate('me','mypass')
#' }
authenticate <- function(username,password){
  if (!missing(username) && !missing(password)){
      options(depotr_user = list(username=username,password=password))
  }
  invisible(getOption("depotr_user"))
}


#' Provide a connection object
#'
#' @return A function holding the `connection` and its `close` method.
#' @importFrom RMariaDB dbConnect dbIsValid dbDisconnect
#'
get_connection <- function(){
  con <- do.call(RMariaDB::dbConnect,getOption("depotr_db"))
  connection <- function(){
    if (!RMariaDB::dbIsValid(con)){
      con <<- do.call(RMariaDB::dbConnect,getOption("depotr_db"))
    }
    con
  }
  close <- function(){RMariaDB::dbDisconnect(con)}
  list(connection=connection, close = close)
}

#' Book a trade or casfhlow ticket against the backend
#'
#' @param broker The broker's name
#' @param external_id The depot's ID/name with the broker.
#' @param valuedate the value date of the ticket, e.g. trade date + 2.
#' @param ... The actual ticket content. At the moment, we accept `cashflow` and
#' `trade` tickets. See examples.
#'
#' @return To be implemented.
#' @export
#' @importFrom magrittr %<>% %>%
#'
#' @examples
#' \dontrun{
#' initDB('localhost',3306,'batch_user','batch_password')
#'
#' # a trade with a single payment attached. Payment is optional:
#' book_ticket(
#'   broker        = 'bank inc',
#'   external_id = 'BI_adam_123',
#'   valuedate     = '2021-05-10',
#'   isin          = "DE1234567890",
#'   trade         = list(qty = 100,
#'                        prc = 999,
#'                        ccy = "EUR"),
#'   payment       = list(type   = "tax",
#'                        amount = 999,
#'                        ccy    = "EUR"))
#'
#' # Trade with two payments
#' book_ticket(
#'   broker        = 'bank inc',
#'   external_id = 'BI_adam_123',
#'   valuedate     = '2021-05-10',
#'   isin          = "DE1234567890",
#'   trade         = list(qty = 100,
#'                        prc = 999,
#'                        ccy = "EUR"),
#'   payment       = list(
#'                      list(type   = "tax",
#'                           amount = 999,
#'                           ccy    = "EUR"),
#'                      list(type   = "fee",
#'                           amount = 100
#'                           ccy    = "EUR")))
#'
#'  Dividend type cashflow
#' book_ticket(
#'   broker        = 'bank inc',
#'   external_id = 'BI_adam_123',
#'   valuedate     = '2021-05-10',
#'   isin          = "DE1234567890",
#'   cashflow      = list(type   = "dividend/distribution",
#'                        amount = 50,
#'                        ccy    = "EUR"))
#'}
book_ticket <- function(broker,external_id,valuedate, ...){
  p <- list(...)
  p$valuedate <- valuedate
  p$depot <- list(broker = broker,external_id = external_id)
  if (exists("payment",p)){
    if ("type" %in% names(p[["payment"]])){p$payment <- list(p$payment)}
  }
  if (exists("cashflow",p)){
    if ("type" %in% names(p[["cashflow"]])){p$cashflow <- list(p$cashflow)}
  }
  p %<>% jsonlite::toJSON(auto_unbox = TRUE)
  p %>% sprintf("SELECT is_valid_json_ticket_verbose('%s');",.) %>%
    exec_wrapper(authenticate=TRUE)
  p %>% sprintf("CALL book_ticket('%s');",.) %>%
    exec_wrapper(authenticate=TRUE)
}

#' SQL execute wrapper
#'
#' @param sql_statement A prepared SQL statement
#'
#' @return
#' @importFrom magrittr %>%
#' @importFrom RMariaDB dbExecute dbGetQuery
#'
#' @examples
#' \dontrun{
#' exec_wrapper("CALL add_user('myname');")
#' }
exec_wrapper <- function(sql_statement,authenticate=FALSE){
  con <- get_connection()
  if (authenticate){
    sql <- sprintf("CALL authenticate_user('%s','%s');",
                   authenticate()$username,
                   authenticate()$password)
    RMariaDB::dbExecute(con$connection(),sql)
  }
  RMariaDB::dbExecute(con$connection(),sql_statement)
  msg <- RMariaDB::dbGetQuery(con$connection(),"SHOW ERRORS LIMIT 1;")
  if (length(msg$Message)!=0){
    con$close()
    stop(paste0("Backend replies: ",msg$Message))
  }
  con$close()
}


#' SQL get wrapper
#'
#' @param sql_statement A prepared SQL statement
#'
#' @return
#' @importFrom magrittr %>%
#' @importFrom RMariaDB dbGetQuery
#' @importFrom tibble as_tibble
#'
#' @examples
#' \dontrun{
#' get_wrapper("SELECT * FROM v_last_symbol_data;")
#' }
get_wrapper <- function(sql_statement,authenticate=FALSE){
  con <- get_connection()
  if (authenticate){
    sql <- sprintf("CALL authenticate_user('%s','%s');",
                   authenticate()$username,
                   authenticate()$password)
    RMariaDB::dbExecute(con$connection(),sql)
  }
  out <- RMariaDB::dbGetQuery(con$connection(),sql_statement)
  msg <- RMariaDB::dbGetQuery(con$connection(),"SHOW ERRORS LIMIT 1;")
  if (length(msg$Message)!=0){
    con$close()
    stop(paste0("Backend replies: ",msg$Message))
  }
  con$close()
  out %>% tibble::as_tibble()
}


#' Add a new user to the system
#'
#' @param username The new username
#' @param password The new password
#'
#' @return NULL
#' @export
#' @importFrom magrittr %>%
#'
#' @examples
#' \dontrun{
#' add_user('me','mypass')
#' }
add_user <- function(username,password){
  sprintf("CALL add_user('%s','%s')",username,password) %>%
    exec_wrapper()
}

#' Add a new depot
#'
#' @param username The owner's user name
#' @param broker The portfolio's broker / bank
#' @param external_id The portfolio's ID with the broker
#' @param ccy The depot's currency.
#'
#' @return NULL
#' @export
#' @importFrom magrittr %>%
#'
#' @examples
#' \dontrun{
#' add_depot('me','my bank','portfolio 123132','EUR')
#' }
add_depot <- function(username,broker,external_id,ccy){
  sprintf("CALL add_depot('%s','%s','%s','%s');",
          username,broker,external_id,ccy) %>% exec_wrapper()
}

#' Introduce a new ticker symbol
#'
#' @param vendor Name of the vendor that's providing the symbol, e.g. 'IEX'
#' @param mic The symbol's market, e.g. 'XETR', 'NYSE'
#' @param isin International Securities Identification Number of the symbol, e.g.
#' 'DE1234566780'
#' @param ccy The trading currency, e.g. 'EUR'
#' @param symbol The actual symbol, e.g. 'ALV.DE' (Alphavantage) or 'ALV-GY' (IEX')
#'
#' @return
#' @export
#' @importFrom magrittr %>%
#'
#' @examples
#' \dontrun{
#' add_or_update_symbol('IEX','XETR','DE1234567879','EUR','MYSYMB-GY')
#' }
add_or_update_symbol <- function(vendor,mic,isin,ccy,symbol){
  sprintf("CALL add_or_update_symbol('%s','%s','%s','%s','%s')",
          vendor,mic,isin,ccy,symbol) %>% exec_wrapper()
}

#' Introduce a new security
#'
#' @param isin International Securities Idenficiation Number of the new object,
#' e.g. 'DE1234567890'
#' @param name A name, e.g. 'Acme Inc Pref. Shares'
#' @param ccy  The company's / fund's reporting currency, e.g. 'EUR'
#' @param vendor Optional vendor name if a symbol is to be set
#' @param market Optional market identificer code (mic) if a symbol is to be set
#' @param symbol Optional vendor-market symbol if a symbol is to be set
#' @param sym_ccy Optional symbol ccy if a symbol is to be set (or reuse ccy)
#'
#' @return NULL
#' @export
#' @importFrom magrittr %>%
#'
#' @examples
#' \dontrun{
#' add_instrument('DE1234567890','Acme Inc','EUR')
#' }
add_instrument <- function(isin,name,ccy,vendor,mic,symbol,symccy){

  sprintf("CALL add_instrument('%s','%s','%s');",
          isin,name,ccy) %>% exec_wrapper()

  if (all(!missing(vendor), !missing(mic), !missing(symbol))){
    if (missing(symccy)){symccy <- ccy}
    add_or_update_symbol(vendor,mic,isin,symccy,symbol)
  }
}

#' Grant, or revoke, read/write permissions to your portfolios
#'
#' @param to_user The grantee
#' @param broker The depot's brokerage
#' @param external_id The depot's id with your broker
#' @param permission_level The targeted permission level, must be 'revoke', 'read' or 'write'
#'
#' @return NULL
#' @importFrom magrittr %>%
#' @export
#'
#' @examples
#' \dontrun{
#' grant_depot_permission('you','my broker','MB12311/2','read')
#' }
grant_depot_permission <- function(to_user,broker,external_id,
                                   permission_level = c("revoke","read","write")){
  sprintf("CALL grant_depot_permission('%s','%s','%s','%s');",
    broker,external_id,to_user,permission_level) %>%
    exec_wrapper(authenticate=TRUE)
}

#' Download latest symbol data from IEX cloud
#'
#' @return A tibble with `vendor`, `symbol`, `date`, `OHLC`, and volume
#' @export
#' @importFrom dplyr mutate
#' @importFrom iexcloudr prices
#' @importFrom magrittr %>%
#' @importFrom purrr map_dfr
#' @importFrom stringr str_pad
#'
#' @examples
#' \dontrun{
#' latest_prices()
#' }
latest_prices <- function(){
  current <- get_wrapper("SELECT * FROM v_last_symbol_data;")
  nr <- nrow(current)
  result <- purrr::map_dfr(1:nrow(current),function(i){
    x <- iexcloudr::prices(current$symbol[[i]],start_date = current$maxdate[[i]]+1)
    message("Batch download :",
            stringr::str_pad(i,nchar(nr),side = "left"),"/",nr,
            " : " ,stringr::str_pad(current$symbol[[i]],width = 8,side = "right"),
            " : ",nrow(x))
    x
  }) %>% dplyr::mutate(vendor="IEX",.before=symbol)
}

#' Load new market data to database, based on a data tibble.
#'
#' @param prices A tibble with `vendor`, `symbol`, `date`, `OHLC`, and volume
#'
#' @return NULL
#' @export
#' @importFrom dplyr  select
#' @importFrom readr write_csv
#' @importFrom magrittr %>%
#'
#' @examples
store_prices <- function(prices){
  if (nrow(prices)==0){
    message("Batch download : No new market data available. Exiting.")
    return(invisible())
  }
  outfile <- tempfile(fileext = ".csv")
  prices %>%
    dplyr::select(dplyr::all_of(c("vendor","symbol","date","open","high","low","close","volume"))) %>%
    readr::write_csv(outfile,col_names = TRUE,append = FALSE)
  sql <- paste("LOAD DATA LOCAL INFILE '%s' INTO TABLE etl_price",
               "CHARACTER SET 'utf8'",
               "FIELDS TERMINATED BY ','",
               "IGNORE 1 LINES;")
  sql %<>% sprintf(normalizePath(outfile,winslash = "/"))
  tryCatch({
    exec_wrapper(sql)
    unlink(outfile)
    exec_wrapper("CALL load_price_from_etl();")
    message(sprintf("batch insert of %d new price rows completed.",nrow(prices)))
    },
  error = function(cond){
    unlink(outfile)
    stop(cond)
   if (grepl("denied to user",cond)){stop(  get_wrapper("SHOW ERRORS LIMIT 1;")$Message)} else {stop(cond)} })
}




#' Store price adjustments from corporate actions
#'
#' @param actions A tibble with `vendor`, `symbol`, `date`,`close`, `dividend` and `split_factor`.
#'
#' @return NULL
#' @export
#' @importFrom dplyr select
#' @importFrom readr write_csv
#'
#' @examples
#' \dontrun{
#' iexcloudr::prices("ALV-GY") %>%
#' iexcloudr:extract_corporate_actions() %>%
#' store_corporate_actions()}
store_corporate_actions <- function(actions){
   if (nrow(actions)>0){
     message("Adding corporate actions")
     outfile <- tempfile(fileext = ".csv")
     actions %>%
       dplyr::select(.data$vendor,.data$symbol,valuedate = .data$date,.data$close,.data$dividend,.data$split_factor) %>%
       readr::write_csv(outfile,col_names = TRUE,append = FALSE,na = "NULL",quote_escape = "none")
     sql <- paste("LOAD DATA LOCAL INFILE '%s' INTO TABLE etl_price_adjustment",
                  "CHARACTER SET 'utf8'",
                  "FIELDS TERMINATED BY ','",
                  "IGNORE 1 LINES;")
     sql %<>% sprintf(normalizePath(outfile,winslash = "/"))
     tryCatch({
       exec_wrapper(sql)
       unlink(outfile)
       exec_wrapper("CALL load_price_adjustment_from_etl();")
       message("price adjustments have been updated.")
       },
       error = function(cond){
       unlink(outfile)
       stop(cond)
     })
   }
}

#' Get position table for active user
#'
#' @return A tibble with depot properties (owner,broker, external_id, ccy),
#' instrument properties (isin,ccy), position properties (date, qty, vol, ccy)
#' @export
#'
#' @examples
#' \dontrun{
#' authenticate('me','mypass')
#' position()
#' }
position <- function(){
  "SELECT * FROM v_position;" %>%
    get_wrapper(authenticate=TRUE)
}

#' Get list of trades for active user
#'
#' @return A tibble with depot properties (owner,broker, external_id, ccy),
#' instrument properties (isin,ccy), trade properties (date, qty, prc, vol, ccy)
#' @export
#'
#' @examples
#' \dontrun{
#' authenticate('me','mypass')
#' trades()
#' }
trades <- function(){
  "SELECT * FROM v_trade;" %>%
    get_wrapper(authenticate=TRUE)
}


#' Extract corporate actions from (un-)adjusted closing prices
#'
#' @param prices A tibble with `symbol`, `date`, unadjusted close `uClose`,
#' split adjusted close `close` and fully-adjusted `fClose`.
#'
#' @return A tibble with `symbol`, `date`,`close`, `split_factor` and `dividend`
#' @export
#' @importFrom magrittr %>% %<>%
#' @importFrom dplyr arrange desc mutate group_by group_modify
#' @importFrom purrr map_dfr
#' @importFrom tibble tibble
#'
#' @examples
#' prices <- tibble::tibble(
#'     symbol = c("ALV-GY","ALV-GY","ALV-GY"),
#'       date = c("2021-05-04","2021-05-05","2021-05-06"),
#'      close = c(216.5000, 221.5000, 212.7000),
#'     aClose = c(216.5000, 221.5000, 212.7000),
#'     fClose = c(207.1167, 211.9000, 212.7000))
#' extract_corporate_actions(prices)
extract_corporate_actions <- function(prices){
  prices %<>% dplyr::arrange(symbol,dplyr::desc(date))
  prices %>% dplyr::group_by(symbol) %>% dplyr::group_modify(function(symbolprices,y){
    purrr::map_dfr(1:nrow(symbolprices),function(i){
      item <- symbolprices[i,]
      date <- item$date
      dividend <- round(item$aClose-item$fClose,2)
      div_factor <- (1-dividend/item$aClose)
      split_factor <- item$aClose/item$close
      if ( (abs(dividend)>1e-3) || (abs(log(split_factor))>1e-4 )){
        symbolprices <<- symbolprices %>% dplyr::mutate(aClose = .data$aClose / split_factor,
                                                        fClose = .data$fClose / split_factor / div_factor)
        tibble::tibble(date = item$date,close=item$close, split_factor = split_factor, dividend = dividend)
      }
    }) %>% dplyr::arrange(.data$date)

  }) %>% dplyr::ungroup()

}
