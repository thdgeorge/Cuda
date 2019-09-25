/*
* This sample implements a separable convolution
* of a 2D image with an arbitrary filter.
*/

#include <stdio.h>
#include <stdlib.h>

//unsigned int filter_radius;

#define filter_radius 16
#define FILTER_LENGTH 	(2 * filter_radius + 1)
#define ABS(val)  	((val)<0.0 ? (-(val)) : (val))
#define accuracy  	0.00005
#define TILE_WIDTH 32
#define TILE_W1 64
#define TILE_H1 64
#define TILE_W2 64
#define TILE_H2 64


#define gpuErrchk(ans) { gpuAssert((ans), __FILE__, __LINE__); }
inline void gpuAssert(cudaError_t code, const char *file, int line, bool abort=true) {
   if (code != cudaSuccess)
   {
      fprintf(stderr,"GPUassert: %s %s %d\n", cudaGetErrorString(code), file, line);
      if (abort) exit(code);
   }
}

void convolutionRowCPU(float *h_Dst, float *h_Src, float *h_Filter, int imageW, int imageH, int filterR);
void convolutionColumnCPU(float *h_Dst, float *h_Src, float *h_Filter, int imageW, int imageH, int filterR);

__constant__ float d_Filter[FILTER_LENGTH];

//Kernel gia efarmogh filtrou kata grammes
 __global__
 void convolutionRowGPU(float *d_Buffer, float *d_Input, int imageW, int imageH) {

	__shared__ float data[TILE_H1 * (TILE_W1 + 2*filter_radius)];

	int y = blockIdx.y * 2*blockDim.y + threadIdx.y;
	int x = blockIdx.x * 2*blockDim.x + threadIdx.x;

	int reg = (y + filter_radius) * (imageW + 2*filter_radius) + (x + filter_radius);
	int data_reg = threadIdx.x + threadIdx.y * (TILE_W1 + 2*filter_radius);

	int k;
	data[data_reg] = d_Input[reg - filter_radius];
	data[data_reg + blockDim.x] = d_Input[reg + filter_radius];
	data[data_reg + 2*blockDim.x] = d_Input[reg + filter_radius + blockDim.x];
	
	data[data_reg + blockDim.y * (TILE_W1 + 2*filter_radius)] = d_Input[reg + blockDim.y * (imageW + 2*filter_radius) - filter_radius];
	data[data_reg + blockDim.x + blockDim.y * (TILE_W1 + 2*filter_radius)] = d_Input[reg + blockDim.y * (imageW + 2*filter_radius) + filter_radius];
	data[data_reg + 2*blockDim.x + blockDim.y * (TILE_W1 + 2*filter_radius)] = d_Input[reg + blockDim.y * (imageW + 2*filter_radius) + filter_radius + blockDim.x];
	

	__syncthreads();

	float sum1, sum2, sum3, sum4;
	sum1 = sum2 = sum3 = sum4 = 0;
	#pragma unroll
	for (k = -filter_radius; k <= filter_radius; k++) {
		sum1 += data[data_reg + filter_radius + k] * d_Filter[filter_radius - k];
		sum2 += data[data_reg + blockDim.x + filter_radius + k] * d_Filter[filter_radius - k];
		sum3 += data[data_reg + blockDim.y * (TILE_W1 + 2*filter_radius) + filter_radius + k] * d_Filter[filter_radius - k];
		sum4 += data[data_reg + blockDim.y * (TILE_W1 + 2*filter_radius) + blockDim.x + filter_radius + k] * d_Filter[filter_radius - k];
	}

	d_Buffer[reg] = sum1;
	d_Buffer[reg + blockDim.x] = sum2;
	d_Buffer[reg + blockDim.y * (imageW + 2*filter_radius)] = sum3;
	d_Buffer[reg + blockDim.y * (imageW + 2*filter_radius) + blockDim.x] = sum4;
 }

