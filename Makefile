ROOT_DIR=$(CURDIR)/../..
include $(ROOT_DIR)/make.conf
INCLUDE_DIR=$(ROOT_DIR)/src/
NAME=converter
NAME2=saver
DIRNAME=hdf5_logging

TYPES:=$(wildcard types/*.h)
HEXARRS:=$(TYPES:%=%.hexarr)
HEXARRS += $(NAME).lua.hexarr
HEXARRS += $(NAME2).lua.hexarr

all: $(NAME).so $(NAME2).so

$(NAME).so: $(NAME).o $(INCLUDE_DIR)/libubx.so
		${CC} $(CFLAGS_SHARED) -o $(NAME).so $(NAME).o $(INCLUDE_DIR)/libubx.so -lluajit-5.1  -lpthread

$(NAME).lua.hexarr: $(NAME).lua
		../../tools/file2carr.lua $(NAME).lua

$(NAME).o: $(NAME).c $(INCLUDE_DIR)/ubx.h $(INCLUDE_DIR)/ubx_types.h $(INCLUDE_DIR)/ubx.c $(HEXARRS)
		${CC} -fPIC -I$(INCLUDE_DIR) -c $(CFLAGS) $(NAME).c

$(NAME2).so: $(NAME2).o $(INCLUDE_DIR)/libubx.so
		${CC} $(CFLAGS_SHARED) -o $(NAME2).so $(NAME2).o $(INCLUDE_DIR)/libubx.so -lluajit-5.1  -lpthread

$(NAME2).lua.hexarr: $(NAME2).lua
		../../tools/file2carr.lua $(NAME2).lua

$(NAME2).o: $(NAME2).c $(INCLUDE_DIR)/ubx.h $(INCLUDE_DIR)/ubx_types.h $(INCLUDE_DIR)/ubx.c $(HEXARRS)
		${CC} -fPIC -I$(INCLUDE_DIR) -c $(CFLAGS) $(NAME2).c

#$(NAME).c: ../logging/file_logger.c
		#echo "$$(cat ../../src/ubx.c | sed -n 1,31p)\n" | cat - ../logging/file_logger.c | sed -e 's/file_logger/$(NAME)/g' -e 's/logging/$(DIRNAME)/g' -e 's/writes to a/& $(NAME)/' -e 's/BSD-3-Clause/& LGPL-2.1+/' > $@

clean:
		#rm -f *.o *.so *.c *~ core $(HEXARRS)
		rm -f *.o *.so *~ core $(HEXARRS)
