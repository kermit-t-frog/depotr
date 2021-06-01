


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
#' @examples \dontrun{
#' store_prices(pricetbl)}
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
       message(sprintf("Batch insert of %s corporate actions completed.",nrow(actions)))
       },
       error = function(cond){
       unlink(outfile)
       stop(cond)
     })
   }
}

#' Extract corporate actions from (un-)adjusted closing prices
#'
#' @param prices A tibble with `symbol`, `date`, unadjusted close `uClose`,
#' split adjusted close `close` and fully-adjusted `fClose`.
#' @param accuracy Some instruments pay dividends in smaller currency denominations.
#' By default, `accuracy` is set to `2`, e.g. EUR-cents.
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
extract_corporate_actions <- function(prices,accuracy = 2){
  prices %<>% dplyr::arrange(symbol,dplyr::desc(date))
  prices %>% dplyr::group_by(symbol) %>% dplyr::group_modify(function(symbolprices,y){
    purrr::map_dfr(1:nrow(symbolprices),function(i){
      item <- symbolprices[i,]
      date <- item$date
      dividend <- round(item$aClose-item$fClose,accuracy)
      if (dividend<0){
        message("Observed negative dividend on ",date,". Setting dividend to zero.")
        dividend <- 0
      }
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


#' Obtain daily OHLC prices and volumes per isin/ccy.
#'
#' @param isins Optional list of ISINs.
#' @param from Optional start date, defaults to '1999-12-31'
#' @param to Optional end date, defaults to today.
#' @param ... Optional filter parameters passed to the backend
#'
#' @return A tibble with `isin`, `ccy`, `valuedate`, ohlc, fully adjusted close `fClose`, and volume.
#' @export
#'
#' @examples \dontrun{
#' get_market()
#'
#' get_market("DE0008404005")
#' get_market(,,,valuedate=="2021-05-05")
#' }
get_market <- function(isins,from,to,...){

  if (missing(isins)){isins<-NULL}
  if (missing(from)){from<-as.Date("1999-12-31")} else {from %<>% as.Date}
  if (missing(to)){to<-Sys.Date()} else {to %<>% to}

  con <- get_connection()

  res <- dplyr::tbl(con$connection(),"v_market") %>%
    {if (!is.null(isins)){dplyr::filter(.,.data$isin %in% isins)} else {.}} %>%
    dplyr::filter(dplyr::between(valuedate,from,to)) %>%
    dplyr::filter(...) %>%
    dplyr::select(isin,ccy,valuedate,open,high,low,close,fClose,volume) %>%
    dplyr::collect()
  con$close()
  res
}