//Kernel gia efarmogh filtrou kata sthles
 __global__
 void convolutionColumnGPU(float *d_Output, float *d_Buffer, int imageW, int imageH) {

	__shared__ float data[TILE_W2 * (TILE_H2 + 2*filter_radius)];

	int y = blockIdx.y * 2*blockDim.y + threadIdx.y;
	int x = blockIdx.x * 2*blockDim.x + threadIdx.x;

	int reg = (y + filter_radius) * (imageW + 2*filter_radius) + (x + filter_radius);
	int data_reg = threadIdx.x + threadIdx.y * TILE_W2;
	
	data[data_reg] = d_Buffer[reg - (imageW + 2*filter_radius) * filter_radius];
	data[data_reg + blockDim.x] = d_Buffer[reg + blockDim.x - (imageW + 2*filter_radius) * filter_radius];
	
	data[data_reg + blockDim.y * TILE_W2] = d_Buffer[reg + (imageW + 2*filter_radius) * filter_radius];
	data[data_reg + blockDim.y * TILE_W2 + blockDim.x] = d_Buffer[reg + blockDim.x + (imageW + 2*filter_radius) * filter_radius];
	
	data[data_reg + 2*blockDim.y * TILE_W2] = d_Buffer[reg + (imageW + 2*filter_radius) * (filter_radius + blockDim.x)];
	data[data_reg + 2*blockDim.y * TILE_W2 + blockDim.x] = d_Buffer[reg + blockDim.x + (imageW + 2*filter_radius) * (filter_radius + blockDim.x)];


	__syncthreads();

	float sum1, sum2, sum3, sum4;
	sum1 = sum2 = sum3 = sum4 = 0;
	#pragma unroll
	for (int k = -filter_radius; k <= filter_radius; k++) {
		sum1 += data[data_reg + (k + filter_radius) * TILE_W2] * d_Filter[filter_radius - k];
		sum2 += data[data_reg + (k + filter_radius) * TILE_W2 + blockDim.x] * d_Filter[filter_radius - k];
		sum3 += data[data_reg + (blockDim.y + k + filter_radius) * TILE_W2] * d_Filter[filter_radius - k];
		sum4 += data[data_reg + (blockDim.y + k + filter_radius) * TILE_W2 + blockDim.x] * d_Filter[filter_radius - k];
	}

	d_Output[y * imageW + x] = sum1;
	d_Output[y * imageW + x + blockDim.x] = sum2;
	d_Output[(y + blockDim.y) * imageW + x] = sum3;
	d_Output[(y + blockDim.y) * imageW + x + blockDim.x] = sum4;
}

////////////////////////////////////////////////////////////////////////////////
// Reference row convolution filter
////////////////////////////////////////////////////////////////////////////////
void convolutionRowCPU(float *h_Dst, float *h_Src, float *h_Filter,
                       int imageW, int imageH, int filterR) {

  int x, y, k;

  for (y = 0; y < imageH; y++) {
    for (x = 0; x < imageW; x++) {
      float sum = 0;

      for (k = -filterR; k <= filterR; k++) {
        int d = x + k;

        if (d >= 0 && d < imageW) {
          sum += h_Src[y * imageW + d] * h_Filter[filterR - k];
        }

        h_Dst[y * imageW + x] = sum;
      }
    }
  }

}


////////////////////////////////////////////////////////////////////////////////
// Reference column convolution filter
////////////////////////////////////////////////////////////////////////////////
void convolutionColumnCPU(float *h_Dst, float *h_Src, float *h_Filter,
    			   int imageW, int imageH, int filterR) {

  int x, y, k;

  for (y = 0; y < imageH; y++) {
    for (x = 0; x < imageW; x++) {
      float sum = 0;

      for (k = -filterR; k <= filterR; k++) {
        int d = y + k;

        if (d >= 0 && d < imageH) {
          sum += h_Src[d * imageW + x] * h_Filter[filterR - k];
        }

        h_Dst[y * imageW + x] = sum;
      }
    }
  }

}


