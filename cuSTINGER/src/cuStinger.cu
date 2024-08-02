
#include <thrust/device_vector.h>
#include <thrust/host_vector.h>

#include "utils.hpp"
#include "update.hpp"
#include "memoryManager.hpp"
#include "cuStinger.hpp"

using namespace std;
#include <stdio.h>
#include <string.h>


// void initializeCuStinger(cuStingerConfig);

// __global__ void devInitVertexData(cuStinger* custing,uint8_t* temp)
__global__ void devInitVertexData(cuStinger::cusVertexData *dVD,vertexId_t nv,uint8_t* temp)
{
	if(threadIdx.x!=0 || blockIdx.x!=0)
		DEV_CUSTINGER_ERROR("Number of threads and thread blocks for initializing vertex should always be one");
	// cuStinger::cusVertexData *dVD = custing->dVD;

	dVD->mem = temp;
	int32_t pos=0;

	dVD->adj 		= (cuStinger::cusEdgeData**)(dVD->getMem() + pos); 	pos+=sizeof(cuStinger::cusEdgeData*)*nv;
	dVD->edMem 		= (uint8_t**)(dVD->getMem() + pos); 				pos+=sizeof(uint8_t*)*nv;
	dVD->used 		= (length_t*)(dVD->getMem() + pos); 				pos+=sizeof(length_t)*nv;
	dVD->max        = (length_t*)(dVD->getMem() + pos); 				pos+=sizeof(length_t)*nv;
	dVD->vw         = (vweight_t*)(dVD->getMem() + pos); 				pos+=sizeof(vweight_t)*nv;
	dVD->vt         = (vtype_t*)(dVD->getMem() + pos); 					pos+=sizeof(vtype_t)*nv;
}

void cuStinger::initVertexDataPointers(cuStinger::cusVertexData *dVD, uint8_t* temp){
	// devInitVertexData<<<1,1>>>(	d_cuStinger,temp);
	devInitVertexData<<<1,1>>>(	dVD,nv,temp);
}

__global__ void devInitEdgeData(cuStinger* custing, int verticesPerThreadBlock){
	vertexId_t v_init=blockIdx.x*verticesPerThreadBlock+threadIdx.x;
	length_t nv = custing->getMaxNV();
	for (vertexId_t v_hat=0; v_hat<verticesPerThreadBlock; v_hat+=blockDim.x){
		vertexId_t v=v_init+v_hat;
		if(v>=nv)
			break;

		//epv = edge per vertex
		length_t epv = custing->dVD->getMax()[v];

		int32_t pos=0;
		cuStinger::cusEdgeData *dED = custing->dVD->adj[v];

		dED->mem = custing->dVD->edMem[v];
		dED->dst = (vertexId_t*)(dED->getMem() + pos); 	pos+=sizeof(vertexId_t)*epv;
		dED->ew  = (eweight_t*)(dED->getMem() + pos); 	pos+=sizeof(eweight_t)*epv;
		dED->et  = (etype_t*)(dED->getMem() + pos); 	pos+=sizeof(etype_t)*epv;
		dED->t1  = (timestamp_t*)(dED->getMem() + pos); pos+=sizeof(timestamp_t)*epv;
		dED->t2  = (timestamp_t*)(dED->getMem() + pos); pos+=sizeof(timestamp_t)*epv;
	}
}

void cuStinger::initEdgeDataPointers(){
	dim3 numBlocks(1, 1);
	int32_t threads=64;
	dim3 threadsPerBlock(threads, 1);

	numBlocks.x = ceil((float)nv/(float)threads);
	if (numBlocks.x>16000){
		numBlocks.x=16000;
	}	

	int32_t verticesPerThreadBlock = threads;

	if(numBlocks.x>1)
		 verticesPerThreadBlock = ceil(float(nv)/float(numBlocks.x-1));		

	devInitEdgeData<<<numBlocks,threadsPerBlock>>>(	d_cuStinger,verticesPerThreadBlock);
}

__global__ void devMakeGPUStinger(vertexId_t* d_off, length_t* d_adj,
	int verticesPerThreadBlock,cuStinger* custing){
	length_t* d_utilized = custing->dVD->getUsed();
	length_t* d_max = custing->dVD->getMax();


	int32_t v_init=blockIdx.x*verticesPerThreadBlock;
	for (int v_hat=0; v_hat<verticesPerThreadBlock; v_hat++){
		int32_t v=v_init+v_hat;

		if(v>=custing->nv)
			break;
		cuStinger::cusEdgeData* adjv = custing->dVD->adj[v];
		for(int32_t e=threadIdx.x; e<d_utilized[v]; e+=blockDim.x){
				adjv->dst[e]=d_adj[d_off[v]+e];
		}
		for(int32_t e=threadIdx.x + d_utilized[v]; e < d_max[v]; e+=blockDim.x){
			adjv->dst[e]=DELETION_MARKER;
		}
	}
}

