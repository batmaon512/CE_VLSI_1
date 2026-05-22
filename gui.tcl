set DESIGN SPI_Top
###############################################################
## Library setup
###############################################################
read_libs "../LIB/slow.lib ../LIB/pll.lib ../LIB/CDK_S128x16.lib ../LIB/CDK_S256x16.lib ../LIB/CDK_R512x16.lib "
read_physical -lef " ../LEF/gsclib045_tech.lef ../LEF/gsclib045_macro.lef ../LEF/pll.lef ../LEF/CDK_S128x16.lef ../LEF/CDK_S256x16.lef
../LEF/CDK_R512x16.lef "
####################################################################
## Load Design
####################################################################
read_hdl "./outputs/SPI_Top_m.v"
elaborate $DESIGN