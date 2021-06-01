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

#' Get position table for active user
#'
#' @param valuedate As of which date is the position to be returned?
#' Defaults to _today_.
#' @return A tibble with depot properties (owner,broker, external_id, ccy),
#' instrument properties (isin,ccy), position properties (date, qty, vol, ccy)
#' @export
#'
#' @examples
#' \dontrun{
#' authenticate('me','mypass')
#' position()
#' }
position <- function(valuedate=Sys.Date()){
  valuedate %<>% as.Date()
  pos <- "CALL position_as_of('%s');" %>%
    sprintf(valuedate) %>%
    get_wrapper(authenticate = TRUE)
  mkt <- "CALL market_as_of('%s')" %>%
    sprintf(valuedate) %>%
    get_wrapper %>% dplyr::select(.data$isin, .data$ccy,mkt_valuedate = .data$valuedate, .data$close)
  pos %>%
    dplyr::left_join(mkt,by=c("isin","pos_ccy"="ccy")) %>%
    dplyr::mutate(pos_valuedate = valuedate,
                  mkt_value = .data$pos_qty * .data$close) %>%
    dplyr::select(-.data$close)
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

#' Get all portfolio cashflows for a time period
#'
#' @param from Start date, inclusive. Defaults to first of the year
#' @param to End date, inclusive. Defaults to 'today'.
#'
#' @return A tibble with depot and instrument identifiers,
#' cash flow properties and amounts.
#' @export
#'
#' @examples
#' \dontrun{cashflows()}
cashflows <- function(from='1990-01-01',to=Sys.Date()){
  "CALL cashflow_from_to('%s','%s');" %>%
    sprintf(from,to) %>%
    get_wrapper(authenticate=TRUE)
}

#' Cash flows to/from your depot(s) on isin/ccy level, assuming
#' initial position to be an investment at market prices (neg. sign)
#'
#' @param from Start date, inclusive.
#' @param to End date, inclusive.
#'
#' @return A tibble with depot and isin identifiers, cash flow size and ccy.
#' @export
#'
#' @examples \dontrun{flow_table('2021-01-01','2021-05-31')}
flow_table <- function(from,to){
  from %<>% as.Date()
  to %<>% as.Date()

  # build the flow tibble from position value at start date, at end date, and
  # interim cashflows
  dplyr::bind_rows(
    # starting point: interpret the position as 'investment', i.e. negative sign
    position(from) %>%
      dplyr::mutate(
        mkt_value = dplyr::if_else(is.na(mkt_value),-1*pos_vol,-1*mkt_value)
      ),
    position(to) %>%
      dplyr::mutate(
        mkt_value = dplyr::if_else(is.na(mkt_value),pos_vol,mkt_value))
  ) %>%
    dplyr::select(
      owner  = depot_owner,
      broker = depot_broker,
      extid  = depot_external_id,
      date   = pos_valuedate,
      isin,
      ccy    = pos_ccy,
      amount = mkt_value) %>%
    dplyr::bind_rows(
      cashflows(as.Date(from) ,as.Date(to)) %>%
        dplyr::filter(!(flow_type %in% c("buy","sell") && valuedate==from)) %>%
        dplyr::filter(!(flow_type %in% c("buy","sell") && valuedate==to)) %>%
        dplyr::group_by(depot_owner, depot_broker,depot_external_id, valuedate, isin,flow_ccy) %>%
        dplyr::summarise(cf = sum(flow_amount), .groups="drop") %>%
        dplyr::select(
          owner = depot_owner,
          broker= depot_broker,
          extid = depot_external_id,
          date  = valuedate,
          isin,
          ccy   = flow_ccy,amount=cf)
    )
}


