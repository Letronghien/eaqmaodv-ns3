build_lib(
  LIBNAME eaqmaodv
  SOURCE_FILES
    model/eaqmaodv-rtable.cc
    model/eaqmaodv-rqueue.cc
    model/eaqmaodv-packet.cc
    model/eaqmaodv-qtable.cc
    model/eaqmaodv-id-cache.cc
    model/eaqmaodv-dpd.cc
    model/eaqmaodv-neighbor.cc
    model/eaqmaodv-routing-protocol.cc
    helper/eaqmaodv-helper.cc
  HEADER_FILES
    model/eaqmaodv-rtable.h
    model/eaqmaodv-rqueue.h
    model/eaqmaodv-packet.h
    model/eaqmaodv-qtable.h
    model/eaqmaodv-id-cache.h
    model/eaqmaodv-dpd.h
    model/eaqmaodv-neighbor.h
    model/eaqmaodv-routing-protocol.h
    helper/eaqmaodv-helper.h
  LIBRARIES_TO_LINK ${libinternet}
                  ${libwifi}
)
