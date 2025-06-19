# Image-Processing-SV-RTL
Features a Convolution Filter and Bilinear interpolator that are written and tested in System Verilog, using adjustable Fixed Pointed Arithmetic.
These work on a typical data stream of pixels coming from a camera for example (stream processing). This was developed by me during my time working
at the BiV lab headed by Professor Emma Alexander at Nothwestern University (see https://www.alexander.vision/) and used in her DfDD 
techniques (Depth from Defocus) demo at CVPR conference 2025 (Computer Vision and Pattern Recognition). I worked with John Mamish 
(https://www.linkedin.com/in/john-mamish-712453253/) to place the design on a low powered FPGA (the ECP%). A publication will soon be made
and i will link here.

## Convolution Filter
The convolution filter allows you to apply a filter of any size and of any coefficients. In the convolution_engine_tb testbench,
I perform a simple box filter to demonstrate it working. The files will be placed in the simulate folder, which will show the
input (gen_x), golden model output (mdl_x) and the the dut output (which are then compared to check for correctness). The waveform
(.vcd file) is also produced in the simulate folder. This structure is also the same with the bilinear_xform_engine_tb.

Before  
![alt text](https://github.com/Marc103/Image-Processing-SV-RTL/blob/main/conv_gen_image_0.png)

After - 4x4 box filter  
![alt text](https://github.com/Marc103/Image-Processing-SV-RTL/blob/main/conv_dut_image_0.png)

### Saving Resources
Since multipliers are expensive, the module also has a CLKS_PER_PIXEL parameter, which allows it to take more than
1 cycle to process a MAC of the convolution. Of course, that means that pixels cannot be fed in less than
CLKS_PER_PIXEL cycles per pixel. So for a 4x4 which is 16 multiplies we could reduce it to 16/4 if we set CLKS_PER+_PIXEL = 4,
giving us very nice savings.

## Bilinear Interpolator
The bilinear interpolator allow you to apply an affine transformation as represented by a 3x3 transformation matrix.
In the bilinear_xform_engine_tb, we set the matrix in the test_transformations/generate_mappings.py file to a small 
rotation and scaling. Images are stored in a upside down coordinate system (y = 0 is the top of the image
,y = image_height - 1 is the bottom, x = 0 is the left, x = image_width - 1 is the right), and so this has to be
taken into account when creating the transformation matrix. Finally, because the coordinates are being reverse mapped,
find the inverse of the matrix.

Another important aspect of Bilinear Interpolator is how many lines we buffer; Generally speaking, the less lines we buffer,
the less we can perform bigger transformations. For instance, if you wanted to flip the image upside down, we would have to
buffer the entire image. But for small rotations, scaling and translations, we can use, say, a quater of the number of lines
of the image. This is controlled by the N_LINES_POW_2 parameters (i.e setting this to 6 will give us 2**6 lines).

Before  
![alt text](https://github.com/Marc103/Image-Processing-SV-RTL/blob/main/bxform_gen_image_0.png)

After - 5 degree rotation with 0.9 scaling with 32 lines buffered.  
![alt text](https://github.com/Marc103/Image-Processing-SV-RTL/blob/main/bxform_dut_image_0.png)


### Fixed Pointer Arithmetic
- Using fixed pointer arithmetic, you can set at what order of magnitude you want to do your calculations
- M - number of integer bits
- N - number of fractional bits
- S - 1 or 0, signed or unsigned
- For example, in the convolution filter, the image is presented as an 8 bit image but the kernel coefficients is represented in
  4 - bit fractional bits, allowing us to set box filter fractional values.

### Notes on Installation and Simulating
Lattice Diamond must be installed for the simulation to run (3.13 is what we used). On linux when installing Lattice diamond,
the main issue is making sure that all the correct pacakges are installed. This involves try to run it, getting an error about
missing packages, and installing them until it works. The tricky part however, is at some point the error messages start 
giving red herrings from what is actually still missing packages. At this point, try running the GUI for modelsim (vsim), it will
tell you what you are missing. Also a license is required (which is free). Use the node locked license.

I used Ubuntu 24.04 LTS with these lines included in the .bashrc :

export PATH="/usr/local/diamond/3.13/bin/lin64:$PATH"
export PATH="/usr/local/diamond/3.13/modeltech/linuxloem:$PATH"
export PATH="/usr/local/diamond/3.13/bin/lin64/toolapps/:$PATH"

To run a testbench, navigate to it's directory and execute the simulate.sh file. 
