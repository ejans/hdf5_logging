#!/bin/bash

source $UBX_ROOT/env.sh
exec $UBX_ROOT/tools/ubx_launch -webif 8888 -c hdf5_logger.usc
