/*
* This sample implements a separable convolution 
* of a 2D image with an arbitrary filter.
*/

#include <stdio.h>
#include <stdlib.h>

unsigned int filter_radius;

#define FILTER_LENGTH 	(2 * filter_radius + 1)
#define ABS(val)  	((val)<0.0 ? (-(val)) : (val))
#define accuracy  	0.00005

#define gpuErrchk(ans) { gpuAssert((ans), __FILE__, __LINE__); }
inline void gpuAssert(cudaError_t code, const char *file, int line, bool abort=true)
{
   if (code != cudaSuccess) 
   {
      fprintf(stderr,"GPUassert: %s %s %d\n", cudaGetErrorString(code), file, line);
      if (abort) exit(code);
   }
}


void convolutionRowCPU(float *h_Dst, float *h_Src, float *h_Filter, int imageW, int imageH, int filterR);
void convolutionColumnCPU(float *h_Dst, float *h_Src, float *h_Filter, int imageW, int imageH, int filterR);


 __global__
 void convolutionGPU(float *d_Dst, float *d_Input, float *d_Buffer, float *d_Filter, int imageW, int imageH, int filter_radius) {
	int k;
	float sum = 0;
	for (k = -filter_radius; k <= filter_radius; k++) {
		int d = threadIdx.x + k;
		
		if (d >= 0 && d < imageW) {
			sum += d_Input[threadIdx.y * imageW + d] * d_Filter[filter_radius - k];
        }   
 
        d_Buffer[threadIdx.y * imageW + threadIdx.x] = sum;
	}
	
	//__syncthreads();
	
	sum = 0;
	for (k = -filter_radius; k <= filter_radius; k++) {
		int d = threadIdx.y + k;
		
		if (d >= 0 && d < imageH) {
			sum += d_Buffer[d * imageW + threadIdx.x] * d_Filter[filter_radius - k];
        }   
 
       d_Dst[threadIdx.y * imageW + threadIdx.x] = sum;
	}
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
    
	float
	*h_Filter,
	*h_Input,
	*h_Buffer,
	*h_OutputCPU,
	*h_OutputGPU,
	*d_Dst,
	*d_Input,
	*d_Filter,
	*d_Buffer;

	
	int imageW;
	int imageH;
	unsigned int i;

	printf("Enter filter radius : ");
	scanf("%d", &filter_radius);

	// Ta imageW, imageH ta dinei o xrhsths kai thewroume oti einai isa,
	// dhladh imageW = imageH = N, opou to N to dinei o xrhsths.
	// Gia aplothta thewroume tetragwnikes eikones.  

	printf("Enter image size. Should be a power of two and greater than %d : ", FILTER_LENGTH);
	scanf("%d", &imageW);
	imageH = imageW;

	printf("Image Width x Height = %i x %i\n\n", imageW, imageH);
	printf("Allocating and initializing host arrays...\n");
	// Tha htan kalh idea na elegxete kai to apotelesma twn malloc...
	h_Filter    = (float *)malloc(FILTER_LENGTH * sizeof(float));
	h_Input     = (float *)malloc(imageW * imageH * sizeof(float));
	h_Buffer    = (float *)malloc(imageW * imageH * sizeof(float));
	h_OutputCPU = (float *)malloc(imageW * imageH * sizeof(float));
	h_OutputGPU = (float *)malloc(imageW * imageH * sizeof(float));
	if (h_Filter == NULL || h_Input == NULL || h_Buffer == NULL || h_OutputCPU == NULL || h_OutputGPU == NULL) {
		printf("Apotuxia Desmeushs mnhmhs \n Termatismos programmatos...\n");
		return(1);
	}
	
	printf("Allocating and initializing device arrays...\n");
	gpuErrchk( cudaMalloc((void**)&d_Filter, FILTER_LENGTH * sizeof(float)) );
	gpuErrchk( cudaMalloc((void**)&d_Input, imageW * imageH * sizeof(float)) );
	gpuErrchk( cudaMalloc((void**)&d_Dst, imageW * imageH * sizeof(float)) );
	gpuErrchk( cudaMalloc((void**)&d_Buffer, imageW * imageH * sizeof(float)) );
	

		
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

	
	
    // To parakatw einai to kommati pou ekteleitai sthn CPU kai me vash auto prepei na ginei h sugrish me thn GPU.
	printf("CPU computation...\n");

	convolutionRowCPU(h_Buffer, h_Input, h_Filter, imageW, imageH, filter_radius); // convolution kata grammes
	convolutionColumnCPU(h_OutputCPU, h_Buffer, h_Filter, imageW, imageH, filter_radius); // convolution kata sthles

	
	
	//To parakatw einai to kommati pou xreiazetai gia thn ektelesh sthn GPU
	
	dim3 dimGrid(1, 1);
	dim3 dimBlock(imageW, imageH);
	
	gpuErrchk( cudaMemcpy(d_Filter, h_Filter, FILTER_LENGTH * sizeof(float), cudaMemcpyHostToDevice) );
	gpuErrchk( cudaMemcpy(d_Input, h_Input, imageW * imageH * sizeof(float), cudaMemcpyHostToDevice) );

	printf("GPU computation...\n");
	
	//Kaloume ton Kernel
	convolutionGPU<<<dimGrid, dimBlock>>>(d_Dst, d_Input, d_Buffer, d_Filter, imageW, imageH, filter_radius);

	gpuErrchk( cudaPeekAtLastError() );
	gpuErrchk( cudaMemcpy(h_OutputGPU, d_Dst,  imageW * imageH * sizeof(float), cudaMemcpyDeviceToHost) );
	
	// Kanete h sugrish anamesa se GPU kai CPU kai an estw kai kapoio apotelesma xeperna thn akriveia
    // pou exoume orisei, tote exoume sfalma kai mporoume endexomenws na termatisoume to programma mas  

	for (i = 0; i < imageW * imageH; i++) {
		if (ABS(h_OutputCPU[i] - h_OutputGPU[i]) > accuracy) {
			printf("Sfalma akriveias \n Termatismos programmatos...\n");
			return(2);
		}
	}


    // free all the allocated memory
	cudaFree(d_Filter);
	cudaFree(d_Input);
	cudaFree(d_Dst);
	cudaFree(d_Buffer);
	
	free(h_OutputGPU);
	free(h_OutputCPU);
	free(h_Buffer);
	free(h_Input);
	free(h_Filter);

    // Do a device reset just in case... Bgalte to sxolio otan ylopoihsete CUDA
    cudaDeviceReset();


    return 0;
}
