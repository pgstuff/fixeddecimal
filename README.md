FIXEDDECIMAL
============

Works with PostgreSQL 9.5 and Postgres-XL 9.5

Overview
--------

XXX Remove this paragraph if accepted upstream. This feature fork adds half even
    rounding. The rounding works accurately when parsing a string and casting
    from the numeric data type. During division, extra digits are used to detect
    if the result might be on a midpoint. If so, a modulus is used to indicate
    midpoint rounding if there are only 0's past the midpoint (5). I am not sure
    if the modulus is able to accurately indicate that there is a remainder if
    the remainder is a string of 0's past the midpoint, and past the scale of
    this calculation, changes to non-0 digits. This is where base 2 can cause
    problems for someone expecting base 10 results.
    Regardless, this feature significantly removes the bias present in
    truncation and has less bias than the more biased rounding types. This may
    be good enough for statistics, but financial calculations may want to type
    cast to numeric before performing division or multiplication until this code
    is proven to match decimal (base 10) calculations with the standard half
    even rounding. These changes should not impact the performance advantage of
    this data type outside of the operations described above.
    It is my opinion that an exact data type should not offer inexact operations
    without requiring something explicit like a type cast per the principle of
    least surprise. I expect PostgreSQL not to violate that principle. I expect
    that truncation was originally chosen because it may produce consistent
    results between base 10 and base 2 operations, but I cannot think of many
    use cases where truncation would be preferable over a low bias rounding
    method, even with the base 10 consistency that it offers.
    Note that exact means the ability to represent base 10 and its rounding
    rules when fraction data underflows. Base 2 is not inexact in itself, it is
    just that there are fractions in base 10 that can be exactly represented as
    a number while base 2 cannot exactly represent the same number. But this
    rule is true the other way around. Consider this, where float produces an
    exact answer and numeric does not:
SELECT (1 * (987654321.0 * 123456789.0) / (0.123456789 / 998877665544332211.0)) / (987654321.0 * 123456789.0) * (0.123456789 / 998877665544332211.0) AS "Should be 1";
SELECT (1::FLOAT * (987654321.0 * 123456789.0) / (0.123456789 / 998877665544332211.0)) / (987654321.0 * 123456789.0) * (0.123456789 / 998877665544332211.0) AS "Should be 1";
    The expectation that base 2 is less exact is probably due to the fact that
    we display base 2 numbers in decimal notation. If numbers were commonly
    displayed in binary notation, we would call float exact and decimal inexact.
    Likewise, decimal is inexact for dozenal.

XXX Also, fix numeric and the round function so that it uses unbiased rounding
    (someone might be working on this). For example, check the results of these
    before and after this patch:
SELECT (54::fixeddecimal / 0.03::fixeddecimal) / 54::fixeddecimal * 0.03::fixeddecimal AS "Should be 1";
SELECT (54::numeric(8,4) / 0.03::numeric(8,4)) / 54::numeric(8,4) * 0.03::numeric(8,4) AS "Should be 1";

XXX Fix capitalization inconsistencies: FixedDecimal, Fixeddecimal,
    fixeddecimal, FIXEDDECIMAL.

FixedDecimal is a fixed precision decimal type which provides a subset of the
features of PostgreSQL's builtin NUMERIC type, but with vastly increased
performance. Fixeddecimal is targeted to cases where performance and disk space
are a critical.

Often there are data storage requirements where the built in REAL and
DOUBLE PRECISION types cannot be used due to the non-exact representation of
numbers using these types, e.g. where monetary values need to be stored. In many
of these cases NUMERIC is an almost perfect type, although with NUMERIC
performance is no match for the performance of REAL or DOUBLE PRCISION, as
these use CPU native processor types. FixedDecimal aims to offer performance
advantages over NUMERIC without the imprecise representations that are
apparent in REAL and DOUBLE PRECISION, but it comes with some caveats...

Behavioural differences between FIXEDDECIMAL and NUMERIC
--------------------------------------------------------

It should be noted that there are cases were FIXEDDECIMAL behaves differently
from NUMERIC.

1.	FIXEDDECIMAL has a much more limited range of values than NUMERIC. By
	default this type can represent a maximum range of FIXEDDECIMAL(17,2),
	although the underlying type is unable to represent the full range of
	of the 17th significant digit.

2.	FIXEDDECIMAL uses base 2 instead of base 10 for operations. It is exact
	until you multiply with a number that exceeds the scale or divide. Then,
	numbers past the scale are subject to base 2 representation and may round
	differently than a base 10 operation would. See the Caution section for
	details.