////////////////////////////////////////////////////////////////////////////////
// Main program
////////////////////////////////////////////////////////////////////////////////
int main(int argc, char **argv) {
	
	//cudaDeviceSetCacheConfig(cudaFuncCachePreferShared);
	//cudaFuncSetCacheConfig(convolutionRowGPU, cudaFuncCachePreferShared);
	//cudaFuncSetCacheConfig(convolutionColumnGPU, cudaFuncCachePreferShared);

	//struct timespec  tv1, tv2;

    float
    *h_Filter,
    *h_Input,
    *h_Buffer,
    //*h_OutputCPU,
	*h_OutputGPU,
	*h_Input_padding,
	*d_Input,
	*d_Buffer,
	*d_Output;


    int imageW;
    int imageH;
    unsigned int i;

	//printf("Enter filter radius : ");
	//scanf("%d", &filter_radius);

    // Ta imageW, imageH ta dinei o xrhsths kai thewroume oti einai isa,
    // dhladh imageW = imageH = N, opou to N to dinei o xrhsths.
    // Gia aplothta thewroume tetragwnikes eikones.
	
	FILE *ifp, *ofp;
    ifp = fopen("Input.txt","r");
    ofp = fopen("Output_32_64x64_64x64.txt","w");
	
	int tile_width = TILE_WIDTH;
	int tile_w1 = TILE_W1;
	int tile_h1 = TILE_H1;
	int tile_w2 = TILE_W2;
	int tile_h2 = TILE_H2;
	
	fprintf(ofp,"TILE_WIDTH: %d\nTILE_W1: %d\nTILE_H1: %d\nTILE_W2: %d\nTILE_H2: %d\n-------------------\n", tile_width, tile_w1, tile_h1, tile_w2, tile_h2);
	

    for (int k = 1; k < 9 ; k++) {

		float sum_GPU = 0;

		//printf("Enter image size. Should be a power of two and greater than %d : ", FILTER_LENGTH);
		fscanf(ifp, "%d", &imageW);
		if ( imageW < FILTER_LENGTH ) {
			printf("Image size lower than %d\nTermatismos programmatos...\n", FILTER_LENGTH);
			return(2);
		}
		else if ( imageW % 2 != 0 ) {
			printf("Image size is not a power of two\nTermatismos programmatos...\n");
			return(3);
		}
		imageH = imageW;

		printf("Image Width x Height = %i x %i\n\n", imageW, imageH);
		
		for (int j = 1; j < 13; j++) {
			
			//printf("Allocating and initializing host arrays...\n");
			// Tha htan kalh idea na elegxete kai to apotelesma twn malloc...
			h_Filter    = (float *)malloc(FILTER_LENGTH * sizeof(float));
			h_Input     = (float *)malloc(imageW * imageH * sizeof(float));
			h_Buffer    = (float *)malloc(imageW * imageH * sizeof(float));
			//h_OutputCPU = (float *)malloc(imageW * imageH * sizeof(float));
			h_OutputGPU = (float *)malloc(imageW * imageH * sizeof(float));
			
			h_Input_padding 	= (float *)malloc((imageW + 2*filter_radius) * (imageH + 2*filter_radius) * sizeof(float));
			
			//Elegxos apotelesmatwn twn malloc
			if (h_Filter == NULL || h_Input == NULL || h_Buffer == NULL || h_OutputGPU == NULL || h_Input_padding == NULL ) {
				printf("Apotuxia Desmeushs mnhmhs \n Termatismos programmatos...\n");
				return(1);
			}

			//Desmeush mnhmhs gia to device
			//printf("Allocating and initializing device arrays...\n");
			gpuErrchk( cudaMalloc((void**)&d_Input, (imageW + 2*filter_radius) * (imageH + 2*filter_radius) * sizeof(float)) );
			gpuErrchk( cudaMalloc((void**)&d_Buffer, (imageW + 2*filter_radius) * (imageH + 2*filter_radius) * sizeof(float)) );
			gpuErrchk( cudaMalloc((void**)&d_Output, imageW * imageH * sizeof(float)) );



			// to 'h_Filter' apotelei to filtro me to opoio ginetai to convolution kai
			// arxikopoieitai tuxaia. To 'h_Input' einai h eikona panw sthn opoia ginetai
			// to convolution kai arxikopoieitai kai auth tuxaia.

			srand(200);

			for (i = 0; i < FILTER_LENGTH; i++) {
				h_Filter[i] = (float)(rand() % 16);
			}

			for (i = 0; i < imageW * imageH; i++) {
				h_Input[i] = (float)rand() / ((float)RAND_MAX / 255) + (float)rand() / (float)RAND_MAX;
			}
			
			
			//Topothethsh tou padding perimetrika ths eikonas eisodou
			for (i=0; i < (imageW + 2*filter_radius) * filter_radius; i++)
				h_Input_padding[i] = 0;
			
			int p = 0, k = 0;
			for (i = (imageW + 2*filter_radius) * filter_radius; i < (imageW + 2*filter_radius) * (filter_radius + imageW); i++ ) {
				if ( p < filter_radius || p >= filter_radius + imageW ) {
					h_Input_padding[i] = 0;
				}
				else {
					h_Input_padding[i] = h_Input[k];
					k++;
				}
				p++;
				if ( p == 2*filter_radius + imageW )
					p = 0;
			}
			
			for (i=(imageW + 2*filter_radius) * (filter_radius + imageW); i < (imageW + 2*filter_radius) * (2*filter_radius + imageW); i++)
				h_Input_padding[i] = 0;
			
			
			


			// To parakatw einai to kommati pou ekteleitai sthn CPU kai me vash auto prepei na ginei h sugrish me thn GPU.
			//printf("CPU computation...\n");

			//clock_gettime(CLOCK_MONOTONIC_RAW, &tv1);

			//convolutionRowCPU(h_Buffer, h_Input, h_Filter, imageW, imageH, filter_radius); // convolution kata grammes
			//convolutionColumnCPU(h_OutputCPU, h_Buffer, h_Filter, imageW, imageH, filter_radius); // convolution kata sthles

			//clock_gettime(CLOCK_MONOTONIC_RAW, &tv2);



			//To parakatw einai to kommati pou xreiazetai gia thn ektelesh sthn GPU

			cudaEvent_t start, stop;
			cudaEventCreate(&start);
			cudaEventCreate(&stop);

			dim3 dimGrid1(imageW/TILE_W1, imageH/TILE_H1);
			dim3 dimGrid2(imageW/TILE_W2, imageH/TILE_H2);
			dim3 dimBlock(TILE_WIDTH, TILE_WIDTH);

			

			//Metafora dedomenwn apo ton host pros to device
			gpuErrchk( cudaMemcpyToSymbol(d_Filter, h_Filter, FILTER_LENGTH * sizeof(float)) );
			gpuErrchk( cudaMemcpy(d_Input, h_Input_padding, (imageW + 2*filter_radius) * (2*filter_radius + imageW) * sizeof(float), cudaMemcpyHostToDevice) );
			gpuErrchk( cudaMemset(d_Buffer, 0, (imageW + 2*filter_radius) * (2*filter_radius + imageW) * sizeof(float)) );

			cudaEventRecord(start);

			//Kaloume ton prwto Kernel
			convolutionRowGPU<<<dimGrid1, dimBlock>>>(d_Buffer, d_Input, imageW, imageH);

			gpuErrchk( cudaPeekAtLastError() );


			//Kaloume ton deutero Kernel
			convolutionColumnGPU<<<dimGrid2, dimBlock>>>(d_Output, d_Buffer, imageW, imageH);

			gpuErrchk( cudaPeekAtLastError() );

			cudaEventRecord(stop);
			cudaEventSynchronize(stop);
			float GPUtime;
			cudaEventElapsedTime(&GPUtime, start, stop);

			//Metafora apotelesmatos apo to device ston host
			gpuErrchk( cudaMemcpy(h_OutputGPU, d_Output,  imageW * imageH * sizeof(float), cudaMemcpyDeviceToHost) );


			// Kanete h sugrish anamesa se GPU kai CPU kai an estw kai kapoio apotelesma xeperna thn akriveia
			// pou exoume orisei, tote exoume sfalma kai mporoume endexomenws na termatisoume to programma mas

			/*for (i = 0; i < imageW * imageH; i++) {
				if (ABS(h_OutputCPU[i] - h_OutputGPU[i]) > accuracy) {
					printf("Sfalma akriveias \n Termatismos programmatos...\n");
					return(2);
				}
				//printf("h_OutputCPU[%d]: %f\nh_OutputGPU[%d]: %f\n\n", i, h_OutputCPU[i], i, h_OutputGPU[i]);
			}
			*/


			//Ektypwsh xronwn
			/*printf ("Time for the CPU: %10g s\n",
					(double) (tv2.tv_nsec - tv1.tv_nsec) / 1000000000.0 +
					(double) (tv2.tv_sec - tv1.tv_sec));
			printf("Time for the GPU: %f s\n", GPUtime / 1000 );
			*/


			sum_GPU += GPUtime / 1000;
			
			// free all the allocated memory
			cudaFree(d_Input);
			cudaFree(d_Buffer);
			cudaFree(d_Output);

			free(h_OutputGPU);
			//free(h_OutputCPU);
			free(h_Buffer);
			free(h_Input);
			free(h_Filter);
			free(h_Input_padding);
			

			// Do a device reset just in case... Bgalte to sxolio otan ylopoihsete CUDA
			cudaDeviceReset();

			printf("End of run %d\n", j);
		}
		
		fprintf(ofp, "GPU: %f\n----------------------\n", sum_GPU/12);

	}

    return 0;
}