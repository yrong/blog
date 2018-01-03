---
author: Ron
catalog: false
date: 2016-10-03T15:00:00Z
header-img: img/post-bg-kuaidi.jpg
tags:
- elasticsearch
title: ElasticSearch的存储结构
url: /2016/10/03/elasticsearch-storelayer/
---

# Elasticsearch的存储结构 #


## Node Data ##

Simply starting Elasticsearch from a empty data directory yields the following directory tree:


```
$ tree data
data
└── elasticsearch
    └── nodes
        └── 0
            ├── _state
            │   └── global-0.st
            └── node.lock
```

The node.lock file is there to ensure that only one Elasticsearch installation is reading/writing from a single data directory at a time.

More interesting is the global-0.st-file. The global-prefix indicates that this is a global state file while the .st extension indicates that this is a state file that contains metadata. As you might have guessed, this binary file contains global metadata about your cluster and the number after the prefix indicates the cluster metadata version, a strictly increasing versioning scheme that follows your cluster.
		

## Index Data ##

Let’s create a single shard index and look at the files changed by Elasticsearch:

```
$ curl localhost:9200/foo -XPOST -d '{"settings":{"index.number_of_shards": 1}}'
{"acknowledged":true}

$ tree -h data
data
└── [ 102]  elasticsearch
    └── [ 102]  nodes
        └── [ 170]  0
            ├── [ 102]  _state
            │   └── [ 109]  global-0.st
            ├── [ 102]  indices
            │   └── [ 136]  foo
            │       ├── [ 170]  0
            │       │   ├── .....
            │       └── [ 102]  _state
            │           └── [ 256]  state-0.st
            └── [   0]  node.lock
```

We see that a new directory has been created corresponding to the index name. This directory has two sub-folders: _state and 0. The former contains what’s called a index state file (indices/{index-name}/_state/state-{version}.st), which contains metadata about the index, such as its creation timestamp. It also contains a unique identifier as well as the settings and the mappings for the index. The latter contains data relevant for the first (and only) shard of the index (shard 0). Next up, we’ll have a closer look at this.

## Shard Data ##

The shard data directory contains a state file for the shard that includes versioning as well as information about whether the shard is considered a primary shard or a replica.

```
$ tree -h data/elasticsearch/nodes/0/indices/foo/0
data/elasticsearch/nodes/0/indices/foo/0
├── [ 102]  _state
│   └── [  81]  state-0.st
├── [ 170]  index
│   ├── [  36]  segments.gen
│   ├── [  79]  segments_1
│   └── [   0]  write.lock
└── [ 102]  translog
    └── [  17]  translog-1429697028120
```

The {shard_id}/index directory contains files owned by Lucene. Elasticsearch generally does not write directly to this folder. The files in these directories constitute the bulk of the size of any Elasticsearch data directory.

Before we enter the world of Lucene, we’ll have a look at the Elasticsearch transaction log, which is unsurprisingly found in the per-shard translog directory with the prefix translog-. The transaction log is very important for the functionality and performance of Elasticsearch, so we’ll explain its use a bit closer in the next section.

## Per-Shard Transaction Log ##
The [Elasticsearch transaction log](http://www.elastic.co/guide/en/elasticsearch/reference/current/index-modules-translog.html) makes sure that data can safely be indexed into Elasticsearch without having to perform [elasticsearch flush](http://www.elasticsearch.org/guide/en/elasticsearch/reference/current/indices-flush.html) which actually triggers a low-level Lucene commit for every document. Committing a Lucene index creates a new segment on the Lucene level which is fsync()-ed and results in a significant amount of disk I/O which affects performance.

In order to accept a document for indexing and make it searchable without requiring a full Lucene commit, Elasticsearch adds it to the [Lucene IndexWriter](http://lucene.apache.org/core/5_1_0/core/org/apache/lucene/index/IndexWriter.html) and appends it to the transaction log. After each [refresh_interval](https://www.elastic.co/guide/en/elasticsearch/reference/current/setup-configuration.html#configuration-index-settings) it will call [elasticsearch refresh](http://www.elasticsearch.org/guide/en/elasticsearch/reference/current/indices-refresh.html) which actually triggers reopen() on the Lucene indexes and will make the data searchable without requiring a commit. This is part of the Lucene Near Real Time API. When the IndexWriter eventually commits due to either an automatic flush of the transaction log or due to an explicit flush operation, the previous transaction log is discarded and a new one takes its place.

Should recovery be required, the segments written to disk in Lucene will be recovered first, then the transaction log will be replayed in order to prevent the loss of operations not yet fully committed to disk.


## Lucene Index Files ##

Lucene has done a good job at documenting the files in the [Lucene index directory](https://lucene.apache.org/core/5_1_0/core/org/apache/lucene/codecs/lucene50/package-summary.html), reproduced here for your convenience:

| Name	|Extension	|Brief Description|
| ------| ------ | ------ |
| Segments File	|segments_N	|Stores information about a commit point|
| Lock File	|write.lock	|The Write lock prevents multiple IndexWriters from writing to the same file.|
| Segment Info	|.si	|Stores metadata about a segment|
| Compound File	|.cfs, .cfe	|An optional “virtual” file consisting of all the other index files for systems that frequently run out of file handles.
| Fields	|.fnm	|Stores information about the fields
| Field Index	|.fdx	|Contains pointers to field data
| Field Data	|.fdt	|The stored fields for documents
| Term Dictionary	|.tim	|The term dictionary, stores term info
| Term Index	|.tip	|The index into the Term Dictionary
| Frequencies	|.doc	|Contains the list of docs which contain each term along with frequency
| Positions	|.pos	|Stores position information about where a term occurs in the index
| Payloads	|.pay	|Stores additional per-position metadata information such as character offsets and user payloads
| Norms	.nvd, |.nvm	|Encodes length and boost factors for docs and fields
| Per-Document Values	|.dvd, .dvm	|Encodes additional scoring factors or other per-document information.
| Term Vector Index	|.tvx	|Stores offset into the document data file
| Term Vector Documents	|.tvd	|Contains information about each document that has term vectors
| Term Vector Fields	|.tvf	|The field level info about term vectors
| Live Documents	|.liv	|Info about what files are live

> When using the Compound File format (default in 1.4 and greater) all these files (except for the Segment info file, the Lock file, and Deleted documents file) are collapsed into a single .cfs file.