void cuStinger::internalCSRTocuStinger(length_t* h_off, vertexId_t* h_adj, length_t ne){
	length_t* d_off = (length_t*)allocDeviceArray(nv+1,sizeof(length_t));
	vertexId_t* d_adj = (vertexId_t*)allocDeviceArray(ne,sizeof(vertexId_t));
	copyArrayHostToDevice(h_off,d_off,nv+1,sizeof(length_t));
	copyArrayHostToDevice(h_adj,d_adj,ne,sizeof(vertexId_t));

	dim3 numBlocks(1, 1);
	int32_t threads=64;
	dim3 threadsPerBlock(threads, 1);

	numBlocks.x = ceil((float)nv/(float)threads);
	if (numBlocks.x>16000){
		numBlocks.x=16000;
	}	

	int32_t verticesPerThreadBlock;
	if(numBlocks.x==1)
		verticesPerThreadBlock=nv;
	else
		verticesPerThreadBlock= ceil(float(nv)/float(numBlocks.x-1));

	devMakeGPUStinger<<<numBlocks,threadsPerBlock>>>(d_off,d_adj,verticesPerThreadBlock, d_cuStinger);

	freeDeviceArray(d_adj);	
	freeDeviceArray(d_off);
}



#define SUM_BLOCK_SIZE 512
__global__ void devSumArray(length_t * input, length_t * output, length_t len) {
    __shared__ length_t partialSum[2 * SUM_BLOCK_SIZE];
    //Load a segment of the input vector into shared memory
    length_t tid = threadIdx.x, start = 2 * blockIdx.x * SUM_BLOCK_SIZE;
    if (start + tid < len)
       partialSum[tid] = input[start + tid];
    else
       partialSum[tid] = 0;

    if (start + SUM_BLOCK_SIZE + tid < len)
       partialSum[SUM_BLOCK_SIZE + tid] = input[start + SUM_BLOCK_SIZE + tid];
    else
       partialSum[SUM_BLOCK_SIZE + tid] = 0;

    //Traverse the reduction tree
    for (int stride = SUM_BLOCK_SIZE; stride >= 1; stride >>= 1) {
       __syncthreads();
       if (tid < stride)
          partialSum[tid] += partialSum[tid+stride];
    }
    //Write the computed sum of the block to the output vector at the correct index
    if (tid == 0)
       output[blockIdx.x] = partialSum[0];
}

length_t cuStinger::sumDeviceArray(length_t* arr, length_t len){
	length_t numOutputElements = len / (SUM_BLOCK_SIZE<<1);
    if (len % (SUM_BLOCK_SIZE<<1)) {
        numOutputElements++;
    }

	length_t* d_out = (length_t*)allocDeviceArray(len, sizeof(length_t*));

	devSumArray<<<numOutputElements,SUM_BLOCK_SIZE>>>(arr,d_out,len);

	length_t* h_out = (length_t*)allocHostArray(len, sizeof(length_t*));
	
	length_t sum=0;
	copyArrayDeviceToHost(d_out, h_out, len, sizeof(length_t));
	for(int i=0; i<numOutputElements; i++){
		sum+=h_out[i];
	}
	freeHostArray(h_out);
	freeDeviceArray(d_out);	
	return sum;
}

