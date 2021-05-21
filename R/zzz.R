.onLoad <- function(libname,pkgname){
  options(depotr_user = list(username="",password=""))
}

.onAttach <- function(libname,pkgname){
  packageStartupMessage("depotr: Set backend with depotr::initDB()\n        Set user with depotr::authenticate()")
}

.onDetach <- function(libpath){
  options(depotr_db="")
  options(depotr_user="")
}

.onUnload <- function(libpath){
  options(depotr_db="")
  options(depotr_user="")
}
