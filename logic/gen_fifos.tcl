#!/bin/env -S af -F

generate_fifo out_fifo  -data_widths {36 18} -address_depths 256 -sync_stages 3 -fifo_mode normal
generate_fifo in_fifo   -data_widths {16 32} -address_depths 512 -sync_stages 3 -fifo_mode showahead
generate_fifo data_fifo -data_widths {32  8} -address_depths 256 -sync_stages 1 -fifo_mode showahead