__global__ void deviceCopyMultipleAdjacencies(cuStinger* custing, cuStinger::cusVertexData* olddVD, 
	vertexId_t* requireUpdates, length_t requireCount ,length_t verticesPerThreadBlock)
{
	// int32_t** d_cuadj = custing->d_adj;
	// length_t* d_utilized = custing->getDeviceUsed();

	length_t v_init=blockIdx.x*verticesPerThreadBlock;
	for (int v_hat=0; v_hat<verticesPerThreadBlock; v_hat++){
		if((v_init+v_hat)>=requireCount)
			break;
		vertexId_t v=requireUpdates[v_init+v_hat];

		cuStinger::cusEdgeData *dED = custing->dVD->adj[v];
		cuStinger::cusEdgeData *olddED = olddVD->adj[v];

		//epv = edge per vertex
		length_t epv = olddVD->getMax()[v];
		int32_t pos=0;

		dED->mem = custing->dVD->edMem[v];
		dED->dst = (vertexId_t*)(dED->getMem() + pos); 	pos+=sizeof(vertexId_t)*epv;
		dED->ew  = (eweight_t*)(dED->getMem() + pos); 	pos+=sizeof(eweight_t)*epv;
		dED->et  = (etype_t*)(dED->getMem() + pos); 	pos+=sizeof(etype_t)*epv;
		dED->t1  = (timestamp_t*)(dED->getMem() + pos); pos+=sizeof(timestamp_t)*epv;
		dED->t2  = (timestamp_t*)(dED->getMem() + pos); pos+=sizeof(timestamp_t)*epv;

		__syncthreads();

		for(length_t e=threadIdx.x; e<olddVD->getUsed()[v]; e+=blockDim.x){
			dED->dst[e] = olddED->dst[e];
			if(custing->isSemantic){
				dED->ew[e] = olddED->ew[e];	
			}
			else if(custing->useEWeight){
				dED->ew[e] = olddED->ew[e];	
				dED->et[e] = olddED->et[e];	
				dED->t1[e] = olddED->t1[e];	
				dED->t2[e] = olddED->t1[e];	
			}
		}
	}
}


void cuStinger::copyMultipleAdjacencies(cusVertexData* olddVD, 
	vertexId_t* requireUpdates, length_t requireCount){

	dim3 numBlocks(1, 1);
	int32_t threads=32;
	dim3 threadsPerBlock(threads, 1);

	numBlocks.x = ceil((float)requireCount);
	if (numBlocks.x>16000){
		numBlocks.x=16000;
	}	
	int32_t verticesPerThreadBlock;
	if(numBlocks.x == requireCount)
		verticesPerThreadBlock=1;
	else
		verticesPerThreadBlock = ceil(float(requireCount)/float(numBlocks.x-1));


	deviceCopyMultipleAdjacencies<<<numBlocks,threadsPerBlock>>>(d_cuStinger,
		olddVD, requireUpdates, requireCount, verticesPerThreadBlock);
	checkLastCudaError("Error in the first update sweep");
}



__global__ void deviceCheckForDuplicateEdges(cuStinger* custing, length_t verticesPerThreadBlock)
{
	vertexId_t v_init=blockIdx.x*verticesPerThreadBlock+threadIdx.x;
	length_t nv = custing->getMaxNV();

	__shared__ int dupFound;

	for (vertexId_t v_hat=0; v_hat<verticesPerThreadBlock; v_hat++){
		vertexId_t v=v_init+v_hat;
		if(v>=nv)
			break;
		length_t edges = custing->dVD->getUsed()[v];
		cuStinger::cusEdgeData *dED = custing->dVD->adj[v];

		// if(v ==45788 && threadIdx.x==0){
		// 	for(length_t e=0; e<edges; e++)
		// 		printf("%d ,",dED->dst[e]);
		// 	printf("\n");
		// }

		for (length_t e=0; e<edges; e++){
			vertexId_t currDest=dED->dst[e];
			dupFound=-1;
			__syncthreads();


			for (length_t e2=0; e2<edges; e2+=blockDim.x){
				vertexId_t currDest2 = dED->dst[e2];
				if(currDest==currDest2 && e!=e2){
					dupFound=e2;
				}
			}
			__syncthreads();
			if(dupFound!=-1)
				printf("DUP FOUND IN CUSTIGER\n");
		}

	}


}


void cuStinger::checkDuplicateEdges(){

	dim3 numBlocks(1, 1);
	int32_t threads=32;
	dim3 threadsPerBlock(threads, 1);
	int32_t verticesPerThreadBlock;

	numBlocks.x = ceil((float)nv/(float)threads);
	if (numBlocks.x>16000){
		numBlocks.x=16000;
	}	
	verticesPerThreadBlock = ceil(float(nv)/float(numBlocks.x));

	// cout << "checkDuplicateEdges : " << verticesPerThreadBlock<< endl;
	// cout << "checkDuplicateEdges : " << numBlocks.x << endl;
	// cout << "Deletions : " << threadsPerBlock.x << endl;

	deviceCheckForDuplicateEdges<<<numBlocks,threadsPerBlock>>>(d_cuStinger,
		verticesPerThreadBlock);
	checkLastCudaError("Error in the first update sweep");
}




