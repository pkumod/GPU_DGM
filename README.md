# Towards Sufficient GPU-accelerated Dynamic Graph Management: Survey and Experiment
------------
+ This is the artifacts of our paper titled Towards Sufficient GPU-accelerated Dynamic Graph Management: Survey and Experiment for VLDB 2025.

## Environment Requirements

- g++ 9.4 or higher (C++ 14 required)
- CUDA 11.3 or higher
- Nvidia modern GPU (We tested on cards of Volta and Ampere architecture)

## Dataset

Due to the file size limit of github, users can download preprocessed datasets from this [link](https://drive.google.com/drive/folders/1u99TgRftbVKoZD04f7kI5exvKuBWZ8gM?usp=drive_link), and put them into `dataset` folder. 

All of the evaluated datasets are publicly available: road, Wiki, Patent, Pokec, LiveJournal, Stack, and Orkut are from [SNAP](https://snap.stanford.edu/data/index.html). Graph500 is produced by Kronecker Generator from the [Graph 500 benchmark](https://graph500.org/?page_id=12#tbl:classes). LDBC-SF30 and LDBC-SF100 are from [LDBC social network benchmark](https://ldbcouncil.org/benchmarks/snb-interactive/). uk-2005 is from [Laboratory for Web Algorithms](https://law.di.unimi.it/webdata/uk-2005/).


If you want to run with your own datasets, you can use the following data format as input, which is similar to .txt format of [SNAP](https://snap.stanford.edu/data/index.html) datasets.

```
vertex_number edge_number
1 2
1 3
1 4
......
```

For a graph of N edges, the edgelist file contains N+1 lines. The first line indicates the number of vertices and edges. Each of the next N lines indicates an edge consisting of a source vertex ID and a destination vertex ID(first the source vertex, then the destination)(t1,t2,t3 in the example). 

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
For cuSTINGER, faimgraph, gunrock, and hornet:
```
cd [path to a system]
mkdir build && cd build
cmake ..
make -j8
```

For LPMA and GPMA:
```
cd [path to a system]
make -j8
```

