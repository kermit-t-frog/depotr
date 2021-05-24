suppressWarnings(library(magrittr))
# helper functions for setting the read and admin users for db connection
init_read <- function(){
  initDB(host = 'localhost',
         port = 3399,
         user = Sys.getenv('DEPOT_READUSER'),
         Sys.getenv('DEPOT_READPASS'),
         dbname=Sys.getenv('DEPOT_DBNAME'))
}

init_admin <- function(){
  initDB(host = 'localhost',
         port = 3399,
         user = Sys.getenv('DEPOT_ADMINUSER'),
         Sys.getenv('DEPOT_ADMINPASS'),
         dbname=Sys.getenv('DEPOT_DBNAME'))
}

test_that("Can access database", {
  init_read()
  testthat::expect_true(nrow(depotr:::get_wrapper("SHOW GRANTS;"))>1)
  init_admin()
  testthat::expect_true(nrow(depotr:::get_wrapper("SHOW GRANTS;"))>1)
})

test_that("Can add instrument", {
  init_read()
  testthat::expect_error(add_instrument('DE1234567890','testisin','EUR'))
  init_admin()
  testthat::expect_silent(add_instrument('DE1234567890','testisin','EUR'))
  testthat::expect_error(add_instrument('DE1234567890','testisin','EUR'),regexp="Instrument exists")
})


test_that("Can add a user", {
  init_read()
  testthat::expect_error(add_user('testuser1','password1'))
  init_admin()
  testthat::expect_silent(add_user('testuser1','password1'))
  testthat::expect_silent(add_user('testuser2','password2'))
  testthat::expect_error(add_user('testuser1','password1'))
})

test_that("Can add a depot", {
  init_read()
  testthat::expect_silent(add_depot('testuser1','broker1','accountid1','EUR'))
  testthat::expect_silent(add_depot('testuser1','broker1','accountid2','EUR'))
  testthat::expect_error(add_depot('testuser1','broker1','accountid1','EUR'),'Depot already exists')
  testthat::expect_error(add_depot('testuser2','broker1','accountid1','EUR'),'Depot already exists')

  init_admin()
  testthat::expect_silent(add_depot('testuser2','broker2','accountid1','EUR'))

})

test_that("Can grant a portfolio", {
  init_read()
  authenticate('','')
  testthat::expect_error(grant_depot_permission('testuser1','broker1','accountid1','write'),'Bad user')
  authenticate('testuser1','password1')
  testthat::expect_error(grant_depot_permission('testuser1','broker1','accountid1','write'),'Grant to self not allowed')
  testthat::expect_silent(grant_depot_permission('testuser2','broker1','accountid1','read'))
})

test_that("Can book a ticket", {
  init_read()
  authenticate('','')
  testthat::expect_error(book_ticket('broker1','accountid1','2021-04-21',trade=list(qty=7,prc=50.01,ccy='EUR'),isin='DE1234567890'),'Bad user')
  authenticate('testuser1','password1')
  testthat::expect_silent(book_ticket('broker1','accountid1','2021-04-21',trade=list(qty=13,prc=50.01,ccy='EUR'),isin='DE1234567890'))
  testthat::expect_silent(book_ticket('broker1','accountid2','2021-04-21',trade=list(qty=17,prc=50.01,ccy='EUR'),isin='DE1234567890'))
  testthat::expect_error(book_ticket('broker2','accountid1','2021-04-21',trade=list(qty=19,prc=50.01,ccy='EUR'),isin='DE1234567890'),'Depot denied')

  authenticate('testuser2','password2')
  testthat::expect_silent(book_ticket('broker2','accountid1','2021-04-21',trade=list(qty=23,prc=50.01,ccy='EUR'),isin='DE1234567890'))
  })

test_that("see only my position", {
  init_read()
  authenticate('','')
  testthat::expect_error(position(),'Bad user')

  authenticate('testuser1','password1')
  testthat::expect_true(sum(position()$pos_vol) == sum(c(650.13,850.17)))



  authenticate('testuser2','password2')
  testthat::expect_true(sum(position()$pos_vol) == sum(c(650.13,1150.23)))
})

test_that("adding symbols works", {
  init_read()
  iexcloudr::apikey(Sys.getenv("IEXAPIKEYPUBLIC"),sandbox = TRUE)
  authenticate('','')
  testthat::expect_error(  add_or_update_symbol('IEX','XETR','DE0008404005','EUR','ALV-GY'))

  init_admin()
  testthat::expect_silent(  add_or_update_symbol('IEX','XETR','DE0008404005','EUR','ALV-GY'))

  init_read()
  prices <- readr::read_csv("prices.csv") %>% dplyr::mutate(vendor="IEX",.before = symbol)
  testthat::expect_error(store_prices(prices),'denied to user')

  init_admin()
  testthat::expect_message(store_prices(prices),'rows completed.')

})

test_that("can extract dividend / split info", {
  prices <- tibble::tibble(
    symbol = c("ALV-GY","ALV-GY","ALV-GY"),
    date = c("2021-05-04","2021-05-05","2021-05-06"),
    close = c(216.5000, 221.5000, 212.7000),
    aClose = c(216.5000, 221.5000, 212.7000),
    fClose = c(207.1167, 211.9000, 212.7000))
  x <- extract_corporate_actions(prices)
  expect_equal(x$dividend , 9.6)
  expect_equal (x$date , "2021-05-05")
})

test_that("can upload dividends", {
  prices <- readr::read_csv("prices.csv")
  actions <- prices %>%
  extract_corporate_actions() %>%
    dplyr::mutate(vendor="IEX",.before = .data$symbol)
  init_read()
  expect_error(store_corporate_actions(actions),'denied to user')
  init_admin()
  expect_message(store_corporate_actions(actions),'have been updated')
  prices2 <-   depotr:::get_wrapper("SELECT * FROM v_price_adjusted;")
  expect_equal(
    prices %>% dplyr::filter(date==as.Date("2021-05-05")) %$% fClose,
    prices2 %>% dplyr::filter(valuedate==as.Date("2021-05-05")) %$% close
  )

})



