MODULE_big = fixeddecimal
OBJS = fixeddecimal.o

EXTENSION = fixeddecimal
AGGSTATESQL := $(shell pg_config --version | grep -qE "XL" && echo fixeddecimalaggstate.sql)
AGGFUNCSSQL := $(shell pg_config --version | grep -qE "XL" && echo fixeddecimal--xlaggs.sql || echo fixeddecimal--aggs.sql)
BRINSQL := $(shell pg_config --version | grep -qE "9\.[5-9]| 10\.0" && echo fixeddecimal--brin.sql)
SQLFILES := $(shell cat $(AGGSTATESQL) fixeddecimal--1.0.0_base.sql $(AGGFUNCSSQL) $(BRINSQL) > fixeddecimal--1.0.0.sql)

DATA = fixeddecimal--1.0.0.sql

MODULES = fixeddecimal

CFLAGS =`pg_config --includedir-server`

TESTS = $(wildcard test/sql/*.sql)

REGRESS_BRIN := $(shell pg_config --version | grep -qE "XL 9\.[5-9]| 10\.0" && echo brin-xl)
REGRESS_BRIN += $(shell pg_config --version | grep -E "9\.[5-9]| 10\.0" | grep -qEv "XL" && echo brin)
REGRESS_VERSION_SPECIFIC := $(shell pg_config --version | grep -qE "XL" && echo index-xl || echo index)
REGRESS = $(shell echo aggregate cast comparison overflow round $(REGRESS_BRIN) $(REGRESS_VERSION_SPECIFIC))

REGRESS_OPTS = --inputdir=test --outputdir=test --load-extension=fixeddecimal

PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

fixeddecimal.so: fixeddecimal.o

fixeddecimal.o: fixeddecimal.c
