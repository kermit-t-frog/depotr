initDB(host = 'localhost',
       port = 3399,
       'TEST_APPUSER',
       Sys.getenv("DEPOTRPASS"),
       dbname="depotdbtest")

test_that("Can access database", {
  testthat::expect_true(nrow(depotr:::get_wrapper("SHOW GRANTS;"))>1)
})

test_that("Can add instrument", {
  add_instrument('DE1234567890','testisin','EUR')
})



test_that("Can add a user", {
  expect_silent(add_user('testuser','testuser'))
  expect_silent(add_user('testuser2','testuser2'))
    expect_error(add_user('testuser','testuser'))
})

test_that("Can add a depot", {
  expect_silent(add_depot('testuser','testbroker','tb100','EUR'))
  expect_error(add_depot('testuser','testbroker','tb100','EUR'))
})



