---
author: Ron
catalog: false
date: 2016-07-16T18:00:00Z
header-img: img/post-bg-universe.jpg
tags:
- elasticsearch
title: ElasticSearch源码解析之文档索引
url: /2016/07/16/elasticsearch-analysis/
---


es5.0版本主要改进应该是lucene版本升级到6.0,利用插件机制把netty从core中剥离出来接入NetworkModule,代码在Netty3Plugin.

``` java
public void onModule(NetworkModule networkModule) {
        if (networkModule.canRegisterHttpExtensions()) {
            networkModule.registerHttpTransport(NETTY_HTTP_TRANSPORT_NAME, Netty3HttpServerTransport.class);
        }
        networkModule.registerTransport(NETTY_TRANSPORT_NAME, Netty3Transport.class);
    }
```    


client通过reset api来调用es的索引接口,RestIndexAction的handleRequest处理文档索引请求,调用TransportReplicationAction在ReroutePhase完成分片,参看OperationRouting的shardid算法.

``` java
static int generateShardId(IndexMetaData indexMetaData, String id, @Nullable String routing) {
        final int hash;
        if (routing == null) {
            hash = Murmur3HashFunction.hash(id);
        } else {
            hash = Murmur3HashFunction.hash(routing);
        }
        // we don't use IMD#getNumberOfShards since the index might have been shrunk such that we need to use the size
        // of original index to hash documents
        return Math.floorMod(hash, indexMetaData.getRoutingNumShards()) / indexMetaData.getRoutingFactor();
    }
``` 
找到数据主分片，本地处理或是通过netty转发到所在节点处理

``` java
if (primary.currentNodeId().equals(state.nodes().getLocalNodeId())) {
                performLocalAction(state, primary, node);
            } else {
                performRemoteAction(state, primary, node);
            }
``` 


TransportReplicationAction在AsyncPrimaryAction的onResponse完成消息处理,通过调用ReplicationOperation的execute方法,完成索引在primary shard和replica shard的处理,参看

```java
public void execute() throws Exception {
        final String writeConsistencyFailure = checkWriteConsistency ? checkWriteConsistency() : null;
        final ShardRouting primaryRouting = primary.routingEntry();
        final ShardId primaryId = primaryRouting.shardId();
        if (writeConsistencyFailure != null) {
            finishAsFailed(new UnavailableShardsException(primaryId,
                "{} Timeout: [{}], request: [{}]", writeConsistencyFailure, request.timeout(), request));
            return;
        }

        totalShards.incrementAndGet();
        pendingShards.incrementAndGet();
        primaryResult = primary.perform(request);
        final ReplicaRequest replicaRequest = primaryResult.replicaRequest();
        assert replicaRequest.primaryTerm() > 0 : "replicaRequest doesn't have a primary term";
        if (logger.isTraceEnabled()) {
            logger.trace("[{}] op [{}] completed on primary for request [{}]", primaryId, opType, request);
        }

        performOnReplicas(primaryId, replicaRequest);

        successfulShards.incrementAndGet();
        decPendingAndFinishIfNeeded();
    }
``` 

在主shard的处理部分调用TransportWriteAction的shardOperationOnPrimary,进而调用TransportIndexAction的executeIndexRequestOnPrimary

``` java
public static WriteResult<IndexResponse> executeIndexRequestOnPrimary(IndexRequest request, IndexShard indexShard,
            MappingUpdatedAction mappingUpdatedAction) throws Exception {
        Engine.Index operation = prepareIndexOperationOnPrimary(request, indexShard);
        Mapping update = operation.parsedDoc().dynamicMappingsUpdate();
        final ShardId shardId = indexShard.shardId();
        if (update != null) {
            mappingUpdatedAction.updateMappingOnMaster(shardId.getIndex(), request.type(), update);
            operation = prepareIndexOperationOnPrimary(request, indexShard);
            update = operation.parsedDoc().dynamicMappingsUpdate();
            if (update != null) {
                throw new ReplicationOperation.RetryOnPrimaryException(shardId,
                    "Dynamic mappings are not available on the node that holds the primary yet");
            }
        }
        final boolean created = indexShard.index(operation);

        // update the version on request so it will happen on the replicas
        final long version = operation.version();
        request.version(version);
        request.versionType(request.versionType().versionTypeForReplicationAndRecovery());

        assert request.versionType().validateVersionForWrites(request.version());

        IndexResponse response = new IndexResponse(shardId, request.type(), request.id(), request.version(), created);
        return new WriteResult<>(response, operation.getTranslogLocation());
    }
``` 

IndexShard的index方法通过调用InternalEngine的innerIndex完成写lucene索引操作,并将index operation写入transaction log,防止flush前断电导致索引数据丢失

``` java
private boolean innerIndex(Index index) throws IOException {
        try (Releasable ignored = acquireLock(index.uid())) {
            lastWriteNanos = index.startTime();
            final long currentVersion;
            final boolean deleted;
            final VersionValue versionValue = versionMap.getUnderLock(index.uid());
            if (versionValue == null) {
                currentVersion = loadCurrentVersionFromIndex(index.uid());
                deleted = currentVersion == Versions.NOT_FOUND;
            } else {
                currentVersion = checkDeletedAndGCed(versionValue);
                deleted = versionValue.delete();
            }

            final long expectedVersion = index.version();
            if (checkVersionConflict(index, currentVersion, expectedVersion, deleted)) return false;

            final long updatedVersion = updateVersion(index, currentVersion, expectedVersion);

            final boolean created = indexOrUpdate(index, currentVersion, versionValue);

            maybeAddToTranslog(index, updatedVersion, Translog.Index::new, NEW_VERSION_VALUE);

            return created;
        }
    }
``` 

注意maybeAddToTranslog并未完成translog的sync操作,而是在TransportWriteAction的postWriteActions部分

``` java
 boolean fsyncTranslog = indexShard.getTranslogDurability() == Translog.Durability.REQUEST && location != null && indexShard.getTranslog().sizeInBytes()>=indexShard.indexSettings().getFlushThresholdSize().getBytes();
        if (fsyncTranslog) {
            indexShard.sync(location);
        }
```         
此处做了一些定制化改造,对应并发客户段不使用bulk批量操作,而采用单条小索引请求.此处不开启Translog.Durability.ASYNC异步提交日志模式,而是根据translog中的未提交到lucene中的字节数(上一次flush到现在缓存的数据)来判断是否需要做日志同步