ROOT_DIR=$(CURDIR)/../..
include $(ROOT_DIR)/make.conf
INCLUDE_DIR=$(ROOT_DIR)/src/

TYPES:=$(wildcard types/*.h)
HEXARRS:=$(TYPES:%=%.hexarr)
HEXARRS += hdf5_logger.lua.hexarr

hdf5_logger.so: hdf5_logger.o $(INCLUDE_DIR)/libubx.so
	${CC} $(CFLAGS_SHARED) -o hdf5_logger.so hdf5_logger.o $(INCLUDE_DIR)/libubx.so -lluajit-5.1  -lpthread

hdf5_logger.lua.hexarr: hdf5_logger.lua
	../../tools/file2carr.lua hdf5_logger.lua

hdf5_logger.o: hdf5_logger.c $(INCLUDE_DIR)/ubx.h $(INCLUDE_DIR)/ubx_types.h $(INCLUDE_DIR)/ubx.c $(HEXARRS)
	${CC} -fPIC -I$(INCLUDE_DIR) -c $(CFLAGS) hdf5_logger.c

clean:
	rm -f *.o *.so *~ core $(HEXARRS)
