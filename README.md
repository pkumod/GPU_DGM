# Towards Sufficient GPU-accelerated Dynamic Graph Management: Survey and Experiment
------------
This is the artifact of our paper titled Towards Sufficient GPU-accelerated Dynamic Graph Management: Survey and Experiment for VLDB 2025.

## Environment Requirements

- g++ 9.4 or higher (C++ 14 required)
- CUDA 11.3 or higher
- Nvidia modern GPU (We tested on cards of Volta and Ampere architecture)

## Dataset

Due to the file size limit of github, you can download preprocessed datasets from this [Google Drive link](https://drive.google.com/file/d/1WAZagwzHFvaRShfoiMT3TcwSjBMGsSjI/view?usp=sharing), and put unzipped files into `dataset` folder. 

Here are some publicly available sources of our evaluated datasets: road, Wiki, Patent, Pokec, LiveJournal, Stack, and Orkut are from [SNAP](https://snap.stanford.edu/data/index.html). Graph500 is produced by Kronecker Generator from the [Graph 500 benchmark](https://graph500.org/?page_id=12#tbl:classes). LDBC-SF30 and LDBC-SF100 are from [LDBC social network benchmark](https://ldbcouncil.org/benchmarks/snb-interactive/). uk-2005 is from [Laboratory for Web Algorithms](https://law.di.unimi.it/webdata/uk-2005/).


If you want to run with your own datasets, you can use the following data format as input, which is similar to .txt format of [SNAP](https://snap.stanford.edu/data/index.html) datasets.

```
vertex_number edge_number
1 2
1 3
1 4
......
```

For a graph of N edges, the edgelist file contains N+1 lines. The first line indicates the number of vertices and edges. Each of the next N lines indicates an edge consisting of a source vertex ID and a destination vertex ID(first the source vertex, then the destination). 

## Code Structure
The project directory is organized as follows:

+ `dataset`:  Contains graph datasets
+ `LPMA`: Code for LPMA based on their [open-source version](https://github.com/pkumod/LPMA) 
+ `cuSTINGER`: Code for cuSTINGER based on their [open-source version](https://github.com/cuStinger/cuStinger)
+ `faimgraph`: Code for LPMA based on their [open-source version](https://github.com/GPUPeople/faimGraph)
+ `gpma`: Code for GPMA based on their [open-source version](https://github.com/desert0616/gpma_demo)
+ `gunrock`: Code for Gunrock based on their [open-source version](https://github.com/gunrock/gunrock)
+ `hornet`: Code for hornet based on their [open-source version](https://github.com/hornet-gt/hornet)
+ `test`: The code/scripts for conducting experiments in our paper.

## Compile
Before compiling, please make sure you have modified the corresponding Makefiles of CMakeLists to specify the CUDA arch and gencode of your applied Nvidia GPU architecture. Besides, important parameters like the NVCC path and the included path should be specified.

For cuSTINGER, faimgraph, gunrock, and hornet that use CMake:
```
cd [path to a system]
mkdir build && cd build
cmake ..
make -j8
```

For LPMA and GPMA use simply Makefile:
```
cd [path to a system]
make -j8
```
## Run the code
### Update operations
To run update tests, the following template of commands is used:

```
cd [path to executable files]
./update [data_graph] [batch_size]
```

The first argument `data_path` indicates the location of the data graph file. The second argument `batch_size` instructs the system to generate update batches of this given fixed size, which should be between $10^4$ and $10^8$.

For example, to run faimgraph's update on Orkut with a batch size of $10^5$:
```
cd ./faimgraph/build
./update ../../dataset/orkut.txt 100000
```

### Query primitives and analytic workloads
To run query primitives and analytic workloads:
```
cd [path to executable files]
./[operation_name] [data_graph] [options]
```
We implemented 5 query primitives and 3 analytic workloads based on the aforementioned open-source versions of evaluated systems, including edge check (`./findE`), neighborhood scan (`./getNeighor`), 2-hop neighbor scan (`./get2Hop`), cycle detection(`./findCycle`), clique detection (`./findClique`), breadth-first search(`./bfs`), Pagerank (`./pr`), and betweenness centrality(`./bc`). Corresponding names of executable files are indicated in parentheses above.

To run `./findE`, `./getNeighor`, `./get2Hop`, `./findCycle`, and `./findClique`, one extra option is needed, which is either `uniform` or `biased`. The former instructs the program to sample vertex points or pairs with equal probability to generate a uniform workload. The latter enforces higher sampling probability to a high-degree vertex. 

To run a breadth-first search (`./bfs`), you should provide a random seed to generate starting vertices. For example:
```
./bfs ../../dataset/orkut.txt 9527
```

To run betweenness centrality (`./bc`), an argument `k` is needed to control the sample size to estimate betweenness centrality. `k` should not be larger than the number of distinct vertices in the given data graph.

To run Pagerank, three arguments are required. (1) `damping_factor` is a probability of 0~1 (0.85 by default). (2) `max_iter` is the maximum number of iterations. (3) `tol` is the error tolerance used to check convergence.

For example, to run PageRank with faimgraph on Orkut:
```
./pr ../../dataset/orkut.txt 0.85 100 0.0000001
```
