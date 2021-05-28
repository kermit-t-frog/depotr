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
    # todo: use openssl::sha512  here.
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
  close <- function(){
    RMariaDB::dbDisconnect(con)
  }
  list(connection=connection, close = close)
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


#' Internal rate of return based on flow table
#'
#' @param flows A tibble from `flow_table`.
#'
#' @return
#' @export
#'
#' @examples
#' \dontrun{
#' flow_table('2021-01-01','2021-05-31')
#' performance_table(flows)}
performance_table <- function(flows){
  xirr <- function(dates,flows){
    uniroot(function(r){
      sum( (1+r) ^ (as.numeric( (min(dates) - dates ) / 365 )) * flows)
    },
    interval = c(-0.9999,5),
    tol = 1e-4)$root
  }
  # build the flow tibble from position value at start date, at end date, and
  # interim cashflows
  flows %>%
    dplyr::group_by(ccy) %>%
    dplyr::group_modify(function(x,y){
      tibble::tibble(performance = xirr(x$date,x$amount))
    }) %>%
    dplyr::ungroup()
}
