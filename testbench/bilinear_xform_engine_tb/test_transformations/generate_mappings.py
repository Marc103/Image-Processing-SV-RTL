import math

def apply_transformation(c, m):
    """
    Apply a 3x3 transformation matrix to each set of coordinates.
    (The mathematical way)
    """
    x =   c[0] * m[0][0] +  c[1] * m[0][1] + c[2] * m[0][2]
    y =   c[0] * m[1][0] +  c[1] * m[1][1] + c[2] * m[1][2]
    one = c[0] * m[2][0] +  c[1] * m[2][1] + c[2] * m[2][2]

    return (x,y,one)

# returns the integral and fractal parts separately
# works for int_bits >= 1
def float_to_bin_str(number, int_bits = 16,frac_bits = 8):
    bit_idx = 0
    negative = False
    int_bits_str = ""
    frac_bits_str = ""

    if(number < 0):
        negative = True

    # using log2 is a bit complicated because of what happens between 0 <-> 1
    if(negative):
        while( (-(2**bit_idx)) > number):
            bit_idx += 1
    else:
        while((2**bit_idx) <= number):
            bit_idx += 1
        bit_idx -= 1

    acc = 0
    if(negative):
        acc = -(2**bit_idx)
        bit_idx -= 1
        int_bits_str += "1"

    while(bit_idx > -1):
        calc = acc +  (2**bit_idx)    
        if(calc <= number):
            int_bits_str += "1"
            acc = calc
        else:
            int_bits_str += "0"
        bit_idx -= 1

    while(bit_idx >= (-(frac_bits))):
        calc = acc +  (2**bit_idx)    
        if(calc <= number):
            frac_bits_str += "1"
            acc = calc
        else:
            frac_bits_str += "0"
        bit_idx -= 1

    int_str_len = len(int_bits_str)
    # adjust int bits length by sign extending
    if(int_str_len < int_bits):
        if(negative):
            int_bits_str = ("1" * (int_bits - int_str_len)) + int_bits_str
        else:
            int_bits_str = ("0" * (int_bits - int_str_len)) + int_bits_str
    if(int_str_len > int_bits):
        int_bits_str = int_bits_str[int_str_len - int_bits:]

    return int_bits_str, frac_bits_str
        
# Example usage:
if __name__ == "__main__":
    # Define the width and height
    width = 10
    height = 10

    # file name
    filename = "general_100_100"
    matrixname = "general"

    # Example 3x3 transformation matrix (replace with your matrix)
    matrix = ([[1, 0, 0],
               [0, 1, 0],
               [0, 0, 1]])

    # Define the number of bits for the integer and fractional parts
    num_int_bits = 5
    num_frac_bits = 12

    with open(filename+"_col_int.txt", 'w') as x_int_file, open(filename+"_col_frac.txt", 'w') as x_frac_file, \
         open(filename+"_row_int.txt", 'w') as y_int_file, open(filename+"_row_frac.txt", 'w') as y_frac_file, \
         open(matrixname+"_matrix.txt", 'w') as matrix_file:

        for y in range(3):
            for x in range(3):
                m_int_str, m_frac_str = float_to_bin_str(matrix[y][x], 11, num_frac_bits)
                matrix_file.write(m_int_str+m_frac_str+"\n")
                
        for y in range(height):
            for x in range(width):
                # apply transformation
                x_xform, y_xform, _ = apply_transformation([x, y, 1], matrix)

                # Convert to binary with both integer and fractional parts
                x_int_bin_str, x_frac_bin_str = float_to_bin_str(x_xform, num_int_bits, num_frac_bits)
                y_int_bin_str, y_frac_bin_str = float_to_bin_str(y_xform, num_int_bits, num_frac_bits)
        
                # Write to the respective files
                x_int_file.write(x_int_bin_str+"\n")
                x_frac_file.write(x_frac_bin_str+"\n")
                y_int_file.write(y_int_bin_str+"\n")
                y_frac_file.write(y_frac_bin_str+"\n")
        
        x_int_file.close()
        x_frac_file.close()
        y_int_file.close()
        y_frac_file.close()
        matrix_file.close()




