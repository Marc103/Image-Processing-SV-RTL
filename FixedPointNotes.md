# Notes about Fixed Point Artihmetic
 
Firstly, only signed arithmetic is done. This is easily achieved
by turning unsigned values into signed by appending a zero.
 
 
## i. Initial setup
 
Given two signed numbers 
- sq mx.nx
- sq my.ny
 
If we multiply them, the resulting form looks like
- sq (mx + my + 1).(nx + ny)                         
 
However, since we are then accumulating multiple of these results,
the final result form would actually look like
- sq (mx + my + 1 + $clog2(K_WIDTH  K_HEIGHT)).(nx + ny)  (eq.1)

Lets refer to the form of this (calculated) new number as
- sq mc.nc
and as an array of bits, simply
- 'sqc'
 
 
## ii. Solution no.1 - Absolute Method
 
Given an output form
- sq mo.no OR uq mo.no
and as an array of bits, refered to as
- 'qo' 
 
with which we want to transfrom sq mc.nc into, see the 
small (pseudocode) algorithm below:
 
int sext_lhs;      // sign extension of lhs
int zext_rhs;      // zero extension of rhs
int li;            // left index
int ri;            // right index
int bit_width_sqc; // bit width of sqc
 
bit_width = mc + nc + 1
 
if (mo - mc) > 0: 
   li = bit_width_sqc - 2                      // -2 instead of -1, to skip sign bit
    sext_lhs = mo - mc
else:
   li = bit_width - 2 + (mo - mc)
   sext_lhs = 0
  
if (no - nc) > 0:
   ri = 0
   zext_rhs =  no - nc
else:
   ri = 0 - (no - nc)
   zext_rhs = 0
  
if (li >= 0) && (ri < (bit_width_sqc - 1)):        // if li and ri are within bounds
   if output form is signed (sqo):
       qo = { sqc[bit_width_sqc-1], {sext_lhs{sqc[bit_width_sqc-1]}} , sqc[li:ri] , {zext_rhs{1'b0}} }
   
   else if output form is unsigned (uqo):  
       qo = { {sext_lhs{sqc[bit_width_sqc-1]}} , sqc[li:ri] , {zext_rhs{1'b0}} }
 
else:                                    // effectively, all bits discarded 
   if output form is signed (sqo):
       if ri == (bit_width_sqc - 1):               // means, sign bit is maintained
           qo = { {sqc[0]}, {sext_lhs{sqc[bit_width_sqc-1]}} , {zext_rhs{1'b0}} }
       else:                                       // sign bit effectively discarded
            qo = { {1'b0}, {sext_lhs{1'b0}} , {zext_rhs{1'b0}} }

else if output form is unsigned (uqo):  
    if ri == (bit_width_sqc - 1):               // means, sign bit is maintained
        qo = { {sext_lhs{sqc[bit_width_sqc-1]}} , {zext_rhs{1'b0}} }
    else:                                   // sign bit effectively discarded
        qo = { {sext_lhs{1'b0}} , {zext_rhs{1'b0}} }
 
  
 
## iii. Further Notes
  
When i first started thinking about this problem i thought there would be ways to 
scale numbers to fit the output format. But that doesn't make sense; a sq4.0 number
cannot be transformed into a sq0.4 numbers. They are both 5 bit numbers but scaling
the bits (which in this example wouldn't do anything) would literally change the interpreted
value. 5'b10001 isnt the same as 5'b _ _ _ _ 1 . 0001.
 
sq4.0 -> sq8.0, good!
 
sq4.0 -> sq6.-4 It's going to work but whats the point? All your bits have been effectivley 
                  discarded and as a result, will yield a bunch of sext/zext bits.
 
So it's important to look at the calculated form (sqc) using eq.1 in i. to then 
decided an appropriate output form.
 
Upon further thought, i realized that scaling the numbers to fit the output form might be necessary.
So even though the absolute method i. is correct, we also might need a relative method.
To demonstrate, 320 will never be 0.320 in terms of absolute values. But in the context of
relative scales (which is everything when it comes to pixel values)
 
(999,0) 320 is equivalent to (0.999, 0.000) 0.320
 
Meaning sq3.0 = sq2.1 = sq.1.2 = sq 4.-1 and so on which sort of the defeats the purpose of 
fixed point arithmetic since I think it was intended for solely absolute values.
 
To conclude, I think the best way forward is to use the absolute method and then scale the 
results in a separate module if necessary
 
so if you wanted uq4.0 x uq4.0, a good output form that would maintain the same bit width
would be uq8.-4. And so we get the best of both worlds because we can pick our bit depths
and maintain their absolute value representation.
 