3.	FIXEDDECIMAL does not support NaN.

4.	Any attempt to use a numerical scale other than the default fixed scale
	will result in an error. e.g. SELECT '123.223'::FIXEDDECIMAL(4,1) will fail
	by default, as the default scale is 2, not 1.

Internals
---------

FIXEDDECIMAL internally uses a 64bit integer type for its underlying storage.
This is what gives the type the performance advantage over NUMERIC, as most
calculations are performed as native processor operations rather than software
implementations as in the case with NUMERIC.

FIXEDDECIMAL has a fixed scale value, which by default is 2. Internally numbers
are stores as the actual value multiplied by 100. e.g. 50 would be stored as
5000, and 1.23 would be stored as 123. This internal representation allows very
fast addition and subtraction between two fixeddecimal types. Multiplication
between two fixeddecimal types is slightly more complex.  If we wanted to
perform 2.00 * 3.00 in fixeddecimal, internally these numbers would be 200 and
300 respectively, so internally 200 * 300 becomes 60000, which must be divided
by 100 in order to obtain the correct internal result of 600, which of course
externally is 6.00. This method of multiplication is hazard to overflowing the
internal 64bit integer type, for this reason all multiplication and division is
performed using 128bit integer types.

Internally, by default, FIXEDDECIMAL is limited to a maximum value of
92233720368547758.07 and a minimum value of -92233720368547758.08. If any of
these limits are exceeded the query will fail with an error.

By default the scale of FIXEDDECIMAL is 2 decimal digits after the decimal
point. This value may be changed only by recompiling FIXEDDECIMAL from source,
which is done by altering the FIXEDDECIMAL_MULTIPLIER and FIXEDDECIMAL_SCALE
constants. If the FIXEDDECIMAL_SCALE was set to 4, then the
FIXEDDECIMAL_MULTIPLIER should be set to 10000. Doing this will mean that the
absolute limits of the type decrease to a range of -922337203685477.5808 to
922337203685477.5807.

The rounding is half even to reduce bias and to match the rounding expectations
set by various accounting and computer standards.

Caution
-------

FIXEDDECIMAL is mainly intended as a fast and efficient data type which will
suit a limited set numerical data storage and retrieval needs. Complex
arithmetic could be said to be one of FIXEDDECIMAL's limits. As stated above
FIXEDDECIMAL uses base 2 for operations. This means that when using division or
multiplication with a non-zero fraction, FIXEDDECIMAL may produce results that
are inconsistent with the same operations as performed in base 10.

A workaround of this would be to perform calculations that are not exclusively
addition and subtraction in NUMERIC, and ROUND() the result into the maximum
scale of FIXEDDECIMAL:

```
test=# select round('18.00'::numeric / '59.00'::numeric, 2)::fixeddecimal;
 ?column?
----------
 0.31
(1 row)
```

FIXEDDECIMAL uses an additional set of decimal digits to perform unbiased
rounding. This set only exists when using 128bit for multiplication and
division. When this additional set begins with 5, the remaining are 0's, the
remainder of the division is checked for any non-zero value. This check may not
be accurate 100% of the time. It is used to remove bias like a IEEE 754 data
type, but until the math is proven, it cannot offer the same guarantee.

XXX Operations that can produce a fraction that overflows the scale and causes a
    problem for this logic should be removed, or at least operate with and
    return the numeric data type instead of FIXEDDECIMAL. Based on the history
    of other data types, there is a good argument for making FIXEDDECIMAL /
    FIXEDDECIMAL return numeric instead of FIXEDDECIMAL. For example, money
    divided by money does not produce a money result. It is a ratio, which means
    that it looses the money unit. However, there is a case to be made that
    because this might not be a unit type, but rather might be a performance
    type, it may not be subject to unit rules. Unfortunately, this
    interpretation may be application/user specific and thus not have a single
    correct answer.

Installation
------------

To install fixeddecimal you must build the extension from source code.

First ensure that your PATH environment variable is setup to find the correct
PostgreSQL installation first. You can check this by typing running the
pg_config command and checking the paths listed.

Once you are confident your PATH variable is set correctly

```
make
make install
make installcheck
```

From psql, in order to create the extension you must type:

```
CREATE EXTENSION fixeddecimal;
```

Credits
-------

fixeddecimal is open source using The PostgreSQL Licence, copyright is novated to the PostgreSQL Global Development Group.

Source code developed by 2ndQuadrant, as part of the AXLE project (http://axleproject.eu) which received funding from the European Union’s Seventh Framework Programme (FP7/2007-2015) under grant agreement n° 318633

Lead Developer - David Rowley
